import XCTest
@testable import AMORA

@MainActor
final class AdaptiveCursorTrackingTests: XCTestCase {

    private var testWindow: NSWindow!
    private var testScreen: NSScreen!
    private var notchManager: NotchManager!

    override func setUp() async throws {
        try await super.setUp()
        testScreen = NSScreen.main ?? NSScreen.screens.first!
        testWindow = NSWindow(
            contentRect: NSRect(x: 500, y: 800, width: 200, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        testWindow.orderFrontRegardless()
        IslandModel.shared.expansion = 0.0
        IslandModel.shared.targetState = .collapsed
        IslandModel.shared.displayState = .collapsed
        AppState.shared.stateManager.transition(to: .idle)
        AppState.shared.settings.hoverToExpand = true

        notchManager = NotchManager(window: testWindow, screen: testScreen)
    }

    override func tearDown() async throws {
        notchManager?.stopTracking()
        notchManager = nil
        testWindow?.orderOut(nil)
        testWindow = nil
        testScreen = nil
        IslandModel.shared.expansion = 0.0
        IslandModel.shared.targetState = .collapsed
        IslandModel.shared.displayState = .collapsed
        AppState.shared.stateManager.transition(to: .idle)
        try await super.tearDown()
    }

    // MARK: - 1. Tier Definitions & Frequencies

    func testTrackingTiersPropertiesAndFrequencies() {
        XCTAssertEqual(CursorTrackingTier.active.interval, 0.05)
        XCTAssertEqual(CursorTrackingTier.active.frequencyHz, 20.0)

        XCTAssertEqual(CursorTrackingTier.approaching.interval, 0.12)
        XCTAssertEqual(CursorTrackingTier.approaching.frequencyHz, 8.0)

        XCTAssertEqual(CursorTrackingTier.distant.interval, 0.30)
        XCTAssertEqual(CursorTrackingTier.distant.frequencyHz, 3.0)

        XCTAssertEqual(CursorTrackingTier.idle.interval, 1.00)
        XCTAssertEqual(CursorTrackingTier.idle.frequencyHz, 1.0)

        XCTAssertNil(CursorTrackingTier.suspended.interval)
        XCTAssertEqual(CursorTrackingTier.suspended.frequencyHz, 0.0)
    }

    // MARK: - 2. Window Visibility & Fallback Handling

    func testWindowVisibilityAndFallbackHandling() {
        XCTAssertTrue(testWindow.isVisible)
        XCTAssertTrue(notchManager.isTrackingEnabled)

        // Hiding window while cursor is distant drops to low-power idle fallback tier (1.0s)
        testWindow.orderOut(nil)
        notchManager.trackCursor(at: CGPoint(x: 600, y: 100))
        XCTAssertFalse(testWindow.isVisible)
        XCTAssertEqual(notchManager.currentTier, .idle)
        XCTAssertEqual(notchManager.activeTimerInterval, 1.00)

        // When cursor approaches the notch (< 200 pt), window restores automatically without manual action
        notchManager.trackCursor(at: CGPoint(x: 600, y: 830))
        XCTAssertTrue(testWindow.isVisible)
        XCTAssertEqual(notchManager.currentTier, .active)
        XCTAssertEqual(notchManager.activeTimerInterval, 0.05)

        // Explicit pause (e.g. screen sleep) truly suspends tracking (nil timer)
        notchManager.pauseTracking()
        XCTAssertEqual(notchManager.currentTier, .suspended)
        XCTAssertNil(notchManager.activeTimerInterval)

        // Resume restores active tracking
        notchManager.resumeTracking()
        XCTAssertTrue(notchManager.isTrackingEnabled)
        XCTAssertNotEqual(notchManager.currentTier, .suspended)
        XCTAssertTrue(notchManager.isTimerActive)

        // Injecting near notch point confirms active tier (20 Hz)
        notchManager.trackCursor(at: CGPoint(x: 600, y: 830))
        XCTAssertEqual(notchManager.currentTier, .active)
        XCTAssertEqual(notchManager.activeTimerInterval, 0.05)
    }

    func testOrderedOutWindowRestoresWhenCursorApproachesNotch() {
        testWindow.orderOut(nil)
        XCTAssertFalse(testWindow.isVisible)

        // Distant cursor keeps window hidden and timer in idle fallback
        notchManager.trackCursor(at: CGPoint(x: 600, y: 100))
        XCTAssertFalse(testWindow.isVisible)
        XCTAssertEqual(notchManager.currentTier, .idle)

        // Approaching cursor restores the window automatically
        notchManager.trackCursor(at: CGPoint(x: 600, y: 825))
        XCTAssertTrue(testWindow.isVisible)
        XCTAssertEqual(notchManager.currentTier, .active)
        XCTAssertEqual(AppState.shared.stateManager.currentState, .hover)
    }

    func testMinimizedWindowRestoresWhenCursorApproachesNotch() {
        WindowManager.shared.minimizeAll()
        testWindow.orderOut(nil)
        XCTAssertFalse(testWindow.isVisible)

        // Approaching the notch area restores window and activates tracking
        notchManager.trackCursor(at: CGPoint(x: 600, y: 825))
        XCTAssertTrue(testWindow.isVisible)
        XCTAssertEqual(notchManager.currentTier, .active)
        XCTAssertEqual(notchManager.activeTimerInterval, 0.05)
    }

    func testTimerFallbackOperatesWithoutGlobalEventMonitors() {
        // Even if global mouse monitoring is unavailable (e.g. sandboxed or missing permissions),
        // the timer fallback at 1.0s in idle mode ensures cursor movements are evaluated safely.
        XCTAssertTrue(notchManager.isTimerActive)

        // Cursor distant: 3 stationary ticks demote to idle fallback at 1.00s
        let distantPoint = CGPoint(x: 600, y: 100)
        notchManager.trackCursor(at: distantPoint)
        notchManager.trackCursor(at: distantPoint)
        notchManager.trackCursor(at: distantPoint)
        XCTAssertEqual(notchManager.currentTier, .idle)
        XCTAssertEqual(notchManager.activeTimerInterval, 1.00)

        // Next timer tick with cursor near notch promotes to .active (20 Hz) safely
        notchManager.trackCursor(at: CGPoint(x: 600, y: 825))
        XCTAssertEqual(notchManager.currentTier, .active)
        XCTAssertEqual(notchManager.activeTimerInterval, 0.05)
    }

    func testNoDuplicateTimersAccumulateOnRepeatedResumeOrReconfiguration() {
        // Repeated calls to resumeTracking must not leak or stack timers
        for _ in 0..<10 {
            notchManager.resumeTracking()
        }
        XCTAssertTrue(notchManager.isTimerActive)
        XCTAssertNotNil(notchManager.activeTimerInterval)

        // Deterministically position near notch to verify timer remains at 0.05s
        notchManager.trackCursor(at: CGPoint(x: 600, y: 830))
        XCTAssertEqual(notchManager.activeTimerInterval, 0.05)

        // Repeated screen parameter notifications must not duplicate timers
        for _ in 0..<5 {
            NotificationCenter.default.post(
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil
            )
        }
        XCTAssertTrue(notchManager.isTimerActive)
        XCTAssertNotNil(notchManager.activeTimerInterval)
    }

    // MARK: - 3. Proximity Zone Classification

    func testProximityZoneClassificationAndTierPromotion() {
        // Window is at (500, 800, 200, 40). Center is (600, 820).

        // Zone 1: Hover area (< 60 pt) -> .active (20 Hz)
        notchManager.trackCursor(at: CGPoint(x: 600, y: 830))
        XCTAssertEqual(notchManager.currentTier, .active)
        XCTAssertEqual(notchManager.activeTimerInterval, 0.05)
        XCTAssertLessThan(notchManager.lastObservedDistance, 60.0)

        // Zone 2: Watching area (60..<200 pt) -> .active (20 Hz)
        notchManager.trackCursor(at: CGPoint(x: 600, y: 720))
        XCTAssertEqual(notchManager.currentTier, .active)
        XCTAssertEqual(notchManager.activeTimerInterval, 0.05)
        XCTAssertGreaterThanOrEqual(notchManager.lastObservedDistance, 60.0)
        XCTAssertLessThan(notchManager.lastObservedDistance, 200.0)

        // Zone 3: Approaching buffer area (250..<450 pt) -> .approaching (~8 Hz)
        notchManager.trackCursor(at: CGPoint(x: 600, y: 500))
        XCTAssertEqual(notchManager.currentTier, .approaching)
        XCTAssertEqual(notchManager.activeTimerInterval, 0.12)
        XCTAssertGreaterThanOrEqual(notchManager.lastObservedDistance, 250.0)
        XCTAssertLessThan(notchManager.lastObservedDistance, 450.0)

        // Zone 4: Distant moving area (>= 450 pt) -> .distant (~3.3 Hz)
        notchManager.trackCursor(at: CGPoint(x: 600, y: 200))
        XCTAssertEqual(notchManager.currentTier, .distant)
        XCTAssertEqual(notchManager.activeTimerInterval, 0.30)
        XCTAssertGreaterThanOrEqual(notchManager.lastObservedDistance, 450.0)
        XCTAssertEqual(notchManager.stationaryTicks, 0)
    }

    // MARK: - 4. Stationary Cursor Idle Demotion & Wakeup

    func testStationaryCursorDemotesToIdleAndWakesOnMovement() {
        let distantPoint = CGPoint(x: 600, y: 200)

        // Initial move to distant point sets .distant with stationaryTicks = 0
        notchManager.trackCursor(at: distantPoint)
        XCTAssertEqual(notchManager.currentTier, .distant)
        XCTAssertEqual(notchManager.stationaryTicks, 0)

        // First stationary tick increments counter, stays .distant
        notchManager.trackCursor(at: distantPoint)
        XCTAssertEqual(notchManager.stationaryTicks, 1)
        XCTAssertEqual(notchManager.currentTier, .distant)

        // Second stationary tick triggers demotion to .idle (1 Hz)
        notchManager.trackCursor(at: distantPoint)
        XCTAssertGreaterThanOrEqual(notchManager.stationaryTicks, 2)
        XCTAssertEqual(notchManager.currentTier, .idle)
        XCTAssertEqual(notchManager.activeTimerInterval, 1.00)

        // Cursor moves: immediately wakes out of idle
        let movedPoint = CGPoint(x: 610, y: 205)
        notchManager.trackCursor(at: movedPoint)
        XCTAssertEqual(notchManager.stationaryTicks, 0)
        XCTAssertEqual(notchManager.currentTier, .distant)
        XCTAssertEqual(notchManager.activeTimerInterval, 0.30)

        // Moving into active range immediately elevates to .active
        notchManager.trackCursor(at: CGPoint(x: 600, y: 820))
        XCTAssertEqual(notchManager.currentTier, .active)
        XCTAssertEqual(notchManager.activeTimerInterval, 0.05)
    }

    // MARK: - 5. Proximity State Transitions

    func testProximityStateTransitions() {
        // Initially idle
        AppState.shared.stateManager.transition(to: .idle)
        AppState.shared.settings.hoverToExpand = true

        // Approach hover area (< 60 pt)
        notchManager.trackCursor(at: CGPoint(x: 600, y: 825))
        XCTAssertEqual(AppState.shared.stateManager.currentState, .hover)

        // Move to watching area (60..<200 pt)
        AppState.shared.stateManager.transition(to: .idle)
        notchManager.trackCursor(at: CGPoint(x: 600, y: 720))
        XCTAssertEqual(AppState.shared.stateManager.currentState, .watching)

        // Move outside watching area (>= 200 pt)
        notchManager.trackCursor(at: CGPoint(x: 600, y: 500))
        XCTAssertEqual(AppState.shared.stateManager.currentState, .idle)
    }

    // MARK: - 6. Expanded Island Locking

    func testExpandedIslandLocksToActiveTier() {
        // Expand island
        IslandModel.shared.expansion = 1.0
        IslandModel.shared.targetState = .quick
        IslandModel.shared.displayState = .quick
        AppState.shared.stateManager.transition(to: .expanded)

        // Even when mouse is far away (700 pt), tracking must remain .active (20 Hz)
        notchManager.trackCursor(at: CGPoint(x: 600, y: 100))
        XCTAssertEqual(notchManager.currentTier, .active)
        XCTAssertEqual(notchManager.activeTimerInterval, 0.05)

        // Proximity transitions must not disrupt expanded state
        XCTAssertEqual(AppState.shared.stateManager.currentState, .expanded)

        // Collapse island
        IslandModel.shared.expansion = 0.0
        IslandModel.shared.targetState = .collapsed
        IslandModel.shared.displayState = .collapsed
        notchManager.trackCursor(at: CGPoint(x: 600, y: 100))
        XCTAssertEqual(notchManager.currentTier, .distant)
    }

    // MARK: - 7. Gaze Tracking Notification & Clamping

    private final class Box: @unchecked Sendable {
        var x: Double?
        var y: Double?
    }

    func testGazeTrackingNormalizedCoordinatesClamped() {
        let box = Box()

        let observer = NotificationCenter.default.addObserver(
            forName: .cursorMoved,
            object: nil,
            queue: .main
        ) { notif in
            box.x = notif.userInfo?["normalizedX"] as? Double
            box.y = notif.userInfo?["normalizedY"] as? Double
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // Window center is (600, 820), width: 200 (half: 100), height: 40 (half: 20)
        // 1. Center
        notchManager.trackCursor(at: CGPoint(x: 600, y: 820))
        XCTAssertNotNil(box.x)
        XCTAssertNotNil(box.y)
        XCTAssertEqual(box.x!, 0.0, accuracy: 0.01)
        XCTAssertEqual(box.y!, 0.0, accuracy: 0.01)

        // 2. Far Right (should clamp to 1.0)
        notchManager.trackCursor(at: CGPoint(x: 900, y: 820))
        XCTAssertEqual(box.x!, 1.0, accuracy: 0.001)

        // 3. Far Left (should clamp to -1.0)
        notchManager.trackCursor(at: CGPoint(x: 300, y: 820))
        XCTAssertEqual(box.x!, -1.0, accuracy: 0.001)

        // 4. Far Top (should clamp to 1.0)
        notchManager.trackCursor(at: CGPoint(x: 600, y: 900))
        XCTAssertEqual(box.y!, 1.0, accuracy: 0.001)

        // 5. Far Bottom (should clamp to -1.0)
        notchManager.trackCursor(at: CGPoint(x: 600, y: 500))
        XCTAssertEqual(box.y!, -1.0, accuracy: 0.001)
    }

    // MARK: - 8. Lifecycle: Pause, Resume, Stop

    func testLifecyclePauseResumeAndStop() {
        XCTAssertTrue(notchManager.isTrackingEnabled)
        XCTAssertTrue(notchManager.isTimerActive)

        // Pause
        notchManager.pauseTracking()
        XCTAssertFalse(notchManager.isTrackingEnabled)
        XCTAssertEqual(notchManager.currentTier, .suspended)
        XCTAssertFalse(notchManager.isTimerActive)
        XCTAssertNil(notchManager.activeTimerInterval)

        // Resume
        notchManager.resumeTracking()
        XCTAssertTrue(notchManager.isTrackingEnabled)
        XCTAssertTrue(notchManager.isTimerActive)
        XCTAssertNotEqual(notchManager.currentTier, .suspended)

        // Stop
        notchManager.stopTracking()
        XCTAssertFalse(notchManager.isTrackingEnabled)
        XCTAssertEqual(notchManager.currentTier, .suspended)
        XCTAssertFalse(notchManager.isTimerActive)
    }

    // MARK: - 9. Screen Sleep and Wake Observers

    func testScreenSleepAndWakeNotifications() {
        XCTAssertTrue(notchManager.isTrackingEnabled)

        // Screen sleep
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        XCTAssertFalse(notchManager.isTrackingEnabled)
        XCTAssertEqual(notchManager.currentTier, .suspended)
        XCTAssertFalse(notchManager.isTimerActive)

        // Screen wake
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        XCTAssertTrue(notchManager.isTrackingEnabled)
        XCTAssertTrue(notchManager.isTimerActive)
        XCTAssertNotEqual(notchManager.currentTier, .suspended)
    }

    // MARK: - 10. Screen Configuration Change Observer

    func testScreenParametersChangedNotification() {
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // Verify tracking state remains intact
        XCTAssertTrue(notchManager.isTrackingEnabled)
        XCTAssertTrue(notchManager.isTimerActive)
    }

    // MARK: - 11. WindowManager Minimize and Restore Integration

    func testWindowManagerMinimizeAndRestoreIntegration() {
        // WindowManager minimize/restore methods call NotchManager safely
        WindowManager.shared.minimizeAll()
        // Calling restoreAll restores island window state
        WindowManager.shared.restoreAll()
    }

    // MARK: - 12. Wakeup Reduction Metrics

    func testTimerWakeupComparison() {
        let baselineFrequencyHz = 20.0
        let baselineWakeupsPerMinute = baselineFrequencyHz * 60.0 // 1,200 wakeups/min

        let idleFrequencyHz = CursorTrackingTier.idle.frequencyHz // 1.0 Hz
        let idleWakeupsPerMinute = idleFrequencyHz * 60.0       // 60 wakeups/min

        let reductionFraction = (baselineWakeupsPerMinute - idleWakeupsPerMinute) / baselineWakeupsPerMinute
        let reductionPercent = reductionFraction * 100.0

        XCTAssertEqual(baselineWakeupsPerMinute, 1200.0)
        XCTAssertEqual(idleWakeupsPerMinute, 60.0)
        XCTAssertEqual(reductionPercent, 95.0, accuracy: 0.1)

        let suspendedWakeupsPerMinute = CursorTrackingTier.suspended.frequencyHz * 60.0
        XCTAssertEqual(suspendedWakeupsPerMinute, 0.0)
    }
}
