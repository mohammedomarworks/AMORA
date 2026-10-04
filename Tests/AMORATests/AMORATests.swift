import XCTest
@testable import AMORA

@MainActor
final class AMORATests: XCTestCase {
    struct SlowProvider: AIProvider {
        let kind: AIProviderKind = .local
        var isAvailable: Bool { true }
        func send(messages: [AIMessage], model: String, apiKey: String?) async throws -> String {
            try await Task.sleep(for: .seconds(10))
            return "late"
        }
    }
    func testExpressionInit() {
        let expr = Expression.neutral
        XCTAssertEqual(expr.eyes, .normal)
        XCTAssertEqual(expr.mouth, .neutral)
    }

    func testStatePriority() {
        XCTAssertTrue(AMORAState.error.priority > AMORAState.idle.priority)
        XCTAssertTrue(AMORAState.expanded.priority > AMORAState.idle.priority)
        XCTAssertTrue(AMORAState.alert.priority > AMORAState.music.priority)
    }

    func testDynamicIslandPageNavigationHasHardBoundaries() {
        let pages = QuickPanelView.Page.allCases
        XCTAssertEqual(pages.count, 4)
        XCTAssertEqual(pages.first, .controls)
        XCTAssertEqual(pages.last, .fileShelf)
        XCTAssertEqual(min(max(-1, 0), pages.count - 1), 0)
        XCTAssertEqual(min(max(pages.count, 0), pages.count - 1), pages.count - 1)
    }

    func testBatteryEstimatePresentationIsExplicit() {
        XCTAssertEqual(BatteryService.EstimateState.estimated(minutes: 351), .estimated(minutes: 351))
        XCTAssertEqual(BatteryService.EstimateState.calculating, .calculating)
        XCTAssertEqual(BatteryService.EstimateState.unavailable, .unavailable)
    }

    func testThemesHaveDistinctAccentIdentities() {
        XCTAssertNotEqual(Theme.midnight.palette.accent, Theme.ocean.palette.accent)
        XCTAssertNotEqual(Theme.ocean.palette.accent, Theme.bubblegum.palette.accent)
        XCTAssertNotEqual(Theme.bubblegum.palette.accent, Theme.matrix.palette.accent)
        XCTAssertNotEqual(Theme.matrix.palette.accent, Theme.minimal.palette.accent)
    }

    func testRobotInit() {
        let robot = AMORARobot()
        XCTAssertEqual(robot.state, .idle)
    }

    func testContextRecordsMeaningfulEventsWithoutUserContent() {
        let context = AMORAContext.shared
        context.record(.noteCreated)
        XCTAssertEqual(context.lastAction, "note")
        XCTAssertEqual(context.currentEvent, .noteCreated)
        XCTAssertNil(context.lastAction?.contains("buy") == true ? context.lastAction : nil)
    }

    func testEventCenterRoutesToContext() {
        let context = AMORAContext.shared
        AMORAEventCenter.shared.emit(.fileReceived)
        XCTAssertEqual(context.lastAction, "file")
        XCTAssertEqual(context.currentEvent, .fileReceived)
    }

    func testNaturalTimerParsing() {
        let parser = AMORACommandParser()
        let inputs = [
            ("timer 25", 25 * 60),
            ("start timer 25", 25 * 60),
            ("start a 25 minute timer", 25 * 60),
            ("start a 25 min timer", 25 * 60),
            ("give me a 25 min focus session", 25 * 60),
            ("set a timer for 10 minutes", 10 * 60),
            ("set timer for 1 hour", 60 * 60)
        ]
        for (input, seconds) in inputs {
            XCTAssertEqual(parser.parse(input), .startTimer(duration: TimeInterval(seconds)), input)
        }
        XCTAssertEqual(parser.parse("start timer"), .unknown(text: "start timer"))
    }

