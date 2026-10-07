import XCTest
@testable import AMORA

@MainActor
final class ContextAwareActionDecisionTests: XCTestCase {

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

    final class MockAppLauncher: AmoraApplicationLaunching, @unchecked Sendable {
        var availableApps: [String: URL] = [:]
        var openedURLs: [URL] = []
        var shouldFailLaunch = false

        func resolveApplicationURL(named name: String) -> URL? {
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return availableApps[normalized]
        }

        func openApplication(at url: URL) async throws {
            if shouldFailLaunch {
                throw NSError(domain: "MockAppLauncher", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
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

    // Helper to build test snapshot
    private func makeSnapshot(
        app: AmoraApplicationContext? = nil,
        media: AmoraMediaContext? = nil,
        timer: AmoraTimerContext? = nil,
        amora: AmoraUIContext? = nil,
        battery: AmoraBatteryContext? = nil,
        shelf: AmoraFileShelfContext? = nil
    ) -> AmoraContextSnapshot {
        AmoraContextSnapshot(
            timestamp: Date(),
            currentApplication: app,
            media: media,
            timer: timer,
            battery: battery,
            amora: amora,
            fileShelf: shelf,
            formattedLocalTime: "12:00 PM"
        )
    }

    // Helper to create test engine with mocks
    private func makeTestEngine(decider: any AmoraActionDeciding = AmoraActionDecisionEngine()) -> (
        engine: AmoraActionEngine,
        media: MockMediaController,
        app: MockAppLauncher,
        folder: MockFolderOpener,
        workspace: MockWorkspaceController,
        timer: MockTimerController
    ) {
        let media = MockMediaController()
        let app = MockAppLauncher()
        let folder = MockFolderOpener()
        let workspace = MockWorkspaceController()
        let timer = MockTimerController()

        let registry = AmoraActionRegistry()
        AmoraActionEngine.registerDefaultActions(
            into: registry,
            mediaController: media,
            appLauncher: app,
            folderOpener: folder,
            workspaceController: workspace,
            timerController: timer
        )
        let engine = AmoraActionEngine(registry: registry, decider: decider)
        return (engine, media, app, folder, workspace, timer)
    }

    // MARK: - 1. Pause Music When Already Paused

    func testPauseMusicWhenAlreadyPausedReportsState() {
        let decider = AmoraActionDecisionEngine()
        let snapshot = makeSnapshot(
            media: AmoraMediaContext(source: "Spotify", state: "paused", title: "Blinding Lights", artist: "The Weeknd")
        )
        let context = AmoraActionContext(snapshot: snapshot)

        let decision = decider.decide(action: .pauseMusic, context: context)
        XCTAssertTrue(decision.isAlreadyInState)
        if case let .alreadyInState(actionId, message, data) = decision {
            XCTAssertEqual(actionId, "media.pause")
            XCTAssertEqual(message, "Music is already paused.")
            XCTAssertEqual(data["source"], "Spotify")
        } else {
            XCTFail("Expected .alreadyInState")
        }
    }

    func testPauseMusicWhenPlayingExecutes() {
        let decider = AmoraActionDecisionEngine()
        let snapshot = makeSnapshot(
            media: AmoraMediaContext(source: "Spotify", state: "playing", title: "Blinding Lights", artist: "The Weeknd")
        )
        let context = AmoraActionContext(snapshot: snapshot)

        let decision = decider.decide(action: .pauseMusic, context: context)
        XCTAssertEqual(decision, .execute(.pauseMusic))
    }

    // MARK: - 2. Start Spotify When Active Playing Media

    func testStartSpotifyWhenSpotifyIsAlreadyActivePlayingAvoidsRedundantAction() {
        let decider = AmoraActionDecisionEngine()
        let snapshot = makeSnapshot(
            media: AmoraMediaContext(source: "Spotify", state: "playing", title: "Midnight City", artist: "M83")
        )
        let context = AmoraActionContext(snapshot: snapshot)

        let decision = decider.decide(action: .openApplication(name: "Spotify"), context: context)
        XCTAssertTrue(decision.isAlreadyInState)
        if case let .alreadyInState(actionId, message, data) = decision {
            XCTAssertEqual(actionId, "app.open")
            XCTAssertEqual(message, "Music is already playing on Spotify.")
            XCTAssertEqual(data["source"], "Spotify")
        } else {
            XCTFail("Expected .alreadyInState")
        }
    }

    func testStartSpotifyWhenAnotherAppIsPlayingExecutes() {
        let decider = AmoraActionDecisionEngine()
        let snapshot = makeSnapshot(
            media: AmoraMediaContext(source: "Apple Music", state: "playing", title: "Song", artist: "Artist")
        )
        let context = AmoraActionContext(snapshot: snapshot)

        let decision = decider.decide(action: .openApplication(name: "Spotify"), context: context)
        XCTAssertEqual(decision, .execute(.openApplication(name: "Spotify")))
    }

    // MARK: - 3. Open Workspace When Already Open

    func testOpenWorkspaceWhenAlreadyOpenReportsAlreadyOpen() {
        let decider = AmoraActionDecisionEngine()
        let snapshot = makeSnapshot(amora: AmoraUIContext(state: "workspace"))
        let context = AmoraActionContext(snapshot: snapshot)

        let decision = decider.decide(action: .openWorkspace(section: nil), context: context)
        XCTAssertTrue(decision.isAlreadyInState)
        if case let .alreadyInState(actionId, message, data) = decision {
            XCTAssertEqual(actionId, "workspace.open")
            XCTAssertEqual(message, "Workspace is already open.")
            XCTAssertEqual(data["state"], "workspace")
        } else {
            XCTFail("Expected .alreadyInState")
        }
    }

    func testOpenWorkspaceWithSpecificSectionExecutesEvenIfWorkspaceIsOpen() {
        let decider = AmoraActionDecisionEngine()
        let snapshot = makeSnapshot(amora: AmoraUIContext(state: "workspace"))
        let context = AmoraActionContext(snapshot: snapshot)

        // Requesting a specific section should execute so user can navigate to that section
        let decision = decider.decide(action: .openWorkspace(section: "Notes"), context: context)
        XCTAssertEqual(decision, .execute(.openWorkspace(section: "Notes")))
    }

    func testOpenWorkspaceWhenCollapsedExecutes() {
        let decider = AmoraActionDecisionEngine()
        let snapshot = makeSnapshot(amora: AmoraUIContext(state: "collapsed"))
        let context = AmoraActionContext(snapshot: snapshot)

        let decision = decider.decide(action: .openWorkspace(section: nil), context: context)
        XCTAssertEqual(decision, .execute(.openWorkspace(section: nil)))
    }

    // MARK: - 4. Equivalent Active Timer Handling

    func testStartTimerWhenEquivalentTimerIsRunningReportsAlreadyRunning() {
        let decider = AmoraActionDecisionEngine()
        let snapshot = makeSnapshot(
            timer: AmoraTimerContext(running: true, remainingSeconds: 295, duration: 300, isPaused: false)
        )
        let context = AmoraActionContext(snapshot: snapshot)

        let decision = decider.decide(action: .startTimer(duration: 300), context: context)
        XCTAssertTrue(decision.isAlreadyInState)
        if case let .alreadyInState(actionId, message, data) = decision {
            XCTAssertEqual(actionId, "timer.start")
            XCTAssertTrue(message.contains("already running"))
            XCTAssertTrue(message.contains("5 minute") || message.contains("300"))
            XCTAssertEqual(data["seconds"], "300")
            XCTAssertEqual(data["remainingSeconds"], "295")
        } else {
            XCTFail("Expected .alreadyInState")
        }
    }

    func testStartTimerWhenDifferentDurationIsRequestedExecutes() {
        let decider = AmoraActionDecisionEngine()
        let snapshot = makeSnapshot(
            timer: AmoraTimerContext(running: true, remainingSeconds: 295, duration: 300, isPaused: false)
        )
        let context = AmoraActionContext(snapshot: snapshot)

        // Starting a 10m timer (600s) when a 5m timer is running is allowed to execute
        let decision = decider.decide(action: .startTimer(duration: 600), context: context)
        XCTAssertEqual(decision, .execute(.startTimer(duration: 600)))
    }

    func testStartTimerWhenNoTimerIsRunningExecutes() {
        let decider = AmoraActionDecisionEngine()
        let snapshot = makeSnapshot(timer: .stopped)
        let context = AmoraActionContext(snapshot: snapshot)

        let decision = decider.decide(action: .startTimer(duration: 300), context: context)
        XCTAssertEqual(decision, .execute(.startTimer(duration: 300)))
    }

    // MARK: - 5. Application Already Open

    func testOpenApplicationWhenAlreadyFrontmostReportsAlreadyOpen() {
        let decider = AmoraActionDecisionEngine()
        let snapshot = makeSnapshot(
            app: AmoraApplicationContext(name: "Safari", bundleIdentifier: "com.apple.Safari")
        )
        let context = AmoraActionContext(snapshot: snapshot)

        let decision = decider.decide(action: .openApplication(name: "Safari"), context: context)
        XCTAssertTrue(decision.isAlreadyInState)
        if case let .alreadyInState(actionId, message, _) = decision {
            XCTAssertEqual(actionId, "app.open")
            XCTAssertEqual(message, "Safari is already open.")
        } else {
            XCTFail("Expected .alreadyInState")
        }
    }

    // MARK: - 6. Context Awareness Disabled (OFF)

    func testContextAwarenessDisabledOmitsContextSnapshotAndExecutesAll() {
        let decider = AmoraActionDecisionEngine()
        // snapshot is nil when contextAwarenessEnabled is false
        let context = AmoraActionContext(snapshot: nil)

        // All decisions must evaluate to .execute when context is absent
        XCTAssertEqual(decider.decide(action: .pauseMusic, context: context), .execute(.pauseMusic))
        XCTAssertEqual(decider.decide(action: .openApplication(name: "Spotify"), context: context), .execute(.openApplication(name: "Spotify")))
        XCTAssertEqual(decider.decide(action: .openWorkspace(section: nil), context: context), .execute(.openWorkspace(section: nil)))
        XCTAssertEqual(decider.decide(action: .startTimer(duration: 300), context: context), .execute(.startTimer(duration: 300)))
    }

    // MARK: - 7. Multi-Step Plan Progression (Compound Commands)

    func testPlanCompoundCommandSimulatesStateProgression() {
        let decider = AmoraActionDecisionEngine()
        let initialSnapshot = makeSnapshot(
            media: AmoraMediaContext(source: "Spotify", state: "paused", title: "Song", artist: "Artist"),
            amora: AmoraUIContext(state: "collapsed")
        )
        let context = AmoraActionContext(snapshot: initialSnapshot)

        // Compound plan:
        // 1. open workspace (currently collapsed -> executes)
        // 2. open workspace again (now workspace is simulated open -> already in state!)
        // 3. play music (currently paused -> executes)
        // 4. open Spotify (now playing Spotify -> already in state!)
        let actions: [AmoraAction] = [
            .openWorkspace(section: nil),
            .openWorkspace(section: nil),
            .playMusic,
            .openApplication(name: "Spotify")
        ]

        let planDecisions = decider.plan(actions: actions, context: context)
        XCTAssertEqual(planDecisions.count, 4)

        XCTAssertEqual(planDecisions[0].decision, AmoraActionDecision.execute(.openWorkspace(section: nil)))
        XCTAssertTrue(planDecisions[1].decision.isAlreadyInState)
        XCTAssertEqual(planDecisions[2].decision, AmoraActionDecision.execute(.playMusic))
        XCTAssertTrue(planDecisions[3].decision.isAlreadyInState)
    }

    // MARK: - 8. Engine Execution of Context-Aware Compound Commands

    func testEngineExecutesCompoundSequenceWithAlreadyInStateSteps() async {
        let (engine, media, _, folder, workspace, _) = makeTestEngine()
        folder.resolvedFolders = ["downloads": URL(fileURLWithPath: "/fake/Downloads")]

        // Initial snapshot: Music is already paused, Workspace is open
        let snapshot = makeSnapshot(
            media: AmoraMediaContext(source: "Spotify", state: "paused"),
            amora: AmoraUIContext(state: "workspace")
        )
        let context = AmoraActionContext(snapshot: snapshot)

        // Compound command: Pause music, open workspace, open Downloads
        let actions: [AmoraAction] = [
            .pauseMusic,
            .openWorkspace(section: nil),
            .openFolder(location: "Downloads")
        ]

        let results = await engine.executeSequence(actions, context: context)
        XCTAssertEqual(results.count, 3)

        // Step 0: Already paused
        XCTAssertTrue(results[0].isAlreadyInState)
        XCTAssertEqual(results[0].message, "Music is already paused.")
        XCTAssertEqual(media.pauseCallCount, 0, "Should not call pause on controller when already paused")

        // Step 1: Already open workspace
        XCTAssertTrue(results[1].isAlreadyInState)
        XCTAssertEqual(results[1].message, "Workspace is already open.")
        XCTAssertEqual(workspace.showWorkspaceCallCount, 0, "Should not call showWorkspace when already open")

        // Step 2: Open Downloads
        XCTAssertEqual(results[2].status, .success)
        XCTAssertEqual(folder.openedURLs.count, 1)

        // Truthful combined message includes all states
        let combined = AmoraActionResult.combineMessages(from: results)
        XCTAssertTrue(combined.contains("Music is already paused."))
        XCTAssertTrue(combined.contains("Workspace is already open."))
        XCTAssertTrue(combined.contains("Opening Downloads."))
    }

    // MARK: - 9. Safety & Confirmation Preservation

    func testConfirmationPreservedForSensitiveActionsUnderContextDecisions() async {
        let (engine, _, _, _, _, _) = makeTestEngine()
        let snapshot = makeSnapshot()
        let unconfirmedContext = AmoraActionContext(isConfirmed: false, snapshot: snapshot)

        let action = AmoraAction.confirmTest(actionName: "Sensitive Task", prompt: "Are you sure you want to proceed?")
        let result = await engine.execute(action, context: unconfirmedContext)
        XCTAssertEqual(result.status, AmoraActionResultStatus.needsConfirmation)
        XCTAssertEqual(result.message, "Are you sure you want to proceed?")
    }

    // MARK: - 10. AssistantManager Context Awareness ON vs OFF

    func testAssistantManagerAppliesContextAwarenessWhenEnabled() async {
        let jsonResponse = """
        {"actions":[{"action":"media.pause"}]}
        """
        let provider = ContextAwarenessTests.RecordingAIProvider(cannedResponse: jsonResponse)
        let assistant = AssistantManager(provider: provider)

        // Set up AmoraContextProvider with paused media via mediaProvider
        struct PausedMediaMock: AmoraMediaContextProvider {
            func currentMediaContext() -> AmoraMediaContext {
                AmoraMediaContext(source: "Spotify", state: "paused", title: "Blinding Lights", artist: "The Weeknd")
            }
        }
        AmoraContextProvider.shared.mediaProvider = PausedMediaMock()
        AmoraContextProvider.shared.captureSnapshot()

        // Context awareness enabled
        let settingsOn = AISettingsSnapshot(
            enabled: true,
            provider: .local,
            model: "mock",
            apiKey: nil,
            contextAwarenessEnabled: true
        )

        let answer = await assistant.submit("pause music", settings: settingsOn)
        XCTAssertTrue(answer.contains("already paused"), "Expected already paused in answer, got: \(answer)")
    }
}
