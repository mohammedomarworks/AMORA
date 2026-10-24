import XCTest
@testable import AMORA

@MainActor
final class TruthfulBrowserMediaControlTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        ChromeMessageBridge.shared.resetForTesting()
        MusicService.shared.resetControlStateForTesting()
    }

    override func tearDown() async throws {
        ChromeMessageBridge.shared.resetForTesting()
        MusicService.shared.resetControlStateForTesting()
        try await super.tearDown()
    }

    private func makeYouTubeConnectedBridge(tabId: Int = 42, title: String = "Test YouTube Video", isPlaying: Bool = false) {
        let bridge = ChromeMessageBridge.shared
        let setupPayload = """
        {
            "type": "mediaState",
            "browser": "Chrome",
            "provider": "YouTube",
            "title": "\(title)",
            "channel": "Test Channel",
            "isPlaying": \(isPlaying),
            "currentTime": 15.0,
            "duration": 180.0,
            "url": "https://www.youtube.com/watch?v=truthful_test",
            "tabId": \(tabId),
            "windowId": 1,
            "trackedMediaTabCount": 1,
            "contentScriptReady": true,
            "hasVideo": true
        }
        """
        bridge.receive(setupPayload)
        MusicService.shared.checkCurrentTrack()
        MusicService.shared.preferredSource = .youtube
    }

    // MARK: - 1. Successful Browser Command Acknowledgment

    func testSuccessfulBrowserCommandPlayAcknowledgment() async {
        makeYouTubeConnectedBridge(tabId: 101, title: "Bohemian Rhapsody", isPlaying: false)
        let bridge = ChromeMessageBridge.shared
        XCTAssertEqual(bridge.status, .connected)
        XCTAssertEqual(MusicService.shared.source, .youtube)

        let engine = AmoraActionEngine.makeDefault()

        let playTask = Task {
            await engine.execute(.playMusic)
        }

        // Wait for command creation in bridge diagnostics
        var diagnostic: ChromeCommandDiagnostic?
        for _ in 0..<50 {
            if let last = bridge.commandDiagnostics.last, last.action == .play, last.tabId == 101 {
                diagnostic = last
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        guard let diag = diagnostic else {
            XCTFail("Play command was not dispatched to bridge diagnostics")
            return
        }

        let ackPayload = """
        {
            "type": "mediaCommandResult",
            "provider": "youtube",
            "action": "play",
            "requestId": "\(diag.requestId)",
            "tabId": 101,
            "success": true,
            "state": {
                "isPlaying": true,
                "title": "Bohemian Rhapsody",
                "currentTime": 15.0,
                "duration": 180.0,
                "url": "https://www.youtube.com/watch?v=truthful_test"
            }
        }
        """
        bridge.receive(ackPayload)

        let result = await playTask.value
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.actionId, "media.play")
        XCTAssertEqual(result.message, "Music playback started.")
        XCTAssertEqual(result.data["source"], "YouTube")
        XCTAssertEqual(result.data["track"], "Bohemian Rhapsody")
    }

    func testSuccessfulBrowserCommandPauseAcknowledgment() async {
        makeYouTubeConnectedBridge(tabId: 102, title: "Hotel California", isPlaying: true)
        let bridge = ChromeMessageBridge.shared
        XCTAssertEqual(bridge.status, .connected)
        XCTAssertEqual(MusicService.shared.source, .youtube)

        let engine = AmoraActionEngine.makeDefault()

        let pauseTask = Task {
            await engine.execute(.pauseMusic)
        }

        var diagnostic: ChromeCommandDiagnostic?
        for _ in 0..<50 {
            if let last = bridge.commandDiagnostics.last, last.action == .pause, last.tabId == 102 {
                diagnostic = last
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        guard let diag = diagnostic else {
            XCTFail("Pause command was not dispatched to bridge diagnostics")
            return
        }

        let ackPayload = """
        {
            "type": "mediaCommandResult",
            "provider": "youtube",
            "action": "pause",
            "requestId": "\(diag.requestId)",
            "tabId": 102,
            "success": true,
            "state": {
                "isPlaying": false,
                "title": "Hotel California",
                "currentTime": 45.0,
                "duration": 240.0,
                "url": "https://www.youtube.com/watch?v=truthful_test"
            }
        }
        """
        bridge.receive(ackPayload)

        let result = await pauseTask.value
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.actionId, "media.pause")
        XCTAssertEqual(result.message, "Music playback paused.")
        XCTAssertEqual(result.data["source"], "YouTube")
    }

    // MARK: - 2. Disconnected Bridge and Missing / Unsupported Target

    func testDisconnectedBridgeReturnsHonestFailure() async {
        let bridge = ChromeMessageBridge.shared
        bridge.resetForTesting()
        MusicService.shared.preferredSource = .youtube
        MusicService.shared.checkCurrentTrack()
        XCTAssertEqual(bridge.status, .extensionDisconnected)

        let engine = AmoraActionEngine.makeDefault()
        let result = await engine.execute(.playMusic)

        XCTAssertNotEqual(result.status, .success)
        XCTAssertEqual(result.status, .unavailable)
        XCTAssertEqual(result.message, "Chrome is disconnected.")
        XCTAssertEqual(result.data["reason"], "bridge_disconnected")
    }

    func testMissingTargetTabReturnsHonestFailure() async {
        let bridge = ChromeMessageBridge.shared
        // Connected connectionState but no mediaState
        bridge.receive("{\"type\":\"connectionState\",\"state\":\"connected\"}")
        MusicService.shared.preferredSource = .youtube
        MusicService.shared.checkCurrentTrack()
        XCTAssertEqual(bridge.status, .connected)
        XCTAssertNil(bridge.state)

        let engine = AmoraActionEngine.makeDefault()
        let result = await engine.execute(.playMusic)

        XCTAssertNotEqual(result.status, .success)
        XCTAssertEqual(result.status, .unavailable)
        XCTAssertEqual(result.message, "No controllable YouTube video is available.")
        XCTAssertEqual(result.data["reason"], "no_media_target")
    }

    func testUnsupportedActionReturnsHonestFailure() async {
        let bridge = ChromeMessageBridge.shared
        let setupPayload = """
        {
            "type": "mediaState",
            "browser": "Chrome",
            "provider": "YouTube",
            "title": "Unsupported Action Video",
            "channel": "Test Channel",
            "isPlaying": true,
            "currentTime": 10.0,
            "duration": 100.0,
            "url": "https://www.youtube.com/watch?v=truthful_test",
            "tabId": 108,
            "controlAvailable": true,
            "capabilities": {
                "play": true,
                "pause": false
            }
        }
        """
        bridge.receive(setupPayload)
        MusicService.shared.checkCurrentTrack()
        MusicService.shared.preferredSource = .youtube

        let engine = AmoraActionEngine.makeDefault()
        let result = await engine.execute(.pauseMusic)

        XCTAssertNotEqual(result.status, .success)
        XCTAssertEqual(result.status, .unavailable)
        XCTAssertEqual(result.message, "This media action is not supported here.")
        XCTAssertEqual(result.data["reason"], "unsupported")
    }

    func testTargetTabDoesNotExistReturnsHonestFailure() async {
        makeYouTubeConnectedBridge(tabId: 103, title: "Ghost Video", isPlaying: false)
        let bridge = ChromeMessageBridge.shared

        let engine = AmoraActionEngine.makeDefault()
        let playTask = Task {
            await engine.execute(.playMusic)
        }

        var diagnostic: ChromeCommandDiagnostic?
        for _ in 0..<50 {
            if let last = bridge.commandDiagnostics.last, last.tabId == 103 {
                diagnostic = last
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        guard let diag = diagnostic else {
            XCTFail("Command was not dispatched to bridge diagnostics")
            return
        }

        let failPayload = """
        {
            "type": "mediaCommandResult",
            "provider": "youtube",
            "action": "play",
            "requestId": "\(diag.requestId)",
            "tabId": 103,
            "success": false,
            "reason": "target_tab_does_not_exist"
        }
        """
        bridge.receive(failPayload)

        let result = await playTask.value
        XCTAssertNotEqual(result.status, .success)
        XCTAssertEqual(result.status, .unavailable)
        XCTAssertEqual(result.message, "The selected tab is no longer open.")
        XCTAssertEqual(result.data["reason"], "target_tab_does_not_exist")
    }

    func testTargetTabNotYouTubeReturnsHonestFailure() async {
        makeYouTubeConnectedBridge(tabId: 104, title: "Unrelated Web Page", isPlaying: false)
        let bridge = ChromeMessageBridge.shared

        let engine = AmoraActionEngine.makeDefault()
        let playTask = Task {
            await engine.execute(.playMusic)
        }

        var diagnostic: ChromeCommandDiagnostic?
        for _ in 0..<50 {
            if let last = bridge.commandDiagnostics.last, last.tabId == 104 {
                diagnostic = last
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        guard let diag = diagnostic else {
            XCTFail("Command was not dispatched to bridge diagnostics")
            return
        }

        let failPayload = """
        {
            "type": "mediaCommandResult",
            "provider": "youtube",
            "action": "play",
            "requestId": "\(diag.requestId)",
            "tabId": 104,
            "success": false,
            "reason": "target_tab_not_youtube"
        }
        """
        bridge.receive(failPayload)

        let result = await playTask.value
        XCTAssertNotEqual(result.status, .success)
        XCTAssertEqual(result.status, .unavailable)
        XCTAssertEqual(result.message, "The selected tab is not playing a YouTube video.")
        XCTAssertEqual(result.data["reason"], "target_tab_not_youtube")
    }

    // MARK: - 3. Rejected or Malformed Acknowledgment

    func testRejectedCommandAcknowledgmentReturnsHonestFailure() async {
        makeYouTubeConnectedBridge(tabId: 105, title: "Autoplay Blocked Video", isPlaying: false)
        let bridge = ChromeMessageBridge.shared

        let engine = AmoraActionEngine.makeDefault()
        let playTask = Task {
            await engine.execute(.playMusic)
        }

        var diagnostic: ChromeCommandDiagnostic?
        for _ in 0..<50 {
            if let last = bridge.commandDiagnostics.last, last.tabId == 105 {
                diagnostic = last
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        guard let diag = diagnostic else {
            XCTFail("Command was not dispatched to bridge diagnostics")
            return
        }

        let failPayload = """
        {
            "type": "mediaCommandResult",
            "provider": "youtube",
            "action": "play",
            "requestId": "\(diag.requestId)",
            "tabId": 105,
            "success": false,
            "reason": "play_rejected"
        }
        """
        bridge.receive(failPayload)

        let result = await playTask.value
        XCTAssertNotEqual(result.status, .success)
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.message, "YouTube did not allow playback to start.")
        XCTAssertEqual(result.data["reason"], "play_rejected")
    }

    func testMalformedAcknowledgmentReturnsHonestFailure() async {
        makeYouTubeConnectedBridge(tabId: 106, title: "Malformed Response Video", isPlaying: false)
        let bridge = ChromeMessageBridge.shared

        let engine = AmoraActionEngine.makeDefault()
        let playTask = Task {
            await engine.execute(.playMusic)
        }

        var diagnostic: ChromeCommandDiagnostic?
        for _ in 0..<50 {
            if let last = bridge.commandDiagnostics.last, last.tabId == 106 {
                diagnostic = last
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        guard let diag = diagnostic else {
            XCTFail("Command was not dispatched to bridge diagnostics")
            return
        }

        // Malformed: missing action field but carries requestId
        let malformedPayload = """
        {
            "type": "mediaCommandResult",
            "provider": "youtube",
            "requestId": "\(diag.requestId)",
            "tabId": 106
        }
        """
        bridge.receive(malformedPayload)

        let result = await playTask.value
        XCTAssertNotEqual(result.status, .success)
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.message, "Chrome returned an incomplete YouTube control response.")
        XCTAssertEqual(result.data["reason"], "ack_malformed")
    }

    // MARK: - 4. Command Timeout

    func testCommandTimeoutReturnsHonestFailure() async {
        makeYouTubeConnectedBridge(tabId: 107, title: "Hanging Chrome Video", isPlaying: false)
        let bridge = ChromeMessageBridge.shared
        bridge.commandTimeoutSeconds = 0.05 // 50ms fast timeout for deterministic testing
        defer { bridge.commandTimeoutSeconds = 5.0 }

        let engine = AmoraActionEngine.makeDefault()
        let result = await engine.execute(.playMusic)

        XCTAssertNotEqual(result.status, .success)
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.message, "Chrome did not respond in time.")
        XCTAssertEqual(result.data["reason"], "command_timeout")
    }

    // MARK: - 4b. Command Cancellation and Late Acknowledgment Lifecycle

    func testCommandCancellationRemovesPendingStateAndReturnsNotPermitted() async {
        makeYouTubeConnectedBridge(tabId: 109, title: "Long Running Video", isPlaying: false)
        let bridge = ChromeMessageBridge.shared

        let engine = AmoraActionEngine.makeDefault()

        let task = Task {
            await engine.execute(.playMusic)
        }

        // Wait for command dispatch
        var diagnostic: ChromeCommandDiagnostic?
        for _ in 0..<50 {
            if let last = bridge.commandDiagnostics.last, last.tabId == 109 {
                diagnostic = last
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        guard let diag = diagnostic else {
            XCTFail("Play command was not dispatched to bridge diagnostics")
            return
        }

        // Cancel the task
        task.cancel()

        let result = await task.value
        XCTAssertEqual(result.status, .notPermitted)
        XCTAssertEqual(result.message, "Action cancelled by user.")
        XCTAssertEqual(result.data["reason"], "command_cancelled")

        // Diagnostics must record command_cancelled
        let updatedDiag = bridge.commandDiagnostics.first(where: { $0.requestId == diag.requestId })
        XCTAssertEqual(updatedDiag?.success, false)
        XCTAssertEqual(updatedDiag?.failureReason, "command_cancelled")

        // Late acknowledgment from Chrome after cancellation must be rejected as stale
        let lateAck = """
        {
            "type": "mediaCommandResult",
            "provider": "youtube",
            "action": "play",
            "requestId": "\(diag.requestId)",
            "tabId": 109,
            "success": true,
            "state": {
                "isPlaying": true,
                "title": "Long Running Video"
            }
        }
        """
        bridge.receive(lateAck)

        // MusicService control state must remain idle / not playing
        XCTAssertFalse(MusicService.shared.controlPending)
        XCTAssertNil(MusicService.shared.controlStatus)
    }

    func testStaleAcknowledgmentAfterTimeoutCannotTriggerSuccess() async {
        makeYouTubeConnectedBridge(tabId: 110, title: "Slow Video", isPlaying: false)
        let bridge = ChromeMessageBridge.shared
        bridge.commandTimeoutSeconds = 0.05
        defer { bridge.commandTimeoutSeconds = 5.0 }

        let engine = AmoraActionEngine.makeDefault()
        let result = await engine.execute(.playMusic)

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.data["reason"], "command_timeout")

        let diag = bridge.commandDiagnostics.last(where: { $0.tabId == 110 })
        guard let requestId = diag?.requestId else {
            XCTFail("Missing diagnostic requestId")
            return
        }

        // Late response arrives after timeout
        let lateAck = """
        {
            "type": "mediaCommandResult",
            "provider": "youtube",
            "action": "play",
            "requestId": "\(requestId)",
            "tabId": 110,
            "success": true,
            "state": {
                "isPlaying": true,
                "title": "Slow Video"
            }
        }
        """
        bridge.receive(lateAck)

        // Must remain in failed state without triggering success
        XCTAssertFalse(MusicService.shared.controlPending)
        XCTAssertNil(MusicService.shared.controlStatus)
    }

    func testDisconnectDuringPendingCommandCleansStateAndLateAckIsDropped() async {
        makeYouTubeConnectedBridge(tabId: 111, title: "Disconnecting Video", isPlaying: false)
        let bridge = ChromeMessageBridge.shared

        let engine = AmoraActionEngine.makeDefault()
        let playTask = Task {
            await engine.execute(.playMusic)
        }

        var diagnostic: ChromeCommandDiagnostic?
        for _ in 0..<50 {
            if let last = bridge.commandDiagnostics.last, last.tabId == 111 {
                diagnostic = last
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        guard let diag = diagnostic else {
            XCTFail("Play command was not dispatched to bridge diagnostics")
            return
        }

        // Bridge disconnects while command is in flight
        bridge.receive("{\"type\":\"connectionState\",\"state\":\"disconnected\"}")

        let result = await playTask.value
        XCTAssertEqual(result.status, .unavailable)
        XCTAssertEqual(result.data["reason"], "bridge_disconnected")

        // Late response arriving after disconnect
        let lateAck = """
        {
            "type": "mediaCommandResult",
            "provider": "youtube",
            "action": "play",
            "requestId": "\(diag.requestId)",
            "tabId": 111,
            "success": true
        }
        """
        bridge.receive(lateAck)

        XCTAssertFalse(MusicService.shared.controlPending)
        XCTAssertNil(MusicService.shared.controlStatus)
    }

    // MARK: - 5. Successful Local-Player Behavior Remains Intact

    func testSuccessfulLocalPlayerMockIntact() async {
        final class LocalPlayerMock: AmoraMediaControlling, @unchecked Sendable {
            var playCallCount = 0
            var pauseCallCount = 0
            var nextCallCount = 0
            var previousCallCount = 0
            var isPlaying = false
            var isAvailable = true
            var trackTitle = "Local Audio Track"
            var sourceName = "MockPlayer"

            func play() { playCallCount += 1; isPlaying = true }
            func pause() { pauseCallCount += 1; isPlaying = false }
            func nextTrack() { nextCallCount += 1 }
            func previousTrack() { previousCallCount += 1 }
        }

        let mock = LocalPlayerMock()
        let registry = AmoraActionRegistry()
        AmoraActionEngine.registerDefaultActions(
            into: registry,
            mediaController: mock,
            appLauncher: NativeAmoraApplicationLauncher(),
            folderOpener: NativeAmoraFolderOpener(),
            workspaceController: DefaultAmoraWorkspaceController(),
            timerController: DefaultAmoraTimerController()
        )
        let engine = AmoraActionEngine(registry: registry)

        // 1. Play
        let playRes = await engine.execute(.playMusic)
        XCTAssertEqual(playRes.status, .success)
        XCTAssertEqual(playRes.message, "Music playback started.")
        XCTAssertEqual(mock.playCallCount, 1)
        XCTAssertTrue(mock.isPlaying)

        // 2. Pause
        let pauseRes = await engine.execute(.pauseMusic)
        XCTAssertEqual(pauseRes.status, .success)
        XCTAssertEqual(pauseRes.message, "Music playback paused.")
        XCTAssertEqual(mock.pauseCallCount, 1)
        XCTAssertFalse(mock.isPlaying)
    }

    func testControlledMediaControllerForEvaluationIntact() async {
        let engine = AmoraActionEngine.makeControlledForEvaluation()
        let playRes = await engine.execute(.playMusic)
        XCTAssertEqual(playRes.status, .success)
        XCTAssertEqual(playRes.message, "Music playback started.")
        XCTAssertEqual(playRes.data["source"], "Synthetic Music")

        let pauseRes = await engine.execute(.pauseMusic)
        XCTAssertEqual(pauseRes.status, .success)
        XCTAssertEqual(pauseRes.message, "Music playback paused.")
        XCTAssertEqual(pauseRes.data["source"], "Synthetic Music")
    }

    // MARK: - 6. Failed Media Actions Do Not Produce False Success Outcomes

    func testUserCancellationWhileBrowserMediaPendingEmitsAICancelled() async {
        makeYouTubeConnectedBridge(tabId: 112, title: "Long Movie", isPlaying: false)
        let bridge = ChromeMessageBridge.shared

        let mockAI = MockAIProvider(response: "{\"actions\":[{\"action\":\"media.play\"}]}")
        let manager = AssistantManager(provider: mockAI)
        let settings = AISettingsSnapshot(enabled: true, provider: .openAI, model: "gpt", apiKey: "test-key")

        let submitTask = Task {
            await manager.submit("play music", settings: settings)
        }

        // Wait for command dispatch
        var diagnostic: ChromeCommandDiagnostic?
        for _ in 0..<50 {
            if let last = bridge.commandDiagnostics.last, last.tabId == 112 {
                diagnostic = last
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        guard let diag = diagnostic else {
            XCTFail("Play command was not dispatched to bridge diagnostics")
            return
        }

        // User cancels while command is in flight
        manager.cancel()

        let response = await submitTask.value

        // 1. Assistant state and event MUST be cancelled, NEVER failed or succeeded
        XCTAssertEqual(manager.state, .cancelled)
        XCTAssertEqual(AMORAContext.shared.currentEvent, .aiCancelled)

        // 2. Response must not claim success or crash
        XCTAssertFalse(response.localizedCaseInsensitiveContains("Music playback started"))
        XCTAssertFalse(response.localizedCaseInsensitiveContains("started playing"))

        // 3. Diagnostics must record cancellation
        let updatedDiag = bridge.commandDiagnostics.first(where: { $0.requestId == diag.requestId })
        XCTAssertEqual(updatedDiag?.success, false)
        XCTAssertEqual(updatedDiag?.failureReason, "command_cancelled")

        // 4. Late acknowledgment from Chrome after cancellation is dropped
        let lateAck = """
        {
            "type": "mediaCommandResult",
            "provider": "youtube",
            "action": "play",
            "requestId": "\(diag.requestId)",
            "tabId": 112,
            "success": true
        }
        """
        bridge.receive(lateAck)
        XCTAssertFalse(MusicService.shared.controlPending)
        XCTAssertNil(MusicService.shared.controlStatus)
    }

    func testBrowserMediaCommandTimeoutEmitsAIFailedNeverSuccessNorCancelled() async {
        makeYouTubeConnectedBridge(tabId: 113, title: "Frozen YouTube Video", isPlaying: false)
        let bridge = ChromeMessageBridge.shared
        bridge.commandTimeoutSeconds = 0.05
        defer { bridge.commandTimeoutSeconds = 5.0 }

        let mockAI = MockAIProvider(response: "{\"actions\":[{\"action\":\"media.play\"}]}")
        let manager = AssistantManager(provider: mockAI)
        let settings = AISettingsSnapshot(enabled: true, provider: .openAI, model: "gpt", apiKey: "test-key")

        let response = await manager.submit("play music", settings: settings)

        // 1. Must record failure, NEVER cancelled or succeeded
        XCTAssertEqual(manager.lastLoopResult?.completedSuccessfully, false)
        XCTAssertEqual(AMORAContext.shared.currentEvent, .aiFailed)
        XCTAssertNotEqual(AMORAContext.shared.currentEvent, .aiCancelled)
        XCTAssertNotEqual(AMORAContext.shared.currentEvent, .aiSucceeded)

        // 2. Response must report timeout honestly
        XCTAssertTrue(response.contains("Chrome did not respond in time."))
        XCTAssertFalse(response.localizedCaseInsensitiveContains("Music playback started"))
    }

    func testFailedMediaActionEmitsAIFailedAndNeverClaimsSuccess() async {
        let bridge = ChromeMessageBridge.shared
        bridge.resetForTesting()
        MusicService.shared.preferredSource = .youtube
        MusicService.shared.checkCurrentTrack()
        XCTAssertEqual(bridge.status, .extensionDisconnected)

        let mockAI = MockAIProvider(response: "{\"actions\":[{\"action\":\"media.play\"}]}")
        let manager = AssistantManager(provider: mockAI)
        let settings = AISettingsSnapshot(enabled: true, provider: .openAI, model: "gpt", apiKey: "test-key")

        let response = await manager.submit("play music", settings: settings)

        // 1. Assistant manager must record failure, not success
        XCTAssertEqual(manager.lastLoopResult?.completedSuccessfully, false)
        XCTAssertEqual(AMORAContext.shared.currentEvent, .aiFailed)

        // 2. Response must NOT claim success
        XCTAssertFalse(response.localizedCaseInsensitiveContains("Music playback started"))
        XCTAssertFalse(response.localizedCaseInsensitiveContains("started playing"))

        // 3. Response must honestly report failure/unavailability
        XCTAssertTrue(
            response.contains("Chrome is disconnected") || response.contains("No active media player"),
            "Expected honest failure output in assistant response: \(response)"
        )
    }
}
