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

    private final class RemoteCaptureAIProvider: AIProvider, @unchecked Sendable {
        var kind: AIProviderKind = .anthropic
        var isAvailable: Bool = true
        var availability: AIAvailability = .available
        var capturedMessages: [AIMessage] = []
        var outboundRequests: [[AIMessage]] = []
        var queuedResponses: [String] = []

        func send(messages: [AIMessage], model: String, apiKey: String?) async throws -> String {
            self.capturedMessages = messages
            self.outboundRequests.append(messages)
            if !queuedResponses.isEmpty {
                return queuedResponses.removeFirst()
            }
            return "Remote response"
        }
    }

    // MARK: - 1. Save Test
    func testSave() async throws {
        let storage = AmoraInMemoryStorage()
        let store = AmoraMemoryStore(storage: storage)

        let item = try await store.save(key: "editor", value: "VS Code")
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
    func testUpdateExistingMemory() async throws {
        let storage = AmoraInMemoryStorage()
        let store = AmoraMemoryStore(storage: storage)

        let first = try await store.save(key: "favorite editor", value: "VS Code")
        let list1 = await store.list()
        XCTAssertEqual(list1.count, 1)
        XCTAssertEqual(list1.first?.value, "VS Code")

        // Small delay to ensure timestamp resolution
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Save with matching key (different case)
        let updated = try await store.save(key: "Favorite Editor", value: "Sublime Text")
        let list2 = await store.list()
        XCTAssertEqual(list2.count, 1)
        XCTAssertEqual(list2.first?.id, first.id)
        XCTAssertEqual(list2.first?.value, "Sublime Text")
        XCTAssertGreaterThanOrEqual(updated.updatedAt, first.createdAt)
    }

    // MARK: - 3. List Test
    func testList() async throws {
        let storage = AmoraInMemoryStorage()
        let store = AmoraMemoryStore(storage: storage)

        let emptyList = await store.list()
        XCTAssertTrue(emptyList.isEmpty)

        _ = try await store.save(key: "music", value: "Spotify")
        _ = try await store.save(key: "editor", value: "VS Code")
        _ = try await store.save(key: "browser", value: "Chrome")

        let items = await store.list()
        XCTAssertEqual(items.count, 3)
        let keys = items.map(\.key)
        XCTAssertTrue(keys.contains("music"))
        XCTAssertTrue(keys.contains("editor"))
        XCTAssertTrue(keys.contains("browser"))
    }

    // MARK: - 4. Relevant Memory Retrieval Test
    func testRelevantMemoryRetrieval() async throws {
        let storage = AmoraInMemoryStorage()
        let store = AmoraMemoryStore(storage: storage)

        _ = try await store.save(key: "music", value: "I use Spotify")
        _ = try await store.save(key: "favorite editor", value: "VS Code")
        _ = try await store.save(key: "pet", value: "I have a dog named Milo")

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
    func testDelete() async throws {
        let storage = AmoraInMemoryStorage()
        let store = AmoraMemoryStore(storage: storage)

        let item1 = try await store.save(key: "music", value: "Spotify")
        let item2 = try await store.save(key: "editor", value: "VS Code")
        let initialList = await store.list()
        XCTAssertEqual(initialList.count, 2)

        // Delete by ID
        let deleted1 = try await store.delete(id: item1.id)
        XCTAssertTrue(deleted1)
        let listAfterDelete1 = await store.list()
        XCTAssertEqual(listAfterDelete1.count, 1)
        let item1Retrieved = await store.get(id: item1.id)
        XCTAssertNil(item1Retrieved)

        // Delete non-existent ID
        let deletedMissing = try await store.delete(id: UUID())
        XCTAssertFalse(deletedMissing)

        // Delete matching query
        let deletedByQuery = try await store.deleteMatching(query: "VS Code")
        XCTAssertEqual(deletedByQuery.count, 1)
        XCTAssertEqual(deletedByQuery.first?.id, item2.id)
        let finalList = await store.list()
        XCTAssertTrue(finalList.isEmpty)
    }

    // MARK: - 6. Clear All Test
    func testClearAll() async throws {
        let storage = AmoraInMemoryStorage()
        let store = AmoraMemoryStore(storage: storage)

        _ = try await store.save(key: "music", value: "Spotify")
        _ = try await store.save(key: "editor", value: "VS Code")
        _ = try await store.save(key: "city", value: "Berlin")
        let initialList = await store.list()
        XCTAssertEqual(initialList.count, 3)

        try await store.clearAll()
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
        _ = try await store1.save(key: "music", value: "Spotify")
        _ = try await store1.save(key: "editor", value: "VS Code")

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
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            for f in AmoraFileMemoryStorage.quarantinedFiles(for: tempURL) {
                try? FileManager.default.removeItem(at: f)
            }
        }

        // Write corrupt JSON bytes
        let corruptData = Data("!!! This is definitely not valid JSON {{{".utf8)
        try corruptData.write(to: tempURL)

        // Storage load recovers gracefully and returns empty array
        let storage = AmoraFileMemoryStorage(fileURL: tempURL)
        let loaded = await storage.load()
        XCTAssertTrue(loaded.isEmpty)

        // Verify quarantined backup was created rather than destroying data
        let quarantined = AmoraFileMemoryStorage.quarantinedFiles(for: tempURL)
        XCTAssertEqual(quarantined.count, 1, "A quarantined backup file must be preserved upon encountering corrupt data.")
        if let backup = quarantined.first {
            let backupData = try Data(contentsOf: backup)
            XCTAssertEqual(backupData, corruptData, "Quarantined backup must preserve original bytes for recovery.")
        }

        // Store can now save valid items safely
        let store = AmoraMemoryStore(storage: storage)
        let saved = try await store.save(key: "editor", value: "VS Code")
        XCTAssertEqual(saved.value, "VS Code")

        let reloaded = await store.list()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.key, "editor")

        // Quarantined file still exists intact after new save
        let quarantinedAfterSave = AmoraFileMemoryStorage.quarantinedFiles(for: tempURL)
        XCTAssertEqual(quarantinedAfterSave.count, 1, "Quarantined backup must not be destroyed when new memories are written.")
    }

    // MARK: - 9. Storage Write Failure Rollback Test
    func testFailedStorageRollback() async throws {
        let storage = AmoraInMemoryStorage()
        await storage.setShouldFailSave(true)
        let store = AmoraMemoryStore(storage: storage)

        do {
            _ = try await store.save(key: "testKey", value: "testVal")
            XCTFail("Expected store.save to throw when storage write fails")
        } catch {
            // Expected
        }

        let itemsAfterFailedSave = await store.list()
        XCTAssertTrue(itemsAfterFailedSave.isEmpty, "Memory must not be kept in cachedItems if storage write fails.")

        // Test delete rollback on failure
        await storage.setShouldFailSave(false)
        let saved = try await store.save(key: "editor", value: "VS Code")
        let countAfterSave = (await store.list()).count
        XCTAssertEqual(countAfterSave, 1)

        await storage.setShouldFailSave(true)
        do {
            _ = try await store.delete(id: saved.id)
            XCTFail("Expected store.delete to throw when storage write fails")
        } catch {
            // Expected
        }

        let itemsAfterFailedDelete = await store.list()
        XCTAssertEqual(itemsAfterFailedDelete.count, 1, "Memory must be restored to cachedItems if storage delete fails.")
    }

    // MARK: - 10. Conflicting Memory Handling Test
    func testConflictingMemoryHandling() async throws {
        let storage = AmoraInMemoryStorage()
        let store = AmoraMemoryStore(storage: storage)

        _ = try await store.save(key: "music preference", value: "YouTube")
        let list1 = await store.list()
        XCTAssertEqual(list1.count, 1)
        XCTAssertEqual(list1.first?.value, "YouTube")

        // Overwrite conflicting preference
        _ = try await store.save(key: "music preference", value: "Apple Music")
        let list2 = await store.list()
        XCTAssertEqual(list2.count, 1, "Conflicting preference should update existing memory instead of creating duplicates.")
        XCTAssertEqual(list2.first?.value, "Apple Music")
    }

    // MARK: - 11. Explicit-Only Saving Test
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

    // MARK: - 12. Sensitive-Memory Rejection Test
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

    // MARK: - 13. Memory OFF Behavior Test
    @MainActor
    func testMemoryOffBehavior() async throws {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        _ = try await store.save(key: "music", value: "Spotify")

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

        // 5. Agent loop tools also respect memory OFF toggle
        let agentProvider = MockSequentialAIProvider(responses: [
            "{\"type\":\"tool_call\",\"tool\":\"remember_fact\",\"arguments\":{\"key\":\"editor\",\"value\":\"VS Code\"}}",
            "{\"type\":\"final_answer\",\"answer\":\"I understand memory is off.\"}"
        ])
        let loop = AmoraAgentLoop(provider: agentProvider, memoryStore: store)
        let agentResult = try await loop.run(input: "remember editor", settings: settingsOff, memoryStore: store)
        XCTAssertTrue(agentResult.completedSuccessfully)
        let vsCodeStillNil = await store.get(key: "editor")
        XCTAssertNil(vsCodeStillNil, "remember_fact in agent loop must NOT save when Memory is OFF")

        // 6. User can still inspect and delete existing memories via service even when OFF
        _ = try await store.save(key: "note_fact", value: "Keep safe")
        let service = AmoraMemoryService(store: store)
        await service.refresh()
        XCTAssertEqual(service.memories.count, 1, "User must still be able to inspect memories in Settings when memory is OFF")
        await service.clearAll()
        XCTAssertTrue(service.memories.isEmpty, "User must still be able to delete memories in Settings when memory is OFF")
    }

    // MARK: - 14. Context Awareness OFF Behavior Test
    @MainActor
    func testContextAwarenessOffBehavior() async throws {
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

    // MARK: - 15. Concurrent Access Test
    func testConcurrentAccess() async {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    _ = try? await store.save(key: "item_\(i)", value: "value_\(i)")
                    _ = await store.list()
                    _ = await store.relevantMemories(for: "item_\(i)", limit: 2)
                }
            }
        }

        let total = await store.list()
        XCTAssertEqual(total.count, 50)
    }

    // MARK: - 16. AssistantManager Integration Test
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

    // MARK: - 17. Targeted Recall and Project Prompts Test
    @MainActor
    func testTargetedRecallAndProjectPrompts() async {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        let assistant = AssistantManager(provider: MockAIProvider(response: "Acknowledged."), providerIsInjected: true, memoryStore: store)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil, memoryEnabled: true)

        // 1. Remember preference
        let prefResp = await assistant.submit("Remember that I prefer YouTube over Apple Music.", settings: settings)
        XCTAssertTrue(prefResp.contains("remember") || prefResp.contains("YouTube"))

        // 2. Remember project
        let projResp = await assistant.submit("Remember that I am working on the Amora macOS app.", settings: settings)
        XCTAssertTrue(projResp.contains("remember") || projResp.contains("Amora"))

        // 3. Targeted question about preferences
        let queryPref = await assistant.submit("What do you remember about my preferences?", settings: settings)
        XCTAssertTrue(queryPref.contains("YouTube"), "Recall should return YouTube preference: \(queryPref)")

        // 4. Targeted question about project
        let queryProj = await assistant.submit("What programming project am I working on?", settings: settings)
        XCTAssertTrue(queryProj.contains("Amora"), "Recall should return Amora project: \(queryProj)")

        // 5. Forget preference
        let forgetPref = await assistant.submit("Forget my preference for YouTube.", settings: settings)
        XCTAssertTrue(forgetPref.contains("forgotten") || forgetPref.contains("preference"))

        // 6. Targeted question about preferences when none match
        let queryEmpty = await assistant.submit("What do you remember about my preferences?", settings: settings)
        XCTAssertFalse(queryEmpty.contains("YouTube"))
    }

    // MARK: - 18. AI Prompt Memory Injection Test
    @MainActor
    func testAIPromptMemoryInjection() async throws {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        _ = try await store.save(key: "favorite editor", value: "VS Code")
        _ = try await store.save(key: "music", value: "Spotify")

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

    // MARK: - 19. Remote Provider Privacy Boundary Test
    @MainActor
    func testRemoteProviderNeverReceivesMemories() async throws {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        _ = try await store.save(key: "music preference", value: "YouTube")
        _ = try await store.save(key: "programming project", value: "Amora")

        // 1. Initial Prompt Inspection for Anthropic: No memory injection and no recall/list tools advertised
        let anthropicProvider = RemoteCaptureAIProvider()
        anthropicProvider.kind = .anthropic
        let anthropicLoop = AmoraAgentLoop(provider: anthropicProvider, memoryStore: store)
        let anthropicSettings = AISettingsSnapshot(
            enabled: true,
            provider: .anthropic,
            model: "claude-3-5-sonnet",
            apiKey: "sk-ant-test",
            contextAwarenessEnabled: false,
            memoryEnabled: true
        )

        anthropicProvider.queuedResponses = [
            "{\"type\":\"final_answer\",\"answer\":\"You might enjoy Spotify or Apple Music.\"}"
        ]

        _ = try await anthropicLoop.run(
            input: "What music do I like?",
            settings: anthropicSettings,
            conversationHistory: [],
            memoryStore: store
        )

        let initialRequests = anthropicProvider.outboundRequests
        XCTAssertEqual(initialRequests.count, 1)
        for req in initialRequests {
            for msg in req {
                XCTAssertFalse(msg.content.contains("[Relevant user memories]"), "Outbound prompt to Anthropic must not contain [Relevant user memories]")
                XCTAssertFalse(msg.content.contains("YouTube"), "Outbound prompt to Anthropic must not contain stored memory value 'YouTube'")
                XCTAssertFalse(msg.content.contains("Amora"), "Outbound prompt to Anthropic must not contain stored memory value 'Amora'")
                if msg.content.contains("[AMORA Local Agent V1 Policy]") {
                    XCTAssertFalse(msg.content.contains("recall_memory:"), "Remote provider must not be advertised recall_memory tool")
                    XCTAssertFalse(msg.content.contains("list_memories:"), "Remote provider must not be advertised list_memories tool")
                }
            }
        }

        // 2. Trace agent tool loop: If remote Anthropic model calls recall_memory,
        // saved memory MUST NOT leak into outbound follow-up requests.
        anthropicProvider.outboundRequests.removeAll()
        anthropicProvider.queuedResponses = [
            "{\"type\":\"tool_call\",\"tool\":\"recall_memory\",\"arguments\":{\"query\":\"music preference\"}}",
            "{\"type\":\"final_answer\",\"answer\":\"I have no access to that.\"}"
        ]

        let recallResult = try await anthropicLoop.run(
            input: "What music do I like?",
            settings: anthropicSettings,
            conversationHistory: [],
            memoryStore: store
        )
        XCTAssertTrue(recallResult.completedSuccessfully)

        // There were 2 outbound model requests: Turn 1 (initial) and Turn 2 (with tool result)
        XCTAssertEqual(anthropicProvider.outboundRequests.count, 2, "Expected 2 outbound requests in tool execution loop")
        for (idx, request) in anthropicProvider.outboundRequests.enumerated() {
            for msg in request {
                XCTAssertFalse(msg.content.contains("YouTube"), "Outbound request \(idx) to Anthropic leaked memory 'YouTube'")
                XCTAssertFalse(msg.content.contains("Amora"), "Outbound request \(idx) to Anthropic leaked memory 'Amora'")
            }
        }
        // Verify turn 2 tool result contained the privacy restriction notice rather than stored memory
        let turn2Messages = anthropicProvider.outboundRequests[1]
        guard let toolResultMsg = turn2Messages.first(where: { $0.content.contains("[Tool result for recall_memory]") }) else {
            XCTFail("Expected tool result message in turn 2 outbound request")
            return
        }
        XCTAssertTrue(toolResultMsg.content.contains("restricted to on-device models to protect your privacy"))

        // 3. Trace agent tool loop: If remote OpenAI model calls list_memories,
        // memories MUST NOT leak into outbound follow-up requests.
        let openAIProvider = RemoteCaptureAIProvider()
        openAIProvider.kind = .openAI
        let openAILoop = AmoraAgentLoop(provider: openAIProvider, memoryStore: store)
        let openAISettings = AISettingsSnapshot(
            enabled: true,
            provider: .openAI,
            model: "gpt-4o",
            apiKey: "sk-test",
            contextAwarenessEnabled: false,
            memoryEnabled: true
        )

        openAIProvider.queuedResponses = [
            "{\"type\":\"tool_call\",\"tool\":\"list_memories\",\"arguments\":{}}",
            "{\"type\":\"final_answer\",\"answer\":\"Done.\"}"
        ]

        let listResult = try await openAILoop.run(
            input: "List my memories",
            settings: openAISettings,
            conversationHistory: [],
            memoryStore: store
        )
        XCTAssertTrue(listResult.completedSuccessfully)
        XCTAssertEqual(openAIProvider.outboundRequests.count, 2)
        for (idx, request) in openAIProvider.outboundRequests.enumerated() {
            for msg in request {
                XCTAssertFalse(msg.content.contains("YouTube"), "Outbound request \(idx) to OpenAI leaked memory 'YouTube'")
                XCTAssertFalse(msg.content.contains("Amora"), "Outbound request \(idx) to OpenAI leaked memory 'Amora'")
            }
        }
        let openAITurn2 = openAIProvider.outboundRequests[1]
        let listResultMsg = openAITurn2.first { $0.content.contains("[Tool result for list_memories]") }
        XCTAssertNotNil(listResultMsg)
        XCTAssertTrue(listResultMsg?.content.contains("restricted to on-device models to protect your privacy") == true)

        // 4. Remote remember_fact saves locally without echoing back full memory
        anthropicProvider.outboundRequests.removeAll()
        anthropicProvider.queuedResponses = [
            "{\"type\":\"tool_call\",\"tool\":\"remember_fact\",\"arguments\":{\"key\":\"beverage\",\"value\":\"Matcha Latte\"}}",
            "{\"type\":\"final_answer\",\"answer\":\"Saved.\"}"
        ]

        let saveResult = try await anthropicLoop.run(
            input: "Remember that I like Matcha Latte",
            settings: anthropicSettings,
            conversationHistory: [],
            memoryStore: store
        )
        XCTAssertTrue(saveResult.completedSuccessfully)
        let savedLocally = await store.get(key: "beverage")
        XCTAssertEqual(savedLocally?.value, "Matcha Latte", "Memory must be saved locally when remote provider issues remember_fact")

        // 5. Remote forget_memory deletes locally without leaking deleted memory contents
        anthropicProvider.outboundRequests.removeAll()
        anthropicProvider.queuedResponses = [
            "{\"type\":\"tool_call\",\"tool\":\"forget_memory\",\"arguments\":{\"query\":\"beverage\"}}",
            "{\"type\":\"final_answer\",\"answer\":\"Forgotten.\"}"
        ]

        let forgetResult = try await anthropicLoop.run(
            input: "Forget beverage",
            settings: anthropicSettings,
            conversationHistory: [],
            memoryStore: store
        )
        XCTAssertTrue(forgetResult.completedSuccessfully)
        let deletedLocally = await store.get(key: "beverage")
        XCTAssertNil(deletedLocally, "Memory must be deleted locally when remote provider issues forget_memory")
        let forgetTurn2 = anthropicProvider.outboundRequests[1]
        let forgetResultMsg = forgetTurn2.first { $0.content.contains("[Tool result for forget_memory]") }
        XCTAssertFalse(forgetResultMsg?.content.contains("Matcha Latte") == true, "Outbound forget result must not echo old memory contents")
    }

    // MARK: - 20. Action Engine Memory Operations Test
    @MainActor
    func testActionEngineMemoryOperations() async throws {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        let engine = AmoraActionEngine.makeDefault(memoryStore: store)

        // Save
        let saveResult = await engine.execute(.saveMemory(key: "editor", value: "Xcode"))
        XCTAssertEqual(saveResult.status, .success)
        XCTAssertTrue(saveResult.message.contains("Xcode"))

        let items = await store.list()
        XCTAssertEqual(items.count, 1)

        // Sensitive memory rejection
        let sensitiveResult = await engine.execute(.saveMemory(key: "password", value: "secret123"))
        XCTAssertEqual(sensitiveResult.status, .invalidInput)

        // Forget
        let forgetResult = await engine.execute(.forgetMemory(query: "editor"))
        XCTAssertEqual(forgetResult.status, .success)

        let itemsAfter = await store.list()
        XCTAssertTrue(itemsAfter.isEmpty)

        // Forget missing
        let missingResult = await engine.execute(.forgetMemory(query: "editor"))
        XCTAssertEqual(missingResult.status, .unavailable)
    }

    // MARK: - 21. Tool Registry Memory Execution Test
    @MainActor
    func testToolRegistryMemoryExecution() async throws {
        let registry = AMORAToolRegistry.shared

        let saveResult = await registry.execute(.init(tool: .memory, operation: .saveMemory(key: "test_role", value: "Developer")))
        XCTAssertEqual(saveResult.status, AMORAToolResult.Status.success)

        let recallResult = await registry.execute(.init(tool: .memory, operation: .recallMemory(query: "test_role")))
        XCTAssertEqual(recallResult.status, AMORAToolResult.Status.success)
        XCTAssertTrue(recallResult.message.contains("Developer"))

        let listResult = await registry.execute(.init(tool: .memory, operation: .listMemories))
        XCTAssertEqual(listResult.status, AMORAToolResult.Status.success)

        let forgetResult = await registry.execute(.init(tool: .memory, operation: .forgetMemory(query: "test_role")))
        XCTAssertEqual(forgetResult.status, AMORAToolResult.Status.success)

        let emptyRecall = await registry.execute(.init(tool: .memory, operation: .recallMemory(query: "test_role")))
        XCTAssertTrue(emptyRecall.message.contains("No memories found") || emptyRecall.message.contains("couldn't find") || emptyRecall.message.contains("don't have"))
    }

    // MARK: - 22. Agent Loop Memory Tools Test
    @MainActor
    func testAgentLoopMemoryTools() async throws {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        let provider = MockSequentialAIProvider(responses: [
            "{\"type\":\"tool_call\",\"tool\":\"remember_fact\",\"arguments\":{\"key\":\"coffee\",\"value\":\"Espresso\"}}",
            "{\"type\":\"final_answer\",\"answer\":\"I have remembered your coffee preference.\"}"
        ])

        let loop = AmoraAgentLoop(provider: provider, memoryStore: store)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil, memoryEnabled: true)

        let result = try await loop.run(input: "Remember that I like Espresso", settings: settings, memoryStore: store)
        XCTAssertTrue(result.completedSuccessfully)
        XCTAssertEqual(result.executedToolCount, 1)

        let items = await store.list()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.key, "coffee")
        XCTAssertEqual(items.first?.value, "Espresso")
    }

    // MARK: - 23. Update and Search in Store and Service Test
    @MainActor
    func testUpdateAndSearchInStoreAndService() async throws {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        let service = AmoraMemoryService(store: store)

        let saved = try await store.save(key: "music", value: "Spotify")
        await service.refresh()
        XCTAssertEqual(service.memories.count, 1)

        // Search
        let searchResults = await service.search(query: "spot")
        XCTAssertEqual(searchResults.count, 1)

        // Update
        let updated = try await service.update(id: saved.id, key: "streaming", value: "YouTube Music")
        XCTAssertNotNil(updated)
        XCTAssertEqual(updated?.key, "streaming")
        XCTAssertEqual(updated?.value, "YouTube Music")

        XCTAssertEqual(service.memories.first?.value, "YouTube Music")
    }

    // MARK: - 24. Command Gateway Integration Test
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

    // MARK: - 25. Conversation History Memory Provenance Across Provider Switch
    @MainActor
    func testConversationHistoryMemoryProvenanceAcrossProviderSwitch() async throws {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        _ = try await store.save(key: "secret project", value: "SuperSecretCodenameAMORA")

        let localProvider = CaptureAIProvider()
        let assistant = AssistantManager(provider: localProvider, providerIsInjected: true, memoryStore: store)
        let localSettings = AISettingsSnapshot(enabled: true, provider: .local, model: "local-model", apiKey: nil, memoryEnabled: true)

        // Turn 1: Local provider performs memory recall
        let turn1Response = await assistant.submit("What do you remember about my secret project?", settings: localSettings)
        XCTAssertTrue(turn1Response.contains("SuperSecretCodenameAMORA"), "Turn 1 local response must answer with recalled memory")

        // Switch to remote Anthropic provider for Turn 2
        let remoteProvider = RemoteCaptureAIProvider()
        remoteProvider.kind = .anthropic
        assistant.configure(provider: remoteProvider)
        let remoteSettings = AISettingsSnapshot(enabled: true, provider: .anthropic, model: "claude", apiKey: "test-key", memoryEnabled: true)

        // Turn 2: User asks an unrelated follow-up
        let turn2Response = await assistant.submit("Write a poem about the morning sunrise", settings: remoteSettings)
        XCTAssertEqual(turn2Response, "Remote response")

        // Inspect every outbound request sent to Anthropic
        XCTAssertFalse(remoteProvider.outboundRequests.isEmpty, "Remote provider must have received at least one request")
        for request in remoteProvider.outboundRequests {
            for msg in request {
                XCTAssertFalse(
                    msg.content.contains("SuperSecretCodenameAMORA"),
                    "Outbound request to remote provider must not contain saved memory value 'SuperSecretCodenameAMORA' from previous turn history"
                )
                XCTAssertFalse(
                    msg.content.contains("secret project"),
                    "Outbound request to remote provider must not contain memory-derived prompt query 'secret project' from previous turn history"
                )
                XCTAssertFalse(
                    msg.content.contains("[Relevant user memories]"),
                    "Outbound request to remote provider must not contain '[Relevant user memories]' block"
                )
            }
        }
    }

    // MARK: - 26. Quarantine Name Collision Avoidance Test
    func testQuarantineNameCollisionAvoidance() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("collision_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir.appendingPathComponent("memories.json")

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let storage = AmoraFileMemoryStorage(fileURL: tempURL)

        // Pre-create an existing quarantine file with candidate filename
        let existingURL = tempDir.appendingPathComponent("memories.corrupt-12345-abc.json")
        let existingData = Data("existing backup data".utf8)
        try existingData.write(to: existingURL)

        // Generate quarantine URL with identical timestamp and suffix
        let candidateURL = await storage.generateQuarantineURL(timestamp: 12345, uniqueSuffix: "abc")
        XCTAssertNotEqual(candidateURL.path, existingURL.path, "Collision-resistant naming must not overwrite existing file")
        XCTAssertTrue(candidateURL.lastPathComponent.contains("memories.corrupt-12345-abc-"), "Candidate name should resolve collision with counter suffix")

        // Verify existing file is preserved intact
        let preservedData = try Data(contentsOf: existingURL)
        XCTAssertEqual(preservedData, existingData, "Pre-existing quarantine file must not be modified or overwritten")
    }

    // MARK: - 27. Quarantine Backup Failure Prevents Overwriting Corrupt Original
    func testQuarantineBackupFailurePreventsOverwritingCorruptOriginal() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("backup_fail_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir.appendingPathComponent("memories.json")

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let corruptData = Data("%%% INVALID MEMORIES DATA %%%".utf8)
        try corruptData.write(to: tempURL)

        let storage = AmoraFileMemoryStorage(fileURL: tempURL)
        await storage.setSimulateQuarantineFailure(true)

        // Load catches corruption but quarantine fails
        let loaded = await storage.load()
        XCTAssertTrue(loaded.isEmpty)
        let hasUnquarantined = await storage.hasUnquarantinedCorruptOriginal
        XCTAssertTrue(hasUnquarantined, "Storage must track that the corrupt original is unquarantined")

        // Subsequent save MUST fail and refuse to overwrite the corrupt original
        do {
            try await storage.save([AmoraMemoryItem(key: "testKey", value: "testVal")])
            XCTFail("Save should fail when corrupt file could not be quarantined")
        } catch let error as AmoraMemoryError {
            if case .storageFailed(let msg) = error {
                XCTAssertTrue(msg.contains("quarantine failed"), "Error should explain quarantine failure: \(msg)")
            } else {
                XCTFail("Expected .storageFailed error, got \(error)")
            }
        } catch {
            XCTFail("Expected AmoraMemoryError.storageFailed, got \(error)")
        }

        // Verify the original corrupt data on disk is preserved intact and was NOT overwritten
        let diskData = try Data(contentsOf: tempURL)
        XCTAssertEqual(diskData, corruptData, "Original corrupt file must be preserved intact on disk when quarantine fails")
    }

    // MARK: - 28. Explicit User Intent Enforcement For Memory Mutations
    @MainActor
    func testExplicitUserIntentEnforcementForMemoryMutations() async throws {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())

        // 1. Unrelated user prompt attempting remember_fact tool call must be rejected
        let rogueRememberProvider = MockSequentialAIProvider(responses: [
            "{\"type\":\"tool_call\",\"tool\":\"remember_fact\",\"arguments\":{\"key\":\"music\",\"value\":\"Spotify\"}}",
            "{\"type\":\"final_answer\",\"answer\":\"Done.\"}"
        ])
        let loop1 = AmoraAgentLoop(provider: rogueRememberProvider, memoryStore: store)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil, memoryEnabled: true)

        let result1 = try await loop1.run(input: "I use Spotify for music every day.", settings: settings, memoryStore: store)
        // Memory store must NOT be mutated on unrelated prompt
        let items1 = await store.list()
        XCTAssertTrue(items1.isEmpty, "Memory must not be saved when user prompt lacks explicit remember intent")
        XCTAssertTrue(
            result1.finalAnswer.contains("only save memories when you explicitly ask") ||
            result1.attemptedTools.contains("remember_fact"),
            "Result should indicate restriction or attempted tool call"
        )

        // 2. Unrelated user prompt attempting forget_memory tool call must be rejected
        _ = try await store.save(key: "editor", value: "VS Code")
        let rogueForgetProvider = MockSequentialAIProvider(responses: [
            "{\"type\":\"tool_call\",\"tool\":\"forget_memory\",\"arguments\":{\"query\":\"editor\"}}",
            "{\"type\":\"final_answer\",\"answer\":\"Done.\"}"
        ])
        let loop2 = AmoraAgentLoop(provider: rogueForgetProvider, memoryStore: store)
        _ = try await loop2.run(input: "Delete note 1 from my notes folder", settings: settings, memoryStore: store)

        // Memory store must NOT have deleted the editor memory
        let items2 = await store.list()
        XCTAssertEqual(items2.count, 1, "Memory must not be deleted on unrelated prompt like 'Delete note 1'")
        XCTAssertEqual(items2.first?.key, "editor")

        // 3. Legitimate explicit remember request succeeds
        let validRememberProvider = MockSequentialAIProvider(responses: [
            "{\"type\":\"tool_call\",\"tool\":\"remember_fact\",\"arguments\":{\"key\":\"theme\",\"value\":\"Dark Mode\"}}",
            "{\"type\":\"final_answer\",\"answer\":\"I'll remember that.\"}"
        ])
        let loop3 = AmoraAgentLoop(provider: validRememberProvider, memoryStore: store)
        let result3 = try await loop3.run(input: "Remember that I prefer Dark Mode", settings: settings, memoryStore: store)
        XCTAssertTrue(result3.completedSuccessfully)
        let items3 = await store.list()
        XCTAssertEqual(items3.count, 2, "Explicit remember request must successfully save memory")

        // 4. Legitimate explicit forget request with Memory toggle OFF succeeds
        let settingsMemoryOff = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil, memoryEnabled: false)
        let validForgetProvider = MockSequentialAIProvider(responses: [
            "{\"type\":\"tool_call\",\"tool\":\"forget_memory\",\"arguments\":{\"query\":\"theme\"}}",
            "{\"type\":\"final_answer\",\"answer\":\"Forgotten.\"}"
        ])
        let loop4 = AmoraAgentLoop(provider: validForgetProvider, memoryStore: store)
        let result4 = try await loop4.run(input: "Forget my theme preference", settings: settingsMemoryOff, memoryStore: store)
        XCTAssertTrue(result4.completedSuccessfully)
        let items4 = await store.list()
        XCTAssertEqual(items4.count, 1, "Explicit forget request must succeed even when Memory toggle is turned off")
        XCTAssertEqual(items4.first?.key, "editor")
    }

    // MARK: - 29. Explicit Remember Intent Tightening Test
    func testExplicitRememberIntentTightening() {
        // Positive cases: explicit imperative commands
        let positiveCases = [
            "Remember that I prefer YouTube",
            "Remember that I prefer YouTube over Apple Music",
            "Please remember that my dog's name is Milo",
            "Hey Amora, remember my favorite drink is iced matcha",
            "amora, remember to buy groceries",
            "Don't forget that I have a flight tomorrow",
            "dont forget that my timezone is EST",
            "Don't forget my email address is test@example.com",
            "Save to memory: my car is a Honda Civic",
            "Save to memory that I work remotely",
            "Store in memory that I use Dvorak layout",
            "Keep in mind that I am vegetarian",
            "remember: favorite language is Swift"
        ]

        for command in positiveCases {
            XCTAssertTrue(
                AmoraMemoryCommandParser.hasExplicitRememberIntent(command),
                "Expected explicit remember intent for: '\(command)'"
            )
        }

        // Negative cases: descriptive statements, first-person recollections, queries, unrelated text
        let negativeCases = [
            "I remember that I prefer YouTube",
            "I remember that day vividly",
            "I can't remember my password",
            "i cant remember where I parked",
            "I cannot remember what day it is",
            "I don't remember",
            "i dont remember the title",
            "I seem to remember you said something",
            "As far as I remember, it was Tuesday",
            "As I remember, the store was closed",
            "If I remember correctly, we met in June",
            "We remember our first trip",
            "You remember everything",
            "What do you remember about my preferences?",
            "Do you remember my favorite music?",
            "Did you remember to check the mail?",
            "Can you remember anything?",
            "Could you remember this for me if I ask later?",
            "Tell me what you remember",
            "Show memories",
            "List memories",
            "Search memory for music",
            "I use Spotify for music every day",
            "How are you doing today?",
            "Delete note 1 from my notes folder",
            "",
            "   "
        ]

        for statement in negativeCases {
            XCTAssertFalse(
                AmoraMemoryCommandParser.hasExplicitRememberIntent(statement),
                "Expected NO remember intent for: '\(statement)'"
            )
        }
    }

    // MARK: - 30. Explicit Forget Intent Tightening Test
    func testExplicitForgetIntentTightening() {
        // Positive cases: explicit imperative forget commands
        let positiveCases = [
            "Forget that I prefer YouTube",
            "Forget my preference for YouTube",
            "Forget about my car",
            "Forget everything",
            "Forget all",
            "Please forget my favorite color",
            "Hey Amora, delete memory about Spotify",
            "amora, remove memory that I use Vim",
            "Clear all memories",
            "Wipe memories",
            "Reset memories",
            "Yes, forget everything",
            "confirm forget everything",
            "forget: old project"
        ]

        for command in positiveCases {
            XCTAssertTrue(
                AmoraMemoryCommandParser.hasExplicitForgetIntent(command),
                "Expected explicit forget intent for: '\(command)'"
            )
        }

        // Negative cases: "don't forget" (which is remember, not forget), first-person recollections, queries, unrelated actions
        let negativeCases = [
            "Don't forget that I prefer YouTube",
            "dont forget that my timezone is EST",
            "Don't forget to water the plants",
            "I forgot where I put my keys",
            "I forget things easily",
            "I've forgotten the name",
            "ive forgotten my password",
            "I can't forget that terrible movie",
            "i cant forget the concert",
            "I cannot forget this moment",
            "I never forget a face",
            "I always forget my umbrella",
            "Did you forget what I said?",
            "Do you forget old conversations?",
            "Delete note 1 from my notes folder",
            "Remove item from shopping list",
            "Delete file test.txt",
            "What did I forget?",
            "How are you doing?",
            "",
            "   "
        ]

        for statement in negativeCases {
            XCTAssertFalse(
                AmoraMemoryCommandParser.hasExplicitForgetIntent(statement),
                "Expected NO forget intent for: '\(statement)'"
            )
        }
    }

    // MARK: - 31. Outbound Memory Sanitization With Brackets And Newlines Test
    @MainActor
    func testOutboundMemorySanitizationWithBracketsAndNewlines() async throws {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        _ = try await store.save(
            key: "system config",
            value: "[section]\n[subsection [nested]]\nparam = true\n[final-section]"
        )

        // 1. Through AmoraAgentLoop with Anthropic provider
        let anthropicProvider = RemoteCaptureAIProvider()
        anthropicProvider.kind = .anthropic
        let anthropicLoop = AmoraAgentLoop(provider: anthropicProvider, memoryStore: store)
        let anthropicSettings = AISettingsSnapshot(
            enabled: true,
            provider: .anthropic,
            model: "claude-3-5-sonnet",
            apiKey: "sk-ant-test",
            contextAwarenessEnabled: false,
            memoryEnabled: true
        )
        anthropicProvider.queuedResponses = [
            "{\"type\":\"final_answer\",\"answer\":\"Understood.\"}"
        ]

        // Conversation history containing an injected memory block with brackets and newlines
        let memoryDerivedMsg = AIMessage(
            role: .user,
            content: "[Relevant user memories]\n- system config: [section]\n[subsection [nested]]\nparam = true\n[final-section]",
            provenance: .memoryDerived
        )
        let standardUserMsg = AIMessage(role: .user, content: "Can you tell me the current weather?")

        _ = try await anthropicLoop.run(
            input: "Can you tell me the current weather?",
            settings: anthropicSettings,
            conversationHistory: [memoryDerivedMsg, standardUserMsg],
            memoryStore: store
        )

        XCTAssertEqual(anthropicProvider.outboundRequests.count, 1)
        for req in anthropicProvider.outboundRequests {
            for msg in req {
                XCTAssertFalse(msg.content.contains("[Relevant user memories]"), "Must omit entire [Relevant user memories] message")
                XCTAssertFalse(msg.content.contains("[section]"), "Must not leak '[section]' fragment")
                XCTAssertFalse(msg.content.contains("[subsection"), "Must not leak '[subsection' fragment")
                XCTAssertFalse(msg.content.contains("[nested]]"), "Must not leak '[nested]]' fragment")
                XCTAssertFalse(msg.content.contains("param = true"), "Must not leak 'param = true' fragment")
                XCTAssertFalse(msg.content.contains("[final-section]"), "Must not leak '[final-section]' fragment")
                XCTAssertFalse(msg.content.contains("system config"), "Must not leak memory key 'system config'")
            }
        }

        // 2. Direct AIConversation sanitization for remote providers
        var conversation = AIConversation()
        conversation.append(memoryDerivedMsg)
        conversation.append(standardUserMsg)

        let sanitizedForAnthropic = conversation.messages(for: .anthropic)
        XCTAssertEqual(sanitizedForAnthropic.count, 1)
        XCTAssertEqual(sanitizedForAnthropic.first?.content, "Can you tell me the current weather?")

        let sanitizedForOpenAI = conversation.messages(for: .openAI)
        XCTAssertEqual(sanitizedForOpenAI.count, 1)
        XCTAssertEqual(sanitizedForOpenAI.first?.content, "Can you tell me the current weather?")

        // On-device / local provider retains all messages
        let localMessages = conversation.messages(for: .local)
        XCTAssertEqual(localMessages.count, 2)
    }

    // MARK: - 32. End-to-End Five Commands Lifecycle Test
    @MainActor
    func testEndToEndFiveMemoryCommandsLifecycle() async {
        let store = AmoraMemoryStore(storage: AmoraInMemoryStorage())
        let assistant = AssistantManager(provider: MockAIProvider(), providerIsInjected: true, memoryStore: store)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil, memoryEnabled: true)

        // 1. Save: "Remember that I prefer YouTube over Apple Music."
        let saveResponse = await assistant.submit("Remember that I prefer YouTube over Apple Music.", settings: settings)
        XCTAssertFalse(saveResponse.contains("I can't assist you with that"), "Save command must not fall through to refusal")
        XCTAssertTrue(saveResponse.contains("YouTube"), "Save response must confirm remembering YouTube")
        let storedAfterSave = await store.list()
        XCTAssertEqual(storedAfterSave.count, 1)
        XCTAssertTrue(storedAfterSave.first?.value.contains("YouTube") == true)

        // 2. Recall: "What do you remember about my preferences?"
        let recallResponse = await assistant.submit("What do you remember about my preferences?", settings: settings)
        XCTAssertFalse(recallResponse.contains("I can't assist you with that"), "Recall command must not fall through to refusal")
        XCTAssertTrue(recallResponse.contains("YouTube"), "Recall response must recall preference")

        // 3. Update: "Change my music preference to Spotify."
        let updateResponse = await assistant.submit("Change my music preference to Spotify.", settings: settings)
        XCTAssertFalse(updateResponse.contains("I can't assist you with that"), "Update command must not fall through to refusal")
        XCTAssertTrue(updateResponse.contains("Spotify"), "Update response must confirm updating to Spotify")
        let storedAfterUpdate = await store.list()
        XCTAssertEqual(storedAfterUpdate.count, 1, "Updating preference must update existing memory, not create duplicate")
        XCTAssertEqual(storedAfterUpdate.first?.value, "Spotify")

        // 4. List: "List my memories."
        let listResponse = await assistant.submit("List my memories.", settings: settings)
        XCTAssertFalse(listResponse.contains("I can't assist you with that"), "List command must not fall through to refusal")
        XCTAssertTrue(listResponse.contains("Spotify"), "List response must list Spotify")

        // 5. Forget: "Forget my preference for Spotify."
        let forgetResponse = await assistant.submit("Forget my preference for Spotify.", settings: settings)
        XCTAssertFalse(forgetResponse.contains("I can't assist you with that"), "Forget command must not fall through to refusal")
        XCTAssertTrue(forgetResponse.contains("forgotten") || forgetResponse.contains("Spotify"), "Forget response must confirm deletion")
        let storedAfterForget = await store.list()
        XCTAssertTrue(storedAfterForget.isEmpty, "Store must be empty after forgetting preference")
    }

    // MARK: - 33. Deterministic Router Memory Decisions Test
    @MainActor
    func testDeterministicRouterMemoryDecisions() {
        // Remember
        let rememberDecision = AmoraDeterministicRouter.decision(for: "Remember that I prefer YouTube")
        guard case let .toolCall(tool, args) = rememberDecision else {
            XCTFail("Expected .toolCall for remember")
            return
        }
        XCTAssertEqual(tool, "remember_fact")
        XCTAssertFalse(args["value"]?.isEmpty ?? true)

        // Recall
        let recallDecision = AmoraDeterministicRouter.decision(for: "What do you remember about my preferences?")
        guard case let .toolCall(recallTool, recallArgs) = recallDecision else {
            XCTFail("Expected .toolCall for recall")
            return
        }
        XCTAssertEqual(recallTool, "recall_memory")
        XCTAssertFalse(recallArgs["query"]?.isEmpty ?? true)

        // Update
        let updateDecision = AmoraDeterministicRouter.decision(for: "Change my music preference to Spotify")
        guard case let .toolCall(updateTool, updateArgs) = updateDecision else {
            XCTFail("Expected .toolCall for update")
            return
        }
        XCTAssertEqual(updateTool, "update_memory")
        XCTAssertEqual(updateArgs["value"], "Spotify")

        // Forget
        let forgetDecision = AmoraDeterministicRouter.decision(for: "Forget my preference for Spotify")
        guard case let .toolCall(forgetTool, forgetArgs) = forgetDecision else {
            XCTFail("Expected .toolCall for forget")
            return
        }
        XCTAssertEqual(forgetTool, "forget_memory")
        XCTAssertFalse(forgetArgs["query"]?.isEmpty ?? true)

        // List
        let listDecision = AmoraDeterministicRouter.decision(for: "List my memories")
        guard case let .toolCall(listTool, _) = listDecision else {
            XCTFail("Expected .toolCall for list")
            return
        }
        XCTAssertEqual(listTool, "list_memories")

        // Clear All
        let clearDecision = AmoraDeterministicRouter.decision(for: "Clear all memories")
        guard case let .toolCall(clearTool, clearArgs) = clearDecision else {
            XCTFail("Expected .toolCall for clear all")
            return
        }
        XCTAssertEqual(clearTool, "clear_memories")
        XCTAssertEqual(clearArgs["confirmed"], "false")
    }

    // MARK: - 34. Explicit Update Intent Tightening Test
    func testExplicitUpdateIntentTightening() {
        let positiveCases = [
            "Change my music preference to Spotify",
            "Update my coffee preference to Oat milk",
            "Switch my editor to VS Code",
            "Modify my theme preference to light",
            "change my car to Tesla",
            "update preference for browser to Brave"
        ]
        for query in positiveCases {
            XCTAssertTrue(AmoraMemoryCommandParser.hasExplicitUpdateIntent(query), "Query should have explicit update intent: '\(query)'")
        }

        let negativeCases = [
            "I change clothes every day",
            "The update took five minutes to complete",
            "Switching between screens is fast",
            "What did you change recently?",
            "Can you update me on the news?"
        ]
        for query in negativeCases {
            XCTAssertFalse(AmoraMemoryCommandParser.hasExplicitUpdateIntent(query), "Casual query should NOT have explicit update intent: '\(query)'")
        }
    }

    // MARK: - 35. Store updateMatching With Key and Stem Matching Test
    func testStoreUpdateMatching() async throws {
        let storage = AmoraInMemoryStorage()
        let store = AmoraMemoryStore(storage: storage)

        _ = try await store.save(key: "music preference", value: "YouTube")

        // Update matching key
        let updated = try await store.updateMatching(query: "music preference", newValue: "Spotify", newKey: nil)
        XCTAssertNotNil(updated)
        XCTAssertEqual(updated?.value, "Spotify")

        let current = await store.list()
        XCTAssertEqual(current.count, 1)
        XCTAssertEqual(current.first?.value, "Spotify")

        // Update non-matching query returns nil
        let nonMatch = try await store.updateMatching(query: "unrelated topic", newValue: "something", newKey: nil)
        XCTAssertNil(nonMatch)
    }
}
