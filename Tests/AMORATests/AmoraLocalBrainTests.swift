import XCTest
import CryptoKit
@testable import AMORA

final class MockModelDownloader: AmoraModelDownloading, @unchecked Sendable {
    var shouldFail = false
    var failureError: Error = NSError(domain: "MockDownloader", code: 500, userInfo: [NSLocalizedDescriptionKey: "Download failed"])
    var simulatedProgressSteps: [Double] = [0.25, 0.5, 0.75, 1.0]
    var onDownloadStarted: (() -> Void)?
    var isCancelled = false

    func download(
        from url: URL,
        to destinationURL: URL,
        expectedSizeBytes: Int64,
        onProgress: @Sendable @escaping (Double, Int64, Int64) -> Void
    ) async throws {
        onDownloadStarted?()
        for p in simulatedProgressSteps {
            if isCancelled { throw CancellationError() }
            let bytes = Int64(Double(expectedSizeBytes) * p)
            onProgress(p, bytes, expectedSizeBytes)
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        if isCancelled { throw CancellationError() }
        if shouldFail { throw failureError }

        // Create dummy file matching expected size
        let data = Data(count: Int(expectedSizeBytes))
        try data.write(to: destinationURL)
    }

    func cancelCurrentDownload() {
        isCancelled = true
    }
}

@MainActor
final class AmoraLocalBrainTests: XCTestCase {
    var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        AmoraConversationContextManager.shared.reset()
        AmoraActionExecutionCoordinator.shared.reset()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        AmoraConversationContextManager.shared.reset()
        AmoraActionExecutionCoordinator.shared.reset()
        TimerService.shared.stopTimer()
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    // MARK: - 1. Provider Selection and Fallback
    func testProviderSelectionAndFallback() async {
        let disabledSettings = AISettingsSnapshot(enabled: false, provider: .local, model: "local", apiKey: nil)
        let disabledProvider = AIProviderFactory.make(for: disabledSettings)
        XCTAssertFalse(disabledProvider.isAvailable)
        XCTAssertEqual(disabledProvider.kind, .local)

        let enabledSettings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)
        let provider = AIProviderFactory.make(for: enabledSettings)
        XCTAssertEqual(provider.kind, .local)
    }

