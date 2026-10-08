import XCTest
@testable import AMORA

final class MemoryV1Tests: XCTestCase {

    // Helper capturing provider to inspect prompt messages
    private final class CaptureAIProvider: AIProvider, @unchecked Sendable {
        let kind: AIProviderKind = .local
        var isAvailable: Bool = true
        var availability: AIAvailability = .available
        var capturedMessages: [AIMessage] = []

        func send(messages: [AIMessage], model: String, apiKey: String?) async throws -> String {
            self.capturedMessages = messages
            return "Test response"
        }
    }

    // MARK: - 1. Save Test
    func testSave() async {
        let storage = AmoraInMemoryStorage()
        let store = AmoraMemoryStore(storage: storage)

        let item = await store.save(key: "editor", value: "VS Code")
        XCTAssertEqual(item.key, "editor")
        XCTAssertEqual(item.value, "VS Code")

        let retrieved = await store.get(id: item.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.key, "editor")
        XCTAssertEqual(retrieved?.value, "VS Code")

        let byKey = await store.get(key: "editor")
        XCTAssertNotNil(byKey)
        XCTAssertEqual(byKey?.id, item.id)
    }

    // MARK: - 2. Update Existing Memory Test
    func testUpdateExistingMemory() async {
        let storage = AmoraInMemoryStorage()
        let store = AmoraMemoryStore(storage: storage)

        let first = await store.save(key: "favorite editor", value: "VS Code")
        let list1 = await store.list()
        XCTAssertEqual(list1.count, 1)
        XCTAssertEqual(list1.first?.value, "VS Code")

        // Small delay to ensure timestamp resolution
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Save with matching key (different case)
        let updated = await store.save(key: "Favorite Editor", value: "Sublime Text")
        let list2 = await store.list()
        XCTAssertEqual(list2.count, 1)
        XCTAssertEqual(list2.first?.id, first.id)
        XCTAssertEqual(list2.first?.value, "Sublime Text")
        XCTAssertGreaterThanOrEqual(updated.updatedAt, first.createdAt)
    }

    // MARK: - 3. List Test
    func testList() async {
        let storage = AmoraInMemoryStorage()
        let store = AmoraMemoryStore(storage: storage)

        let emptyList = await store.list()
        XCTAssertTrue(emptyList.isEmpty)

        _ = await store.save(key: "music", value: "Spotify")
        _ = await store.save(key: "editor", value: "VS Code")
        _ = await store.save(key: "browser", value: "Chrome")

        let items = await store.list()
        XCTAssertEqual(items.count, 3)
        let keys = items.map(\.key)
        XCTAssertTrue(keys.contains("music"))
        XCTAssertTrue(keys.contains("editor"))
        XCTAssertTrue(keys.contains("browser"))
    }

    // MARK: - 4. Relevant Memory Retrieval Test
    func testRelevantMemoryRetrieval() async {
        let storage = AmoraInMemoryStorage()
        let store = AmoraMemoryStore(storage: storage)

        _ = await store.save(key: "music", value: "I use Spotify")
        _ = await store.save(key: "favorite editor", value: "VS Code")
        _ = await store.save(key: "pet", value: "I have a dog named Milo")

        // Music query
        let musicMatches = await store.relevantMemories(for: "What music app should I open?", limit: 3)
        XCTAssertFalse(musicMatches.isEmpty)
        XCTAssertEqual(musicMatches.first?.key, "music")

        // Editor query
        let editorMatches = await store.relevantMemories(for: "Which editor do I prefer?", limit: 3)
        XCTAssertFalse(editorMatches.isEmpty)
        XCTAssertEqual(editorMatches.first?.key, "favorite editor")

        // Pet query
        let petMatches = await store.relevantMemories(for: "Tell me about my dog", limit: 3)
        XCTAssertFalse(petMatches.isEmpty)
        XCTAssertEqual(petMatches.first?.key, "pet")

        // Irrelevant query must return empty list (never blind injection)
        let irrelevant = await store.relevantMemories(for: "What is the capital of Japan?", limit: 3)
        XCTAssertTrue(irrelevant.isEmpty)

        // Limit works
        let limited = await store.relevantMemories(for: "music", limit: 1)
        XCTAssertEqual(limited.count, 1)
    }

