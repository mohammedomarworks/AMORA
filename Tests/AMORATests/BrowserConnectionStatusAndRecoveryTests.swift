import XCTest
@testable import AMORA

@MainActor
final class BrowserConnectionStatusAndRecoveryTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        ChromeMessageBridge.shared.resetForTesting()
        MusicService.shared.resetControlStateForTesting()
        MusicService.shared.source = .none
    }

    override func tearDown() async throws {
        ChromeMessageBridge.shared.resetForTesting()
        MusicService.shared.resetControlStateForTesting()
        MusicService.shared.source = .none
        try await super.tearDown()
    }

    // MARK: - 1. Chrome Bridge Connected With No YouTube Tab

    func testBridgeConnectedWithNoYouTubeTabViaContentPong() async {
        let bridge = ChromeMessageBridge.shared
        XCTAssertEqual(bridge.status, .extensionDisconnected)
        XCTAssertNil(bridge.state)

        // Simulate extension responding to content ping when no YouTube tab is open
        let pongPayload = """
        {
            "type": "contentPong",
            "requestId": "test-req-1",
            "tabId": null,
            "success": false,
            "reason": "youtube_tab_unavailable",
            "url": "",
            "hasVideo": false
        }
        """
        bridge.receive(pongPayload)

        XCTAssertEqual(bridge.status, .connected)
        XCTAssertNil(bridge.state)
        XCTAssertEqual(bridge.contentDiagnostic?.reason, "youtube_tab_unavailable")
        XCTAssertFalse(bridge.contentDiagnostic?.success ?? true)
        XCTAssertFalse(bridge.contentDiagnostic?.hasVideo ?? true)
    }

    func testBridgeConnectedWithNoYouTubeTabViaExtensionClear() async {
        let bridge = ChromeMessageBridge.shared
        XCTAssertEqual(bridge.status, .extensionDisconnected)
        XCTAssertNil(bridge.state)

        // Clear payload sent by service-worker when 0 media tabs exist
        let clearPayload = """
        {
            "type": "clear",
            "trackedMediaTabCount": 0,
            "currentMediaTabId": null
        }
        """
        bridge.receive(clearPayload)

        XCTAssertEqual(bridge.status, .connected)
        XCTAssertNil(bridge.state)
    }

    // MARK: - 2. Chrome or Native Host Unavailable

    func testBridgeUnavailableWhenHostOrExtensionDisconnected() async {
        let bridge = ChromeMessageBridge.shared
        XCTAssertEqual(bridge.status, .extensionDisconnected)
        XCTAssertNil(bridge.state)

        // Explicit disconnected payload
        bridge.receive("{\"type\":\"connectionState\",\"state\":\"disconnected\"}")
        XCTAssertEqual(bridge.status, .extensionDisconnected)
        XCTAssertNil(bridge.state)

        MusicService.shared.preferredSource = .youtube
        MusicService.shared.checkCurrentTrack()

        let engine = AmoraActionEngine.makeDefault()
        let playResult = await engine.execute(.playMusic)
        XCTAssertEqual(playResult.status, .unavailable)
        XCTAssertEqual(playResult.message, "Chrome is disconnected.")
        XCTAssertEqual(playResult.data["reason"], "bridge_disconnected")

        let pauseResult = await engine.execute(.pauseMusic)
        XCTAssertEqual(pauseResult.status, .unavailable)
        XCTAssertEqual(pauseResult.message, "Chrome is disconnected.")
        XCTAssertEqual(pauseResult.data["reason"], "bridge_disconnected")
    }

    // MARK: - 3. YouTube Target Appearing After Startup

    func testYouTubeTargetAppearingAfterStartup() async {
        let bridge = ChromeMessageBridge.shared

        // 1. Startup: Bridge connects but no media tab is open
        bridge.receive("""
        {
            "type": "clear",
            "trackedMediaTabCount": 0,
            "currentMediaTabId": null
        }
        """)
        XCTAssertEqual(bridge.status, .connected)
        XCTAssertNil(bridge.state)

        // 2. User opens YouTube video in Chrome -> mediaState arrives
        let mediaPayload = """
        {
            "type": "mediaState",
            "browser": "Chrome",
            "provider": "YouTube",
            "title": "Late Night Coding Session",
            "channel": "Tech Beats",
            "isPlaying": false,
            "currentTime": 0.0,
            "duration": 3600.0,
            "url": "https://www.youtube.com/watch?v=startup_recovery",
            "tabId": 204,
            "windowId": 1,
            "trackedMediaTabCount": 1,
            "contentScriptReady": true,
            "hasVideo": true
        }
        """
        bridge.receive(mediaPayload)

        XCTAssertEqual(bridge.status, .connected)
        XCTAssertNotNil(bridge.state)
        XCTAssertEqual(bridge.state?.title, "Late Night Coding Session")
        XCTAssertEqual(bridge.state?.tabId, 204)
        XCTAssertFalse(bridge.state?.isPlaying ?? true)

        MusicService.shared.preferredSource = .youtube
        MusicService.shared.checkCurrentTrack()
        XCTAssertEqual(MusicService.shared.source, .youtube)
        XCTAssertEqual(MusicService.shared.trackTitle, "Late Night Coding Session")
    }

    // MARK: - 4. Chrome Disconnect and Reconnect

    func testChromeDisconnectAndReconnectLifecycle() async {
        let bridge = ChromeMessageBridge.shared

        // 1. Initially active YouTube playback
        let initialMedia = """
        {
            "type": "mediaState",
            "browser": "Chrome",
            "provider": "YouTube",
            "title": "Podcast Episode 42",
            "channel": "Conversations",
            "isPlaying": true,
            "currentTime": 120.0,
            "duration": 1800.0,
            "url": "https://www.youtube.com/watch?v=podcast_42",
            "tabId": 305,
            "windowId": 1,
            "trackedMediaTabCount": 1,
            "contentScriptReady": true,
            "hasVideo": true
        }
        """
        bridge.receive(initialMedia)
        XCTAssertEqual(bridge.status, .connected)
        XCTAssertNotNil(bridge.state)

        // 2. Chrome terminates
        bridge.handleChromeTerminated()
        XCTAssertEqual(bridge.status, .extensionDisconnected)
        XCTAssertNil(bridge.state)

        // 3. Command while disconnected fails honestly
        MusicService.shared.preferredSource = .youtube
        MusicService.shared.checkCurrentTrack()
        let engine = AmoraActionEngine.makeDefault()
        let disconnectResult = await engine.execute(.playMusic)
        XCTAssertEqual(disconnectResult.status, .unavailable)
        XCTAssertEqual(disconnectResult.data["reason"], "bridge_disconnected")

        // 4. Chrome restarts and extension reconnects
        bridge.receive("{\"type\":\"connectionState\",\"state\":\"connected\"}")
        XCTAssertEqual(bridge.status, .connected)
        XCTAssertNil(bridge.state) // Target not yet open

        // 5. User re-navigates to video
        let reconnectedMedia = """
        {
            "type": "mediaState",
            "browser": "Chrome",
            "provider": "YouTube",
            "title": "Podcast Episode 42",
            "channel": "Conversations",
            "isPlaying": false,
            "currentTime": 125.0,
            "duration": 1800.0,
            "url": "https://www.youtube.com/watch?v=podcast_42",
            "tabId": 401,
            "windowId": 2,
            "trackedMediaTabCount": 1,
            "contentScriptReady": true,
            "hasVideo": true
        }
        """
        bridge.receive(reconnectedMedia)
        XCTAssertEqual(bridge.status, .connected)
        XCTAssertEqual(bridge.state?.tabId, 401)
        XCTAssertEqual(bridge.state?.title, "Podcast Episode 42")
    }

    // MARK: - 5. Media Commands Fail Honestly When No Controllable Target Exists

    func testMediaCommandsFailHonestlyWhenBridgeConnectedWithNoTarget() async {
        let bridge = ChromeMessageBridge.shared

        // Bridge is connected, but no media target exists
        bridge.receive("""
        {
            "type": "contentPong",
            "requestId": "probe-target",
            "tabId": null,
            "success": false,
            "reason": "youtube_tab_unavailable",
            "url": "",
            "hasVideo": false
        }
        """)
        XCTAssertEqual(bridge.status, .connected)
        XCTAssertNil(bridge.state)

        MusicService.shared.preferredSource = .youtube
        MusicService.shared.checkCurrentTrack()

        let engine = AmoraActionEngine.makeDefault()
        let result = await engine.execute(.playMusic)

        XCTAssertEqual(result.status, .unavailable)
        XCTAssertEqual(result.message, "No controllable YouTube video is available.")
        XCTAssertEqual(result.data["source"], "YouTube")
        XCTAssertEqual(result.data["reason"], "no_media_target")
        XCTAssertEqual(AMORAContext.shared.currentEvent, .commandFailed)
    }

    func testAssistantTurnEmitsAIFailedWhenNoTargetExists() async {
        let bridge = ChromeMessageBridge.shared
        bridge.receive("""
        {
            "type": "clear",
            "trackedMediaTabCount": 0,
            "currentMediaTabId": null
        }
        """)
        XCTAssertEqual(bridge.status, .connected)
        XCTAssertNil(bridge.state)

        MusicService.shared.preferredSource = .youtube
        MusicService.shared.checkCurrentTrack()

        let mockProvider = MockAIProvider(response: "{\"actions\":[{\"action\":\"media.play\"}]}")
        let assistant = AssistantManager(provider: mockProvider, providerIsInjected: true)
        let settings = AISettingsSnapshot(enabled: true, provider: .openAI, model: "gpt", apiKey: "test-key")

        let response = await assistant.submit("play music", settings: settings)

        XCTAssertTrue(response.contains("No controllable YouTube video is available."))
        XCTAssertFalse(response.localizedCaseInsensitiveContains("Music playback started"))
        XCTAssertEqual(assistant.lastLoopResult?.completedSuccessfully, false)
        XCTAssertEqual(AMORAContext.shared.currentEvent, .aiFailed)
        XCTAssertNotEqual(AMORAContext.shared.currentEvent, .aiSucceeded)
    }
}
