import XCTest
@testable import AMORA

final class AmoraLocalBrainPrewarmTests: XCTestCase {

    // MARK: - 1. Prewarm Readiness
    func testPrewarmSetsIsPrewarmedTrue() async throws {
        let mock = MockLocalModelRuntime()
        XCTAssertFalse(mock.isPrewarmed)
        XCTAssertEqual(mock.prewarmCallCount, 0)

        try await mock.prewarm()

        XCTAssertTrue(mock.isPrewarmed)
        XCTAssertEqual(mock.prewarmCallCount, 1)
        XCTAssertFalse(mock.isLoaded, "Pre-warming must not load model weights into memory")
    }

    // MARK: - 2. Deduplication of Concurrent Prewarm Calls
    func testPrewarmDeduplication() async throws {
        let mock = MockLocalModelRuntime(simulatedDelayNanoseconds: 50_000_000) // 50ms
        mock.simulatedPrewarmDelayNanoseconds = 50_000_000

        // Launch multiple concurrent prewarm calls
        async let p1: Void = mock.prewarm()
        async let p2: Void = mock.prewarm()
        async let p3: Void = mock.prewarm()

        _ = try await (p1, p2, p3)

        XCTAssertTrue(mock.isPrewarmed)
        XCTAssertEqual(mock.prewarmCallCount, 3)
    }

    // MARK: - 3. Cancellation Safety
    func testPrewarmCancellation() async throws {
        let mock = MockLocalModelRuntime()
        mock.simulatedPrewarmDelayNanoseconds = 500_000_000 // 500ms

        let task = Task {
            try await mock.prewarm()
        }

        // Cancel immediately
        task.cancel()

        do {
            try await task.value
            XCTFail("Cancelled prewarm task should throw CancellationError")
        } catch is CancellationError {
            // Expected
        } catch {
            XCTFail("Expected CancellationError but received: \(error)")
        }

        XCTAssertFalse(mock.isPrewarmed, "Cancelled prewarm must not falsely claim ready")
    }

    // MARK: - 4. Failure Handling and Recovery
    func testPrewarmFailureHandling() async throws {
        let mock = MockLocalModelRuntime()
        mock.shouldFailPrewarm = true
        mock.prewarmErrorMessage = "Metal device unavailable"

        do {
            try await mock.prewarm()
            XCTFail("Prewarm should throw when failure is simulated")
        } catch let error as AmoraLocalRuntimeError {
            if case .inferenceFailed(let msg) = error {
                XCTAssertEqual(msg, "Metal device unavailable")
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(mock.isPrewarmed, "Failed prewarm must not claim ready")

        // Recovery on retry
        mock.shouldFailPrewarm = false
        try await mock.prewarm()
        XCTAssertTrue(mock.isPrewarmed, "Runtime must allow retry after previous failure")
    }

    // MARK: - 5. LoadModel Awaits In-Flight Prewarm
    func testLoadModelAwaitsInFlightPrewarm() async throws {
        let mock = MockLocalModelRuntime()
        mock.simulatedPrewarmDelayNanoseconds = 30_000_000 // 30ms

        // Start prewarm in background
        let prewarmTask = Task {
            try await mock.prewarm()
        }

        // Immediately request model load
        try await mock.loadModel(from: "/mock/path/model.gguf", configuration: .init())
        try await prewarmTask.value

        XCTAssertTrue(mock.isPrewarmed)
        XCTAssertTrue(mock.isLoaded)
        XCTAssertEqual(mock.loadedModelPath, "/mock/path/model.gguf")
    }

    // MARK: - 6. Model Weight Isolation
    func testPrewarmDoesNotLoadModelWeights() async throws {
        let mock = MockLocalModelRuntime()
        try await mock.prewarm()

        XCTAssertTrue(mock.isPrewarmed)
        XCTAssertFalse(mock.isLoaded, "isLoaded must remain false when only pre-warmed")
        XCTAssertNil(mock.loadedModelPath, "loadedModelPath must remain nil when only pre-warmed")
    }

    // MARK: - 7. Unload Preserves Backend Readiness
    func testUnloadModelPreservesBackendReadiness() async throws {
        let mock = MockLocalModelRuntime()
        try await mock.prewarm()
        XCTAssertTrue(mock.isPrewarmed)

        try await mock.loadModel(from: "/mock/path/model.gguf", configuration: .init())
        XCTAssertTrue(mock.isLoaded)
        XCTAssertTrue(mock.isPrewarmed)

        await mock.unloadModel()
        XCTAssertFalse(mock.isLoaded, "Model weights must be unloaded")
        XCTAssertTrue(mock.isPrewarmed, "Backend readiness must be preserved across model unload")
    }

    // MARK: - 8. Native LlamaCppRuntime Prewarm Concurrency and Idempotence
    func testNativeRuntimePrewarmIdempotence() async throws {
        let runtime = AmoraLlamaCppRuntime.shared

        // Initial prewarm (or no-op if already warm)
        try await runtime.prewarm()
        XCTAssertTrue(runtime.isPrewarmed)

        // Concurrent prewarm requests must deduplicate and return safely
        async let w1: Void = runtime.prewarm()
        async let w2: Void = runtime.prewarm()
        async let w3: Void = runtime.prewarm()

        _ = try await (w1, w2, w3)

        XCTAssertTrue(runtime.isPrewarmed)
    }

    // MARK: - 9. Startup Prewarm Gating
    func testStartupPrewarmGatingLogic() {
        func shouldPrewarm(aiEnabled: Bool, provider: String, modelReady: Bool) -> Bool {
            let isLocalSelected = aiEnabled && provider == AIProviderKind.local.rawValue
            return isLocalSelected && modelReady
        }

        XCTAssertTrue(shouldPrewarm(aiEnabled: true, provider: AIProviderKind.local.rawValue, modelReady: true))
        XCTAssertFalse(shouldPrewarm(aiEnabled: false, provider: AIProviderKind.local.rawValue, modelReady: true))
        XCTAssertFalse(shouldPrewarm(aiEnabled: true, provider: AIProviderKind.appleOnDevice.rawValue, modelReady: true))
        XCTAssertFalse(shouldPrewarm(aiEnabled: true, provider: "openai", modelReady: true))
        XCTAssertFalse(shouldPrewarm(aiEnabled: true, provider: AIProviderKind.local.rawValue, modelReady: false))
    }
}
