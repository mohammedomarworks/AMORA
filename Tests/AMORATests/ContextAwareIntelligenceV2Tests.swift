import XCTest
@testable import AMORA

@MainActor
final class ContextAwareIntelligenceV2Tests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        AmoraConversationContextManager.shared.reset()
        AmoraActionExecutionCoordinator.shared.reset()
    }

    override func tearDown() async throws {
        AmoraConversationContextManager.shared.reset()
        AmoraActionExecutionCoordinator.shared.reset()
        try await super.tearDown()
    }

    // MARK: - 1. Follow-Up Commands & Pronouns (it, that, this)

    func testAppFollowUpWithPronouns() {
        let resolver = AmoraContextualFollowUpResolver()
        var context = AmoraConversationContext()
        context.lastReferencedApp = "Safari"
        context.lastRelevantAction = .openApplication(name: "Safari")

        // "open it"
        let res1 = resolver.resolve(input: "open it", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res1, .resolvedAction(.openApplication(name: "Safari")))

        // "open that"
        let res2 = resolver.resolve(input: "open that", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res2, .resolvedAction(.openApplication(name: "Safari")))

        // "open this again"
        let res3 = resolver.resolve(input: "open this again", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res3, .resolvedAction(.openApplication(name: "Safari")))

        // "launch it"
        let res4 = resolver.resolve(input: "launch it", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res4, .resolvedAction(.openApplication(name: "Safari")))

        // "reopen it"
        let res5 = resolver.resolve(input: "reopen it", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res5, .resolvedAction(.openApplication(name: "Safari")))
    }

    func testMediaFollowUpWithPronounsAndOmittedTargets() {
        let resolver = AmoraContextualFollowUpResolver()
        var context = AmoraConversationContext()
        context.lastReferencedMedia = AmoraMediaReference(source: "Spotify", title: "Song A", isPlaying: true)
        context.lastRelevantAction = .playMusic

        // "pause it"
        let res1 = resolver.resolve(input: "pause it", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res1, .resolvedAction(.pauseMusic))

        // "pause that"
        let res2 = resolver.resolve(input: "pause that", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res2, .resolvedAction(.pauseMusic))

        // "pause" (omitted target)
        let res3 = resolver.resolve(input: "pause", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res3, .resolvedAction(.pauseMusic))

        // "skip it"
        let res4 = resolver.resolve(input: "skip it", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res4, .resolvedAction(.nextTrack))

        // "next" (omitted target)
        let res5 = resolver.resolve(input: "next", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res5, .resolvedAction(.nextTrack))

        // "previous on that"
        let res6 = resolver.resolve(input: "previous on that", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res6, .resolvedAction(.previousTrack))

        // "replay it"
        let res7 = resolver.resolve(input: "replay it", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res7, .resolvedAction(.previousTrack))

        // When paused, "resume it" / "play it"
        context.lastReferencedMedia = AmoraMediaReference(source: "Spotify", title: "Song A", isPlaying: false)
        context.lastRelevantAction = .pauseMusic

        let res8 = resolver.resolve(input: "play it", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res8, .resolvedAction(.playMusic))

        let res9 = resolver.resolve(input: "resume it", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res9, .resolvedAction(.playMusic))
    }

    func testTimerFollowUpWithPronounsAndOmittedTargets() {
        let resolver = AmoraContextualFollowUpResolver()
        var context = AmoraConversationContext()
        context.activeTimerReference = AmoraTimerReference(duration: 600, remainingSeconds: 600, isPaused: false)
        context.lastRelevantAction = .startTimer(duration: 600)

        // "pause it"
        let res1 = resolver.resolve(input: "pause it", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res1, .resolvedAction(.pauseTimer))

        // "pause" (omitted target)
        let res2 = resolver.resolve(input: "pause", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res2, .resolvedAction(.pauseTimer))

        // "stop that"
        let res3 = resolver.resolve(input: "stop that", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res3, .resolvedAction(.cancelTimer))

        // "cancel it"
        let res4 = resolver.resolve(input: "cancel it", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res4, .resolvedAction(.cancelTimer))

        // "turn it off"
        let res5 = resolver.resolve(input: "turn it off", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res5, .resolvedAction(.cancelTimer))

        // When paused, "resume it"
        context.activeTimerReference = AmoraTimerReference(duration: 600, remainingSeconds: 300, isPaused: true)
        context.lastRelevantAction = .pauseTimer

        let res6 = resolver.resolve(input: "resume it", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res6, .resolvedAction(.resumeTimer))

        let res7 = resolver.resolve(input: "resume", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res7, .resolvedAction(.resumeTimer))
    }

    // MARK: - 2. Context Reset & Expiration

    func testExplicitContextReset() {
        let manager = AmoraConversationContextManager(ttl: 300)
        manager.recordApp("Xcode")
        manager.recordAction(.openApplication(name: "Xcode"))
        manager.recordTimer(AmoraTimerReference(duration: 900))
        manager.recordWorkspaceSection("Notes")

        XCTAssertFalse(manager.currentContext.isEmpty)
        XCTAssertEqual(manager.currentContext.lastReferencedApp, "Xcode")
        XCTAssertEqual(manager.currentContext.currentWorkspaceSection, "Notes")

        manager.reset()

        XCTAssertTrue(manager.currentContext.isEmpty)
        XCTAssertNil(manager.currentContext.lastReferencedApp)
        XCTAssertNil(manager.currentContext.activeTimerReference)
        XCTAssertNil(manager.currentContext.currentWorkspaceSection)
        XCTAssertNil(manager.currentContext.lastRelevantAction)
    }

    func testContextExpirationViaTTL() {
        final class MockClock: @unchecked Sendable {
            var now = Date()
        }
        let clock = MockClock()
        let manager = AmoraConversationContextManager(ttl: 10, dateProvider: { clock.now })
        manager.recordApp("Terminal")

        // 5 seconds later: still valid
        clock.now = clock.now.addingTimeInterval(5)
        XCTAssertFalse(manager.isExpired())
        XCTAssertNotNil(manager.validContext())
        XCTAssertEqual(manager.validContext()?.lastReferencedApp, "Terminal")

        // 12 seconds later (17s total): expired
        clock.now = clock.now.addingTimeInterval(7)
        XCTAssertTrue(manager.isExpired())
        XCTAssertNil(manager.validContext())

        // Resolver will ignore expired context
        let resolver = AmoraContextualFollowUpResolver()
        let res = resolver.resolve(input: "open it", context: manager.validContext(), snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res, .unhandled)
    }

    func testAssistantStartNewConversationResetsContext() {
        AmoraConversationContextManager.shared.recordApp("Final Cut Pro")
        XCTAssertEqual(AmoraConversationContextManager.shared.currentContext.lastReferencedApp, "Final Cut Pro")

        AssistantManager.shared.startNewConversation()
        XCTAssertTrue(AmoraConversationContextManager.shared.currentContext.isEmpty)
        XCTAssertNil(AmoraConversationContextManager.shared.currentContext.lastReferencedApp)
    }

    // MARK: - 3. Timer Modification

    func testTimerRelativeModification() {
        let resolver = AmoraContextualFollowUpResolver()
        var context = AmoraConversationContext()
        context.activeTimerReference = AmoraTimerReference(duration: 600)
        context.lastRelevantAction = .startTimer(duration: 600)

        // "add 5 minutes to it"
        let res1 = resolver.resolve(input: "add 5 minutes to it", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res1, .resolvedCommand(.addTimerTime(duration: 300)))

        // "add 5 minutes" (omitted target)
        let res2 = resolver.resolve(input: "add 5 minutes", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res2, .resolvedCommand(.addTimerTime(duration: 300)))

        // "extend it by 10 minutes"
        let res3 = resolver.resolve(input: "extend it by 10 minutes", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res3, .resolvedCommand(.addTimerTime(duration: 600)))

        // "add 30 seconds to that"
        let res4 = resolver.resolve(input: "add 30 seconds to that", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res4, .resolvedCommand(.addTimerTime(duration: 30)))
    }

    func testTimerAbsoluteModification() {
        let resolver = AmoraContextualFollowUpResolver()
        var context = AmoraConversationContext()
        context.activeTimerReference = AmoraTimerReference(duration: 600)
        context.lastRelevantAction = .startTimer(duration: 600)

        // "make it 15 minutes"
        let res1 = resolver.resolve(input: "make it 15 minutes", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res1, .resolvedAction(.startTimer(duration: 900)))

        // "change it to 20 minutes"
        let res2 = resolver.resolve(input: "change it to 20 minutes", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res2, .resolvedAction(.startTimer(duration: 1200)))

        // "set it to 5 minutes"
        let res3 = resolver.resolve(input: "set it to 5 minutes", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res3, .resolvedAction(.startTimer(duration: 300)))

        // "change timer to 25 minutes"
        let res4 = resolver.resolve(input: "change timer to 25 minutes", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res4, .resolvedAction(.startTimer(duration: 1500)))

        // "set timer to 1 hour"
        let res5 = resolver.resolve(input: "set timer to 1 hour", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res5, .resolvedAction(.startTimer(duration: 3600)))
    }

    func testTimerModificationWithoutActiveTimerReportsMissingTimer() {
        let resolver = AmoraContextualFollowUpResolver()
        var context = AmoraConversationContext()
        context.lastReferencedApp = "Notes"

        // No timer active
        let res1 = resolver.resolve(input: "add 5 minutes to it", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res1, .ambiguous(prompt: "There isn't an active timer to extend.", candidates: []))

        let res2 = resolver.resolve(input: "make it 15 minutes", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res2, .ambiguous(prompt: "There isn't an active timer to change.", candidates: []))
    }

    // MARK: - 4. Media Follow-Up

    func testMediaFollowUpFromSpotifyCommand() {
        let manager = AmoraConversationContextManager.shared
        manager.recordCommand(.playSpotify)

        XCTAssertEqual(manager.currentContext.lastReferencedApp, "Spotify")
        XCTAssertEqual(manager.currentContext.lastRelevantAction, .playMusic)
        XCTAssertEqual(manager.currentContext.lastReferencedMedia?.source, "Spotify")

        let resolver = AmoraContextualFollowUpResolver()
        let res = resolver.resolve(input: "pause that", context: manager.currentContext, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res, .resolvedAction(.pauseMusic))
    }

    func testMediaFollowUpSkipAndPrevious() {
        let resolver = AmoraContextualFollowUpResolver()
        var context = AmoraConversationContext()
        context.lastReferencedMedia = AmoraMediaReference(source: "Apple Music", isPlaying: true)

        let nextRes = resolver.resolve(input: "skip this", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(nextRes, .resolvedAction(.nextTrack))

        let prevRes = resolver.resolve(input: "previous song", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(prevRes, .resolvedAction(.previousTrack))
    }

    // MARK: - 5. Workspace Follow-Up

    func testWorkspaceFollowUpSections() {
        let resolver = AmoraContextualFollowUpResolver()
        var context = AmoraConversationContext()
        context.lastRelevantAction = .openWorkspace()
        context.currentWorkspaceSection = "Overview"

        // "switch to notes"
        let res1 = resolver.resolve(input: "switch to notes", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res1, .resolvedAction(.openWorkspace(section: "Notes")))

        // "change that to clipboard"
        let res2 = resolver.resolve(input: "change that to clipboard", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res2, .resolvedAction(.openWorkspace(section: "Clipboard")))

        // "go to file shelf"
        let res3 = resolver.resolve(input: "go to file shelf", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res3, .resolvedAction(.openWorkspace(section: "File Shelf")))

        // "switch section to overview"
        let res4 = resolver.resolve(input: "switch section to overview", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res4, .resolvedAction(.openWorkspace(section: "Overview")))

        // Bare words in workspace context: "notes"
        let res5 = resolver.resolve(input: "notes", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res5, .resolvedAction(.openWorkspace(section: "Notes")))

        // "open that" refers to workspace
        let res6 = resolver.resolve(input: "open that", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res6, .resolvedAction(.openWorkspace(section: nil)))
    }

    // MARK: - 6. Context Awareness OFF

    func testContextAwarenessDisabledBypassesFollowUpResolution() {
        let resolver = AmoraContextualFollowUpResolver()
        var context = AmoraConversationContext()
        context.lastReferencedApp = "Safari"
        context.activeTimerReference = AmoraTimerReference(duration: 600)
        context.lastReferencedMedia = AmoraMediaReference(source: "Spotify", isPlaying: true)
        context.currentWorkspaceSection = "Notes"

        // With contextAwarenessEnabled = false: all return unhandled!
        XCTAssertEqual(resolver.resolve(input: "open it", context: context, snapshot: nil, contextAwarenessEnabled: false), .unhandled)
        XCTAssertEqual(resolver.resolve(input: "pause that", context: context, snapshot: nil, contextAwarenessEnabled: false), .unhandled)
        XCTAssertEqual(resolver.resolve(input: "add 5 minutes to it", context: context, snapshot: nil, contextAwarenessEnabled: false), .unhandled)
        XCTAssertEqual(resolver.resolve(input: "make it 15 minutes", context: context, snapshot: nil, contextAwarenessEnabled: false), .unhandled)
        XCTAssertEqual(resolver.resolve(input: "switch to notes", context: context, snapshot: nil, contextAwarenessEnabled: false), .unhandled)
        XCTAssertEqual(resolver.resolve(input: "stop it", context: context, snapshot: nil, contextAwarenessEnabled: false), .unhandled)
    }

    func testContextAwarenessDisabledOmitsContextInComposer() {
        var context = AmoraConversationContext()
        context.lastReferencedApp = "Figma"
        context.activeTimerReference = AmoraTimerReference(duration: 1200)

        // When conversationContext is nil (because Context Awareness is OFF):
        let emptySnapshot = AmoraContextSnapshot()
        let result = AIContextComposer.composeRelevantContext(for: "open it", from: emptySnapshot, conversationContext: nil)
        XCTAssertNil(result)
    }

    // MARK: - 7. Ambiguous References

    func testAmbiguousPauseWhenBothTimerAndMusicAreActive() {
        let resolver = AmoraContextualFollowUpResolver()
        var context = AmoraConversationContext()
        context.activeTimerReference = AmoraTimerReference(duration: 600, remainingSeconds: 400, isPaused: false)
        context.lastReferencedMedia = AmoraMediaReference(source: "Spotify", isPlaying: true)
        // Neither was explicitly the sole last action (e.g. compound turn or earlier workspace open)
        context.lastRelevantAction = .openWorkspace()

        let snapshot = AmoraContextSnapshot(
            media: AmoraMediaContext(source: "Spotify", state: "playing"),
            timer: AmoraTimerContext(running: true, remainingSeconds: 400, duration: 600, isPaused: false)
        )

        let res = resolver.resolve(input: "pause it", context: context, snapshot: snapshot, contextAwarenessEnabled: true)
        XCTAssertEqual(res, .ambiguous(prompt: "Did you mean the timer or music?", candidates: ["Timer", "Music"]))

        let stopRes = resolver.resolve(input: "stop that", context: context, snapshot: snapshot, contextAwarenessEnabled: true)
        XCTAssertEqual(stopRes, .ambiguous(prompt: "Did you mean the timer or music?", candidates: ["Timer", "Music"]))

        let resumeRes = resolver.resolve(input: "resume", context: context, snapshot: snapshot, contextAwarenessEnabled: true)
        XCTAssertEqual(resumeRes, .ambiguous(prompt: "Did you mean the timer or music?", candidates: ["Timer", "Music"]))
    }

    func testTieBreakingWhenLastActionWasExplicitlyMedia() {
        let resolver = AmoraContextualFollowUpResolver()
        var context = AmoraConversationContext()
        context.activeTimerReference = AmoraTimerReference(duration: 600, remainingSeconds: 400, isPaused: false)
        context.lastReferencedMedia = AmoraMediaReference(source: "Spotify", isPlaying: true)
        // Explicitly set media as last action
        context.lastRelevantAction = .playMusic

        let snapshot = AmoraContextSnapshot(
            media: AmoraMediaContext(source: "Spotify", state: "playing"),
            timer: AmoraTimerContext(running: true, remainingSeconds: 400, duration: 600, isPaused: false)
        )

        let res = resolver.resolve(input: "pause it", context: context, snapshot: snapshot, contextAwarenessEnabled: true)
        XCTAssertEqual(res, .resolvedAction(.pauseMusic))
    }

    func testTieBreakingWhenLastActionWasExplicitlyTimer() {
        let resolver = AmoraContextualFollowUpResolver()
        var context = AmoraConversationContext()
        context.activeTimerReference = AmoraTimerReference(duration: 600, remainingSeconds: 400, isPaused: false)
        context.lastReferencedMedia = AmoraMediaReference(source: "Spotify", isPlaying: true)
        // Explicitly set timer as last action
        context.lastRelevantAction = .startTimer(duration: 600)

        let snapshot = AmoraContextSnapshot(
            media: AmoraMediaContext(source: "Spotify", state: "playing"),
            timer: AmoraTimerContext(running: true, remainingSeconds: 400, duration: 600, isPaused: false)
        )

        let res = resolver.resolve(input: "pause it", context: context, snapshot: snapshot, contextAwarenessEnabled: true)
        XCTAssertEqual(res, .resolvedAction(.pauseTimer))
    }

    func testAmbiguousAppWhenNoAppWasReferenced() {
        let resolver = AmoraContextualFollowUpResolver()
        var context = AmoraConversationContext()
        context.activeTimerReference = AmoraTimerReference(duration: 600)

        let res = resolver.resolve(input: "open it", context: context, snapshot: nil, contextAwarenessEnabled: true)
        XCTAssertEqual(res, .ambiguous(prompt: "Which application would you like me to open?", candidates: []))
    }

    // MARK: - 8. End-to-End Gateway Integration

    func testGatewayResolvesFollowUpOpenIt() async {
        let gateway = AMORACommandGateway()
        let settings = AISettingsSnapshot(
            enabled: false,
            provider: .appleOnDevice,
            model: "on-device",
            apiKey: "",
            contextAwarenessEnabled: true
        )

        // Seed context with an app
        AmoraConversationContextManager.shared.recordApp("Calculator")

        let result = await gateway.submit("open it", settings: settings)
        // ActionEngine will attempt to open Calculator and report opening or result
        switch result {
        case .success(let msg):
            XCTAssertTrue(msg.contains("Calculator") || msg.contains("Opening"), "Result was: \(msg)")
        case .failure(let msg):
            XCTAssertTrue(msg.contains("Calculator") || msg.contains("couldn't find") || msg.contains("Failed"), "Result was: \(msg)")
        default:
            XCTFail("Unexpected result status: \(result)")
        }
    }

    func testGatewayResolvesAmbiguousFollowUp() async {
        let gateway = AMORACommandGateway()
        let settings = AISettingsSnapshot(
            enabled: false,
            provider: .appleOnDevice,
            model: "on-device",
            apiKey: "",
            contextAwarenessEnabled: true
        )

        // Seed both timer and media as active with no tiebreaker
        AmoraConversationContextManager.shared.recordTimer(AmoraTimerReference(duration: 600))
        AmoraConversationContextManager.shared.recordMedia(AmoraMediaReference(source: "Spotify", isPlaying: true))
        AmoraConversationContextManager.shared.recordAction(.openWorkspace())

        let result = await gateway.submit("pause it", settings: settings)
        XCTAssertEqual(result, AMORACommandResult.needsInformation(prompt: "Did you mean the timer or music?"))
    }
}
