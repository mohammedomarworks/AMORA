import XCTest
@testable import AMORA

@MainActor
final class ActionEngineTests: XCTestCase {

    // MARK: - Test Mocks

    final class MockMediaController: AmoraMediaControlling, @unchecked Sendable {
        var playCallCount = 0
        var pauseCallCount = 0
        var nextCallCount = 0
        var previousCallCount = 0
        var isPlaying = false
        var isAvailable = true
        var trackTitle = "Test Song"
        var sourceName = "MockMusic"

        func play() { playCallCount += 1; isPlaying = true }
        func pause() { pauseCallCount += 1; isPlaying = false }
        func nextTrack() { nextCallCount += 1 }
        func previousTrack() { previousCallCount += 1 }
    }

    final class MockApplicationLauncher: AmoraApplicationLaunching, @unchecked Sendable {
        var availableApps: [String: URL] = [:]
        var openedURLs: [URL] = []
        var shouldFailLaunch = false

        func resolveApplicationURL(named name: String) -> URL? {
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return availableApps[normalized]
        }

        func openApplication(at url: URL) async throws {
            if shouldFailLaunch {
                throw NSError(domain: "MockApplicationLauncher", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
            }
            openedURLs.append(url)
        }
    }

    final class MockFolderOpener: AmoraFolderOpening, @unchecked Sendable {
        var resolvedFolders: [String: URL] = [:]
        var openedURLs: [URL] = []
        var shouldFail = false

        func resolveFolderURL(for location: String) -> URL? {
            let normalized = location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return resolvedFolders[normalized]
        }

        func openFolder(at url: URL) async throws {
            if shouldFail {
                throw NSError(domain: "MockFolderOpener", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
            }
            openedURLs.append(url)
        }
    }

    final class MockWorkspaceController: AmoraWorkspaceControlling, @unchecked Sendable {
        var showWorkspaceCallCount = 0
        var lastSection: String?

        func showWorkspace(section: String?) {
            showWorkspaceCallCount += 1
            lastSection = section
        }
    }

    final class MockTimerController: AmoraTimerControlling, @unchecked Sendable {
        var startTimerCallCount = 0
        var stopTimerCallCount = 0
        var lastSeconds: Int?
        var isRunning = false
        var isPaused = false
        var remainingSeconds = 0

        func startTimer(seconds: Int) {
            startTimerCallCount += 1
            lastSeconds = seconds
            isRunning = true
            remainingSeconds = seconds
        }

        func stopTimer() {
            stopTimerCallCount += 1
            isRunning = false
            remainingSeconds = 0
        }
    }

    // MARK: - Action Engine Factory Helper

    private func makeTestEngine(
        media: MockMediaController = MockMediaController(),
        launcher: MockApplicationLauncher = MockApplicationLauncher(),
        folder: MockFolderOpener = MockFolderOpener(),
        workspace: MockWorkspaceController = MockWorkspaceController(),
        timer: MockTimerController = MockTimerController()
    ) -> (AmoraActionEngine, MockMediaController, MockApplicationLauncher, MockFolderOpener, MockWorkspaceController, MockTimerController) {
        let registry = AmoraActionRegistry()
        AmoraActionEngine.registerDefaultActions(
            into: registry,
            mediaController: media,
            appLauncher: launcher,
            folderOpener: folder,
            workspaceController: workspace,
            timerController: timer
        )
        let engine = AmoraActionEngine(registry: registry)
        return (engine, media, launcher, folder, workspace, timer)
    }

    // MARK: - Tests

    func testValidActionRegistration() {
        let registry = AmoraActionRegistry()
        XCTAssertFalse(registry.isRegistered(identifier: "custom.action"))

        let definition = AmoraActionDefinition(
            identifier: "custom.action",
            name: "Custom Action",
            description: "A test action.",
            handler: { _, _ in .success(actionId: "custom.action", message: "Executed") }
        )
        registry.register(definition)

        XCTAssertTrue(registry.isRegistered(identifier: "custom.action"))
        XCTAssertEqual(registry.definition(for: "custom.action")?.name, "Custom Action")
        XCTAssertEqual(registry.allDescriptors.count, 1)
        XCTAssertEqual(registry.allDescriptors.first?.id, "custom.action")
    }