    // MARK: - 5. Delete Test
    func testDelete() async {
        let storage = AmoraInMemoryStorage()
        let store = AmoraMemoryStore(storage: storage)

        let item1 = await store.save(key: "music", value: "Spotify")
        let item2 = await store.save(key: "editor", value: "VS Code")
        let initialList = await store.list()
        XCTAssertEqual(initialList.count, 2)

        // Delete by ID
        let deleted1 = await store.delete(id: item1.id)
        XCTAssertTrue(deleted1)
        let listAfterDelete1 = await store.list()
        XCTAssertEqual(listAfterDelete1.count, 1)
        let item1Retrieved = await store.get(id: item1.id)
        XCTAssertNil(item1Retrieved)

        // Delete non-existent ID
        let deletedMissing = await store.delete(id: UUID())
        XCTAssertFalse(deletedMissing)

        // Delete matching query
        let deletedByQuery = await store.deleteMatching(query: "VS Code")
        XCTAssertEqual(deletedByQuery.count, 1)
        XCTAssertEqual(deletedByQuery.first?.id, item2.id)
        let finalList = await store.list()
        XCTAssertTrue(finalList.isEmpty)
    }

    // MARK: - 6. Clear All Test
    func testClearAll() async {
        let storage = AmoraInMemoryStorage()
        let store = AmoraMemoryStore(storage: storage)

        _ = await store.save(key: "music", value: "Spotify")
        _ = await store.save(key: "editor", value: "VS Code")
        _ = await store.save(key: "city", value: "Berlin")
        let initialList = await store.list()
        XCTAssertEqual(initialList.count, 3)

        await store.clearAll()
        let clearedList = await store.list()
        XCTAssertTrue(clearedList.isEmpty)
    }

    // MARK: - 7. Persistence and Reload Test
    func testPersistenceAndReload() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("amora_mem_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Session 1: save
        let storage1 = AmoraFileMemoryStorage(fileURL: tempURL)
        let store1 = AmoraMemoryStore(storage: storage1)
        _ = await store1.save(key: "music", value: "Spotify")
        _ = await store1.save(key: "editor", value: "VS Code")

        // Session 2: reload from same file URL
        let storage2 = AmoraFileMemoryStorage(fileURL: tempURL)
        let store2 = AmoraMemoryStore(storage: storage2)
        let reloaded = await store2.list()

        XCTAssertEqual(reloaded.count, 2)
        XCTAssertTrue(reloaded.contains(where: { $0.key == "music" && $0.value == "Spotify" }))
        XCTAssertTrue(reloaded.contains(where: { $0.key == "editor" && $0.value == "VS Code" }))
    }