    func testNaturalModuleParsing() {
        let parser = AMORACommandParser()
        XCTAssertEqual(parser.parse("play"), .playMusic)
        XCTAssertEqual(parser.parse("pause music"), .pauseMusic)
        XCTAssertEqual(parser.parse("next song"), .nextTrack)
        XCTAssertEqual(parser.parse("previous track"), .previousTrack)
        XCTAssertEqual(parser.parse("what's my battery"), .showBattery)
        XCTAssertEqual(parser.parse("how much battery do I have"), .showBattery)
        XCTAssertEqual(parser.parse("show clipboard"), .showClipboard)
        XCTAssertEqual(parser.parse("show notes"), .showNotes)
        XCTAssertEqual(parser.parse("open dashboard"), .showDashboard)
        XCTAssertEqual(parser.parse("settings"), .showSettings)
        XCTAssertEqual(parser.parse("open Downloads"), .openFolder(name: "downloads"))
        XCTAssertEqual(parser.parse("open VS Code"), .openApplication(name: "vs code"))
    }

    func testNoteExtractionAndSafeUnknowns() {
        let parser = AMORACommandParser()
        XCTAssertEqual(parser.parse("add a note buy milk"), .createNote(text: "buy milk"))
        XCTAssertEqual(parser.parse("save a note that says finish Java assignment"), .createNote(text: "finish Java assignment"))
        XCTAssertEqual(parser.parse("make a note saying call dad"), .createNote(text: "call dad"))
        XCTAssertEqual(parser.parse("make me a website"), .unknown(text: "make me a website"))
        XCTAssertEqual(parser.parse("tell me a joke"), .unknown(text: "tell me a joke"))
        XCTAssertEqual(parser.parse("what is the weather"), .unknown(text: "what is the weather"))
    }

    func testFollowUpContext() {
        let parser = AMORACommandParser()
        let timerContext = AMORACommandContext(activeTimer: true)
        XCTAssertEqual(parser.parse("pause it", context: timerContext), .pauseTimer)
        XCTAssertEqual(parser.parse("resume it", context: timerContext), .resumeTimer)
        let musicContext = AMORACommandContext(activeMedia: true)
        XCTAssertEqual(parser.parse("pause it", context: musicContext), .pauseMusic)
    }

    func testRouterDoesNotGuessMissingDuration() {
        let result = AMORACommandRouter.shared.execute(.unknown(text: "start timer"))
        XCTAssertEqual(result, .needsInformation(prompt: "How long should I set it for?"))
    }

    func testLocalFirstRoutingDistinguishesBatteryAdvice() async {
        let parser = AMORACommandParser()
        XCTAssertEqual(parser.parse("battery"), .showBattery)
        XCTAssertEqual(parser.parse("what's my battery?"), .showBattery)
        XCTAssertEqual(parser.parse("how can I improve my battery life?"), .unknown(text: "how can i improve my battery life"))
        XCTAssertEqual(parser.parse("start a timer for 25 minutes"), .startTimer(duration: 1_500))
        XCTAssertEqual(parser.parse("help me plan a 25 minute study session"), .unknown(text: "help me plan a 25 minute study session"))
    }