    func testLookupOfKnownActions() {
        let (engine, _, _, _, _, _) = makeTestEngine()
        let expectedIdentifiers = [
            "app.open",
            "folder.open",
            "media.next",
            "media.pause",
            "media.play",
            "media.previous",
            "timer.cancel",
            "timer.pause",
            "timer.resume",
            "timer.start",
            "workspace.open"
        ]
        XCTAssertEqual(engine.registry.registeredIdentifiers, expectedIdentifiers)

        for id in expectedIdentifiers {
            let def = engine.registry.definition(for: id)
            XCTAssertNotNil(def, "Action definition for \(id) should exist")
            XCTAssertFalse(def!.name.isEmpty)
            XCTAssertFalse(def!.description.isEmpty)
        }
    }

    func testUnknownActionRejection() async {
        let (engine, _, _, _, _, _) = makeTestEngine()
        engine.registry.unregister(identifier: "media.play")

        let result = await engine.execute(.playMusic)
        XCTAssertEqual(result.status, .unavailable)
        XCTAssertTrue(result.message.contains("not registered"))
    }

    func testSuccessfulMediaActionRoutingUsingMocks() async {
        let (engine, media, _, _, _, _) = makeTestEngine()

        // 1. Play
        let playResult = await engine.execute(.playMusic)
        XCTAssertEqual(playResult.status, .success)
        XCTAssertEqual(media.playCallCount, 1)
        XCTAssertTrue(media.isPlaying)

        // 2. Pause
        let pauseResult = await engine.execute(.pauseMusic)
        XCTAssertEqual(pauseResult.status, .success)
        XCTAssertEqual(media.pauseCallCount, 1)
        XCTAssertFalse(media.isPlaying)

        // 3. Next
        let nextResult = await engine.execute(.nextTrack)
        XCTAssertEqual(nextResult.status, .success)
        XCTAssertEqual(media.nextCallCount, 1)

        // 4. Previous
        let prevResult = await engine.execute(.previousTrack)
        XCTAssertEqual(prevResult.status, .success)
        XCTAssertEqual(media.previousCallCount, 1)
    }

    func testApplicationNotFoundHandling() async {
        let (engine, _, launcher, _, _, _) = makeTestEngine()
        launcher.availableApps = ["safari": URL(fileURLWithPath: "/Applications/Safari.app")]

        let result = await engine.execute(.openApplication(name: "NonExistentApp12345"))
        XCTAssertEqual(result.status, .unavailable)
        XCTAssertTrue(result.message.contains("Could not find application"))
        XCTAssertTrue(launcher.openedURLs.isEmpty)
    }

    func testApplicationLaunchSuccessUsingMock() async {
        let (engine, _, launcher, _, _, _) = makeTestEngine()
        let fakeURL = URL(fileURLWithPath: "/Applications/Safari.app")
        launcher.availableApps = ["safari": fakeURL]

        let result = await engine.execute(.openApplication(name: "Safari"))
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.data["appURL"], fakeURL.path)
        XCTAssertEqual(launcher.openedURLs.count, 1)
        XCTAssertEqual(launcher.openedURLs.first, fakeURL)
    }

    func testApplicationLaunchValidationRejectsEmptyName() async {
        let (engine, _, launcher, _, _, _) = makeTestEngine()

        let result = await engine.execute(.openApplication(name: "   "))
        XCTAssertEqual(result.status, .invalidInput)
        XCTAssertTrue(result.message.contains("cannot be empty"))
        XCTAssertTrue(launcher.openedURLs.isEmpty)
    }