    // MARK: - 8. Corrupt Storage Recovery Test
    func testCorruptStorageRecovery() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("amora_corrupt_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Write corrupt JSON bytes
        let corruptData = Data("!!! This is definitely not valid JSON {{{".utf8)
        try corruptData.write(to: tempURL)

        // Storage load recovers gracefully and returns empty array
        let storage = AmoraFileMemoryStorage(fileURL: tempURL)
        let loaded = await storage.load()
        XCTAssertTrue(loaded.isEmpty)

        // Store can now save valid items safely
        let store = AmoraMemoryStore(storage: storage)
        let saved = await store.save(key: "editor", value: "VS Code")
        XCTAssertEqual(saved.value, "VS Code")

        let reloaded = await store.list()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.key, "editor")
    }

    // MARK: - 9. Explicit-Only Saving Test
    @MainActor
    func testExplicitOnlySaving() async {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        let assistant = AssistantManager(provider: MockAIProvider(response: "I see."), providerIsInjected: true, memoryStore: store)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil, memoryEnabled: true)

        // Normal conversation sentences must NOT trigger memory creation
        let normal1 = "I use Spotify for all my playlists."
        XCTAssertNil(AmoraMemoryCommandParser.shared.parse(normal1))
        _ = await assistant.submit(normal1, settings: settings)
        let list1 = await store.list()
        XCTAssertTrue(list1.isEmpty)

        let normal2 = "My favorite editor is VS Code and I love Swift."
        XCTAssertNil(AmoraMemoryCommandParser.shared.parse(normal2))
        _ = await assistant.submit(normal2, settings: settings)
        let list2 = await store.list()
        XCTAssertTrue(list2.isEmpty)

        // Explicit command saves
        let explicit = "Remember that I use Spotify."
        let parsed = AmoraMemoryCommandParser.shared.parse(explicit)
        XCTAssertNotNil(parsed)
        let answer = await assistant.submit(explicit, settings: settings)
        XCTAssertTrue(answer.contains("remember") || answer.contains("Spotify"))

        let savedItems = await store.list()
        XCTAssertEqual(savedItems.count, 1)
        XCTAssertEqual(savedItems.first?.value, "I use Spotify")
    }

    // MARK: - 10. Sensitive-Memory Rejection Test
    @MainActor
    func testSensitiveMemoryRejection() async {
        let validator = AmoraMemoryPrivacyValidator.shared

        // Passwords & Credentials
        XCTAssertEqual(validator.validate(key: "password", value: "hunter2"),
                       .rejected(reason: "I can't save sensitive credentials or passwords to protect your privacy."))
        XCTAssertEqual(validator.validate(text: "Remember my passcode is 1234"),
                       .rejected(reason: "I can't save sensitive credentials or passcodes to protect your privacy."))

        // API Keys & Tokens
        let keyResult = validator.validate(text: "Remember my API key is sk-1234567890abcdef12345")
        if case .rejected = keyResult {} else { XCTFail("Expected API key rejection") }

        let patResult = validator.validate(text: "Remember my GitHub token is ghp_1234567890abcdef12345")
        if case .rejected = patResult {} else { XCTFail("Expected token rejection") }

        // Financial Secrets
        let ccResult = validator.validate(text: "Remember my credit card is 4111 2222 3333 4444")
        if case .rejected = ccResult {} else { XCTFail("Expected credit card rejection") }

        let ssnResult = validator.validate(text: "Remember my SSN is 123-45-6789")
        if case .rejected = ssnResult {} else { XCTFail("Expected SSN rejection") }

        // Health Data
        let healthResult = validator.validate(text: "Remember my prescription dose is 50mg insulin")
        if case .rejected = healthResult {} else { XCTFail("Expected health data rejection") }

        // Raw capture / Keystrokes / Clipboard
        let clipResult = validator.validate(text: "Remember my clipboard contents")
        if case .rejected = clipResult {} else { XCTFail("Expected clipboard rejection") }

        let keyloggerResult = validator.validate(text: "Remember my keystrokes from today")
        if case .rejected = keyloggerResult {} else { XCTFail("Expected keystroke rejection") }

        // End-to-end rejection via AssistantManager
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        let assistant = AssistantManager(provider: MockAIProvider(), providerIsInjected: true, memoryStore: store)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil, memoryEnabled: true)

        let response = await assistant.submit("Remember that my password is secret123", settings: settings)
        XCTAssertTrue(response.contains("protect your privacy") || response.contains("can't save"))
        let listAfterSensitive = await store.list()
        XCTAssertTrue(listAfterSensitive.isEmpty)
    }

    // MARK: - 11. Memory OFF Behavior Test
    @MainActor
    func testMemoryOffBehavior() async {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        _ = await store.save(key: "music", value: "Spotify")

        let captureProvider = CaptureAIProvider()
        let assistant = AssistantManager(provider: captureProvider, providerIsInjected: true, memoryStore: store)
        let settingsOff = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil, memoryEnabled: false)

        // 1. Remember command is rejected when Memory is OFF
        let rememberResp = await assistant.submit("Remember that I use VS Code", settings: settingsOff)
        XCTAssertTrue(rememberResp.contains("turned off in Settings"))
        let vsCodeItem = await store.get(key: "VS Code")
        XCTAssertNil(vsCodeItem)

        // 2. Listing is prevented when Memory is OFF
        let listResp = await assistant.submit("What do you remember about me?", settings: settingsOff)
        XCTAssertTrue(listResp.contains("turned off in Settings"))

        // 3. AI prompt does NOT inject memory when Memory is OFF
        _ = await assistant.submit("What music should I play?", settings: settingsOff)
        let containsMemory = captureProvider.capturedMessages.contains { $0.content.contains("[Relevant user memories]") }
        XCTAssertFalse(containsMemory)

        // 4. Explicit user delete/clear commands MUST still work when Memory is OFF (Requirement 5)
        let forgetResp = await assistant.submit("Forget that I use Spotify", settings: settingsOff)
        XCTAssertTrue(forgetResp.contains("forgotten that"))
        let finalOffList = await store.list()
        XCTAssertTrue(finalOffList.isEmpty)
    }

    // MARK: - 12. Context Awareness OFF Behavior Test
    @MainActor
    func testContextAwarenessOffBehavior() async {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        let captureProvider = CaptureAIProvider()
        let assistant = AssistantManager(provider: captureProvider, providerIsInjected: true, memoryStore: store)

        let settings = AISettingsSnapshot(
            enabled: true,
            provider: .local,
            model: "mock",
            apiKey: nil,
            contextAwarenessEnabled: false,
            memoryEnabled: true
        )

        // Explicit memory commands work when Context Awareness is OFF (Requirement 5)
        let saveResp = await assistant.submit("Remember that I use Spotify", settings: settings)
        XCTAssertTrue(saveResp.contains("Spotify"))
        let countAfterSave = await store.list()
        XCTAssertEqual(countAfterSave.count, 1)

        let listResp = await assistant.submit("What do you remember about me?", settings: settings)
        XCTAssertTrue(listResp.contains("Spotify"))

        // AI request gets memory injected even though context awareness is OFF
        _ = await assistant.submit("What music should I listen to?", settings: settings)
        let hasSystemContext = captureProvider.capturedMessages.contains { $0.content.contains("[System context]") }
        let hasMemoryContext = captureProvider.capturedMessages.contains { $0.content.contains("[Relevant user memories]") }
        XCTAssertFalse(hasSystemContext, "System context should NOT be present when Context Awareness is OFF")
        XCTAssertTrue(hasMemoryContext, "Relevant memory SHOULD be present when Memory is ON")

        // Explicit forget works
        let forgetResp = await assistant.submit("Forget that I use Spotify", settings: settings)
        XCTAssertTrue(forgetResp.contains("forgotten"))
        let countAfterForget = await store.list()
        XCTAssertTrue(countAfterForget.isEmpty)
    }

    // MARK: - 13. Concurrent Access Test
    func testConcurrentAccess() async {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    _ = await store.save(key: "item_\(i)", value: "value_\(i)")
                    _ = await store.list()
                    _ = await store.relevantMemories(for: "item_\(i)", limit: 2)
                }
            }
        }

        let total = await store.list()
        XCTAssertEqual(total.count, 50)
    }

    // MARK: - 14. AssistantManager Integration Test
    @MainActor
    func testAssistantManagerIntegration() async {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        let assistant = AssistantManager(provider: MockAIProvider(), providerIsInjected: true, memoryStore: store)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil, memoryEnabled: true)

        // 1. Remember
        let saveResp = await assistant.submit("Remember that my favorite editor is VS Code.", settings: settings)
        XCTAssertTrue(saveResp.contains("VS Code"))
        let countAfterRemember = await store.list()
        XCTAssertEqual(countAfterRemember.count, 1)

        // 2. What do you remember
        let listResp = await assistant.submit("What do you remember about me?", settings: settings)
        XCTAssertTrue(listResp.contains("favorite editor"))
        XCTAssertTrue(listResp.contains("VS Code"))

        // 3. Graceful response when memory doesn't exist to delete
        let missingResp = await assistant.submit("Forget that I use Vim", settings: settings)
        XCTAssertEqual(missingResp, "I don't have a memory matching that.")

        // 4. Forget existing memory
        let forgetResp = await assistant.submit("Forget my favorite editor", settings: settings)
        XCTAssertTrue(forgetResp.contains("forgotten that"))
        let countAfterForget = await store.list()
        XCTAssertTrue(countAfterForget.isEmpty)

        // 5. Graceful response for empty list
        let emptyListResp = await assistant.submit("What do you remember about me?", settings: settings)
        XCTAssertEqual(emptyListResp, "I don't have any memories stored yet.")

        // 6. Clear all confirmation flow
        _ = await assistant.submit("Remember that I use Spotify", settings: settings)
        let countBeforeClearPrompt = await store.list()
        XCTAssertEqual(countBeforeClearPrompt.count, 1)

        let clearPrompt = await assistant.submit("Forget everything you remember", settings: settings)
        XCTAssertTrue(clearPrompt.contains("Are you sure"))
        let countStillPresent = await store.list()
        XCTAssertEqual(countStillPresent.count, 1) // not deleted yet

        let confirmedClear = await assistant.submit("Yes, forget everything", settings: settings)
        XCTAssertTrue(confirmedClear.contains("cleared all stored memories"))
        let countAfterClear = await store.list()
        XCTAssertTrue(countAfterClear.isEmpty)
    }

    // MARK: - 15. AI Prompt Memory Injection Test
    @MainActor
    func testAIPromptMemoryInjection() async {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        _ = await store.save(key: "favorite editor", value: "VS Code")
        _ = await store.save(key: "music", value: "Spotify")

        let captureProvider = CaptureAIProvider()
        let assistant = AssistantManager(provider: captureProvider, providerIsInjected: true, memoryStore: store)

        // A. Enabled and relevant query
        let settingsOn = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil, memoryEnabled: true)
        _ = await assistant.submit("Which editor should I open?", settings: settingsOn)

        guard let memMsg = captureProvider.capturedMessages.first(where: { $0.content.contains("[Relevant user memories]") }) else {
            XCTFail("Expected [Relevant user memories] section in prompt")
            return
        }
        XCTAssertTrue(memMsg.content.contains("VS Code"))
        XCTAssertFalse(memMsg.content.contains("Spotify"), "Should not blindly inject unrelated Spotify memory")

        // B. Enabled but completely irrelevant query -> no memory injected
        captureProvider.capturedMessages.removeAll()
        _ = await assistant.submit("What is photosynthesis?", settings: settingsOn)
        let hasIrrelevantMemory = captureProvider.capturedMessages.contains { $0.content.contains("[Relevant user memories]") }
        XCTAssertFalse(hasIrrelevantMemory, "Should not inject any memories for completely irrelevant queries")

        // C. Disabled memory -> no memory injected
        captureProvider.capturedMessages.removeAll()
        let settingsOff = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil, memoryEnabled: false)
        _ = await assistant.submit("Which editor should I open?", settings: settingsOff)
        let hasDisabledMemory = captureProvider.capturedMessages.contains { $0.content.contains("[Relevant user memories]") }
        XCTAssertFalse(hasDisabledMemory, "Should not inject memories when Memory is disabled")
    }

    // MARK: - 16. Command Gateway Integration Test
    @MainActor
    func testAMORACommandGatewayMemoryIntegration() async {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        let assistant = AssistantManager(provider: MockAIProvider(), providerIsInjected: true, memoryStore: store)
        let gateway = AMORACommandGateway(assistant: assistant)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil, memoryEnabled: true)

        // 1. Remember via Gateway
        let saveResult = await gateway.submit("Remember that I use Spotify.", settings: settings)
        guard case let .success(saveMsg) = saveResult else {
            XCTFail("Expected .success for remember")
            return
        }
        XCTAssertTrue(saveMsg.contains("Spotify"))

        // 2. List via Gateway
        let listResult = await gateway.submit("What do you remember about me?", settings: settings)
        guard case let .success(listMsg) = listResult else {
            XCTFail("Expected .success for list")
            return
        }
        XCTAssertTrue(listMsg.contains("Spotify"))

        // 3. Clear All prompt via Gateway -> returns needsConfirmation
        let clearResult = await gateway.submit("Forget everything you remember", settings: settings)
        guard case let .needsConfirmation(confirmPrompt) = clearResult else {
            XCTFail("Expected .needsConfirmation for unconfirmed clear all")
            return
        }
        XCTAssertTrue(confirmPrompt.contains("Are you sure"))

        // 4. Confirmed Clear via Gateway -> returns success and clears
        let confirmedResult = await gateway.submit("Yes, forget everything", settings: settings)
        guard case let .success(clearedMsg) = confirmedResult else {
            XCTFail("Expected .success for confirmed clear all")
            return
        }
        XCTAssertTrue(clearedMsg.contains("cleared all stored memories"))
        let items = await store.list()
        XCTAssertTrue(items.isEmpty)
    }
}