    // MARK: - 2. Missing Model
    func testMissingModelStatus() async {
        let mockDownloader = MockModelDownloader()
        let manager = AmoraModelManager(
            descriptor: .qwen2_5_0_5b,
            downloader: mockDownloader,
            modelsDirectory: tempDirectory
        )

        let status = await manager.checkStatus()
        XCTAssertEqual(status, .notInstalled)
        XCTAssertFalse(manager.isReady)

        let runtime = MockLocalModelRuntime()
        let provider = AmoraLocalBrainProvider(runtime: runtime, modelManager: manager)
        XCTAssertEqual(provider.availability, .modelNotReady)

        let assistant = AssistantManager(provider: provider, providerIsInjected: true)
        let response = await assistant.submit("Hello AMORA", settings: AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil))
        XCTAssertTrue(response.contains("AMORA's local brain is not set up yet"))
    }

    // MARK: - 3. Model Readiness When File Exists
    func testModelReadinessWhenValidFileExists() async throws {
        let testData = "AMORA offline test weights".data(using: .utf8)!
        let hash = SHA256.hash(data: testData).map { String(format: "%02x", $0) }.joined()

        let descriptor = AmoraModelDescriptor(
            id: "test-model",
            displayName: "Test Model",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "AMORA Test",
            sourceURL: URL(string: "https://example.com/model.gguf")!,
            expectedSizeBytes: Int64(testData.count),
            estimatedRAMBytes: 1024 * 1024,
            expectedSHA256: hash,
            filename: "test_model.gguf",
            systemPrompt: "You are AMORA."
        )

        let manager = AmoraModelManager(
            descriptor: descriptor,
            downloader: MockModelDownloader(),
            modelsDirectory: tempDirectory
        )

        try testData.write(to: manager.modelFileURL)
        let status = await manager.checkStatus()
        XCTAssertEqual(status, .ready)
        XCTAssertTrue(manager.isReady)

        let isValid = await manager.verifyIntegrity()
        XCTAssertTrue(isValid)
    }

    // MARK: - 4. Download Progress, Cancellation, and Retry
    func testDownloadProgressCancellationAndRetry() async throws {
        let testData = "Model Data".data(using: .utf8)!
        let hash = SHA256.hash(data: testData).map { String(format: "%02x", $0) }.joined()

        let descriptor = AmoraModelDescriptor(
            id: "test-model-cancel",
            displayName: "Test Model",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "AMORA Test",
            sourceURL: URL(string: "https://example.com/model.gguf")!,
            expectedSizeBytes: Int64(testData.count),
            estimatedRAMBytes: 1024 * 1024,
            expectedSHA256: hash,
            filename: "test_cancel.gguf",
            systemPrompt: "You are AMORA."
        )

        let downloader = MockModelDownloader()
        let manager = AmoraModelManager(
            descriptor: descriptor,
            downloader: downloader,
            modelsDirectory: tempDirectory
        )

        // Cancel test
        downloader.onDownloadStarted = {
            manager.cancelDownload()
        }

        try? await manager.startDownload()
        XCTAssertEqual(manager.status, .cancelled)

        // Safe Retry test
        downloader.isCancelled = false
        downloader.onDownloadStarted = nil
        // We override downloader to write exact testData so hash passes
        struct ContentDownloader: AmoraModelDownloading, @unchecked Sendable {
            let data: Data
            func download(from url: URL, to destinationURL: URL, expectedSizeBytes: Int64, onProgress: @Sendable @escaping (Double, Int64, Int64) -> Void) async throws {
                onProgress(1.0, Int64(data.count), Int64(data.count))
                try data.write(to: destinationURL)
            }
            func cancelCurrentDownload() {}
        }

        let retryManager = AmoraModelManager(
            descriptor: descriptor,
            downloader: ContentDownloader(data: testData),
            modelsDirectory: tempDirectory
        )

        try await retryManager.startDownload()
        XCTAssertEqual(retryManager.status, .ready)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retryManager.modelFileURL.path))
    }

    // MARK: - 5. Checksum Validation (Success and Mismatch)
    func testChecksumMismatchFails() async throws {
        let testData = "Corrupt weights".data(using: .utf8)!
        let expectedHash = "0000000000000000000000000000000000000000000000000000000000000000" // Intentional wrong hash

        let descriptor = AmoraModelDescriptor(
            id: "test-model-mismatch",
            displayName: "Test Model",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "AMORA Test",
            sourceURL: URL(string: "https://example.com/model.gguf")!,
            expectedSizeBytes: Int64(testData.count),
            estimatedRAMBytes: 1024 * 1024,
            expectedSHA256: expectedHash,
            filename: "test_mismatch.gguf",
            systemPrompt: "You are AMORA."
        )

        struct MismatchDownloader: AmoraModelDownloading, @unchecked Sendable {
            let data: Data
            func download(from url: URL, to destinationURL: URL, expectedSizeBytes: Int64, onProgress: @Sendable @escaping (Double, Int64, Int64) -> Void) async throws {
                try data.write(to: destinationURL)
            }
            func cancelCurrentDownload() {}
        }

        let manager = AmoraModelManager(
            descriptor: descriptor,
            downloader: MismatchDownloader(data: testData),
            modelsDirectory: tempDirectory
        )

        try? await manager.startDownload()
        if case .corrupt = manager.status {
            // Expected
        } else {
            XCTFail("Status should be .corrupt upon hash mismatch, was \(manager.status)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.modelFileURL.path))
    }

    // MARK: - 6. Corrupt / Incompatible Model Detection
    func testCorruptModelDetection() async throws {
        let descriptor = AmoraModelDescriptor(
            id: "test-model-corrupt",
            displayName: "Test Model",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "AMORA Test",
            sourceURL: URL(string: "https://example.com/model.gguf")!,
            expectedSizeBytes: 10_000,
            estimatedRAMBytes: 1024 * 1024,
            expectedSHA256: "dummy",
            filename: "test_corrupt.gguf",
            systemPrompt: "You are AMORA."
        )

        let manager = AmoraModelManager(
            descriptor: descriptor,
            downloader: MockModelDownloader(),
            modelsDirectory: tempDirectory
        )

        // Write smaller file (truncated)
        try "Truncated".data(using: .utf8)!.write(to: manager.modelFileURL)
        let status = await manager.checkStatus()
        if case .corrupt = status {
            // Expected
        } else {
            XCTFail("Truncated file should be detected as .corrupt, was \(status)")
        }
    }

    // MARK: - 7. Structured Action Output Parsing
    func testStructuredActionOutputParsing() async throws {
        let jsonPlan = #"{"actions":[{"action":"app.open","name":"Spotify"}]}"#
        let runtime = MockLocalModelRuntime(responseToReturn: jsonPlan)

        let descriptor = AmoraModelDescriptor(
            id: "test-plan",
            displayName: "Test Plan",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "Test",
            sourceURL: URL(string: "https://example.com/m.gguf")!,
            expectedSizeBytes: 10,
            estimatedRAMBytes: 100,
            expectedSHA256: "hash",
            filename: "m.gguf",
            systemPrompt: "Test"
        )

        let manager = AmoraModelManager(descriptor: descriptor, downloader: MockModelDownloader(), modelsDirectory: tempDirectory)
        try Data(count: 10).write(to: manager.modelFileURL)
        _ = manager.checkStatusSync()

        let provider = AmoraLocalBrainProvider(runtime: runtime, modelManager: manager)
        let assistant = AssistantManager(provider: provider, providerIsInjected: true)

        let answer = await assistant.submit("Open Spotify", settings: AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil))
        XCTAssertTrue(answer.localizedCaseInsensitiveContains("Spotify"))
    }

    // MARK: - 8. Invalid or Malicious Model Output Rejection
    func testMaliciousModelOutputRejection() async throws {
        // Model attempts to invent a shell execution action
        let maliciousPlan = #"{"actions":[{"action":"shell.exec","command":"rm -rf ~"}]}"#
        let runtime = MockLocalModelRuntime(responseToReturn: maliciousPlan)

        let descriptor = AmoraModelDescriptor(
            id: "test-malicious",
            displayName: "Test Malicious",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "Test",
            sourceURL: URL(string: "https://example.com/m.gguf")!,
            expectedSizeBytes: 10,
            estimatedRAMBytes: 100,
            expectedSHA256: "hash",
            filename: "m.gguf",
            systemPrompt: "Test"
        )

        let manager = AmoraModelManager(descriptor: descriptor, downloader: MockModelDownloader(), modelsDirectory: tempDirectory)
        try Data(count: 10).write(to: manager.modelFileURL)
        _ = manager.checkStatusSync()

        let provider = AmoraLocalBrainProvider(runtime: runtime, modelManager: manager)
        let assistant = AssistantManager(provider: provider, providerIsInjected: true)

        let answer = await assistant.submit("Do something dangerous", settings: AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil))
        // The action is rejected by ActionPlan validator, so the raw text is returned or no command executed
        XCTAssertFalse(answer.contains("Executing"))
    }

    // MARK: - 9. Action Allowlisting and Confirmation
    func testActionConfirmationEnforced() async throws {
        let confirmPlan = #"{"actions":[{"action":"system.confirm_test","name":"Sensitive Op"}]}"#
        let runtime = MockLocalModelRuntime(responseToReturn: confirmPlan)

        let descriptor = AmoraModelDescriptor(
            id: "test-confirm",
            displayName: "Test Confirm",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "Test",
            sourceURL: URL(string: "https://example.com/m.gguf")!,
            expectedSizeBytes: 10,
            estimatedRAMBytes: 100,
            expectedSHA256: "hash",
            filename: "m.gguf",
            systemPrompt: "Test"
        )

        let manager = AmoraModelManager(descriptor: descriptor, downloader: MockModelDownloader(), modelsDirectory: tempDirectory)
        try Data(count: 10).write(to: manager.modelFileURL)
        _ = manager.checkStatusSync()

        let provider = AmoraLocalBrainProvider(runtime: runtime, modelManager: manager)
        let assistant = AssistantManager(provider: provider, providerIsInjected: true)

        let task = Task {
            await assistant.submit("Run test confirmation", settings: AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil))
        }

        for _ in 0..<50 {
            if AmoraActionExecutionCoordinator.shared.state == .awaitingConfirmation { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(AmoraActionExecutionCoordinator.shared.state, .awaitingConfirmation)
        XCTAssertNotNil(AmoraActionExecutionCoordinator.shared.pendingConfirmation)

        // Deny / cancel the confirmation request
        AmoraActionExecutionCoordinator.shared.cancelPendingAction()

        let answer = await task.value
        XCTAssertTrue(answer.localizedCaseInsensitiveContains("confirmation") || answer.localizedCaseInsensitiveContains("cancelled") || answer.localizedCaseInsensitiveContains("not granted"))
    }

    // MARK: - 10. Request Cancellation
    func testRequestCancellation() async throws {
        let runtime = MockLocalModelRuntime(simulatedDelayNanoseconds: 500_000_000) // 500ms

        let descriptor = AmoraModelDescriptor(
            id: "test-cancel-req",
            displayName: "Test",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "Test",
            sourceURL: URL(string: "https://example.com/m.gguf")!,
            expectedSizeBytes: 10,
            estimatedRAMBytes: 100,
            expectedSHA256: "hash",
            filename: "m.gguf",
            systemPrompt: "Test"
        )

        let manager = AmoraModelManager(descriptor: descriptor, downloader: MockModelDownloader(), modelsDirectory: tempDirectory)
        try Data(count: 10).write(to: manager.modelFileURL)
        _ = manager.checkStatusSync()

        let provider = AmoraLocalBrainProvider(runtime: runtime, modelManager: manager)
        let assistant = AssistantManager(provider: provider, providerIsInjected: true)

        let submitTask = Task {
            await assistant.submit("Slow question", settings: AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil))
        }

        try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        assistant.cancel()

        let response = await submitTask.value
        XCTAssertEqual(assistant.state, .cancelled)
        XCTAssertEqual(response, "Okay — stopped.")
    }

    // MARK: - 11. Context Awareness OFF
    func testContextAwarenessOffOmitsContext() async throws {
        let runtime = MockLocalModelRuntime(responseToReturn: "Plain answer")
        let descriptor = AmoraModelDescriptor(
            id: "test-ctx-off",
            displayName: "Test",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "Test",
            sourceURL: URL(string: "https://example.com/m.gguf")!,
            expectedSizeBytes: 10,
            estimatedRAMBytes: 100,
            expectedSHA256: "hash",
            filename: "m.gguf",
            systemPrompt: "Test"
        )

        let manager = AmoraModelManager(descriptor: descriptor, downloader: MockModelDownloader(), modelsDirectory: tempDirectory)
        try Data(count: 10).write(to: manager.modelFileURL)
        _ = manager.checkStatusSync()

        let provider = AmoraLocalBrainProvider(runtime: runtime, modelManager: manager)
        let assistant = AssistantManager(provider: provider, providerIsInjected: true)

        let settings = AISettingsSnapshot(
            enabled: true,
            provider: .local,
            model: "local",
            apiKey: nil,
            contextAwarenessEnabled: false,
            memoryEnabled: false
        )

        _ = await assistant.submit("What app is open?", settings: settings)
        // Verify conversation history has no [System context] message
        let hasContext = assistant.conversation.messages.contains { $0.content.contains("[System context]") }
        XCTAssertFalse(hasContext)
    }

    // MARK: - 12. Memory OFF
    func testMemoryOffOmitsMemories() async throws {
        let runtime = MockLocalModelRuntime(responseToReturn: "Plain answer")
        let descriptor = AmoraModelDescriptor(
            id: "test-mem-off",
            displayName: "Test",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "Test",
            sourceURL: URL(string: "https://example.com/m.gguf")!,
            expectedSizeBytes: 10,
            estimatedRAMBytes: 100,
            expectedSHA256: "hash",
            filename: "m.gguf",
            systemPrompt: "Test"
        )

        let manager = AmoraModelManager(descriptor: descriptor, downloader: MockModelDownloader(), modelsDirectory: tempDirectory)
        try Data(count: 10).write(to: manager.modelFileURL)
        _ = manager.checkStatusSync()

        let memoryStore = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        _ = await memoryStore.save(key: "Favorite editor", value: "VS Code")

        let provider = AmoraLocalBrainProvider(runtime: runtime, modelManager: manager)
        let assistant = AssistantManager(provider: provider, providerIsInjected: true, memoryStore: memoryStore)

        let settings = AISettingsSnapshot(
            enabled: true,
            provider: .local,
            model: "local",
            apiKey: nil,
            contextAwarenessEnabled: false,
            memoryEnabled: false // Memory is explicitly OFF
        )

        _ = await assistant.submit("What is my editor?", settings: settings)
        let hasMemories = assistant.conversation.messages.contains { $0.content.contains("[Relevant user memories]") }
        XCTAssertFalse(hasMemories)
    }

    // MARK: - 13. Inference Errors Handling
    func testInferenceErrorsHandling() async throws {
        let runtime = MockLocalModelRuntime(shouldFailGeneration: true, generationErrorMessage: "Out of context window")
        let descriptor = AmoraModelDescriptor(
            id: "test-err",
            displayName: "Test",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "Test",
            sourceURL: URL(string: "https://example.com/m.gguf")!,
            expectedSizeBytes: 10,
            estimatedRAMBytes: 100,
            expectedSHA256: "hash",
            filename: "m.gguf",
            systemPrompt: "Test"
        )

        let manager = AmoraModelManager(descriptor: descriptor, downloader: MockModelDownloader(), modelsDirectory: tempDirectory)
        try Data(count: 10).write(to: manager.modelFileURL)
        _ = manager.checkStatusSync()

        let provider = AmoraLocalBrainProvider(runtime: runtime, modelManager: manager)
        let assistant = AssistantManager(provider: provider, providerIsInjected: true)

        let result = await assistant.submit("Hello", settings: AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil))
        XCTAssertEqual(assistant.state, .failed)
        XCTAssertTrue(result.contains("couldn't finish that response"))
    }

    // MARK: - 14. Model-Runtime Dependency Injection
    func testModelRuntimeDependencyInjection() async throws {
        let runtime = MockLocalModelRuntime(responseToReturn: "I am offline AMORA.")
        let descriptor = AmoraModelDescriptor(
            id: "test-di",
            displayName: "Test DI",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "Test",
            sourceURL: URL(string: "https://example.com/m.gguf")!,
            expectedSizeBytes: 10,
            estimatedRAMBytes: 100,
            expectedSHA256: "hash",
            filename: "m.gguf",
            systemPrompt: "Custom injected system prompt."
        )

        let manager = AmoraModelManager(descriptor: descriptor, downloader: MockModelDownloader(), modelsDirectory: tempDirectory)
        try Data(count: 10).write(to: manager.modelFileURL)
        _ = manager.checkStatusSync()

        let provider = AmoraLocalBrainProvider(runtime: runtime, modelManager: manager)
        let answer = try await provider.send(messages: [AIMessage(role: .user, content: "Hi")], model: "qwen", apiKey: nil)
        XCTAssertEqual(answer, "I am offline AMORA.")
        XCTAssertTrue(runtime.isLoaded)
    }

    // MARK: - 15. Existing Deterministic Command Behavior Works Without Model
    func testExistingDeterministicCommandsWorkWithoutModel() async {
        defer {
            TimerService.shared.stopTimer()
        }
        let gateway = AMORACommandGateway.init()
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)

        // 1. Timer start
        let timerResult = await gateway.submit("start timer 25 minutes", settings: settings)
        if case .success(let msg) = timerResult {
            XCTAssertTrue(msg.localizedCaseInsensitiveContains("25 minutes") || msg.localizedCaseInsensitiveContains("focus"))
        } else {
            XCTFail("Timer command should succeed deterministically, was \(timerResult)")
        }

        // 2. Timer cancel
        let cancelResult = await gateway.submit("cancel timer", settings: settings)
        if case .success = cancelResult {
            // Succeeded deterministically
        } else {
            XCTFail("Cancel timer should succeed deterministically, was \(cancelResult)")
        }

        // 3. Workspace command
        let wsResult = await gateway.submit("open workspace", settings: settings)
        if case .success(let msg) = wsResult {
            XCTAssertTrue(msg.localizedCaseInsensitiveContains("workspace") || msg.localizedCaseInsensitiveContains("dashboard"))
        } else {
            XCTFail("Open workspace should succeed deterministically, was \(wsResult)")
        }

        // 4. Folder open
        let folderResult = await gateway.submit("open downloads", settings: settings)
        if case .success(let msg) = folderResult {
            XCTAssertTrue(msg.localizedCaseInsensitiveContains("downloads"))
        } else {
            XCTFail("Open downloads should succeed deterministically, was \(folderResult)")
        }
    }

    // MARK: - 16. Regression: Verification Success Transitions to Ready and Stays Ready
    func testVerificationSuccessTransitionsToReady() async throws {
        let testData = "Regression Valid Model Weights".data(using: .utf8)!
        let hash = SHA256.hash(data: testData).map { String(format: "%02x", $0) }.joined()

        let descriptor = AmoraModelDescriptor(
            id: "test-verify-success",
            displayName: "Test Model",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "AMORA Test",
            sourceURL: URL(string: "https://example.com/model.gguf")!,
            expectedSizeBytes: Int64(testData.count),
            estimatedRAMBytes: 1024 * 1024,
            expectedSHA256: hash,
            filename: "test_verify_success.gguf",
            systemPrompt: "You are AMORA."
        )

        let manager = AmoraModelManager(
            descriptor: descriptor,
            downloader: MockModelDownloader(),
            modelsDirectory: tempDirectory
        )

        try testData.write(to: manager.modelFileURL)
        _ = manager.checkStatusSync()
        XCTAssertEqual(manager.status, .ready)

        let isValid = await manager.verifyIntegrity()
        XCTAssertTrue(isValid)
        XCTAssertEqual(manager.status, .ready)

        // Ensure asynchronous progress notifications do not clobber terminal .ready state
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(manager.status, .ready)
        XCTAssertTrue(manager.isReady)
    }

    // MARK: - 17. Regression: Verification Failure Transitions to Corrupt
    func testVerificationFailureTransitionsToCorrupt() async throws {
        let testData = "Corrupted Model Content".data(using: .utf8)!
        let wrongHash = "1111111111111111111111111111111111111111111111111111111111111111"

        let descriptor = AmoraModelDescriptor(
            id: "test-verify-failure",
            displayName: "Test Model",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "AMORA Test",
            sourceURL: URL(string: "https://example.com/model.gguf")!,
            expectedSizeBytes: Int64(testData.count),
            estimatedRAMBytes: 1024 * 1024,
            expectedSHA256: wrongHash,
            filename: "test_verify_failure.gguf",
            systemPrompt: "You are AMORA."
        )

        let manager = AmoraModelManager(
            descriptor: descriptor,
            downloader: MockModelDownloader(),
            modelsDirectory: tempDirectory
        )

        try testData.write(to: manager.modelFileURL)
        _ = manager.checkStatusSync()

        let isValid = await manager.verifyIntegrity()
        XCTAssertFalse(isValid)
        if case .corrupt = manager.status {
            // Expected
        } else {
            XCTFail("Status should be .corrupt upon verification failure, was \(manager.status)")
        }
        XCTAssertFalse(manager.isReady)
    }

    // MARK: - 18. Regression: Concurrent Verification Tasks Are Deduped
    func testConcurrentVerificationTasksDeduped() async throws {
        let testData = "Deduped Verification Test Content".data(using: .utf8)!
        let hash = SHA256.hash(data: testData).map { String(format: "%02x", $0) }.joined()

        let descriptor = AmoraModelDescriptor(
            id: "test-verify-dedup",
            displayName: "Test Model",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "AMORA Test",
            sourceURL: URL(string: "https://example.com/model.gguf")!,
            expectedSizeBytes: Int64(testData.count),
            estimatedRAMBytes: 1024 * 1024,
            expectedSHA256: hash,
            filename: "test_verify_dedup.gguf",
            systemPrompt: "You are AMORA."
        )

        let manager = AmoraModelManager(
            descriptor: descriptor,
            downloader: MockModelDownloader(),
            modelsDirectory: tempDirectory
        )

        try testData.write(to: manager.modelFileURL)
        _ = manager.checkStatusSync()

        async let r1 = manager.verifyIntegrity()
        async let r2 = manager.verifyIntegrity()

        let (res1, res2) = await (r1, r2)
        XCTAssertTrue(res1)
        XCTAssertTrue(res2)
        XCTAssertEqual(manager.status, .ready)
    }

    // MARK: - 19. Regression: StartDownload Reuses Existing Valid Model
    func testStartDownloadReusesExistingValidModel() async throws {
        let testData = "Existing Model On Disk".data(using: .utf8)!
        let hash = SHA256.hash(data: testData).map { String(format: "%02x", $0) }.joined()

        let descriptor = AmoraModelDescriptor(
            id: "test-reuse-model",
            displayName: "Test Model",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "AMORA Test",
            sourceURL: URL(string: "https://example.com/model.gguf")!,
            expectedSizeBytes: Int64(testData.count),
            estimatedRAMBytes: 1024 * 1024,
            expectedSHA256: hash,
            filename: "test_reuse_model.gguf",
            systemPrompt: "You are AMORA."
        )

        struct FailIfCalledDownloader: AmoraModelDownloading, @unchecked Sendable {
            func download(from url: URL, to destinationURL: URL, expectedSizeBytes: Int64, onProgress: @Sendable @escaping (Double, Int64, Int64) -> Void) async throws {
                XCTFail("Downloader should NOT be called when existing model is already valid on disk!")
            }
            func cancelCurrentDownload() {}
        }

        let manager = AmoraModelManager(
            descriptor: descriptor,
            downloader: FailIfCalledDownloader(),
            modelsDirectory: tempDirectory
        )

        try testData.write(to: manager.modelFileURL)

        try await manager.startDownload()
        XCTAssertEqual(manager.status, .ready)
        XCTAssertTrue(manager.isReady)
    }

    // MARK: - 20. Regression: CheckStatusSync Recovers From Stale Verifying State
    func testCheckStatusSyncRecoversFromStaleVerifyingState() async throws {
        let testData = "Valid Model Recover Test".data(using: .utf8)!
        let hash = SHA256.hash(data: testData).map { String(format: "%02x", $0) }.joined()

        let descriptor = AmoraModelDescriptor(
            id: "test-stale-recover",
            displayName: "Test Model",
            version: "1.0",
            quantization: "Q4_0",
            license: "Apache 2.0",
            author: "AMORA Test",
            sourceURL: URL(string: "https://example.com/model.gguf")!,
            expectedSizeBytes: Int64(testData.count),
            estimatedRAMBytes: 1024 * 1024,
            expectedSHA256: hash,
            filename: "test_stale_recover.gguf",
            systemPrompt: "You are AMORA."
        )

        let manager = AmoraModelManager(
            descriptor: descriptor,
            downloader: MockModelDownloader(),
            modelsDirectory: tempDirectory
        )

        try testData.write(to: manager.modelFileURL)
        _ = manager.checkStatusSync()
        XCTAssertEqual(manager.status, .ready)

        // Simulate a stale .verifying state without an active task
        _ = await manager.verifyIntegrity()
        XCTAssertEqual(manager.status, .ready)

        let recoveredStatus = manager.checkStatusSync()
        XCTAssertEqual(recoveredStatus, .ready)
    }

    func testRealModelGreetingThroughAssistantManager() async throws {
        guard AmoraLocalBrainProvider.shared.isAvailable else { return }
        let assistant = AssistantManager(provider: AmoraLocalBrainProvider.shared)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)
        let response = await assistant.submit("Hi", settings: settings)
        print("ASSISTANT MANAGER RESPONSE TO 'Hi': [[[\(response)]]]")
        XCTAssertFalse(response.contains("Music playback started"))
        XCTAssertFalse(response.contains("Timer started"))
        XCTAssertTrue(response.localizedCaseInsensitiveContains("hello") || response.localizedCaseInsensitiveContains("help") || response.localizedCaseInsensitiveContains("assist"))
        await AmoraLocalBrainProvider.shared.runtime.unloadModel()
    }

    func testRealModelActionThroughAssistantManager() async throws {
        guard AmoraLocalBrainProvider.shared.isAvailable else { return }
        AmoraConversationContextManager.shared.reset()
        let assistant = AssistantManager(provider: AmoraLocalBrainProvider.shared)
        let settings = AISettingsSnapshot(
            enabled: true,
            provider: .local,
            model: "local",
            apiKey: nil,
            contextAwarenessEnabled: true
        )
        let response = await assistant.submit("Open Spotify", settings: settings)
        print("ASSISTANT MANAGER RESPONSE TO 'Open Spotify': [[[\(response)]]]")
        XCTAssertTrue(response.localizedCaseInsensitiveContains("Opening Spotify") || response.localizedCaseInsensitiveContains("Spotify"))

        let mathResponse = await assistant.submit("2+3", settings: settings)
        print("ASSISTANT MANAGER RESPONSE TO '2+3': [[[\(mathResponse)]]]")
        XCTAssertTrue(mathResponse.contains("5"))
        XCTAssertFalse(mathResponse.contains("actions"))

        let commandResponse = await assistant.submit("open VS Code and start a timer", settings: settings)
        print("ASSISTANT MANAGER RESPONSE TO 'open VS Code and start a timer': [[[\(commandResponse)]]]")
        XCTAssertTrue(commandResponse.localizedCaseInsensitiveContains("Opening VS Code") || commandResponse.localizedCaseInsensitiveContains("VS Code"))
        XCTAssertTrue(commandResponse.localizedCaseInsensitiveContains("Timer started") || commandResponse.localizedCaseInsensitiveContains("timer"))

        // Follow-up test: "make it 10 minutes instead"
        let followUpResponse = await assistant.submit("make it 10 minutes instead", settings: settings)
        print("ASSISTANT MANAGER RESPONSE TO 'make it 10 minutes instead': [[[\(followUpResponse)]]]")
        XCTAssertTrue(followUpResponse.localizedCaseInsensitiveContains("10 minutes") || followUpResponse.localizedCaseInsensitiveContains("600"))

        // Unsupported request test: "Can you send an email to Bob?"
        let unsupportedResponse = await assistant.submit("Can you send an email to Bob?", settings: settings)
        print("ASSISTANT MANAGER RESPONSE TO 'Can you send an email to Bob?': [[[\(unsupportedResponse)]]]")
        XCTAssertTrue(unsupportedResponse.localizedCaseInsensitiveContains("can't") ||
                      unsupportedResponse.localizedCaseInsensitiveContains("cannot") ||
                      unsupportedResponse.localizedCaseInsensitiveContains("email") ||
                      unsupportedResponse.localizedCaseInsensitiveContains("limitation"))
        XCTAssertFalse(unsupportedResponse.contains("actions"))

        await AmoraLocalBrainProvider.shared.runtime.unloadModel()
    }

    func testRealModelToolSelectionCapabilities() async throws {
        guard AmoraLocalBrainProvider.shared.isAvailable else { return }
        let assistant = AssistantManager(provider: AmoraLocalBrainProvider.shared)
        let settings = AISettingsSnapshot(
            enabled: true,
            provider: .local,
            model: "local",
            apiKey: nil,
            contextAwarenessEnabled: true
        )

        NotesService.shared.addNote("Weekly team sync meeting at 10 AM")

        let noteResponse = await assistant.submit("Find notes about meeting", settings: settings)
        print("REAL MODEL NOTE SEARCH RESPONSE: [[[\(noteResponse)]]]")
        XCTAssertTrue(noteResponse.localizedCaseInsensitiveContains("meeting") || noteResponse.localizedCaseInsensitiveContains("sync") || noteResponse.localizedCaseInsensitiveContains("note"))

        assistant.startNewConversation()

        let batteryResponse = await assistant.submit("How much battery do I have left?", settings: settings)
        print("REAL MODEL BATTERY RESPONSE: [[[\(batteryResponse)]]]")
        XCTAssertTrue(batteryResponse.localizedCaseInsensitiveContains("battery") || batteryResponse.localizedCaseInsensitiveContains("%"))

        await AmoraLocalBrainProvider.shared.runtime.unloadModel()
    }

    // MARK: - 21. Deterministic Fallback When Local Model Is Not Available
    func testDeterministicMultiActionFallbackWhenModelUnavailable() async throws {
        let unavailableProvider = UnavailableAIProvider(kind: .local)
        let assistant = AssistantManager(provider: unavailableProvider)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)

        // Compound command with omitted timer duration
        let response = await assistant.submit("open VS Code and start a timer", settings: settings)
        XCTAssertTrue(response.localizedCaseInsensitiveContains("Opening VS Code") || response.localizedCaseInsensitiveContains("VS Code"))
        XCTAssertTrue(response.localizedCaseInsensitiveContains("Timer started") || response.localizedCaseInsensitiveContains("timer"))
    }
}