    func testApplicationLaunchFailureHandledGracefully() async {
        let (engine, _, launcher, _, _, _) = makeTestEngine()
        let fakeURL = URL(fileURLWithPath: "/Applications/Broken.app")
        launcher.availableApps = ["broken": fakeURL]
        launcher.shouldFailLaunch = true

        let result = await engine.execute(.openApplication(name: "Broken"))
        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.message.contains("Failed to open Broken"))
    }

    func testFolderActionValidationAndExecutionUsingMock() async {
        let (engine, _, _, folder, _, _) = makeTestEngine()
        let fakeDownloads = URL(fileURLWithPath: "/fake/Downloads")
        folder.resolvedFolders = ["downloads": fakeDownloads, "documents": URL(fileURLWithPath: "/fake/Documents")]

        // Valid folder
        let result = await engine.execute(.openFolder(location: "Downloads"))
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(folder.openedURLs.count, 1)
        XCTAssertEqual(folder.openedURLs.first, fakeDownloads)

        // Invalid folder location
        let invalidResult = await engine.execute(.openFolder(location: "system/etc"))
        XCTAssertEqual(invalidResult.status, .invalidInput)
        XCTAssertTrue(invalidResult.message.contains("not a permitted folder"))

        // Unresolved folder
        let missingResult = await engine.execute(.openFolder(location: "Desktop"))
        XCTAssertEqual(missingResult.status, .unavailable)

        // Opener error
        folder.shouldFail = true
        let failedResult = await engine.execute(.openFolder(location: "Downloads"))
        XCTAssertEqual(failedResult.status, .failed)
    }

    func testWorkspaceActionRouting() async {
        let (engine, _, _, _, workspace, _) = makeTestEngine()

        let defaultResult = await engine.execute(.openWorkspace(section: nil))
        XCTAssertEqual(defaultResult.status, .success)
        XCTAssertEqual(workspace.showWorkspaceCallCount, 1)
        XCTAssertNil(workspace.lastSection)

        let sectionResult = await engine.execute(.openWorkspace(section: "Notes"))
        XCTAssertEqual(sectionResult.status, .success)
        XCTAssertEqual(workspace.showWorkspaceCallCount, 2)
        XCTAssertEqual(workspace.lastSection, "Notes")
        XCTAssertEqual(sectionResult.data["section"], "Notes")
    }

    func testTimerValidationAndExecution() async {
        let (engine, _, _, _, _, timer) = makeTestEngine()

        // Valid timer
        let validResult = await engine.execute(.startTimer(duration: 1500))
        XCTAssertEqual(validResult.status, .success)
        XCTAssertEqual(timer.startTimerCallCount, 1)
        XCTAssertEqual(timer.lastSeconds, 1500)
        XCTAssertEqual(validResult.data["seconds"], "1500")

        // Invalid: 0 seconds
        let zeroResult = await engine.execute(.startTimer(duration: 0))
        XCTAssertEqual(zeroResult.status, .invalidInput)

        // Invalid: negative seconds
        let negResult = await engine.execute(.startTimer(duration: -10))
        XCTAssertEqual(negResult.status, .invalidInput)

        // Invalid: > 24 hours (86,400s)
        let tooLongResult = await engine.execute(.startTimer(duration: 90_000))
        XCTAssertEqual(tooLongResult.status, .invalidInput)

        // Cancel timer when running
        timer.isRunning = true
        let cancelResult = await engine.execute(.cancelTimer)
        XCTAssertEqual(cancelResult.status, .success)
        XCTAssertEqual(timer.stopTimerCallCount, 1)

        // Cancel timer when NOT running -> clarifies rather than inventing a duration
        timer.isRunning = false
        let cancelNotRunning = await engine.execute(.cancelTimer)
        XCTAssertEqual(cancelNotRunning.status, .unavailable)
        XCTAssertTrue(cancelNotRunning.message.contains("active timer"))
    }

