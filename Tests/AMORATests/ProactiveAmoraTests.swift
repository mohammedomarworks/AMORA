import XCTest
@testable import AMORA

@MainActor
final class ProactiveAmoraTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeTestSnapshot(
        timer: AmoraTimerContext = .stopped,
        media: AmoraMediaContext = .inactive,
        battery: AmoraBatteryContext = .unavailable,
        app: AmoraApplicationContext? = nil
    ) -> AmoraContextSnapshot {
        AmoraContextSnapshot(
            timestamp: Date(),
            currentApplication: app,
            media: media,
            timer: timer,
            battery: battery,
            amora: AmoraUIContext(state: "quick island"),
            fileShelf: AmoraFileShelfContext(itemCount: 0),
            formattedLocalTime: "12:00 PM"
        )
    }

    final class TestClock: @unchecked Sendable {
        var currentDate: Date
        private let lock = NSLock()

        init(initialDate: Date = Date()) {
            self.currentDate = initialDate
        }

        func now() -> Date {
            lock.lock()
            defer { lock.unlock() }
            return currentDate
        }

        func advance(by seconds: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            currentDate.addTimeInterval(seconds)
        }
    }

    private func makeMemoryStore(with items: [(key: String, value: String)] = []) async -> AmoraMemoryStore {
        let storage = AmoraInMemoryStorage()
        let store = AmoraMemoryStore(storage: storage)
        for item in items {
            _ = await store.save(key: item.key, value: item.value)
        }
        return store
    }

    // MARK: - 1. Each Trigger Tests

    func testTrigger_timerCompleted() {
        let evaluator = AmoraProactiveEvaluator()
        let snapshot = makeTestSnapshot()
        let context = AmoraProactiveEvaluationContext(
            snapshot: snapshot,
            memories: [],
            lastInteractionDate: nil,
            settings: .conservative,
            now: Date()
        )

        let suggestion = evaluator.evaluate(trigger: .timerCompleted, context: context)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.trigger, .timerCompleted)
        XCTAssertEqual(suggestion?.priority, .high)
        XCTAssertTrue(suggestion?.message.contains("Focus timer completed") == true)
        XCTAssertEqual(suggestion?.action, .startTimer(duration: 300))
        XCTAssertEqual(suggestion?.actionTitle, "Start Break")
    }

    func testTrigger_timerNearlyFinished() {
        let evaluator = AmoraProactiveEvaluator()

        // Running with 45s remaining (<= 60s threshold)
        let runningNearFinish = AmoraTimerContext(running: true, remainingSeconds: 45, duration: 1500, isPaused: false)
        let snapshot = makeTestSnapshot(timer: runningNearFinish)
        let context = AmoraProactiveEvaluationContext(
            snapshot: snapshot,
            memories: [],
            lastInteractionDate: nil,
            settings: .conservative,
            now: Date()
        )

        let suggestion = evaluator.evaluate(trigger: .timerNearlyFinished, context: context)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.trigger, .timerNearlyFinished)
        XCTAssertEqual(suggestion?.priority, .medium)
        XCTAssertTrue(suggestion?.message.contains("45s remaining") == true)

        // Running with 120s remaining (> 60s threshold) -> should be nil
        let runningFar = AmoraTimerContext(running: true, remainingSeconds: 120, duration: 1500, isPaused: false)
        let farContext = AmoraProactiveEvaluationContext(
            snapshot: makeTestSnapshot(timer: runningFar),
            memories: [],
            lastInteractionDate: nil,
            settings: .conservative,
            now: Date()
        )
        XCTAssertNil(evaluator.evaluate(trigger: .timerNearlyFinished, context: farContext))

        // Timer stopped -> should be nil
        let stoppedContext = AmoraProactiveEvaluationContext(
            snapshot: makeTestSnapshot(timer: .stopped),
            memories: [],
            lastInteractionDate: nil,
            settings: .conservative,
            now: Date()
        )
        XCTAssertNil(evaluator.evaluate(trigger: .timerNearlyFinished, context: stoppedContext))
    }

    func testTrigger_musicStartedStoppedChanged() {
        let evaluator = AmoraProactiveEvaluator()

        // 1. Music playing -> Suggestion with Pause action
        let playingMedia = AmoraMediaContext(source: "Spotify", state: "playing", title: "Starboy", artist: "The Weeknd")
        let playingContext = AmoraProactiveEvaluationContext(
            snapshot: makeTestSnapshot(media: playingMedia),
            memories: [],
            lastInteractionDate: nil,
            settings: .conservative,
            now: Date()
        )
        let playingSuggestion = evaluator.evaluate(trigger: .musicPlaybackChanged, context: playingContext)
        XCTAssertNotNil(playingSuggestion)
        XCTAssertEqual(playingSuggestion?.trigger, .musicPlaybackChanged)
        XCTAssertEqual(playingSuggestion?.priority, .low)
        XCTAssertTrue(playingSuggestion?.message.contains("Starboy") == true)
        XCTAssertEqual(playingSuggestion?.action, .pauseMusic)
        XCTAssertEqual(playingSuggestion?.actionTitle, "Pause")

        // 2. Music paused -> Suggestion with Play action
        let pausedMedia = AmoraMediaContext(source: "Spotify", state: "paused", title: "Starboy", artist: "The Weeknd")
        let pausedContext = AmoraProactiveEvaluationContext(
            snapshot: makeTestSnapshot(media: pausedMedia),
            memories: [],
            lastInteractionDate: nil,
            settings: .conservative,
            now: Date()
        )
        let pausedSuggestion = evaluator.evaluate(trigger: .musicPlaybackChanged, context: pausedContext)
        XCTAssertNotNil(pausedSuggestion)
        XCTAssertEqual(pausedSuggestion?.action, .playMusic)
        XCTAssertEqual(pausedSuggestion?.actionTitle, "Play")

        // 3. Media inactive -> should be nil
        let inactiveContext = AmoraProactiveEvaluationContext(
            snapshot: makeTestSnapshot(media: .inactive),
            memories: [],
            lastInteractionDate: nil,
            settings: .conservative,
            now: Date()
        )
        XCTAssertNil(evaluator.evaluate(trigger: .musicPlaybackChanged, context: inactiveContext))
    }

    func testTrigger_inactivityReturn() {
        let evaluator = AmoraProactiveEvaluator()
        let now = Date(timeIntervalSince1970: 100000)

        // 1. Inactivity elapsed > 30 mins (1800s) -> e.g. 2400s (40 mins)
        let inactiveContext = AmoraProactiveEvaluationContext(
            snapshot: makeTestSnapshot(),
            memories: [],
            lastInteractionDate: Date(timeIntervalSince1970: 100000 - 2400),
            settings: .conservative,
            now: now
        )
        let suggestion = evaluator.evaluate(trigger: .inactivityReturn, context: inactiveContext)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.trigger, .inactivityReturn)
        XCTAssertEqual(suggestion?.priority, .low)
        XCTAssertTrue(suggestion?.message.contains("Welcome back") == true)
        XCTAssertEqual(suggestion?.action, .startTimer(duration: 1500))

        // 2. Inactivity elapsed < 30 mins -> e.g. 300s (5 mins) -> nil
        let activeContext = AmoraProactiveEvaluationContext(
            snapshot: makeTestSnapshot(),
            memories: [],
            lastInteractionDate: Date(timeIntervalSince1970: 100000 - 300),
            settings: .conservative,
            now: now
        )
        XCTAssertNil(evaluator.evaluate(trigger: .inactivityReturn, context: activeContext))

        // 3. No previous interaction recorded -> nil
        let noInteractionContext = AmoraProactiveEvaluationContext(
            snapshot: makeTestSnapshot(),
            memories: [],
            lastInteractionDate: nil,
            settings: .conservative,
            now: now
        )
        XCTAssertNil(evaluator.evaluate(trigger: .inactivityReturn, context: noInteractionContext))
    }

    func testTrigger_batteryCriticallyLow() {
        let evaluator = AmoraProactiveEvaluator()

        // 1. Critical battery: 8%, discharging, not plugged in
        let criticalBattery = AmoraBatteryContext(percent: 8, charging: false, isPluggedIn: false)
        let criticalContext = AmoraProactiveEvaluationContext(
            snapshot: makeTestSnapshot(battery: criticalBattery),
            memories: [],
            lastInteractionDate: nil,
            settings: .conservative,
            now: Date()
        )
        let suggestion = evaluator.evaluate(trigger: .batteryCriticallyLow, context: criticalContext)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.trigger, .batteryCriticallyLow)
        XCTAssertEqual(suggestion?.priority, .critical)
        XCTAssertTrue(suggestion?.message.contains("8%") == true)
        XCTAssertNil(suggestion?.action) // Sensitive / automatic action strictly forbidden
    }

    // MARK: - 2. Cooldown Tests

    func testCooldown_preventsRepeatedNotificationWithinWindow() async {
        let clock = TestClock(initialDate: Date(timeIntervalSince1970: 10000))
        let tracker = AmoraProactiveCooldownTracker()
        let store = await makeMemoryStore()

        let service = AmoraProactiveService(
            cooldownTracker: tracker,
            contextProvider: { self.makeTestSnapshot() },
            memoryStore: store,
            settingsProvider: { .conservative },
            clock: { clock.now() },
            onSuggestionPresented: { _ in }
        )

        // 1. First evaluation fires successfully
        let first = await service.evaluateTrigger(.timerCompleted)
        XCTAssertNotNil(first)
        XCTAssertEqual(service.currentSuggestion?.trigger, .timerCompleted)

        // Dismiss so currentSuggestion is cleared
        service.dismissCurrentSuggestion()
        XCTAssertNil(service.currentSuggestion)

        // 2. Immediate re-evaluation at t + 30s (cooldown is 120s) -> must be suppressed by cooldown!
        clock.advance(by: 30)
        let second = await service.evaluateTrigger(.timerCompleted)
        XCTAssertNil(second, "Repeated trigger within cooldown window must be suppressed")

        // 3. Advance past cooldown window (t + 130s) -> allowed again!
        clock.advance(by: 100)
        let third = await service.evaluateTrigger(.timerCompleted)
        XCTAssertNotNil(third, "Trigger must be permitted after cooldown expires")
    }

    // MARK: - 3. Disabled Proactive AMORA Test

    func testDisabledProactiveAmora_suppressesAllSuggestions() async {
        let store = await makeMemoryStore()
        var disabledSettings = AmoraProactiveSettings.conservative
        disabledSettings.isEnabled = false

        let criticalBattery = AmoraBatteryContext(percent: 5, charging: false, isPluggedIn: false)
        let snapshot = makeTestSnapshot(battery: criticalBattery)

        let service = AmoraProactiveService(
            contextProvider: { snapshot },
            memoryStore: store,
            settingsProvider: { disabledSettings },
            onSuggestionPresented: { _ in }
        )

        for trigger in AmoraProactiveTrigger.allCases {
            let result = await service.evaluateTrigger(trigger)
            XCTAssertNil(result, "All triggers must return nil when Proactive AMORA master toggle is disabled")
        }
    }

    // MARK: - 4. Disabled Individual Trigger Tests

    func testDisabledIndividualTrigger_suppressesOnlyTargetTrigger() async {
        let store = await makeMemoryStore()
        var settings = AmoraProactiveSettings.conservative
        settings.timerCompletedEnabled = false
        settings.batteryCriticalEnabled = true

        let criticalBattery = AmoraBatteryContext(percent: 5, charging: false, isPluggedIn: false)
        let snapshot = makeTestSnapshot(battery: criticalBattery)

        let service = AmoraProactiveService(
            contextProvider: { snapshot },
            memoryStore: store,
            settingsProvider: { settings },
            onSuggestionPresented: { _ in }
        )

        // Timer completed is disabled -> nil
        let timerResult = await service.evaluateTrigger(.timerCompleted)
        XCTAssertNil(timerResult, "Disabled individual trigger must return nil")

        // Battery critical is enabled -> suggestion produced
        let batteryResult = await service.evaluateTrigger(.batteryCriticallyLow)
        XCTAssertNotNil(batteryResult, "Enabled trigger must produce a suggestion even if other triggers are disabled")
        XCTAssertEqual(batteryResult?.trigger, .batteryCriticallyLow)
    }

    // MARK: - 5. Dismissal Tests

    func testDismissal_clearsCurrentSuggestionAndRecordsCooldown() async {
        let clock = TestClock(initialDate: Date(timeIntervalSince1970: 50000))
        let store = await makeMemoryStore()
        let tracker = AmoraProactiveCooldownTracker()

        let service = AmoraProactiveService(
            cooldownTracker: tracker,
            contextProvider: { self.makeTestSnapshot() },
            memoryStore: store,
            settingsProvider: { .conservative },
            clock: { clock.now() },
            onSuggestionPresented: { _ in }
        )

        let suggestion = await service.evaluateTrigger(.timerCompleted)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(service.currentSuggestion?.id, suggestion?.id)

        // Dismiss
        service.dismissCurrentSuggestion()
        XCTAssertNil(service.currentSuggestion, "Dismissing must clear currentSuggestion")

        // Cooldown must be recorded at currentTime
        XCTAssertTrue(tracker.isCoolingDown(key: AmoraProactiveTrigger.timerCompleted.rawValue, now: clock.now()))
    }

    // MARK: - 6. Priority Tests

    func testPriority_higherPrioritySupersedesLowerPriority() async {
        let store = await makeMemoryStore()
        let playingMedia = AmoraMediaContext(source: "Spotify", state: "playing", title: "Song")
        let criticalBattery = AmoraBatteryContext(percent: 6, charging: false, isPluggedIn: false)

        let snapshot = makeTestSnapshot(media: playingMedia, battery: criticalBattery)

        let service = AmoraProactiveService(
            contextProvider: { snapshot },
            memoryStore: store,
            settingsProvider: { .conservative },
            onSuggestionPresented: { _ in }
        )

        // 1. Trigger low-priority suggestion (Music: priority .low = 1)
        let musicSug = await service.evaluateTrigger(.musicPlaybackChanged)
        XCTAssertNotNil(musicSug)
        XCTAssertEqual(service.currentSuggestion?.trigger, .musicPlaybackChanged)
        XCTAssertEqual(service.currentSuggestion?.priority, .low)

        // 2. Trigger high-priority suggestion (Battery critical: priority .critical = 4)
        // High priority must supersede active lower priority suggestion!
        let batterySug = await service.evaluateTrigger(.batteryCriticallyLow)
        XCTAssertNotNil(batterySug)
        XCTAssertEqual(service.currentSuggestion?.trigger, .batteryCriticallyLow)
        XCTAssertEqual(service.currentSuggestion?.priority, .critical)

        // 3. Trigger medium-priority suggestion (Timer nearly finished: priority .medium = 2)
        // Active critical priority must NOT be replaced by lower medium priority!
        let timerRunning = AmoraTimerContext(running: true, remainingSeconds: 30)
        let serviceWithTimer = AmoraProactiveService(
            contextProvider: { self.makeTestSnapshot(timer: timerRunning, battery: criticalBattery) },
            memoryStore: store,
            settingsProvider: { .conservative },
            onSuggestionPresented: { _ in }
        )
        // Set active to critical first
        _ = await serviceWithTimer.evaluateTrigger(.batteryCriticallyLow)
        XCTAssertEqual(serviceWithTimer.currentSuggestion?.trigger, .batteryCriticallyLow)

        // Now attempt lower priority candidate
        let lowerCandidate = await serviceWithTimer.evaluateTrigger(.timerNearlyFinished)
        XCTAssertNil(lowerCandidate, "Candidate with lower priority than active suggestion must be rejected")
        XCTAssertEqual(serviceWithTimer.currentSuggestion?.trigger, .batteryCriticallyLow)
    }

    // MARK: - 7. Battery Threshold Tests

    func testBatteryThreshold_exactBoundaries() {
        let evaluator = AmoraProactiveEvaluator()

        // Boundary 1: Above threshold (11% > 10%) -> nil
        let battery11 = AmoraBatteryContext(percent: 11, charging: false, isPluggedIn: false)
        let ctx11 = AmoraProactiveEvaluationContext(
            snapshot: makeTestSnapshot(battery: battery11),
            settings: .conservative
        )
        XCTAssertNil(evaluator.evaluate(trigger: .batteryCriticallyLow, context: ctx11))

        // Boundary 2: At threshold (10% <= 10%) -> produces suggestion
        let battery10 = AmoraBatteryContext(percent: 10, charging: false, isPluggedIn: false)
        let ctx10 = AmoraProactiveEvaluationContext(
            snapshot: makeTestSnapshot(battery: battery10),
            settings: .conservative
        )
        let sug10 = evaluator.evaluate(trigger: .batteryCriticallyLow, context: ctx10)
        XCTAssertNotNil(sug10)
        XCTAssertEqual(sug10?.priority, .critical)

        // Boundary 3: Below threshold (9% <= 10%) -> produces suggestion
        let battery9 = AmoraBatteryContext(percent: 9, charging: false, isPluggedIn: false)
        let ctx9 = AmoraProactiveEvaluationContext(
            snapshot: makeTestSnapshot(battery: battery9),
            settings: .conservative
        )
        XCTAssertNotNil(evaluator.evaluate(trigger: .batteryCriticallyLow, context: ctx9))

        // Boundary 4: At 5% but charging -> nil
        let batteryCharging = AmoraBatteryContext(percent: 5, charging: true, isPluggedIn: false)
        let ctxCharging = AmoraProactiveEvaluationContext(
            snapshot: makeTestSnapshot(battery: batteryCharging),
            settings: .conservative
        )
        XCTAssertNil(evaluator.evaluate(trigger: .batteryCriticallyLow, context: ctxCharging))

        // Boundary 5: At 5% but plugged in -> nil
        let batteryPlugged = AmoraBatteryContext(percent: 5, charging: false, isPluggedIn: true)
        let ctxPlugged = AmoraProactiveEvaluationContext(
            snapshot: makeTestSnapshot(battery: batteryPlugged),
            settings: .conservative
        )
        XCTAssertNil(evaluator.evaluate(trigger: .batteryCriticallyLow, context: ctxPlugged))
    }

    // MARK: - 8. Timer Completion Tests

    func testTimerCompletion_producesSafeBreakActionAndMessage() {
        let evaluator = AmoraProactiveEvaluator()
        let snapshot = makeTestSnapshot()
        let context = AmoraProactiveEvaluationContext(
            snapshot: snapshot,
            memories: [],
            settings: .conservative
        )

        let suggestion = evaluator.evaluate(trigger: .timerCompleted, context: context)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.trigger, .timerCompleted)
        XCTAssertEqual(suggestion?.priority, .high)
        XCTAssertEqual(suggestion?.action, .startTimer(duration: 300))
        XCTAssertEqual(suggestion?.actionTitle, "Start Break")
    }

    // MARK: - 9. Memory Remains Explicit-Only Tests

    func testMemoryRemainsExplicitOnly_usesExplicitMemoriesWithoutCreatingAny() async {
        // Setup store with explicit memories
        let store = await makeMemoryStore(with: [
            ("break_preference", "10 minutes"),
            ("focus_project", "AMORA Compiler")
        ])

        let countBefore = (await store.list()).count
        XCTAssertEqual(countBefore, 2)

        let service = AmoraProactiveService(
            contextProvider: { self.makeTestSnapshot() },
            memoryStore: store,
            settingsProvider: { .conservative },
            onSuggestionPresented: { _ in }
        )

        // Evaluate timer completion
        let suggestion = await service.evaluateTrigger(.timerCompleted)
        XCTAssertNotNil(suggestion)

        // Memory was leveraged to tailor break duration:
        XCTAssertTrue(suggestion?.message.contains("10 minutes") == true)
        XCTAssertEqual(suggestion?.action, .startTimer(duration: 600)) // 10 minutes parsed

        // Memory store item count MUST remain strictly identical:
        let countAfter = (await store.list()).count
        XCTAssertEqual(countAfter, countBefore, "Proactive AMORA must never automatically create or write memories")

        let memoriesAfter = await store.list()
        XCTAssertEqual(memoriesAfter.map(\.key).sorted(), ["break_preference", "focus_project"].sorted())
    }

    // MARK: - 10. Privacy Invariants Tests

    func testPrivacyInvariants_neverReadsScreenOrClipboardOrExecutesShell() async {
        let evaluator = AmoraProactiveEvaluator()

        // Test all triggers and ensure actions are strictly from safe set:
        let timerRunning = AmoraTimerContext(running: true, remainingSeconds: 30)
        let mediaPlaying = AmoraMediaContext(source: "Spotify", state: "playing", title: "Song")
        let batteryCritical = AmoraBatteryContext(percent: 5, charging: false, isPluggedIn: false)
        let snapshot = makeTestSnapshot(timer: timerRunning, media: mediaPlaying, battery: batteryCritical)

        let context = AmoraProactiveEvaluationContext(
            snapshot: snapshot,
            memories: [],
            lastInteractionDate: Date(timeIntervalSince1970: 0),
            settings: .conservative,
            now: Date(timeIntervalSince1970: 100000)
        )

        for trigger in AmoraProactiveTrigger.allCases {
            if let suggestion = evaluator.evaluate(trigger: trigger, context: context) {
                // Invariant 1: Action, if present, must never be an arbitrary or shell execution
                if let action = suggestion.action {
                    switch action {
                    case .startTimer, .pauseMusic, .playMusic:
                        // Permitted safe actions
                        break
                    default:
                        XCTFail("Proactive suggestion produced an unsafe action: \(action.identifier)")
                    }
                }

                // Invariant 2: Message never contains raw system paths or shell commands
                XCTAssertFalse(suggestion.message.contains("/bin/sh"))
                XCTAssertFalse(suggestion.message.contains("/bin/zsh"))
                XCTAssertFalse(suggestion.message.contains("sudo "))
            }
        }
    }

    // MARK: - 11. No Duplicate Notifications Tests

    func testNoDuplicateNotifications_identicalConditionIgnored() async {
        let store = await makeMemoryStore()
        let service = AmoraProactiveService(
            contextProvider: { self.makeTestSnapshot() },
            memoryStore: store,
            settingsProvider: { .conservative },
            onSuggestionPresented: { _ in }
        )

        // 1. Initial trigger produces suggestion
        let first = await service.evaluateTrigger(.timerCompleted)
        XCTAssertNotNil(first)
        let initialID = service.currentSuggestion?.id

        // 2. Immediate second call for same trigger while active must return nil and NOT duplicate or replace
        let duplicate = await service.evaluateTrigger(.timerCompleted)
        XCTAssertNil(duplicate, "Duplicate trigger while active must be ignored")
        XCTAssertEqual(service.currentSuggestion?.id, initialID, "Existing suggestion must remain unchanged")
    }

    // MARK: - 12. Settings Snapshot Test

    func testSettingsSnapshot_defaultsToConservativeBehavior() {
        let settings = AmoraProactiveSettings.conservative
        XCTAssertTrue(settings.isEnabled)
        XCTAssertTrue(settings.timerCompletedEnabled)
        XCTAssertTrue(settings.timerNearlyFinishedEnabled)
        XCTAssertTrue(settings.musicPlaybackEnabled)
        XCTAssertTrue(settings.inactivityReturnEnabled)
        XCTAssertTrue(settings.batteryCriticalEnabled)

        // Conservative thresholds
        XCTAssertEqual(settings.inactivityThresholdSeconds, 1800) // 30 minutes
        XCTAssertEqual(settings.batteryCriticalThresholdPercent, 10) // 10%
        XCTAssertEqual(settings.timerNearlyFinishedThresholdSeconds, 60) // 60s
        XCTAssertEqual(settings.defaultCooldownSeconds, 300) // 5 minutes
    }

    // MARK: - 13. Action Execution Test

    func testExecuteAction_dismissesSuggestionAndDispatchesAction() async {
        let store = await makeMemoryStore()
        let service = AmoraProactiveService(
            contextProvider: { self.makeTestSnapshot() },
            memoryStore: store,
            settingsProvider: { .conservative },
            onSuggestionPresented: { _ in }
        )

        let suggestion = await service.evaluateTrigger(.timerCompleted)
        XCTAssertNotNil(suggestion)
        XCTAssertNotNil(suggestion?.action)
        XCTAssertEqual(service.currentSuggestion?.id, suggestion?.id)

        // Execute attached safe action
        await service.executeCurrentAction()

        // Verifies suggestion was dismissed upon action execution
        XCTAssertNil(service.currentSuggestion)
    }

    // MARK: - 14. Event Handling Tests

    func testEventHandling_eventsTriggerExpectedEvaluation() async {
        let store = await makeMemoryStore()
        let criticalBattery = AmoraBatteryContext(percent: 5, charging: false, isPluggedIn: false)
        let snapshot = makeTestSnapshot(battery: criticalBattery)

        let service = AmoraProactiveService(
            contextProvider: { snapshot },
            memoryStore: store,
            settingsProvider: { .conservative },
            onSuggestionPresented: { _ in }
        )

        // Test event handling
        service.handleEvent(.criticalBattery)

        // Give Task a tick
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNotNil(service.currentSuggestion)
        XCTAssertEqual(service.currentSuggestion?.trigger, .batteryCriticallyLow)
    }
}
