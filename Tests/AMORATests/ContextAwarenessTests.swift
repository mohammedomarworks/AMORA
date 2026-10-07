import XCTest
@testable import AMORA

@MainActor
final class ContextAwarenessTests: XCTestCase {

    // Helper recording provider to inspect messages sent to AI
    final class RecordingAIProvider: AIProvider, @unchecked Sendable {
        let kind: AIProviderKind = .local
        var isAvailable: Bool { true }
        var capturedMessages: [AIMessage] = []
        var cannedResponse: String

        init(cannedResponse: String = "Test response") {
            self.cannedResponse = cannedResponse
        }

        func send(messages: [AIMessage], model: String, apiKey: String?) async throws -> String {
            self.capturedMessages = messages
            return cannedResponse
        }
    }

    // MARK: - 1. Context Snapshot Creation
    func test1_ContextSnapshotCreation() {
        let timestamp = Date(timeIntervalSince1970: 1775560000)
        let app = AmoraApplicationContext(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
        let media = AmoraMediaContext(source: "Spotify", state: "playing", title: "Midnight City", artist: "M83")
        let timer = AmoraTimerContext(running: true, remainingSeconds: 600, duration: 1500, isPaused: false)
        let battery = AmoraBatteryContext(percent: 92, charging: false, isPluggedIn: false, estimate: "4h 10m remaining")
        let amora = AmoraUIContext(state: "workspace")
        let shelf = AmoraFileShelfContext(itemCount: 5, missingItemCount: 0)

        let snapshot = AmoraContextSnapshot(
            timestamp: timestamp,
            currentApplication: app,
            media: media,
            timer: timer,
            battery: battery,
            amora: amora,
            fileShelf: shelf,
            formattedLocalTime: "2:00 PM"
        )

        XCTAssertEqual(snapshot.timestamp, timestamp)
        XCTAssertEqual(snapshot.currentApplication?.name, "Xcode")
        XCTAssertEqual(snapshot.currentApplication?.bundleIdentifier, "com.apple.dt.Xcode")
        XCTAssertEqual(snapshot.media?.source, "Spotify")
        XCTAssertEqual(snapshot.media?.state, "playing")
        XCTAssertEqual(snapshot.media?.title, "Midnight City")
        XCTAssertEqual(snapshot.media?.artist, "M83")
        XCTAssertEqual(snapshot.timer?.running, true)
        XCTAssertEqual(snapshot.timer?.remainingSeconds, 600)
        XCTAssertEqual(snapshot.battery?.percent, 92)
        XCTAssertEqual(snapshot.battery?.charging, false)
        XCTAssertEqual(snapshot.amora?.state, "workspace")
        XCTAssertEqual(snapshot.fileShelf?.itemCount, 5)
        XCTAssertEqual(snapshot.formattedLocalTime, "2:00 PM")
        XCTAssertEqual(snapshot.frontmostApplication, "Xcode")
        XCTAssertEqual(snapshot.frontmostApplicationBundleIdentifier, "com.apple.dt.Xcode")
    }

    // MARK: - 2. Current Application Mapping
    func test2_CurrentApplicationMapping() {
        let context = AmoraApplicationContext(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode")
        XCTAssertEqual(context.name, "Visual Studio Code")
        XCTAssertEqual(context.bundleIdentifier, "com.microsoft.VSCode")
        XCTAssertEqual(context.summary, "Visual Studio Code (com.microsoft.VSCode)")

        let nameOnly = AmoraApplicationContext(name: "Finder", bundleIdentifier: nil)
        XCTAssertEqual(nameOnly.summary, "Finder")
    }

    // MARK: - 3. No Frontmost App
    func test3_NoFrontmostApp() {
        let snapshot = AmoraContextSnapshot(
            timestamp: Date(),
            currentApplication: nil,
            media: .inactive,
            timer: .stopped,
            battery: .unavailable,
            amora: AmoraUIContext(state: "collapsed"),
            fileShelf: AmoraFileShelfContext(itemCount: 0),
            formattedLocalTime: "12:00 PM"
        )

        XCTAssertNil(snapshot.currentApplication)
        XCTAssertNil(snapshot.frontmostApplication)
        XCTAssertNil(snapshot.frontmostApplicationBundleIdentifier)

        let result = AIContextComposer.composeRelevantContext(for: "What app am I using?", from: snapshot)
        XCTAssertNil(result)
    }

    // MARK: - 4. Media Context When Spotify Is Playing
    func test4_MediaContextWhenSpotifyIsPlaying() {
        let media = AmoraMediaContext(source: "Spotify", state: "playing", title: "Blinding Lights", artist: "The Weeknd")
        XCTAssertEqual(media.source, "Spotify")
        XCTAssertEqual(media.state, "playing")
        XCTAssertEqual(media.title, "Blinding Lights")
        XCTAssertEqual(media.artist, "The Weeknd")
        XCTAssertTrue(media.isPlaying)
        XCTAssertTrue(media.summary.contains("Spotify is playing"))
        XCTAssertTrue(media.summary.contains("Blinding Lights"))

        let snapshot = AmoraContextSnapshot(media: media)
        let relevant = AIContextComposer.composeRelevantContext(for: "Is Spotify playing?", from: snapshot)
        XCTAssertNotNil(relevant)
        XCTAssertTrue(relevant!.contains("Spotify"))
        XCTAssertTrue(relevant!.contains("Blinding Lights"))
    }

    // MARK: - 5. Media Context When No Media Is Active
    func test5_MediaContextWhenNoMediaIsActive() {
        let media = AmoraMediaContext.inactive
        XCTAssertEqual(media.source, "None")
        XCTAssertEqual(media.state, "inactive")
        XCTAssertNil(media.title)
        XCTAssertNil(media.artist)
        XCTAssertFalse(media.isPlaying)
        XCTAssertEqual(media.summary, "No active media")

        let snapshot = AmoraContextSnapshot(media: media)
        let relevant = AIContextComposer.composeRelevantContext(for: "What music is playing?", from: snapshot)
        XCTAssertNotNil(relevant)
        XCTAssertTrue(relevant!.contains("None / inactive"))
    }

    // MARK: - 6. Timer Running
    func test6_TimerRunning() {
        let timer = AmoraTimerContext(running: true, remainingSeconds: 1450, duration: 1500, isPaused: false)
        XCTAssertTrue(timer.running)
        XCTAssertEqual(timer.remainingSeconds, 1450)
        XCTAssertEqual(timer.duration, 1500)
        XCTAssertEqual(timer.isPaused, false)

        let snapshot = AmoraContextSnapshot(timer: timer)
        let relevant = AIContextComposer.composeRelevantContext(for: "How much time is left?", from: snapshot)
        XCTAssertNotNil(relevant)
        XCTAssertTrue(relevant!.contains("1450 seconds remaining"))
    }

    // MARK: - 7. Timer Stopped
    func test7_TimerStopped() {
        let timer = AmoraTimerContext.stopped
        XCTAssertFalse(timer.running)
        XCTAssertEqual(timer.remainingSeconds, 0)
        XCTAssertEqual(timer.summary, "No timer running")

        let snapshot = AmoraContextSnapshot(timer: timer)
        let relevant = AIContextComposer.composeRelevantContext(for: "How much time is left?", from: snapshot)
        XCTAssertNotNil(relevant)
        XCTAssertTrue(relevant!.contains("None (timer is stopped)"))
    }

    // MARK: - 8. Battery Available
    func test8_BatteryAvailable() {
        let battery = AmoraBatteryContext(percent: 85, charging: true, isPluggedIn: true, estimate: "1h 45m remaining")
        XCTAssertEqual(battery.percent, 85)
        XCTAssertTrue(battery.charging)
        XCTAssertEqual(battery.isPluggedIn, true)
        XCTAssertEqual(battery.estimate, "1h 45m remaining")

        let snapshot = AmoraContextSnapshot(battery: battery)
        let relevant = AIContextComposer.composeRelevantContext(for: "How much battery do I have?", from: snapshot)
        XCTAssertNotNil(relevant)
        XCTAssertTrue(relevant!.contains("85%"))
        XCTAssertTrue(relevant!.contains("charging"))
    }

    // MARK: - 9. Battery Unavailable
    func test9_BatteryUnavailable() {
        let battery = AmoraBatteryContext.unavailable
        XCTAssertNil(battery.percent)
        XCTAssertFalse(battery.charging)
        XCTAssertEqual(battery.summary, "Battery unavailable")

        let snapshot = AmoraContextSnapshot(battery: battery)
        let relevant = AIContextComposer.composeRelevantContext(for: "What is my battery?", from: snapshot)
        XCTAssertNotNil(relevant)
        XCTAssertTrue(relevant!.contains("Unavailable on this Mac"))
    }

    // MARK: - 10. AMORA Collapsed
    func test10_AmoraCollapsed() {
        let ui = AmoraUIContext(state: "collapsed")
        XCTAssertEqual(ui.state, "collapsed")

        let snapshot = AmoraContextSnapshot(amora: ui)
        let relevant = AIContextComposer.composeRelevantContext(for: "What state are you in?", from: snapshot)
        XCTAssertNotNil(relevant)
        XCTAssertTrue(relevant!.contains("collapsed"))
    }

    // MARK: - 11. AMORA Quick Island
    func test11_AmoraQuickIsland() {
        let ui = AmoraUIContext(state: "quick island")
        XCTAssertEqual(ui.state, "quick island")

        let snapshot = AmoraContextSnapshot(amora: ui)
        let relevant = AIContextComposer.composeRelevantContext(for: "What state are you in?", from: snapshot)
        XCTAssertNotNil(relevant)
        XCTAssertTrue(relevant!.contains("quick island"))
    }

    // MARK: - 12. AMORA Workspace
    func test12_AmoraWorkspace() {
        let ui = AmoraUIContext(state: "workspace")
        XCTAssertEqual(ui.state, "workspace")

        let snapshot = AmoraContextSnapshot(amora: ui)
        let relevant = AIContextComposer.composeRelevantContext(for: "What state are you in?", from: snapshot)
        XCTAssertNotNil(relevant)
        XCTAssertTrue(relevant!.contains("workspace"))
    }

    // MARK: - 13. File Shelf Count
    func test13_FileShelfCount() {
        let shelf = AmoraFileShelfContext(itemCount: 4, missingItemCount: 1)
        XCTAssertEqual(shelf.itemCount, 4)
        XCTAssertEqual(shelf.missingItemCount, 1)
        XCTAssertEqual(shelf.summary, "4 items (1 missing)")

        let snapshot = AmoraContextSnapshot(fileShelf: shelf)
        let relevant = AIContextComposer.composeRelevantContext(for: "How many files are on my shelf?", from: snapshot)
        XCTAssertNotNil(relevant)
        XCTAssertTrue(relevant!.contains("4 items"))
        XCTAssertTrue(relevant!.contains("1 missing"))
    }

    // MARK: - 14. Disabled Context Awareness
    func test14_DisabledContextAwareness() async {
        let provider = RecordingAIProvider(cannedResponse: "I am ready.")
        let assistant = AssistantManager(provider: provider)
        let settings = AISettingsSnapshot(
            enabled: true,
            provider: .local,
            model: "mock",
            apiKey: nil,
            contextAwarenessEnabled: false
        )

        _ = await assistant.submit("What app am I using?", settings: settings)
        let hasContext = provider.capturedMessages.contains { $0.content.contains("[System context]") }
        XCTAssertFalse(hasContext, "Context awareness disabled must omit system context.")
    }

    // MARK: - 15. Enabled Context Awareness
    func test15_EnabledContextAwareness() async {
        let provider = RecordingAIProvider(cannedResponse: "You are in Finder.")
        let assistant = AssistantManager(provider: provider)
        let settings = AISettingsSnapshot(
            enabled: true,
            provider: .local,
            model: "mock",
            apiKey: nil,
            contextAwarenessEnabled: true
        )

        // Inject custom mock detector to guarantee app is returned
        struct MockDetector: AmoraApplicationDetecting {
            func currentApplication() -> AmoraApplicationContext? {
                AmoraApplicationContext(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode")
            }
        }
        AmoraContextProvider.shared.appDetector = MockDetector()
        AmoraContextProvider.shared.captureSnapshot()

        _ = await assistant.submit("What app am I using?", settings: settings)
        let contextMessage = provider.capturedMessages.first { $0.content.contains("[System context]") }
        XCTAssertNotNil(contextMessage)
        XCTAssertTrue(contextMessage!.content.contains("Visual Studio Code"))

        // Restore detector
        AmoraContextProvider.shared.appDetector = NativeAmoraApplicationDetector.shared
    }

    // MARK: - 16. Context Serialization and Formatting
    func test16_ContextSerializationAndFormatting() throws {
        let snapshot = AmoraContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1775560000),
            currentApplication: AmoraApplicationContext(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode"),
            media: AmoraMediaContext(source: "Spotify", state: "playing", title: "Song A", artist: "Artist B"),
            timer: AmoraTimerContext(running: true, remainingSeconds: 1450),
            battery: AmoraBatteryContext(percent: 47, charging: false),
            amora: AmoraUIContext(state: "workspace"),
            fileShelf: AmoraFileShelfContext(itemCount: 3)
        )

        guard let jsonString = snapshot.toJSONString(),
              let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to serialize context snapshot to JSON")
            return
        }

        XCTAssertTrue(jsonString.contains("\"Visual Studio Code\""))
        XCTAssertTrue(jsonString.contains("\"com.microsoft.VSCode\""))
        XCTAssertTrue(jsonString.contains("\"Spotify\""))
        XCTAssertTrue(jsonString.contains("\"playing\""))
        XCTAssertTrue(jsonString.contains("\"workspace\""))
        XCTAssertTrue(jsonString.contains("\"itemCount\" : 3"))

        let decoded = try AmoraContextSnapshot.fromJSONData(jsonData)
        XCTAssertEqual(decoded.currentApplication?.name, "Visual Studio Code")
        XCTAssertEqual(decoded.media?.source, "Spotify")
        XCTAssertEqual(decoded.timer?.remainingSeconds, 1450)
        XCTAssertEqual(decoded.battery?.percent, 47)
        XCTAssertEqual(decoded.amora?.state, "workspace")
        XCTAssertEqual(decoded.fileShelf?.itemCount, 3)
    }

    // MARK: - 17. Relevant Context Selection
    func test17_RelevantContextSelection() {
        let snapshot = AmoraContextSnapshot(
            timestamp: Date(),
            currentApplication: AmoraApplicationContext(name: "Finder", bundleIdentifier: "com.apple.finder"),
            media: AmoraMediaContext(source: "Spotify", state: "playing", title: "Song", artist: "Artist"),
            timer: AmoraTimerContext(running: true, remainingSeconds: 300),
            battery: AmoraBatteryContext(percent: 88, charging: false),
            amora: AmoraUIContext(state: "quick island"),
            fileShelf: AmoraFileShelfContext(itemCount: 2)
        )

        // Query 1: App query should select only app
        let appResult = AIContextComposer.composeRelevantContext(for: "What app am I using?", from: snapshot)!
        XCTAssertTrue(appResult.contains("Finder"))
        XCTAssertFalse(appResult.contains("Spotify"))
        XCTAssertFalse(appResult.contains("88%"))
        XCTAssertFalse(appResult.contains("300 seconds"))

        // Query 2: Battery query should select only battery
        let batteryResult = AIContextComposer.composeRelevantContext(for: "How much battery do I have?", from: snapshot)!
        XCTAssertTrue(batteryResult.contains("88%"))
        XCTAssertFalse(batteryResult.contains("Finder"))
        XCTAssertFalse(batteryResult.contains("Spotify"))

        // Query 3: Timer query should select only timer
        let timerResult = AIContextComposer.composeRelevantContext(for: "How much time is left?", from: snapshot)!
        XCTAssertTrue(timerResult.contains("300 seconds"))
        XCTAssertFalse(timerResult.contains("Finder"))
        XCTAssertFalse(batteryResult.contains("300 seconds"))

        // Query 4: Music query should select only music
        let musicResult = AIContextComposer.composeRelevantContext(for: "Is Spotify playing?", from: snapshot)!
        XCTAssertTrue(musicResult.contains("Spotify"))
        XCTAssertFalse(musicResult.contains("Finder"))
        XCTAssertFalse(musicResult.contains("88%"))

        // Query 5: AMORA state query should select only island state
        let uiResult = AIContextComposer.composeRelevantContext(for: "What state are you in?", from: snapshot)!
        XCTAssertTrue(uiResult.contains("quick island"))
        XCTAssertFalse(uiResult.contains("Finder"))
    }

    // MARK: - 18. No Sensitive Data Accidentally Included
    func test18_NoSensitiveDataAccidentallyIncluded() {
        let snapshot = AmoraContextSnapshot(
            timestamp: Date(),
            currentApplication: AmoraApplicationContext(name: "Terminal", bundleIdentifier: "com.apple.Terminal"),
            media: .inactive,
            timer: .stopped,
            battery: AmoraBatteryContext(percent: 50, charging: false),
            amora: AmoraUIContext(state: "collapsed"),
            fileShelf: AmoraFileShelfContext(itemCount: 2)
        )

        let json = snapshot.toJSONString() ?? ""

        // Must not contain filesystem paths
        XCTAssertFalse(json.contains("/Users/"))
        XCTAssertFalse(json.contains("/var/"))
        XCTAssertFalse(json.contains("/System/"))

        // Must not contain API keys or auth tokens
        XCTAssertFalse(json.contains("sk-"))
        XCTAssertFalse(json.contains("Bearer"))
        XCTAssertFalse(json.contains("password"))
        XCTAssertFalse(json.contains("token"))

        // Must not contain clipboard or keyboard logs
        XCTAssertFalse(json.contains("clipboard"))
        XCTAssertFalse(json.contains("keystroke"))
        XCTAssertFalse(json.contains("screenshot"))
    }

    // MARK: - 19. AssistantManager Receives Context When Enabled
    func test19_AssistantManagerReceivesContextWhenEnabled() async {
        let provider = RecordingAIProvider(cannedResponse: "I see your app.")
        let assistant = AssistantManager(provider: provider)
        let settings = AISettingsSnapshot(
            enabled: true,
            provider: .local,
            model: "mock",
            apiKey: nil,
            contextAwarenessEnabled: true
        )

        struct MockDetector: AmoraApplicationDetecting {
            func currentApplication() -> AmoraApplicationContext? {
                AmoraApplicationContext(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
            }
        }
        AmoraContextProvider.shared.appDetector = MockDetector()
        AmoraContextProvider.shared.captureSnapshot()

        _ = await assistant.submit("What app am I using?", settings: settings)

        let contextMsg = provider.capturedMessages.first(where: { $0.content.contains("[System context]") })
        XCTAssertNotNil(contextMsg, "Enabled context awareness must supply [System context].")
        XCTAssertTrue(contextMsg!.content.contains("Xcode"))

        // Restore
        AmoraContextProvider.shared.appDetector = NativeAmoraApplicationDetector.shared
    }

    // MARK: - 20. AssistantManager Omits Context When Disabled
    func test20_AssistantManagerOmitsContextWhenDisabled() async {
        let provider = RecordingAIProvider(cannedResponse: "I don't know what app you are using.")
        let assistant = AssistantManager(provider: provider)
        let settings = AISettingsSnapshot(
            enabled: true,
            provider: .local,
            model: "mock",
            apiKey: nil,
            contextAwarenessEnabled: false
        )

        _ = await assistant.submit("What app am I using?", settings: settings)

        let hasContext = provider.capturedMessages.contains(where: { $0.content.contains("[System context]") })
        XCTAssertFalse(hasContext, "Disabled context awareness must not supply [System context].")
        let hasAppFact = provider.capturedMessages.contains(where: { $0.content.contains("Xcode") || $0.content.contains("Visual Studio Code") })
        XCTAssertFalse(hasAppFact, "Disabled context awareness must not leak application facts.")
    }

    // MARK: - 21. Physical Context Awareness Validation (Items 1 - 8)
    func testPhysicalContextAwarenessValidation() async {
        let provider = RecordingAIProvider(cannedResponse: "Understood.")
        let assistant = AssistantManager(provider: provider)
        let settingsOn = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil, contextAwarenessEnabled: true)
        let settingsOff = AISettingsSnapshot(enabled: true, provider: .local, model: "mock", apiKey: nil, contextAwarenessEnabled: false)

        // 1. VS Code: "What app am I using?" -> identifies Visual Studio Code
        struct VSCodeDetector: AmoraApplicationDetecting {
            func currentApplication() -> AmoraApplicationContext? {
                AmoraApplicationContext(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode")
            }
        }
        AmoraContextProvider.shared.appDetector = VSCodeDetector()
        _ = await assistant.submit("What app am I using?", settings: settingsOn)
        let vsCodeMsg = provider.capturedMessages.first(where: { $0.content.contains("[System context]") })
        XCTAssertNotNil(vsCodeMsg)
        XCTAssertTrue(vsCodeMsg!.content.contains("Visual Studio Code"))
        XCTAssertTrue(vsCodeMsg!.content.contains("com.microsoft.VSCode"))

        // 2. Finder: "What app am I using?" -> identifies Finder
        struct FinderDetector: AmoraApplicationDetecting {
            func currentApplication() -> AmoraApplicationContext? {
                AmoraApplicationContext(name: "Finder", bundleIdentifier: "com.apple.finder")
            }
        }
        AmoraContextProvider.shared.appDetector = FinderDetector()
        _ = await assistant.submit("What app am I using?", settings: settingsOn)
        let finderMsg = provider.capturedMessages.first(where: { $0.content.contains("[System context]") })
        XCTAssertNotNil(finderMsg)
        XCTAssertTrue(finderMsg!.content.contains("Finder"))
        XCTAssertTrue(finderMsg!.content.contains("com.apple.finder"))

        // 3. Spotify: "Is music playing?" -> identifies active media state
        struct SpotifyMockProvider: AmoraMediaContextProvider {
            func currentMediaContext() -> AmoraMediaContext {
                AmoraMediaContext(source: "Spotify", state: "playing", title: "Starboy", artist: "The Weeknd")
            }
        }
        AmoraContextProvider.shared.mediaProvider = SpotifyMockProvider()
        _ = await assistant.submit("Is music playing?", settings: settingsOn)
        let spotifyMsg = provider.capturedMessages.first(where: { $0.content.contains("[System context]") })
        XCTAssertNotNil(spotifyMsg)
        XCTAssertTrue(spotifyMsg!.content.contains("Spotify"))
        XCTAssertTrue(spotifyMsg!.content.localizedCaseInsensitiveContains("playing"))
        XCTAssertTrue(spotifyMsg!.content.contains("Starboy"))

        // 4. Timer 20s: "How much time is left?" -> reports remaining time
        struct Timer20sMockProvider: AmoraTimerContextProvider {
            func currentTimerContext() -> AmoraTimerContext {
                AmoraTimerContext(running: true, remainingSeconds: 20, duration: 20, isPaused: false)
            }
        }
        AmoraContextProvider.shared.timerProvider = Timer20sMockProvider()
        _ = await assistant.submit("How much time is left?", settings: settingsOn)
        let timerMsg = provider.capturedMessages.first(where: { $0.content.contains("[System context]") })
        XCTAssertNotNil(timerMsg)
        XCTAssertTrue(timerMsg!.content.contains("20 seconds"))
        XCTAssertTrue(timerMsg!.content.contains("remaining"))

        // 5. Workspace: "What state are you in?" -> identifies Workspace
        struct WorkspaceMockProvider: AmoraUIContextProvider {
            func currentUIContext() -> AmoraUIContext {
                AmoraUIContext(state: "workspace")
            }
        }
        AmoraContextProvider.shared.uiProvider = WorkspaceMockProvider()
        _ = await assistant.submit("What state are you in?", settings: settingsOn)
        let wsMsg = provider.capturedMessages.first(where: { $0.content.contains("[System context]") })
        XCTAssertNotNil(wsMsg)
        XCTAssertTrue(wsMsg!.content.contains("workspace"))

        // 6. File Shelf: "How many items are in the file shelf?" -> identifies count
        struct FileShelfMockProvider: AmoraFileShelfContextProvider {
            func currentFileShelfContext() -> AmoraFileShelfContext {
                AmoraFileShelfContext(itemCount: 4, missingItemCount: 1)
            }
        }
        AmoraContextProvider.shared.fileShelfProvider = FileShelfMockProvider()
        _ = await assistant.submit("How many files are in my shelf?", settings: settingsOn)
        let shelfMsg = provider.capturedMessages.first(where: { $0.content.contains("[System context]") })
        XCTAssertNotNil(shelfMsg)
        XCTAssertTrue(shelfMsg!.content.contains("4 items"))

        // 7. Turn Context Awareness OFF: "What app am I using?" -> must NOT use context
        _ = await assistant.submit("What app am I using?", settings: settingsOff)
        let noContextMsg = provider.capturedMessages.contains(where: { $0.content.contains("[System context]") })
        XCTAssertFalse(noContextMsg)
        let noAppFact = provider.capturedMessages.contains(where: { $0.content.contains("Current application:") })
        XCTAssertFalse(noAppFact)

        // 8. Turn Context Awareness ON: repeat and verify context returns
        _ = await assistant.submit("What app am I using?", settings: settingsOn)
        let restoredContextMsg = provider.capturedMessages.first(where: { $0.content.contains("[System context]") })
        XCTAssertNotNil(restoredContextMsg)
        XCTAssertTrue(restoredContextMsg!.content.contains("Finder"))

        // Restore real providers
        AmoraContextProvider.shared.appDetector = NativeAmoraApplicationDetector.shared
        AmoraContextProvider.shared.mediaProvider = DefaultAmoraMediaContextProvider()
        AmoraContextProvider.shared.timerProvider = DefaultAmoraTimerContextProvider()
        AmoraContextProvider.shared.uiProvider = DefaultAmoraUIContextProvider()
        AmoraContextProvider.shared.fileShelfProvider = DefaultAmoraFileShelfContextProvider()
    }
}

