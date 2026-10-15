import XCTest
@testable import AMORA

@MainActor
final class PreBetaStabilityTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
    }

    override func tearDown() async throws {
        try await super.tearDown()
    }

    // MARK: - 1. Keychain Credential Lifecycle & Bugfix Verification

    func testKeychainCredentialLifecycleAndOverwriteBugfix() {
        let testKey = "prebeta_test_api_key_\(UUID().uuidString)"
        defer {
            _ = StorageManager.shared.deleteSecureItem(forKey: testKey)
        }

        // 1. Initial write
        let write1 = StorageManager.shared.setSecureItem("sk-initial-12345", forKey: testKey)
        XCTAssertTrue(write1, "Initial write to Keychain should succeed")
        let read1 = StorageManager.shared.getSecureItem(forKey: testKey)
        XCTAssertEqual(read1, "sk-initial-12345", "Read back should match initial value")

        // 2. Overwrite / Update with new key (previously failed with errSecDuplicateItem)
        let write2 = StorageManager.shared.setSecureItem("sk-updated-67890", forKey: testKey)
        XCTAssertTrue(write2, "Updating existing Keychain item to new value must succeed")
        let read2 = StorageManager.shared.getSecureItem(forKey: testKey)
        XCTAssertEqual(read2, "sk-updated-67890", "Read back must reflect the newly updated key")

        // 3. Clear key with empty string
        let writeEmpty = StorageManager.shared.setSecureItem("", forKey: testKey)
        XCTAssertTrue(writeEmpty, "Setting empty string should cleanly remove the credential")
        let readEmpty = StorageManager.shared.getSecureItem(forKey: testKey)
        XCTAssertNil(readEmpty, "Credential should be absent after setting empty value")

        // 4. Deletion idempotency
        let deleteAgain = StorageManager.shared.deleteSecureItem(forKey: testKey)
        XCTAssertTrue(deleteAgain, "Deleting a non-existent item should return true without error")
    }

    // MARK: - 2. Fresh User Data & Clean Install Isolation

    func testCleanInstallIsolatedMemoryStorage() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("memories.json")
        let storage = AmoraFileMemoryStorage(fileURL: fileURL)

        // 1. Fresh install load on non-existent file
        let initialItems = await storage.load()
        XCTAssertTrue(initialItems.isEmpty, "Fresh install with no memory file should return empty array without error")
        let unquarantined = await storage.hasUnquarantinedCorruptOriginal
        XCTAssertFalse(unquarantined)

        // 2. Fresh install save
        let testItem = AmoraMemoryItem(key: "test_key", value: "test_value")
        try await storage.save([testItem])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Memory file should be created atomically")

        // 3. Reload
        let reloaded = await storage.load()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.key, "test_key")
    }

    func testCleanInstallIsolatedAutomationStorage() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("automations.json")
        let storage = AmoraFileAutomationStorage(fileURL: fileURL)

        // 1. Fresh load on non-existent file
        let initialItems = await storage.load()
        XCTAssertTrue(initialItems.isEmpty, "Fresh install with no automations file should return empty array without error")

        // 2. Fresh save
        let auto = AmoraAutomation(
            name: "Test Fresh Auto",
            trigger: .timerCompletion,
            action: .showNotification(message: "Take a break")
        )
        try await storage.save([auto])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // 3. Reload
        let reloaded = await storage.load()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.name, "Test Fresh Auto")
    }

    func testCleanInstallIsolatedModelManager() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = AmoraModelManager(modelsDirectory: tempDir)
        let status = manager.checkStatusSync()
        XCTAssertEqual(status, .notInstalled, "Fresh install should report model .notInstalled")
        XCTAssertFalse(manager.isReady, "Model manager should not be ready on fresh install")
    }

    func testCleanInstallIsolatedNotesService() {
        let service = NotesService.shared
        service.useIsolatedStorage(suiteName: "com.amora.prebeta.test.notes.\(UUID().uuidString)")
        defer {
            service.clearAll()
            service.restoreStandardStorage()
        }

        XCTAssertTrue(service.notes.isEmpty, "Isolated notes service should start empty")
        service.addNote("Beta verification note")
        XCTAssertEqual(service.notes.count, 1)
        XCTAssertEqual(service.notes.first?.text, "Beta verification note")

        let search = service.searchNotes(query: "verification")
        XCTAssertEqual(search.count, 1)

        service.clearAll()
        XCTAssertTrue(service.notes.isEmpty)
    }

    // MARK: - 3. Privacy Guards (Clipboard Enforcement)

    func testClipboardServicePrivacyGuard() {
        let settings = AppState.shared.settings
        let initialSetting = settings.clipboardEnabled
        defer {
            settings.clipboardEnabled = initialSetting
        }

        // Explicitly disable clipboard
        settings.clipboardEnabled = false
        ClipboardService.shared.clearHistory()
        XCTAssertTrue(ClipboardService.shared.history.isEmpty)

        // Simulate clipboard check while disabled
        ClipboardService.shared.checkClipboard()
        XCTAssertTrue(
            ClipboardService.shared.history.isEmpty,
            "ClipboardService must never record pasteboard items when clipboardEnabled is false"
        )
    }

    // MARK: - 4. Lifecycle & Relaunch Recovery

    func testAutomationRelaunchRecoveryCatchesMissedRuns() async throws {
        let calendar = Calendar.current
        let referenceNow = Date()
        let pastDate = referenceNow.addingTimeInterval(-3600) // 1 hour ago

        let missedAutomation = AmoraAutomation(
            name: "Hourly Reminder",
            trigger: .interval(seconds: 3600),
            action: .showNotification(message: "Drink water!"),
            enabled: true,
            createdAt: pastDate.addingTimeInterval(-7200),
            updatedAt: pastDate.addingTimeInterval(-7200),
            nextRunAt: pastDate,
            calendar: calendar
        )

        let inMemoryStorage = AmoraInMemoryAutomationStorage(initialItems: [missedAutomation])
        let inMemoryStore = AmoraAutomationStore(storage: inMemoryStorage)
        let service = AmoraAutomationService(
            store: inMemoryStore,
            clock: { referenceNow },
            calendar: calendar
        )

        await service.load()
        XCTAssertEqual(service.automations.count, 1)

        // Relaunch recovery should catch the missed automation and advance its nextRunAt
        await service.recoverAfterRelaunch(now: referenceNow)

        let updatedList = service.automations
        XCTAssertEqual(updatedList.count, 1)
        if let nextRun = updatedList.first?.nextRunAt {
            XCTAssertGreaterThan(nextRun, referenceNow, "Missed automation's nextRunAt should have advanced past reference now")
        } else {
            XCTFail("Recurring automation should still have a nextRunAt scheduled")
        }
    }

    // MARK: - 5. AppState Lifecycle Teardown

    func testAppStateTerminationTeardownDoesNotCrash() {
        // Verify handleTerminate runs synchronously without exceptions or deadlocks
        AppState.shared.handleTerminate()
        AppState.shared.handleLaunch()
        // Launched event triggers greeting reaction which transitions state to .happy
        XCTAssertTrue(AppState.shared.stateManager.currentState == .happy || AppState.shared.stateManager.currentState == .idle)
    }
}