    func testTimerPauseAndResumeUnsupported() async {
        let (engine, _, _, _, _, _) = makeTestEngine()

        let pauseResult = await engine.execute(.pauseTimer)
        XCTAssertEqual(pauseResult.status, .unavailable)
        XCTAssertEqual(pauseResult.message, "I can stop the timer, but pause/resume isn't available yet.")

        let resumeResult = await engine.execute(.resumeTimer)
        XCTAssertEqual(resumeResult.status, .unavailable)
        XCTAssertEqual(resumeResult.message, "I can stop the timer, but pause/resume isn't available yet.")
    }

    func testConfirmationMetadataAndFlow() async {
        let registry = AmoraActionRegistry()
        registry.register(AmoraActionDefinition(
            identifier: "sensitive.action",
            name: "Sensitive Action",
            description: "An action requiring user confirmation.",
            isConfirmationRequiredByDefault: true,
            confirmationRequirement: { _ in .required(prompt: "Are you sure you want to proceed?") },
            handler: { _, _ in .success(actionId: "sensitive.action", message: "Performed safely") }
        ))

        // Custom action descriptor verification
        let descriptor = registry.definition(for: "sensitive.action")?.descriptor
        XCTAssertEqual(descriptor?.isConfirmationRequired, true)

        // Test with engine: register on existing action id
        let confirmedRegistry = AmoraActionRegistry()
        confirmedRegistry.register(AmoraActionDefinition(
            identifier: "workspace.open",
            name: "Open Workspace Confirmed",
            description: "Test confirmation on workspace",
            confirmationRequirement: { _ in .required(prompt: "Confirm opening workspace?") },
            handler: { _, _ in .success(actionId: "workspace.open", message: "Workspace opened") }
        ))
        let confirmedEngine = AmoraActionEngine(registry: confirmedRegistry)

        // 1. Unconfirmed context returns .needsConfirmation
        let unconfirmedResult = await confirmedEngine.execute(.openWorkspace(section: nil), context: AmoraActionContext(isConfirmed: false))
        XCTAssertEqual(unconfirmedResult.status, .needsConfirmation)
        XCTAssertEqual(unconfirmedResult.message, "Confirm opening workspace?")

        // 2. Confirmed context executes handler
        let confirmedResult = await confirmedEngine.execute(.openWorkspace(section: nil), context: AmoraActionContext(isConfirmed: true))
        XCTAssertEqual(confirmedResult.status, .success)
        XCTAssertEqual(confirmedResult.message, "Workspace opened")
    }

    func testAmoraActionRequestResolution() {
        // Media
        XCTAssertEqual(AmoraActionRequest(actionId: "media.play").resolveAction(), .success(.playMusic))
        XCTAssertEqual(AmoraActionRequest(actionId: "media.pause").resolveAction(), .success(.pauseMusic))
        XCTAssertEqual(AmoraActionRequest(actionId: "media.next").resolveAction(), .success(.nextTrack))
        XCTAssertEqual(AmoraActionRequest(actionId: "media.previous").resolveAction(), .success(.previousTrack))

        // App
        XCTAssertEqual(
            AmoraActionRequest(actionId: "app.open", parameters: ["name": "Slack"]).resolveAction(),
            .success(.openApplication(name: "Slack"))
        )
        XCTAssertEqual(
            AmoraActionRequest(actionId: "app.open", parameters: [:]).resolveAction(),
            .failure(.missingParameter("Missing required 'name' parameter for openApplication action."))
        )

        // Folder
        XCTAssertEqual(
            AmoraActionRequest(actionId: "folder.open", parameters: ["location": "Downloads"]).resolveAction(),
            .success(.openFolder(location: "Downloads"))
        )
        XCTAssertEqual(
            AmoraActionRequest(actionId: "folder.open", parameters: [:]).resolveAction(),
            .failure(.missingParameter("Missing required 'location' parameter for folder.open action."))
        )

        // Workspace
        XCTAssertEqual(
            AmoraActionRequest(actionId: "workspace.open", parameters: ["section": "Notes"]).resolveAction(),
            .success(.openWorkspace(section: "Notes"))
        )

        // Timer
        XCTAssertEqual(
            AmoraActionRequest(actionId: "timer.start", parameters: ["duration": "1200"]).resolveAction(),
            .success(.startTimer(duration: 1200))
        )
        XCTAssertEqual(
            AmoraActionRequest(actionId: "timer.cancel").resolveAction(),
            .success(.cancelTimer)
        )
        XCTAssertEqual(
            AmoraActionRequest(actionId: "cancel_timer").resolveAction(),
            .success(.cancelTimer)
        )
        XCTAssertEqual(
            AmoraActionRequest(actionId: "stop_timer").resolveAction(),
            .success(.cancelTimer)
        )
        XCTAssertEqual(
            AmoraActionRequest(actionId: "turn_off_timer").resolveAction(),
            .success(.cancelTimer)
        )
        XCTAssertEqual(
            AmoraActionRequest(actionId: "timer.pause").resolveAction(),
            .success(.pauseTimer)
        )
        XCTAssertEqual(
            AmoraActionRequest(actionId: "timer.resume").resolveAction(),
            .success(.resumeTimer)
        )
        XCTAssertEqual(
            AmoraActionRequest(actionId: "timer.start", parameters: ["duration": "-5"]).resolveAction(),
            .failure(.invalidParameter("Missing or invalid 'duration' parameter for startTimer action."))
        )

        // Unknown
        XCTAssertEqual(
            AmoraActionRequest(actionId: "arbitrary.shell").resolveAction(),
            .failure(.unknownAction("Unknown action identifier: 'arbitrary.shell'."))
        )
    }

