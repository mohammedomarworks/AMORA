import XCTest
@testable import AMORA

@MainActor
final class FreshInstallAITests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        AppleOnDeviceAvailability.reset()
    }

    override func tearDown() async throws {
        AppleOnDeviceAvailability.reset()
        try await super.tearDown()
    }

    // MARK: - Mock Availability Checker

    private struct MockAppleAvailabilityChecker: AppleOnDeviceAvailabilityChecking {
        let supported: Bool
        let status: AIAvailability

        func isSupported() -> Bool { supported }
        func availability() -> AIAvailability { status }
    }

    // MARK: - 1. Fresh-Install Provider Resolution (Unsupported Apple AI)

    func testFreshInstallProviderResolutionWhenAppleUnsupported() {
        AppleOnDeviceAvailability.current = MockAppleAvailabilityChecker(supported: false, status: .unsupported)

        let suiteName = "com.amora.tests.freshinstall.unsupported.\(UUID().uuidString)"
        guard let testDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults")
            return
        }
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        // Clean-state defaults (no saved AMORA_aiProvider)
        XCTAssertNil(testDefaults.string(forKey: "AMORA_aiProvider"))

        let store = SettingsStore()
        store.load(defaults: testDefaults)

        XCTAssertEqual(store.aiProvider, AIProviderKind.local.rawValue, "Fresh install on unsupported macOS must fall back to .local")
        XCTAssertEqual(store.aiModel, AmoraModelDescriptor.defaultModel.id, "Fresh install fallback to .local must use default offline model ID")
    }

    // MARK: - 2. Fresh-Install Provider Resolution (Supported Apple AI)

    func testFreshInstallProviderResolutionWhenAppleSupported() {
        AppleOnDeviceAvailability.current = MockAppleAvailabilityChecker(supported: true, status: .available)

        let suiteName = "com.amora.tests.freshinstall.supported.\(UUID().uuidString)"
        guard let testDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults")
            return
        }
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        XCTAssertNil(testDefaults.string(forKey: "AMORA_aiProvider"))

        let store = SettingsStore()
        store.load(defaults: testDefaults)

        XCTAssertEqual(store.aiProvider, AIProviderKind.appleOnDevice.rawValue, "Fresh install on supported platform defaults to appleOnDevice")
        XCTAssertEqual(store.aiModel, "apple-on-device")
    }

    // MARK: - 3. Preservation of Saved Preferences for Existing Users

    func testPreservationOfExplicitlySavedProviderChoices() {
        // Even when current OS reports Apple On-Device unsupported...
        AppleOnDeviceAvailability.current = MockAppleAvailabilityChecker(supported: false, status: .unsupported)

        let providersToTest = [
            AIProviderKind.appleOnDevice.rawValue,
            "anthropic",
            "openai",
            AIProviderKind.local.rawValue,
            AIProviderKind.none.rawValue
        ]

        for provider in providersToTest {
            let suiteName = "com.amora.tests.existing.\(UUID().uuidString)"
            guard let testDefaults = UserDefaults(suiteName: suiteName) else { continue }
            defer { testDefaults.removePersistentDomain(forName: suiteName) }

            // User previously saved this provider choice
            testDefaults.set(provider, forKey: "AMORA_aiProvider")
            testDefaults.set("custom-saved-model", forKey: "AMORA_aiModel")
            testDefaults.set(true, forKey: "AMORA_hasCompletedFirstRun")

            let store = SettingsStore()
            store.load(defaults: testDefaults)

            XCTAssertEqual(
                store.aiProvider,
                provider,
                "Explicitly saved provider '\(provider)' must be preserved and never overwritten by fallback logic"
            )
            XCTAssertEqual(store.aiModel, "custom-saved-model")
            XCTAssertTrue(store.hasCompletedFirstRun)
        }
    }

    // MARK: - 4. Missing Model Setup Path

    func testMissingModelSetupPathProvidesClearGuidance() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Model manager in an empty isolated directory has .notInstalled status
        let isolatedManager = AmoraModelManager(modelsDirectory: tempDir)
        XCTAssertFalse(isolatedManager.isReady)
        XCTAssertEqual(isolatedManager.status, .notInstalled)

        let provider = AmoraLocalBrainProvider(modelManager: isolatedManager)
        XCTAssertEqual(provider.kind, .local)
        XCTAssertFalse(provider.isAvailable)
        XCTAssertEqual(provider.availability, .modelNotReady)

        let snapshot = AISettingsSnapshot(
            enabled: true,
            provider: .local,
            model: AmoraModelDescriptor.defaultModel.id,
            apiKey: nil
        )

        let assistant = AssistantManager(provider: provider)
        let response = await assistant.submit("What can you do?", settings: snapshot)

        XCTAssertTrue(
            response.contains("AMORA's local brain is not set up yet"),
            "When offline model is missing, assistant must give actionable setup guidance"
        )
        XCTAssertEqual(assistant.state, .failed)
        XCTAssertEqual(assistant.lastError, .modelNotReady)
    }

    // MARK: - 5. Unsupported Apple Provider Explains Local Brain

    func testUnsupportedAppleProviderMessageExplainsLocalBrain() async {
        AppleOnDeviceAvailability.current = MockAppleAvailabilityChecker(supported: false, status: .unsupported)

        let snapshot = AISettingsSnapshot(
            enabled: true,
            provider: .appleOnDevice,
            model: "apple-on-device",
            apiKey: nil
        )

        let provider = AIProviderFactory.make(for: snapshot)
        XCTAssertEqual(provider.kind, .appleOnDevice)
        XCTAssertFalse(provider.isAvailable)
        XCTAssertEqual(provider.availability, .unsupported)

        let assistant = AssistantManager(provider: provider)
        let response = await assistant.submit("Tell me a story", settings: snapshot)

        XCTAssertTrue(
            response.contains("Apple on-device AI is unsupported on this macOS version"),
            "Unsupported Apple AI must clearly explain platform incompatibility"
        )
        XCTAssertTrue(
            response.contains("AMORA Local Brain"),
            "Message must guide user toward AMORA Local Brain as the alternative"
        )
        XCTAssertEqual(assistant.state, .failed)
    }

    // MARK: - 6. First Run Persistence

    func testSettingsSaveAndFirstRunMarking() {
        let suiteName = "com.amora.tests.firstrun.\(UUID().uuidString)"
        guard let testDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults")
            return
        }
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore()
        XCTAssertFalse(store.hasCompletedFirstRun)

        store.hasCompletedFirstRun = true
        store.save(defaults: testDefaults)

        XCTAssertTrue(testDefaults.bool(forKey: "AMORA_hasCompletedFirstRun"))
        XCTAssertEqual(testDefaults.string(forKey: "AMORA_aiProvider"), store.aiProvider)
    }
}