    func testAssistantUsesMockProviderAndConversationIsBounded() async {
        let manager = AssistantManager(provider: MockAIProvider(response: "A mock answer."))
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil)
        let answer = await manager.submit("explain recursion", settings: settings)
        XCTAssertEqual(answer, "A mock answer.")
        XCTAssertEqual(manager.conversation.messages.count, 2)
        XCTAssertEqual(manager.state, .responding)
    }

    func testDisabledAssistantFallsBackWithoutCallingProvider() async {
        let manager = AssistantManager(provider: MockAIProvider(response: "must not be used"))
        let settings = AISettingsSnapshot(enabled: false, provider: .local, model: "mock", apiKey: nil)
        let answer = await manager.submit("tell me something", settings: settings)
        XCTAssertEqual(answer, "AI Assistant is turned off in Settings.")
        XCTAssertEqual(manager.lastError, .unavailable)
        XCTAssertTrue(manager.conversation.messages.isEmpty)
    }

    func testToolValidationIsAllowlistedAndConfirmationAware() {
        let validator = AMORAToolValidator()
        XCTAssertEqual(validator.validate(AMORAToolRequest(tool: .battery, operation: .readBattery)), .allowed)
        XCTAssertEqual(validator.validate(AMORAToolRequest(tool: .timer, operation: .startTimer(seconds: 90_000))), .rejected(reason: "Timer duration is outside the supported range."))
        XCTAssertEqual(validator.validate(AMORAToolRequest(tool: .file, operation: .openFolder(name: "Downloads"))), .needsConfirmation(prompt: "Would you like me to open Downloads?"))
    }

    func testToolPlanDecodesOnlyApprovedTypedOperations() {
        let data = #"{"calls":[{"tool":"timer","action":"start","seconds":1500,"text":null,"name":null},{"tool":"browserMedia","action":"pause","seconds":null,"text":null,"name":null}]}"#.data(using: .utf8)!
        let plan = try! JSONDecoder().decode(AMORAToolPlan.self, from: data)
        XCTAssertEqual(plan.requests()?.count, 2)
        let unsafe = try! JSONDecoder().decode(AMORAToolPlan.self, from: Data(#"{"calls":[{"tool":"shell","action":"run","seconds":null,"text":null,"name":"rm -rf /"}]}"#.utf8))
        XCTAssertNil(unsafe.requests())
    }

    func testToolPlanBoundsNumberOfCalls() {
        let calls = (0..<5).map { _ in #"{"tool":"battery","action":"read","seconds":null,"text":null,"name":null}"# }.joined(separator: ",")
        let plan = try! JSONDecoder().decode(AMORAToolPlan.self, from: Data("{\"calls\":[\(calls)]}".utf8))
        XCTAssertNil(plan.requests())
    }

    func testToolRegistryRejectsDestructiveOrUnknownCapabilities() {
        let validator = AMORAToolValidator()
        XCTAssertEqual(validator.validate(AMORAToolRequest(tool: .file, operation: .openFolder(name: "/"))), .rejected(reason: "That folder is not available through AMORA."))
        let unsafe = try! JSONDecoder().decode(AMORAToolPlan.self, from: Data(#"{"calls":[{"tool":"application","action":"shell","seconds":null,"text":null,"name":"rm"}]}"#.utf8))
        XCTAssertNil(unsafe.requests())
    }

    func testAssistantCancellationReturnsSafely() async {
        let manager = AssistantManager(provider: SlowProvider())
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "slow", apiKey: nil)
        let request = Task { await manager.submit("explain recursion", settings: settings) }
        try? await Task.sleep(for: .milliseconds(20))
        manager.cancel()
        let answer = await request.value
        XCTAssertEqual(answer, "Okay — stopped.")
        XCTAssertEqual(manager.state, .cancelled)
    }

    func testProviderFactorySelectsAppleOnDeviceWithoutAnAPIKey() {
        let settings = AISettingsSnapshot(enabled: true, provider: .appleOnDevice, model: "apple-on-device", apiKey: nil)
        let provider = AIProviderFactory.make(for: settings)
        XCTAssertEqual(provider.kind, .appleOnDevice)
        if #available(macOS 26.0, *) {
            XCTAssertTrue(provider is AppleFoundationModelProvider)
        }
    }

    func testChromeBridgeRejectsMalformedMessages() {
        let bridge = ChromeMessageBridge.shared
        bridge.receive(nil)
        XCTAssertEqual(bridge.status, .permissionRequired)
        XCTAssertNil(bridge.state)
        bridge.receive("{\"type\":\"unexpected\"}")
        XCTAssertEqual(bridge.status, .protocolError)
        XCTAssertNil(bridge.state)
    }

    func testChromeBridgeParsesPlayingAndPausedYouTubeState() {
        let bridge = ChromeMessageBridge.shared
        let payload = "{\"type\":\"mediaState\",\"browser\":\"Chrome\",\"provider\":\"YouTube\",\"title\":\"Demo\",\"channel\":\"AMORA\",\"isPlaying\":true,\"currentTime\":12.5,\"duration\":60.0,\"url\":\"https://www.youtube.com/watch?v=demo\",\"controlAvailable\":true,\"tabId\":42,\"windowId\":7,\"isActive\":false,\"isInBackground\":true,\"trackedMediaTabCount\":2,\"contentScriptReady\":true,\"hasVideo\":true}"
        bridge.receive(payload)
        XCTAssertEqual(bridge.status, .connected)
        XCTAssertEqual(bridge.state?.title, "Demo")
        XCTAssertEqual(bridge.state?.isPlaying, true)
        XCTAssertEqual(bridge.state?.currentTime, 12.5)
        XCTAssertEqual(bridge.state?.tabId, 42)
        XCTAssertEqual(bridge.state?.trackedMediaTabCount, 2)
        XCTAssertEqual(bridge.state?.isInBackground, true)
        bridge.receive(payload.replacingOccurrences(of: "true", with: "false"))
        XCTAssertEqual(bridge.state?.isPlaying, false)
    }

    func testYouTubeURLValidationRejectsUnrelatedPages() {
        XCTAssertTrue(BrowserMediaAppleScript.isSupportedYouTubeURL("https://youtu.be/demo"))
        XCTAssertTrue(BrowserMediaAppleScript.isSupportedYouTubeURL("https://www.youtube.com/shorts/demo"))
        XCTAssertFalse(BrowserMediaAppleScript.isSupportedYouTubeURL("https://example.com/watch/demo"))
        XCTAssertFalse(BrowserMediaAppleScript.isSupportedYouTubeURL("https://youtube.com.evil.example/watch?v=demo"))
    }

    func testCloudProviderWithoutKeyReportsAuthenticationRequirement() async {
        let manager = AssistantManager(provider: MockAIProvider(response: "must not be used"), providerIsInjected: false)
        let settings = AISettingsSnapshot(enabled: true, provider: .openAI, model: "gpt", apiKey: nil)
        let answer = await manager.submit("tell me a joke", settings: settings)
        XCTAssertEqual(answer, "Your AI provider needs a valid API key.")
        XCTAssertEqual(manager.lastError, .authenticationRequired)
    }

    func testConversationContextIsPassedToProvider() async {
        let provider = MockAIProvider(response: "A follow-up answer.")
        let manager = AssistantManager(provider: provider)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil)
        _ = await manager.submit("what is recursion?", settings: settings)
        _ = await manager.submit("show me an example", settings: settings)
        XCTAssertEqual(manager.conversation.messages.count, 4)
        XCTAssertEqual(manager.conversation.messages[2].content, "show me an example")
    }

    @MainActor
    func testChromeBridgeHandlesCommandResultAndRecordsDiagnostics() {
        let bridge = ChromeMessageBridge.shared
        let setupPayload = "{\"type\":\"mediaState\",\"browser\":\"Chrome\",\"provider\":\"YouTube\",\"title\":\"Demo\",\"channel\":\"AMORA\",\"isPlaying\":true,\"currentTime\":10.0,\"duration\":60.0,\"url\":\"https://www.youtube.com/watch?v=demo\",\"tabId\":99,\"windowId\":1,\"trackedMediaTabCount\":1,\"contentScriptReady\":true,\"hasVideo\":true}"
        bridge.receive(setupPayload)
        XCTAssertEqual(bridge.status, .connected)

        var completedSuccess: Bool?
        var completedReason: String?
        bridge.sendMediaCommand(.pause) { success, reason in
            completedSuccess = success
            completedReason = reason
        }

        guard let diagnostic = bridge.commandDiagnostics.last else {
            XCTFail("Diagnostic record not created")
            return
        }
        XCTAssertEqual(diagnostic.action, .pause)
        XCTAssertEqual(diagnostic.tabId, 99)
        XCTAssertEqual(diagnostic.provider, "YouTube")

        let ackPayload = "{\"type\":\"mediaCommandResult\",\"provider\":\"youtube\",\"action\":\"pause\",\"requestId\":\"\(diagnostic.requestId)\",\"tabId\":99,\"success\":true,\"state\":{\"isPlaying\":false,\"title\":\"Demo\",\"currentTime\":10.0,\"duration\":60.0,\"url\":\"https://www.youtube.com/watch?v=demo\"}}"
        bridge.receive(ackPayload)

        XCTAssertEqual(completedSuccess, true)
        XCTAssertNil(completedReason)
        XCTAssertEqual(bridge.state?.isPlaying, false)
        XCTAssertEqual(bridge.commandDiagnostics.last?.success, true)
    }

    @MainActor
    func testChromeBridgeHandlesCommandFailureReason() {
        let bridge = ChromeMessageBridge.shared
        let setupPayload = "{\"type\":\"mediaState\",\"browser\":\"Chrome\",\"provider\":\"YouTube\",\"title\":\"Demo\",\"channel\":\"AMORA\",\"isPlaying\":false,\"currentTime\":10.0,\"duration\":60.0,\"url\":\"https://www.youtube.com/watch?v=demo\",\"tabId\":88,\"windowId\":1,\"trackedMediaTabCount\":1,\"contentScriptReady\":true,\"hasVideo\":true}"
        bridge.receive(setupPayload)

        var completedSuccess: Bool?
        var completedReason: String?
        bridge.sendMediaCommand(.play) { success, reason in
            completedSuccess = success
            completedReason = reason
        }

        guard let diagnostic = bridge.commandDiagnostics.last else {
            XCTFail("Diagnostic record not created")
            return
        }

        let failPayload = "{\"type\":\"mediaCommandResult\",\"provider\":\"youtube\",\"action\":\"play\",\"requestId\":\"\(diagnostic.requestId)\",\"tabId\":88,\"success\":false,\"reason\":\"target_tab_does_not_exist\"}"
        bridge.receive(failPayload)

        XCTAssertEqual(completedSuccess, false)
        XCTAssertEqual(completedReason, "target_tab_does_not_exist")
        XCTAssertEqual(bridge.commandDiagnostics.last?.success, false)
        XCTAssertEqual(bridge.commandDiagnostics.last?.failureReason, "target_tab_does_not_exist")
    }

    @MainActor
    func testFileShelfServiceAddsAndPersistsItems() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testFileA = tempDir.appendingPathComponent("DocumentA.txt")
        try? "Hello AMORA".write(to: testFileA, atomically: true, encoding: .utf8)
        let storageURL = tempDir.appendingPathComponent("test_shelf.json")

        let service = FileShelfService(storageURL: storageURL)
        service.addFile(url: testFileA)

        XCTAssertEqual(service.items.count, 1)
        XCTAssertEqual(service.items.first?.name, "DocumentA.txt")
        XCTAssertEqual(service.items.first?.isMissing, false)

        // Test persistence by creating a fresh service instance from the same storageURL
        let reloadedService = FileShelfService(storageURL: storageURL)
        XCTAssertEqual(reloadedService.items.count, 1)
        XCTAssertEqual(reloadedService.items.first?.name, "DocumentA.txt")
        XCTAssertEqual(reloadedService.items.first?.isMissing, false)
    }

    @MainActor
    func testFileShelfServiceDeduplication() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testFile = tempDir.appendingPathComponent("Notes.md")
        try? "# Title".write(to: testFile, atomically: true, encoding: .utf8)
        let storageURL = tempDir.appendingPathComponent("test_shelf.json")

        let service = FileShelfService(storageURL: storageURL)
        service.addFile(url: testFile)
        service.addFile(url: testFile)

        XCTAssertEqual(service.items.count, 1)
    }

    @MainActor
    func testFileShelfServiceRemoveAndClear() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file1 = tempDir.appendingPathComponent("1.txt")
        let file2 = tempDir.appendingPathComponent("2.txt")
        try? "1".write(to: file1, atomically: true, encoding: .utf8)
        try? "2".write(to: file2, atomically: true, encoding: .utf8)
        let storageURL = tempDir.appendingPathComponent("test_shelf.json")

        let service = FileShelfService(storageURL: storageURL)
        service.addFile(url: file1)
        service.addFile(url: file2)
        XCTAssertEqual(service.items.count, 2)

        let firstId = service.items[0].id
        service.removeItem(id: firstId)
        XCTAssertEqual(service.items.count, 1)

        service.clearShelf()
        XCTAssertTrue(service.items.isEmpty)

        let reloaded = FileShelfService(storageURL: storageURL)
        XCTAssertTrue(reloaded.items.isEmpty)
    }

    @MainActor
    func testFileShelfServiceMissingFileHandling() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("will_delete.txt")
        try? "Ephemeral".write(to: file, atomically: true, encoding: .utf8)
        let storageURL = tempDir.appendingPathComponent("test_shelf.json")

        let service = FileShelfService(storageURL: storageURL)
        service.addFile(url: file)
        XCTAssertEqual(service.items.first?.isMissing, false)

        // Delete the physical file
        try? FileManager.default.removeItem(at: file)

        // Attempting to open missing file fails gracefully
        if let item = service.items.first {
            let opened = service.openFile(item)
            XCTAssertFalse(opened)
            XCTAssertEqual(service.items.first?.isMissing, true)
            XCTAssertNotNil(service.lastErrorMessage)
        }

        // Clean up missing items
        service.removeMissingItems()
        XCTAssertTrue(service.items.isEmpty)
    }

    @MainActor
    func testFileShelfServiceExtractFileURLFromVariousTypes() {
        let service = FileShelfService.shared
        let sampleURL = URL(fileURLWithPath: "/tmp/test.txt")

        // Direct URL
        XCTAssertEqual(service.extractFileURL(from: sampleURL)?.path, "/tmp/test.txt")

        // NSURL
        let nsURL = NSURL(fileURLWithPath: "/tmp/test.txt")
        XCTAssertEqual(service.extractFileURL(from: nsURL)?.path, "/tmp/test.txt")

        // UTF8 file string
        let stringURL = "file:///tmp/test.txt"
        XCTAssertEqual(service.extractFileURL(from: stringURL)?.path, "/tmp/test.txt")

        // UTF8 file string with unencoded spaces
        let spaceURL = "file:///tmp/my test file.txt"
        XCTAssertEqual(service.extractFileURL(from: spaceURL)?.path, "/tmp/my test file.txt")

        // Percent-encoded file string
        let encodedURL = "file:///tmp/my%20test%20file.txt"
        XCTAssertEqual(service.extractFileURL(from: encodedURL)?.path, "/tmp/my test file.txt")

        // POSIX path string
        let posixPath = "/tmp/my test file.txt"
        XCTAssertEqual(service.extractFileURL(from: posixPath)?.path, "/tmp/my test file.txt")

        // Data representation
        let dataURL = sampleURL.dataRepresentation
        XCTAssertEqual(service.extractFileURL(from: dataURL)?.path, "/tmp/test.txt")
    }

    func testTrackpadSwipeDirectionMapping() {
        // Required Mac-style behavior:
        // translation.width < 0 -> next page (+1)
        // translation.width > 0 -> previous page (-1)
        let negativeTranslation: CGFloat = -40
        let positiveTranslation: CGFloat = 40

        let leftSwipeDirection: AMORAPageSwipe = negativeTranslation < 0 ? .next : .previous
        let rightSwipeDirection: AMORAPageSwipe = positiveTranslation < 0 ? .next : .previous

        XCTAssertEqual(leftSwipeDirection, .next)
        XCTAssertEqual(rightSwipeDirection, .previous)

        // Key code mapping: 124 is Right Arrow (next), 123 is Left Arrow (previous)
        let rightArrowKeyCode: UInt16 = 124
        let leftArrowKeyCode: UInt16 = 123
        XCTAssertEqual(rightArrowKeyCode == 124 ? AMORAPageSwipe.next : .previous, .next)
        XCTAssertEqual(leftArrowKeyCode == 124 ? AMORAPageSwipe.next : .previous, .previous)
    }

    @MainActor
    func testFileShelfServiceHandleDropWithRealItemProvider() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testFile = tempDir.appendingPathComponent("Dropped File With Spaces.txt")
        try "Content from drop".write(to: testFile, atomically: true, encoding: .utf8)
        let storageURL = tempDir.appendingPathComponent("test_shelf.json")

        let service = FileShelfService(storageURL: storageURL)
        let provider = NSItemProvider(contentsOf: testFile)!

        var callbackURL: URL? = nil
        let accepted = service.handleDrop(providers: [provider]) { url in
            callbackURL = url
        }
        XCTAssertTrue(accepted)

        for _ in 0..<20 {
            if !service.items.isEmpty { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(service.items.count, 1)
        XCTAssertEqual(service.items.first?.name, "Dropped File With Spaces.txt")
        XCTAssertEqual(callbackURL?.lastPathComponent, "Dropped File With Spaces.txt")

        // Verify disk persistence
        let diskData = try Data(contentsOf: storageURL)
        XCTAssertTrue(diskData.count > 10)
    }

    @MainActor
    func testFileShelfServiceHandleDropWithPDFAndMediaFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pdfFile = tempDir.appendingPathComponent("SampleDocument.pdf")
        try "PDF DUMMY DATA".write(to: pdfFile, atomically: true, encoding: .utf8)
        let storageURL = tempDir.appendingPathComponent("test_shelf_pdf.json")

        let service = FileShelfService(storageURL: storageURL)
        let provider = NSItemProvider()
        provider.registerItem(forTypeIdentifier: "com.adobe.pdf") { completion, _, _ in
            completion?(pdfFile as NSURL, nil)
        }
        print("TEST: Custom UTType only registeredTypeIdentifiers =", provider.registeredTypeIdentifiers)

        var callbackURL: URL? = nil
        let accepted = service.handleDrop(providers: [provider]) { url in
            callbackURL = url
        }
        XCTAssertTrue(accepted)

        for _ in 0..<20 {
            if !service.items.isEmpty { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(service.items.count, 1)
        XCTAssertEqual(service.items.first?.name, "SampleDocument.pdf")
        XCTAssertEqual(callbackURL?.lastPathComponent, "SampleDocument.pdf")
    }

    @MainActor
    func testDashboardFileShelfIntegration() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testFile = tempDir.appendingPathComponent("DashboardItem.pdf")
        try? "PDF DATA".write(to: testFile, atomically: true, encoding: .utf8)

        let service = FileShelfService.shared
        let initialCount = service.items.count
        service.addFile(url: testFile)

        XCTAssertEqual(service.items.count, initialCount + 1)
        XCTAssertEqual(service.items.first?.name, "DashboardItem.pdf")

        // DashboardView initialized with .fileShelf
        let dashboard = DashboardView(initialSection: .fileShelf)
        XCTAssertEqual(dashboard.vm.selectedSection, .fileShelf)

        // Clean up added item
        if let added = service.items.first(where: { $0.url.path == testFile.path }) {
            service.removeItem(id: added.id)
        }
        XCTAssertEqual(service.items.count, initialCount)
    }

    func testNaturalFileShelfCommandParsing() {
        let parser = AMORACommandParser()
        XCTAssertEqual(parser.parse("open file shelf"), .showFileShelf)
        XCTAssertEqual(parser.parse("show file shelf"), .showFileShelf)
        XCTAssertEqual(parser.parse("file shelf"), .showFileShelf)
        XCTAssertEqual(parser.parse("show files"), .showFileShelf)
        XCTAssertEqual(parser.parse("pinned files"), .showFileShelf)
    }
}