    func testAmoraActionPlanDecodingFromAIJSON() {
        let json = """
        {
            "actions": [
                {"action": "media.play"},
                {"action": "timer.start", "duration": 600},
                {"action": "app.open", "name": "Terminal"},
                {"action": "folder.open", "location": "Downloads"},
                {"action": "workspace.open", "section": "Clipboard"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let plan = try? JSONDecoder().decode(AmoraActionPlan.self, from: data)
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.actions.count, 5)

        let resolved = plan!.resolveActions()
        XCTAssertEqual(resolved.count, 5)
        XCTAssertEqual(resolved[0], .success(.playMusic))
        XCTAssertEqual(resolved[1], .success(.startTimer(duration: 600)))
        XCTAssertEqual(resolved[2], .success(.openApplication(name: "Terminal")))
        XCTAssertEqual(resolved[3], .success(.openFolder(location: "Downloads")))
        XCTAssertEqual(resolved[4], .success(.openWorkspace(section: "Clipboard")))
    }

    func testAssistantExecutesAmoraActionPlanWithMockProvider() async {
        let jsonResponse = """
        {"actions":[{"action":"media.play"}]}
        """
        let provider = MockAIProvider(response: jsonResponse)
        let assistant = AssistantManager(provider: provider)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil)

        let answer = await assistant.submit("play music for me", settings: settings)
        XCTAssertFalse(answer.isEmpty)
        XCTAssertTrue(answer.contains("playback started") || answer.contains("Music"))
    }

    func testStaleContextTimerCancellationInAssistant() async {
        // Mock provider produces timer.start with 10 from previous conversation turn,
        // but user says "Cancel the timer."
        let staleResponse = """
        {"actions":[{"action":"timer.start","duration":10}]}
        """
        let provider = MockAIProvider(response: staleResponse)
        let assistant = AssistantManager(provider: provider)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil)

        // Ensure timer is running first
        TimerService.shared.startTimer(seconds: 10)
        XCTAssertTrue(TimerService.shared.isRunning)

        let answer = await assistant.submit("Cancel the timer.", settings: settings)
        XCTAssertEqual(answer, "Timer stopped.")
        XCTAssertFalse(TimerService.shared.isRunning)
    }

    func testUnsafeShellActionsRejectedFromActionPlan() {
        let json = """
        {
            "actions": [
                {"action": "shell.exec", "name": "rm -rf /"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let plan = try? JSONDecoder().decode(AmoraActionPlan.self, from: data)
        XCTAssertNotNil(plan)
        let resolved = plan!.resolveActions()
        XCTAssertEqual(resolved.count, 1)
        if case .failure(let error) = resolved[0] {
            XCTAssertTrue(error.message.contains("Unknown action identifier"))
        } else {
            XCTFail("Unsafe shell command should not resolve into an AmoraAction")
        }
    }

    func testNativeFolderOpenerCanonicalPaths() {
        let opener = NativeAmoraFolderOpener()
        XCTAssertNotNil(opener.resolveFolderURL(for: "downloads"))
        XCTAssertNotNil(opener.resolveFolderURL(for: "documents"))
        XCTAssertNotNil(opener.resolveFolderURL(for: "desktop"))
        XCTAssertNotNil(opener.resolveFolderURL(for: "home"))
        XCTAssertNil(opener.resolveFolderURL(for: "unsupported_path_xyz"))
    }

    func testNativeApplicationLauncherDynamic() {
        let launcher = NativeAmoraApplicationLauncher()
        // Finder is a standard macOS CoreServices app
        XCTAssertNotNil(launcher.resolveApplicationURL(named: "Finder"))
        XCTAssertNotNil(launcher.resolveApplicationURL(named: "finder.app"))
        // Nonexistent app
        XCTAssertNil(launcher.resolveApplicationURL(named: "NonExistentApp12345"))
    }

    func testCommandParserTimerVariations() {
        let parser = AMORACommandParser()

        // Timer starts
        XCTAssertEqual(parser.parse("start a timer for 10 seconds"), .startTimer(duration: 10))
        XCTAssertEqual(parser.parse("set a 10 second timer"), .startTimer(duration: 10))
        XCTAssertEqual(parser.parse("start a 10 minute timer"), .startTimer(duration: 600))
        XCTAssertEqual(parser.parse("start a timer for 25 minutes"), .startTimer(duration: 1500))

        // Timer cancellations
        XCTAssertEqual(parser.parse("cancel the timer"), .stopTimer)
        XCTAssertEqual(parser.parse("stop the timer"), .stopTimer)
        XCTAssertEqual(parser.parse("end the timer"), .stopTimer)
        XCTAssertEqual(parser.parse("cancel my timer"), .stopTimer)
        XCTAssertEqual(parser.parse("stop my timer"), .stopTimer)
        XCTAssertEqual(parser.parse("turn off the timer"), .stopTimer)
        XCTAssertEqual(parser.parse("clear the timer"), .stopTimer)
        XCTAssertEqual(parser.parse("cancel timer"), .stopTimer)
        XCTAssertEqual(parser.parse("stop timer"), .stopTimer)

        // Timer pause and resume
        XCTAssertEqual(parser.parse("pause the timer"), .pauseTimer)
        XCTAssertEqual(parser.parse("pause timer"), .pauseTimer)
        XCTAssertEqual(parser.parse("resume the timer"), .resumeTimer)
        XCTAssertEqual(parser.parse("resume timer"), .resumeTimer)
    }

    func testCommandParserAppsAndFolders() {
        let parser = AMORACommandParser()

        // Applications
        XCTAssertEqual(parser.parse("open VS Code"), .openApplication(name: "vs code"))
        XCTAssertEqual(parser.parse("open Finder"), .openApplication(name: "finder"))
        XCTAssertEqual(parser.parse("open WhatsApp"), .openApplication(name: "whatsapp"))
        XCTAssertEqual(parser.parse("open Safari"), .openApplication(name: "safari"))
        XCTAssertEqual(parser.parse("open Terminal"), .openApplication(name: "terminal"))
        XCTAssertEqual(parser.parse("open Spotify"), .openApplication(name: "spotify"))

        // Folders
        XCTAssertEqual(parser.parse("open Downloads"), .openFolder(name: "downloads"))
        XCTAssertEqual(parser.parse("show Downloads"), .openFolder(name: "downloads"))
        XCTAssertEqual(parser.parse("open Documents"), .openFolder(name: "documents"))
        XCTAssertEqual(parser.parse("show Documents"), .openFolder(name: "documents"))
        XCTAssertEqual(parser.parse("open Desktop"), .openFolder(name: "desktop"))
        XCTAssertEqual(parser.parse("show Desktop"), .openFolder(name: "desktop"))
        XCTAssertEqual(parser.parse("open Home"), .openFolder(name: "home"))
        XCTAssertEqual(parser.parse("show Home"), .openFolder(name: "home"))
    }

    func testRouterTimerCancelWhenInactive() {
        TimerService.shared.stopTimer()
        let router = AMORACommandRouter.shared

        let result = router.execute(.stopTimer)
        XCTAssertEqual(result, .failure(message: "I don't see an active timer. Would you like to start one?"))

        let unknownCancelResult = router.execute(.unknown(text: "cancel the timer"))
        XCTAssertEqual(unknownCancelResult, .failure(message: "I don't see an active timer. Would you like to start one?"))

        let unknownStopResult = router.execute(.unknown(text: "stop the timer"))
        XCTAssertEqual(unknownStopResult, .failure(message: "I don't see an active timer. Would you like to start one?"))
    }

    func testPhysical12UserCommands() async {
        let gateway = AMORACommandGateway()
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil)

        // 1. "Start a 10 second timer."
        let r1 = await gateway.submit("Start a 10 second timer.", settings: settings)
        XCTAssertEqual(r1, .success(message: "Let's focus. 10 seconds starts now."))
        XCTAssertTrue(TimerService.shared.isRunning)

        // 2. "Stop the timer."
        let r2 = await gateway.submit("Stop the timer.", settings: settings)
        XCTAssertEqual(r2, .success(message: "Timer stopped."))
        XCTAssertFalse(TimerService.shared.isRunning)

        // 3. "Start a 20 second timer."
        let r3 = await gateway.submit("Start a 20 second timer.", settings: settings)
        XCTAssertEqual(r3, .success(message: "Let's focus. 20 seconds starts now."))
        XCTAssertTrue(TimerService.shared.isRunning)

        // 4. "Cancel the timer."
        let r4 = await gateway.submit("Cancel the timer.", settings: settings)
        XCTAssertEqual(r4, .success(message: "Timer stopped."))
        XCTAssertFalse(TimerService.shared.isRunning)

        // 5. "Open VS Code."
        let r5 = await gateway.submit("Open VS Code.", settings: settings)
        XCTAssertEqual(r5, .success(message: "Opening Vs Code."))

        // 6. "Open Finder."
        let r6 = await gateway.submit("Open Finder.", settings: settings)
        XCTAssertEqual(r6, .success(message: "Opening Finder."))

        // 7. "Open Spotify."
        let r7 = await gateway.submit("Open Spotify.", settings: settings)
        XCTAssertEqual(r7, .success(message: "Opening Spotify."))

        // 8. "Open WhatsApp."
        let r8 = await gateway.submit("Open WhatsApp.", settings: settings)
        XCTAssertEqual(r8, .success(message: "Opening Whatsapp."))

        // 9. "Open Downloads."
        let r9 = await gateway.submit("Open Downloads.", settings: settings)
        XCTAssertEqual(r9, .success(message: "Opening Downloads."))

        // 10. "Open Documents."
        let r10 = await gateway.submit("Open Documents.", settings: settings)
        XCTAssertEqual(r10, .success(message: "Opening Documents."))

        // 11. "Open NonExistentApp12345."
        let r11 = await gateway.submit("Open NonExistentApp12345.", settings: settings)
        XCTAssertEqual(r11, .failure(message: "I couldn't find that app."))

        // 12. "Run rm -rf /"
        let r12 = await gateway.submit("Run rm -rf /", settings: settings)
        // Must never succeed as an execution, must be safely rejected / unsupported
        if case .success = r12 {
            XCTFail("Unsafe shell command must not succeed: \(r12)")
        }
    }
}

