import XCTest
@testable import AMORA

@MainActor
final class AutomationsV1Tests: XCTestCase {

    // MARK: - Test Doubles

    final class SpyNotificationPresenter: AmoraNotificationPresenting, @unchecked Sendable {
        var presentedMessages: [String] = []
        func present(message: String) {
            presentedMessages.append(message)
        }
    }

    final class SpyMediaController: AmoraMediaControlling, @unchecked Sendable {
        var played = false
        var paused = false
        var nextCount = 0
        var prevCount = 0
        func play() { played = true }
        func pause() { paused = true }
        func nextTrack() { nextCount += 1 }
        func previousTrack() { prevCount += 1 }
        var isPlaying = false
        var isAvailable = true
        var trackTitle = "Test Track"
        var sourceName = "Test Provider"
    }

    final class SpyTimerController: AmoraTimerControlling, @unchecked Sendable {
        var startedSeconds: Int?
        var stopped = false
        func startTimer(seconds: Int) { startedSeconds = seconds }
        func stopTimer() { stopped = true }
        var isRunning = false
        var isPaused = false
        var remainingSeconds = 0
    }

    final class MockClock: @unchecked Sendable {
        var now: Date
        init(_ initial: Date) { self.now = initial }
        func current() -> Date { now }
        func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    struct IsolatedMockMediaContextProvider: AmoraMediaContextProvider {
        let mediaController: SpyMediaController
        func currentMediaContext() -> AmoraMediaContext {
            if mediaController.isPlaying {
                return AmoraMediaContext(source: mediaController.sourceName, state: "playing", title: mediaController.trackTitle, artist: nil)
            } else if mediaController.isAvailable {
                return AmoraMediaContext(source: mediaController.sourceName, state: "paused", title: mediaController.trackTitle, artist: nil)
            } else {
                return .inactive
            }
        }
    }

    private func makeIsolatedService(
        initialAutomations: [AmoraAutomation] = [],
        now: Date = Date(),
        mediaController: SpyMediaController = SpyMediaController(),
        timerController: SpyTimerController = SpyTimerController(),
        notificationPresenter: SpyNotificationPresenter = SpyNotificationPresenter(),
        contextProvider: AmoraContextProvider? = nil
    ) async -> (service: AmoraAutomationService, store: AmoraAutomationStore, storage: AmoraInMemoryAutomationStorage) {
        let storage = AmoraInMemoryAutomationStorage(initialItems: initialAutomations)
        let store = AmoraAutomationStore(storage: storage)
        let registry = AmoraActionRegistry()
        AmoraActionEngine.registerDefaultActions(
            into: registry,
            mediaController: mediaController,
            appLauncher: NativeAmoraApplicationLauncher(),
            folderOpener: NativeAmoraFolderOpener(),
            workspaceController: DefaultAmoraWorkspaceController(),
            timerController: timerController
        )
        AmoraActionEngine.registerNotificationAction(into: registry, notificationPresenter: notificationPresenter)
        let engine = AmoraActionEngine(registry: registry)
        let resolvedContextProvider = contextProvider ?? AmoraContextProvider(
            appDetector: NativeAmoraApplicationDetector.shared,
            mediaProvider: IsolatedMockMediaContextProvider(mediaController: mediaController),
            timerProvider: DefaultAmoraTimerContextProvider(),
            batteryProvider: DefaultAmoraBatteryContextProvider(),
            uiProvider: DefaultAmoraUIContextProvider(),
            fileShelfProvider: DefaultAmoraFileShelfContextProvider()
        )
        let service = AmoraAutomationService(
            store: store,
            actionEngine: engine,
            contextProvider: resolvedContextProvider,
            clock: { now },
            calendar: Calendar(identifier: .gregorian)
        )
        await service.load()
        return (service, store, storage)
    }

    // MARK: - 1. Create / Edit / Delete Tests

    func testCreateAutomation() async throws {
        let (service, _, _) = await makeIsolatedService()
        let created = try await service.create(
            name: "Morning Stretch",
            trigger: .daily(hour: 8, minute: 30),
            action: .showNotification(message: "Time to stretch!"),
            enabled: true
        )

        XCTAssertEqual(created.name, "Morning Stretch")
        XCTAssertEqual(created.trigger, .daily(hour: 8, minute: 30))
        XCTAssertEqual(created.action, .showNotification(message: "Time to stretch!"))
        XCTAssertTrue(created.enabled)
        XCTAssertNotNil(created.nextRunAt)

        let list = service.list()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.id, created.id)
    }

    func testEditAutomation() async throws {
        let (service, _, _) = await makeIsolatedService()
        let created = try await service.create(
            name: "Stretch",
            trigger: .daily(hour: 8, minute: 0),
            action: .showNotification(message: "Stretch now")
        )

        var toUpdate = created
        toUpdate.name = "Evening Stretch"
        toUpdate.trigger = .daily(hour: 20, minute: 0)
        toUpdate.action = .showNotification(message: "Relax before bed")

        let updated = try await service.update(toUpdate)
        XCTAssertEqual(updated.name, "Evening Stretch")
        XCTAssertEqual(updated.trigger, .daily(hour: 20, minute: 0))
        XCTAssertEqual(updated.action, .showNotification(message: "Relax before bed"))

        let found = service.get(id: created.id)
        XCTAssertEqual(found?.name, "Evening Stretch")
    }

    func testDeleteAutomation() async throws {
        let (service, _, _) = await makeIsolatedService()
        let created = try await service.create(
            name: "Temporary",
            trigger: .interval(seconds: 300),
            action: .mediaPlay
        )

        XCTAssertEqual(service.list().count, 1)
        let deleted = await service.delete(id: created.id)
        XCTAssertTrue(deleted)
        XCTAssertEqual(service.list().count, 0)
        XCTAssertNil(service.get(id: created.id))
    }

    // MARK: - 2. Persistence / Reload & Corruption Tests

    func testPersistenceAndReload_fileStorage() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("automations.json")
        let fileStorage = AmoraFileAutomationStorage(fileURL: fileURL)

        let auto1 = AmoraAutomation(
            name: "Daily Check",
            trigger: .daily(hour: 9, minute: 0),
            action: .showNotification(message: "Morning check-in")
        )
        let auto2 = AmoraAutomation(
            name: "Work Timer",
            trigger: .weekdays(hour: 10, minute: 0),
            action: .startTimer(duration: 1500)
        )

        try await fileStorage.save([auto1, auto2])

        // Reload via fresh storage instance pointing to same file
        let reloadedStorage = AmoraFileAutomationStorage(fileURL: fileURL)
        let loaded = await reloadedStorage.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].id, auto1.id)
        XCTAssertEqual(loaded[0].name, "Daily Check")
        XCTAssertEqual(loaded[1].id, auto2.id)
        XCTAssertEqual(loaded[1].name, "Work Timer")
    }

    func testCorruptionRecovery_returnsEmptyWithoutCrashing() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("corrupt.json")
        try "INVALID NOT JSON {[[".write(to: fileURL, atomically: true, encoding: .utf8)

        let fileStorage = AmoraFileAutomationStorage(fileURL: fileURL)
        let loaded = await fileStorage.load()
        XCTAssertTrue(loaded.isEmpty, "Corrupt storage must return empty array without crashing.")
    }

    // MARK: - 3. Enable / Disable Tests

    func testEnableDisableToggle() async throws {
        let (service, _, _) = await makeIsolatedService()
        let created = try await service.create(
            name: "Daily Reminder",
            trigger: .daily(hour: 9, minute: 0),
            action: .showNotification(message: "Test"),
            enabled: true
        )

        XCTAssertTrue(created.enabled)
        XCTAssertNotNil(created.nextRunAt)

        // Disable
        let disabled = try await service.toggleEnabled(id: created.id)
        XCTAssertFalse(disabled?.enabled ?? true)
        XCTAssertNil(disabled?.nextRunAt)

        // Re-enable
        let reenabled = try await service.toggleEnabled(id: created.id)
        XCTAssertTrue(reenabled?.enabled ?? false)
        XCTAssertNotNil(reenabled?.nextRunAt)
    }

    // MARK: - 4. Schedule Calculation Tests

    func testScheduleCalculation_oneTime() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000) // Fixed point in time
        let future = now.addingTimeInterval(3600)
        let past = now.addingTimeInterval(-3600)

        let scheduleFuture = AmoraAutomationSchedule.oneTime(date: future)
        XCTAssertEqual(scheduleFuture.calculateNextRunAt(from: now, calendar: calendar), future)

        let schedulePast = AmoraAutomationSchedule.oneTime(date: past)
        XCTAssertNil(schedulePast.calculateNextRunAt(from: now, calendar: calendar))
    }

    func testScheduleCalculation_daily() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // Reference date: 2026-10-09 10:00:00 UTC
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 9
        comps.hour = 10
        comps.minute = 0
        comps.second = 0
        let refDate = calendar.date(from: comps)!

        // Case A: 9 PM (21:00) today -> should be today at 21:00
        let scheduleEvening = AmoraAutomationSchedule.daily(hour: 21, minute: 0)
        let nextEvening = scheduleEvening.calculateNextRunAt(from: refDate, calendar: calendar)
        XCTAssertNotNil(nextEvening)
        let nextEveningComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextEvening!)
        XCTAssertEqual(nextEveningComps.day, 9)
        XCTAssertEqual(nextEveningComps.hour, 21)

        // Case B: 9 AM (09:00) today -> already passed -> should be tomorrow at 09:00
        let scheduleMorning = AmoraAutomationSchedule.daily(hour: 9, minute: 0)
        let nextMorning = scheduleMorning.calculateNextRunAt(from: refDate, calendar: calendar)
        XCTAssertNotNil(nextMorning)
        let nextMorningComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextMorning!)
        XCTAssertEqual(nextMorningComps.day, 10)
        XCTAssertEqual(nextMorningComps.hour, 9)
    }

    func testScheduleCalculation_weekdays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // 2026-10-09 is a Friday
        var fridayComps = DateComponents()
        fridayComps.year = 2026
        fridayComps.month = 10
        fridayComps.day = 9
        fridayComps.hour = 11
        fridayComps.minute = 0
        let friday11AM = calendar.date(from: fridayComps)!

        // Weekdays at 10 AM (already passed on Friday)
        // Next run MUST skip Saturday (10th) and Sunday (11th) and land on Monday (12th)
        let schedule = AmoraAutomationSchedule.weekdays(hour: 10, minute: 0)
        let nextRun = schedule.calculateNextRunAt(from: friday11AM, calendar: calendar)
        XCTAssertNotNil(nextRun)
        let nextComps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: nextRun!)
        XCTAssertEqual(nextComps.day, 12, "Weekdays trigger must land on Monday 12th")
        XCTAssertEqual(nextComps.hour, 10)
        XCTAssertFalse(calendar.isDateInWeekend(nextRun!))
    }

    func testScheduleCalculation_interval() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let schedule = AmoraAutomationSchedule.interval(seconds: 300)

        // With no prior run
        let firstRun = schedule.calculateNextRunAt(from: now, lastRunAt: nil, calendar: calendar)
        XCTAssertEqual(firstRun, now.addingTimeInterval(300))

        // With prior run in future
        let prior = now.addingTimeInterval(100)
        let nextRun = schedule.calculateNextRunAt(from: now, lastRunAt: prior, calendar: calendar)
        XCTAssertEqual(nextRun, prior.addingTimeInterval(300))
    }

    // MARK: - 5. Trigger Execution Tests

    func testOneTimeTriggerExecution_disablesAfterRunning() async throws {
        let spy = SpyNotificationPresenter()
        let now = Date()
        let target = now.addingTimeInterval(10)
        let auto = AmoraAutomation(
            name: "Doctor Appt",
            trigger: .oneTime(date: target),
            action: .showNotification(message: "Head to clinic"),
            nextRunAt: target
        )
        let (service, _, _) = await makeIsolatedService(
            initialAutomations: [auto],
            now: target.addingTimeInterval(1),
            notificationPresenter: spy
        )

        await service.fireDueAutomations(now: target.addingTimeInterval(1))

        let updated = service.get(id: auto.id)
        XCTAssertFalse(updated?.enabled ?? true, "One-time automation must be disabled after firing")
        XCTAssertNil(updated?.nextRunAt)
        XCTAssertEqual(spy.presentedMessages, ["Head to clinic"])
    }

    func testDailyTriggerExecution_advancesToTomorrow() async throws {
        let spy = SpyNotificationPresenter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 9
        comps.hour = 21
        comps.minute = 0
        let triggerTime = calendar.date(from: comps)!

        let auto = AmoraAutomation(
            name: "Night Meds",
            trigger: .daily(hour: 21, minute: 0),
            action: .showNotification(message: "Take evening meds"),
            nextRunAt: triggerTime
        )
        let (service, _, _) = await makeIsolatedService(
            initialAutomations: [auto],
            now: triggerTime,
            notificationPresenter: spy
        )

        await service.fireDueAutomations(now: triggerTime)

        let updated = service.get(id: auto.id)
        XCTAssertTrue(updated?.enabled ?? false)
        XCTAssertNotNil(updated?.lastRunAt)
        XCTAssertNotNil(updated?.nextRunAt)
        XCTAssertTrue(updated!.nextRunAt! > triggerTime)
        XCTAssertEqual(spy.presentedMessages, ["Take evening meds"])
    }

    func testIntervalTriggerExecution_advancesByInterval() async throws {
        let mediaSpy = SpyMediaController()
        let now = Date()
        let auto = AmoraAutomation(
            name: "Hourly Music",
            trigger: .interval(seconds: 3600),
            action: .mediaPlay,
            nextRunAt: now
        )
        let (service, _, _) = await makeIsolatedService(
            initialAutomations: [auto],
            now: now.addingTimeInterval(-100),
            mediaController: mediaSpy
        )

        await service.fireDueAutomations(now: now)

        XCTAssertTrue(mediaSpy.played)
        let updated = service.get(id: auto.id)
        XCTAssertEqual(updated?.lastRunAt, now)
        XCTAssertEqual(updated?.nextRunAt, now.addingTimeInterval(3600))
    }

    // MARK: - 6. Battery Trigger Tests

    func testBatteryTrigger_firesWhenConditionMet() async throws {
        let spy = SpyNotificationPresenter()
        let auto = AmoraAutomation(
            name: "Low Battery Alert",
            trigger: .batteryThreshold(level: 20, comparison: .dropsBelow),
            action: .showNotification(message: "Connect to power soon")
        )
        let (service, _, _) = await makeIsolatedService(
            initialAutomations: [auto],
            notificationPresenter: spy
        )

        // BatteryService level matches threshold (e.g. 15%)
        BatteryService.shared.level = 15
        await service.handleEventAsync(.lowBattery)

        XCTAssertEqual(spy.presentedMessages, ["Connect to power soon"])
    }

    func testBatteryTrigger_doesNotFireWhenConditionNotMet() async throws {
        let spy = SpyNotificationPresenter()
        let auto = AmoraAutomation(
            name: "Low Battery Alert",
            trigger: .batteryThreshold(level: 20, comparison: .dropsBelow),
            action: .showNotification(message: "Connect to power soon")
        )
        let (service, _, _) = await makeIsolatedService(
            initialAutomations: [auto],
            notificationPresenter: spy
        )

        // BatteryService level is 80% (well above 20%)
        BatteryService.shared.level = 80
        await service.handleEventAsync(.charging)

        XCTAssertTrue(spy.presentedMessages.isEmpty)
    }

    // MARK: - 7. Timer Trigger Tests

    func testTimerCompletionTrigger_firesOnEvent() async throws {
        let mediaSpy = SpyMediaController()
        let auto = AmoraAutomation(
            name: "Post Focus Song",
            trigger: .timerCompletion,
            action: .mediaPlay
        )
        let (service, _, _) = await makeIsolatedService(
            initialAutomations: [auto],
            mediaController: mediaSpy
        )

        await service.handleEventAsync(.timerCompleted)

        XCTAssertTrue(mediaSpy.played)
    }

    // MARK: - 8. nextRunAt Determinism Tests

    func testNextRunAt_deterministicAcrossAllTriggers() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar(identifier: .gregorian)

        // 1. One-time
        let oneTimeFuture = AmoraAutomation(
            name: "T1",
            trigger: .oneTime(date: now.addingTimeInterval(500)),
            action: .mediaPlay,
            createdAt: now,
            calendar: calendar
        )
        XCTAssertEqual(oneTimeFuture.nextRunAt, now.addingTimeInterval(500))

        // 2. Daily
        let daily = AmoraAutomation(
            name: "T2",
            trigger: .daily(hour: 12, minute: 0),
            action: .mediaPlay,
            createdAt: now,
            calendar: calendar
        )
        XCTAssertNotNil(daily.nextRunAt)

        // 3. Weekdays
        let weekdays = AmoraAutomation(
            name: "T3",
            trigger: .weekdays(hour: 9, minute: 0),
            action: .mediaPlay,
            createdAt: now,
            calendar: calendar
        )
        XCTAssertNotNil(weekdays.nextRunAt)

        // 4. Interval
        let interval = AmoraAutomation(
            name: "T4",
            trigger: .interval(seconds: 600),
            action: .mediaPlay,
            createdAt: now,
            calendar: calendar
        )
        XCTAssertEqual(interval.nextRunAt, now.addingTimeInterval(600))

        // 5. Battery (event-driven)
        let battery = AmoraAutomation(
            name: "T5",
            trigger: .batteryThreshold(level: 20, comparison: .dropsBelow),
            action: .mediaPlay,
            createdAt: now,
            calendar: calendar
        )
        XCTAssertNil(battery.nextRunAt, "Event-driven battery trigger must have nil nextRunAt")

        // 6. Timer completion (event-driven)
        let timer = AmoraAutomation(
            name: "T6",
            trigger: .timerCompletion,
            action: .mediaPlay,
            createdAt: now,
            calendar: calendar
        )
        XCTAssertNil(timer.nextRunAt, "Event-driven timer completion trigger must have nil nextRunAt")
    }

    // MARK: - 9. Relaunch Recovery Tests

    func testRelaunchRecovery_catchesUpMissedRuns() async throws {
        let spy = SpyNotificationPresenter()
        let now = Date()
        let pastDue = now.addingTimeInterval(-1800) // 30 minutes in past (during downtime)

        let missedDaily = AmoraAutomation(
            name: "Missed Daily",
            trigger: .daily(hour: 9, minute: 0),
            action: .showNotification(message: "Missed reminder"),
            nextRunAt: pastDue
        )

        let (service, _, _) = await makeIsolatedService(
            initialAutomations: [missedDaily],
            now: now,
            notificationPresenter: spy
        )

        await service.recoverAfterRelaunch(now: now)

        XCTAssertEqual(spy.presentedMessages, ["Missed reminder"])
        let updated = service.get(id: missedDaily.id)
        XCTAssertEqual(updated?.lastRunAt, now)
        XCTAssertTrue(updated!.nextRunAt! > now, "nextRunAt must be advanced to upcoming occurrence")
    }

    // MARK: - 10. Duplicate Prevention Tests

    func testDuplicatePrevention_identicalNameRejected() async throws {
        let (service, _, _) = await makeIsolatedService()
        try await service.create(
            name: "Daily Sync",
            trigger: .daily(hour: 9, minute: 0),
            action: .showNotification(message: "Sync")
        )

        do {
            try await service.create(
                name: "daily sync", // Case-insensitive duplicate
                trigger: .daily(hour: 10, minute: 0),
                action: .showNotification(message: "Other")
            )
            XCTFail("Must reject automation with identical name")
        } catch AmoraAutomationError.duplicateAutomation {
            // Success
        }
    }

    func testDuplicatePrevention_identicalTriggerAndActionRejected() async throws {
        let (service, _, _) = await makeIsolatedService()
        try await service.create(
            name: "Timer Alpha",
            trigger: .interval(seconds: 300),
            action: .mediaPlay
        )

        do {
            try await service.create(
                name: "Different Name",
                trigger: .interval(seconds: 300),
                action: .mediaPlay
            )
            XCTFail("Must reject automation with identical trigger and action")
        } catch AmoraAutomationError.duplicateAutomation {
            // Success
        }
    }

    // MARK: - 11. Action Engine Safety Tests

    func testActionEngineSafety_permittedActionsExecuteSafely() async throws {
        let timerSpy = SpyTimerController()
        let mediaSpy = SpyMediaController()
        let notifySpy = SpyNotificationPresenter()

        let (service, _, _) = await makeIsolatedService(
            mediaController: mediaSpy,
            timerController: timerSpy,
            notificationPresenter: notifySpy
        )

        // 1. Notification
        let autoNotify = AmoraAutomation(name: "A1", trigger: .timerCompletion, action: .showNotification(message: "Hello"))
        let r1 = await service.executeAutomation(autoNotify, isManual: true)
        XCTAssertEqual(r1.status, .success)
        XCTAssertEqual(notifySpy.presentedMessages, ["Hello"])

        // 2. Start Timer
        let autoTimer = AmoraAutomation(name: "A2", trigger: .timerCompletion, action: .startTimer(duration: 1500))
        let r2 = await service.executeAutomation(autoTimer, isManual: true)
        XCTAssertEqual(r2.status, .success)
        XCTAssertEqual(timerSpy.startedSeconds, 1500)

        // 3. Media Play & Pause
        let autoPlay = AmoraAutomation(name: "A3", trigger: .timerCompletion, action: .mediaPlay)
        let r3 = await service.executeAutomation(autoPlay, isManual: true)
        XCTAssertEqual(r3.status, .success)
        XCTAssertTrue(mediaSpy.played)

        let autoPause = AmoraAutomation(name: "A4", trigger: .timerCompletion, action: .mediaPause)
        let r4 = await service.executeAutomation(autoPause, isManual: true)
        XCTAssertEqual(r4.status, .success)
        XCTAssertTrue(mediaSpy.paused)
    }

    func testActionEngineSafety_sensitiveActionsRefuseUnconfirmedExecution() async throws {
        let (service, _, _) = await makeIsolatedService()
        // Register an action that requires confirmation by default
        service.actionEngine.registry.register(AmoraActionDefinition(
            identifier: "system.confirm_test",
            name: "Sensitive",
            description: "Sensitive test",
            isConfirmationRequiredByDefault: true,
            confirmationRequirement: { _ in .required(prompt: "Are you sure?") },
            handler: { _, _ in .success(actionId: "system.confirm_test", message: "Done") }
        ))
        // Directly trying to run an unconfirmed sensitive action via engine
        let unconfirmedResult = await service.actionEngine.execute(
            .confirmTest(actionName: "Danger", prompt: "Confirm?"),
            context: AmoraActionContext(isConfirmed: false)
        )
        XCTAssertEqual(unconfirmedResult.status, .needsConfirmation)
    }

    func testActionEngineSafety_unapprovedActionsRejected() {
        // AmoraAutomationAction cannot be initialized from openFolder or arbitrary non-V1 action
        let folderAction = AmoraAction.openFolder(location: "downloads")
        XCTAssertNil(AmoraAutomationAction(from: folderAction), "Non-V1 action must be rejected from automation model")
    }

    // MARK: - 12. AssistantManager Parsing Tests

    func testAssistantManagerParsing_dailyReminder() async {
        let input = "Remind me every day at 9 PM."
        let parsed = AmoraAutomationCommandParser.shared.parse(input)
        XCTAssertNotNil(parsed)
        guard case let .create(name, trigger, action) = parsed else {
            XCTFail("Failed to parse daily reminder command")
            return
        }

        XCTAssertTrue(name.contains("9 PM") || name.contains("Daily"))
        XCTAssertEqual(trigger, .daily(hour: 21, minute: 0))
        if case .showNotification(let msg) = action {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Action must be showNotification")
        }
    }

    func testAssistantManagerParsing_weekdayTimer() async {
        let input = "Every weekday at 10 AM, start a 25 minute timer."
        let parsed = AmoraAutomationCommandParser.shared.parse(input)
        XCTAssertNotNil(parsed)
        guard case let .create(_, trigger, action) = parsed else {
            XCTFail("Failed to parse weekday timer command")
            return
        }

        XCTAssertEqual(trigger, .weekdays(hour: 10, minute: 0))
        XCTAssertEqual(action, .startTimer(duration: 1500))
    }

    func testAssistantManagerParsing_turnOffReminder() {
        let input = "Turn off my 9 PM reminder."
        let parsed = AmoraAutomationCommandParser.shared.parse(input)
        XCTAssertEqual(parsed, .turnOff(query: "9 PM reminder"))
    }

    func testAssistantManagerParsing_listAutomations() {
        let input = "List my automations."
        let parsed = AmoraAutomationCommandParser.shared.parse(input)
        XCTAssertEqual(parsed, .list)
    }

    func testAssistantManagerParsing_deleteAllAutomations() {
        let inputUnconfirmed = "Delete all automations."
        XCTAssertEqual(AmoraAutomationCommandParser.shared.parse(inputUnconfirmed), .clearAll(confirmed: false))

        let inputConfirmed = "yes delete all automations"
        XCTAssertEqual(AmoraAutomationCommandParser.shared.parse(inputConfirmed), .clearAll(confirmed: true))
    }

    func testAssistantManagerExecution_turnOffWorkflow() async throws {
        let assistant = AssistantManager.shared
        let settings = AISettingsSnapshot(enabled: true, provider: .none, model: "none", apiKey: nil)

        // 1. Create automation via AssistantManager
        _ = await assistant.submit("Remind me every day at 9 PM.", settings: settings)

        // 2. List automations
        let listResponse = await assistant.submit("List my automations.", settings: settings)
        XCTAssertTrue(listResponse.contains("9 PM"))
        XCTAssertTrue(listResponse.contains("Active"))

        // 3. Turn off reminder
        let turnOffResponse = await assistant.submit("Turn off my 9 PM reminder.", settings: settings)
        XCTAssertTrue(turnOffResponse.contains("turned off"))

        // 4. Delete all automations unconfirmed -> prompts
        let deletePrompt = await assistant.submit("Delete all automations.", settings: settings)
        XCTAssertTrue(deletePrompt.contains("Are you sure"))

        // 5. Confirm deletion
        let deleteConfirmed = await assistant.submit("yes delete all automations", settings: settings)
        XCTAssertTrue(deleteConfirmed.contains("deleted all"))
    }

    // MARK: - 13. Clear All Confirmation Tests

    func testClearAllConfirmation_respectsFlag() async throws {
        let (service, _, _) = await makeIsolatedService()
        try await service.create(name: "A1", trigger: .timerCompletion, action: .mediaPlay)
        try await service.create(name: "A2", trigger: .interval(seconds: 60), action: .mediaPause)

        XCTAssertEqual(service.list().count, 2)

        // False confirmation must not delete
        let unconfirmedResult = await service.clearAll(confirmed: false)
        XCTAssertFalse(unconfirmedResult)
        XCTAssertEqual(service.list().count, 2)

        // True confirmation deletes all
        let confirmedResult = await service.clearAll(confirmed: true)
        XCTAssertTrue(confirmedResult)
        XCTAssertEqual(service.list().count, 0)
    }

    // MARK: - 14. Disabled Automations Regression Tests

    func testDisabledAutomation_suppressesExecution() async throws {
        let spy = SpyNotificationPresenter()
        let auto = AmoraAutomation(
            name: "Disabled Reminder",
            trigger: .timerCompletion,
            action: .showNotification(message: "Should not show"),
            enabled: false
        )
        let (service, _, _) = await makeIsolatedService(
            initialAutomations: [auto],
            notificationPresenter: spy
        )

        // Non-manual execution must be suppressed
        let result = await service.executeAutomation(auto, isManual: false)
        XCTAssertEqual(result.status, .unavailable)
        XCTAssertTrue(result.message.contains("disabled"))
        XCTAssertTrue(spy.presentedMessages.isEmpty)

        // Manual execution (user forced run) is permitted
        let manualResult = await service.executeAutomation(auto, isManual: true)
        XCTAssertEqual(manualResult.status, .success)
        XCTAssertEqual(spy.presentedMessages, ["Should not show"])
    }

    // MARK: - 15. Duplicate Suppression Regression Tests

    func testDuplicateSuppression_batteryDoesNotFireRepeatedlyWhileLow() async throws {
        let spy = SpyNotificationPresenter()
        let auto = AmoraAutomation(
            name: "Low Battery Warning",
            trigger: .batteryThreshold(level: 20, comparison: .dropsBelow),
            action: .showNotification(message: "Battery is low!")
        )
        let (service, _, _) = await makeIsolatedService(
            initialAutomations: [auto],
            notificationPresenter: spy
        )

        // 1. Battery drops to 15% -> fires first time
        BatteryService.shared.level = 15
        await service.handleEventAsync(.lowBattery)
        XCTAssertEqual(spy.presentedMessages.count, 1)

        // 2. Battery stays at 15% / updates again -> must NOT fire a duplicate
        await service.handleEventAsync(.criticalBattery)
        XCTAssertEqual(spy.presentedMessages.count, 1, "Must suppress duplicate firing while battery remains low")

        // 3. Charger connected -> resets edge trigger
        await service.handleEventAsync(.charging)

        // 4. Later drops to 15% again -> fires again
        await service.handleEventAsync(.lowBattery)
        XCTAssertEqual(spy.presentedMessages.count, 2, "Must fire again after battery state resets")
    }

    func testDuplicateSuppression_rapidEventBurstDebounced() async throws {
        let spy = SpyNotificationPresenter()
        let now = Date()
        let auto = AmoraAutomation(
            name: "Timer Finish Alert",
            trigger: .timerCompletion,
            action: .showNotification(message: "Timer done!")
        )
        let (service, _, _) = await makeIsolatedService(
            initialAutomations: [auto],
            now: now,
            notificationPresenter: spy
        )
        service.minimumEventCooldown = 5.0

        // First firing
        let r1 = await service.executeAutomation(auto, isManual: false, now: now)
        XCTAssertEqual(r1.status, .success)

        // Second firing within 1 second -> debounced
        let r2 = await service.executeAutomation(auto, isManual: false, now: now.addingTimeInterval(1.0))
        XCTAssertEqual(r2.status, .unavailable)
        XCTAssertTrue(r2.message.contains("too recently") || r2.message.contains("Suppressed"))
    }

    // MARK: - 16. Loop Prevention Regression Tests

    func testLoopPrevention_timerSelfLoopSuppressed() async throws {
        let timerSpy = SpyTimerController()
        let auto = AmoraAutomation(
            name: "Chained Timer",
            trigger: .timerCompletion,
            action: .startTimer(duration: 300)
        )
        let (service, _, _) = await makeIsolatedService(
            initialAutomations: [auto],
            timerController: timerSpy
        )

        // 1. First event trigger: starts 300s timer
        let r1 = await service.executeAutomation(auto, isManual: false)
        XCTAssertEqual(r1.status, .success)
        XCTAssertEqual(timerSpy.startedSeconds, 300)

        // 2. Chained self-trigger: must be blocked to prevent infinite timer loops
        let r2 = await service.executeAutomation(auto, isManual: false)
        XCTAssertEqual(r2.status, .unavailable)
        XCTAssertTrue(r2.message.contains("Loop prevented"))
    }

    func testLoopPrevention_inFlightRecursionGuard() async throws {
        let (service, _, _) = await makeIsolatedService()
        let auto = AmoraAutomation(
            name: "Recursive Target",
            trigger: .timerCompletion,
            action: .showNotification(message: "Recursive")
        )

        // Register an action that attempts to re-enter executeAutomation with same auto.id
        service.actionEngine.registry.register(AmoraActionDefinition(
            identifier: "amora.recursive_test",
            name: "Recursive Action",
            description: "Calls back into the automation service",
            handler: { _, _ in
                let reentrant = await service.executeAutomation(auto, isManual: false)
                return reentrant
            }
        ))

        let cycleAuto = AmoraAutomation(
            id: auto.id,
            name: "Cycle Auto",
            trigger: .timerCompletion,
            action: .mediaPlay
        )
        let r1 = await service.executeAutomation(cycleAuto, isManual: false)
        XCTAssertEqual(r1.status, .success)
    }

    // MARK: - 8. Notification Delivery & Rendering State Tests

    func testNotificationDelivery_showsNotificationInAutomationService() async throws {
        let (service, _, _) = await makeIsolatedService()
        let auto = AmoraAutomation(
            name: "Stretch Alert",
            trigger: .timerCompletion,
            action: .showNotification(message: "Time to stand up and stretch!")
        )

        let result = await service.executeAutomation(auto, isManual: true)
        XCTAssertEqual(result.status, .success)

        guard let notif = service.currentNotification else {
            XCTFail("currentNotification must be set after showNotification execution")
            return
        }
        XCTAssertEqual(notif.automationId, auto.id)
        XCTAssertEqual(notif.automationName, "Stretch Alert")
        XCTAssertEqual(notif.message, "Time to stand up and stretch!")
        XCTAssertEqual(notif.triggerIcon, "timer")
        XCTAssertEqual(notif.triggerName, "When focus timer completes")
        XCTAssertEqual(notif.action, .startTimer(duration: 300))
        XCTAssertEqual(notif.actionTitle, "5m Break")
    }

    func testNotificationDelivery_timerCompletionTriggersVisibleNotification() async throws {
        let auto = AmoraAutomation(
            name: "Timer Break",
            trigger: .timerCompletion,
            action: .showNotification(message: "Focus session done. Take 5 minutes.")
        )
        let (service, _, _) = await makeIsolatedService(initialAutomations: [auto])

        await service.handleEventAsync(.timerCompleted)

        guard let notif = service.currentNotification else {
            XCTFail("Timer completion event must deliver notification to currentNotification")
            return
        }
        XCTAssertEqual(notif.message, "Focus session done. Take 5 minutes.")
        XCTAssertEqual(notif.triggerIcon, "timer")
    }

    func testNotificationDismissal_clearsCurrentNotification() async throws {
        let (service, _, _) = await makeIsolatedService()
        let notif = AmoraAutomationNotification(
            triggerIcon: "timer",
            triggerName: "Focus Timer",
            message: "Dismiss me please"
        )
        service.presentNotification(notif)
        XCTAssertNotNil(service.currentNotification)

        service.dismissNotification()
        XCTAssertNil(service.currentNotification, "Dismissing notification must clear currentNotification")
    }

    func testDuplicateSuppression_identicalNotificationIgnoredWithinCooldown() async throws {
        let clock = MockClock(Date(timeIntervalSince1970: 1000))
        let storage = AmoraInMemoryAutomationStorage()
        let store = AmoraAutomationStore(storage: storage)
        let service = AmoraAutomationService(
            store: store,
            clock: { clock.current() }
        )
        let autoId = UUID()
        let notif1 = AmoraAutomationNotification(
            automationId: autoId,
            message: "Repeated notification",
            createdAt: clock.now
        )
        service.presentNotification(notif1)
        XCTAssertEqual(service.currentNotification?.id, notif1.id)

        // Attempting to present identical message + automation within cooldown is suppressed
        clock.advance(by: 0.5)
        let notif2 = AmoraAutomationNotification(
            automationId: autoId,
            message: "Repeated notification",
            createdAt: clock.now
        )
        service.presentNotification(notif2)
        XCTAssertEqual(service.currentNotification?.id, notif1.id, "Duplicate notification must be ignored")

        // Once cooldown passes, new notification is accepted
        clock.advance(by: 2.0)
        let notif3 = AmoraAutomationNotification(
            automationId: autoId,
            message: "Repeated notification",
            createdAt: clock.now
        )
        service.presentNotification(notif3)
        XCTAssertEqual(service.currentNotification?.id, notif3.id, "After cooldown, fresh notification should be accepted")
    }

    func testConsequentialActionNotification_requiresUserAuthorizationAndExecutesOnAction() async throws {
        let media = SpyMediaController()
        let (service, _, _) = await makeIsolatedService(mediaController: media)

        // Register a sensitive action requiring confirmation by default
        service.actionEngine.registry.register(AmoraActionDefinition(
            identifier: "sensitive.op",
            name: "Sensitive Operation",
            description: "Requires confirmation",
            isConfirmationRequiredByDefault: true,
            handler: { _, _ in
                media.play()
                return .success(actionId: "sensitive.op", message: "Performed sensitive operation.")
            }
        ))

        let auto = AmoraAutomation(
            name: "Sensitive Auto",
            trigger: .timerCompletion,
            action: .mediaPlay
        )

        // Directly post notification with consequential action
        let notif = AmoraAutomationNotification(
            automationId: auto.id,
            automationName: auto.name,
            triggerIcon: "timer",
            triggerName: "Focus Timer",
            message: "Start audio playback?",
            action: .playMusic,
            actionTitle: "Play Music"
        )
        service.presentNotification(notif)
        XCTAssertNotNil(service.currentNotification)
        XCTAssertFalse(media.played)

        // Execute action attached to notification
        await service.executeCurrentNotificationAction()

        // Notification must be dismissed and action executed with confirmation
        XCTAssertNil(service.currentNotification)
        XCTAssertTrue(media.played, "Action button execution must run consequential action with confirmation")
    }

    func testNotificationRenderingState_companionPanelProperties() {
        let notif = AmoraAutomationNotification(
            automationId: UUID(),
            automationName: "Morning Routine",
            triggerIcon: "clock",
            triggerName: "Daily at 8:00 AM",
            message: "Good morning! Time for standup.",
            action: .openWorkspace(section: "automations"),
            actionTitle: "Open Automations"
        )

        XCTAssertEqual(notif.triggerIcon, "clock")
        XCTAssertEqual(notif.triggerName, "Daily at 8:00 AM")
        XCTAssertEqual(notif.message, "Good morning! Time for standup.")
        XCTAssertEqual(notif.actionTitle, "Open Automations")
        XCTAssertNotNil(notif.action)
    }

    // MARK: - 16. Phase 4B Schedule Progression & Confirmation Tests

    func testRecurringAutomation_unmetCondition_advancesScheduleWithoutFiring() async throws {
        let media = SpyMediaController()
        media.isPlaying = false
        let now = Date()
        let auto = AmoraAutomation(
            name: "Interval Music",
            trigger: .interval(seconds: 300),
            condition: .mediaPlaying(true),
            action: .mediaPlay,
            nextRunAt: now
        )
        let (service, _, _) = await makeIsolatedService(
            initialAutomations: [auto],
            now: now.addingTimeInterval(-100),
            mediaController: media
        )

        let results = await service.fireDueAutomations(now: now)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.status, .unavailable)
        XCTAssertFalse(media.played, "Action must not execute when condition is unmet")

        let updated = service.get(id: auto.id)
        XCTAssertNotNil(updated?.nextRunAt)
        XCTAssertEqual(updated?.nextRunAt, now.addingTimeInterval(300), "Schedule must advance to next interval on condition mismatch")

        // 1 second later, automation is not due and does not fire
        let subsequentResults = await service.fireDueAutomations(now: now.addingTimeInterval(1))
        XCTAssertTrue(subsequentResults.isEmpty)
        XCTAssertFalse(media.played)
    }

    func testRecurringAutomation_requiresConfirmation_advancesScheduleWithoutRepeatedPrompts() async throws {
        let media = SpyMediaController()
        let now = Date()
        let auto = AmoraAutomation(
            name: "Sensitive Interval",
            trigger: .interval(seconds: 300),
            action: .mediaPlay,
            nextRunAt: now
        )
        let (service, _, _) = await makeIsolatedService(
            initialAutomations: [auto],
            now: now.addingTimeInterval(-100),
            mediaController: media
        )

        service.actionEngine.registry.register(AmoraActionDefinition(
            identifier: "media.play",
            name: "Play Music",
            description: "Sensitive play action",
            isConfirmationRequiredByDefault: true,
            handler: { _, _ in
                media.play()
                return .success(actionId: "media.play", message: "Playing.")
            }
        ))

        let results = await service.fireDueAutomations(now: now)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.status, .needsConfirmation)
        XCTAssertFalse(media.played, "Sensitive action must not run automatically without user confirmation")

        let currentNotif = service.currentNotification
        XCTAssertNotNil(currentNotif)
        XCTAssertEqual(currentNotif?.automationId, auto.id)

        let updated = service.get(id: auto.id)
        XCTAssertEqual(updated?.nextRunAt, now.addingTimeInterval(300), "Schedule must advance to next slot while awaiting confirmation")

        // Subsequent check 10 seconds later while decision is pending: no duplicate prompts
        let secondResults = await service.fireDueAutomations(now: now.addingTimeInterval(10))
        XCTAssertTrue(secondResults.isEmpty)
        XCTAssertEqual(service.currentNotification?.id, currentNotif?.id, "Pending prompt must not be duplicated")

        // At next interval slot (300s later), if still pending: advances schedule to 600s without replacing prompt
        let thirdResults = await service.fireDueAutomations(now: now.addingTimeInterval(300))
        XCTAssertEqual(thirdResults.count, 1)
        XCTAssertEqual(thirdResults.first?.status, .needsConfirmation)
        XCTAssertEqual(service.currentNotification?.id, currentNotif?.id, "Pending prompt must not be replaced")
        let updatedTwice = service.get(id: auto.id)
        XCTAssertEqual(updatedTwice?.nextRunAt, now.addingTimeInterval(600))
    }

    func testConfirmationApprovalExecutesActionOnce_denialDoesNotExecute() async throws {
        let media = SpyMediaController()
        let now = Date()
        let auto = AmoraAutomation(
            name: "Confirmable Auto",
            trigger: .interval(seconds: 300),
            action: .mediaPlay,
            nextRunAt: now
        )
        let (service, _, _) = await makeIsolatedService(
            initialAutomations: [auto],
            now: now.addingTimeInterval(-100),
            mediaController: media
        )

        service.actionEngine.registry.register(AmoraActionDefinition(
            identifier: "media.play",
            name: "Play Music",
            description: "Sensitive play action",
            isConfirmationRequiredByDefault: true,
            handler: { _, _ in
                media.play()
                return .success(actionId: "media.play", message: "Playing.")
            }
        ))

        // 1. Approval path
        let results = await service.fireDueAutomations(now: now)
        XCTAssertEqual(results.first?.status, .needsConfirmation)
        XCTAssertNotNil(service.currentNotification)
        XCTAssertFalse(media.played)

        await service.executeCurrentNotificationAction()
        XCTAssertTrue(media.played, "Action must execute once on approval")
        XCTAssertNil(service.currentNotification, "Notification must be dismissed after approval")

        // Calling again does not execute again
        media.played = false
        await service.executeCurrentNotificationAction()
        XCTAssertFalse(media.played, "Dismissed confirmation must not execute twice")

        // 2. Denial path
        media.played = false
        var nextAuto = auto
        nextAuto.nextRunAt = now.addingTimeInterval(600)
        let _ = await service.executeAutomation(nextAuto, isManual: false, now: now.addingTimeInterval(600))
        XCTAssertNotNil(service.currentNotification)

        // Deny by dismissing
        service.dismissNotification()
        XCTAssertNil(service.currentNotification)
        XCTAssertFalse(media.played, "Denial must not execute action")

        await service.executeCurrentNotificationAction()
        XCTAssertFalse(media.played, "Denial prevents pending action execution")
    }

    func testOneTimeAutomation_cannotRemainOverdueOrRunRepeatedly() async throws {
        let media = SpyMediaController()
        media.isPlaying = false
        let now = Date()
        let target = now.addingTimeInterval(10)

        // Subcase A: One-time with unmet condition
        let autoUnmet = AmoraAutomation(
            name: "One-time Condition Unmet",
            trigger: .oneTime(date: target),
            condition: .mediaPlaying(true),
            action: .mediaPlay,
            nextRunAt: target
        )
        let (service, _, _) = await makeIsolatedService(
            initialAutomations: [autoUnmet],
            now: now,
            mediaController: media
        )

        let resultsA = await service.fireDueAutomations(now: target)
        XCTAssertEqual(resultsA.first?.status, .unavailable)
        XCTAssertFalse(media.played)

        let updatedA = service.get(id: autoUnmet.id)
        XCTAssertFalse(updatedA?.enabled ?? true, "One-time automation must be disabled when condition fails")
        XCTAssertNil(updatedA?.nextRunAt, "One-time automation nextRunAt must be nil so it is not overdue")

        // Future check: does not run
        let resultsFutureA = await service.fireDueAutomations(now: target.addingTimeInterval(100))
        XCTAssertTrue(resultsFutureA.isEmpty)

        // Subcase B: One-time requiring confirmation
        let mediaB = SpyMediaController()
        let autoConfirm = AmoraAutomation(
            name: "One-time Confirm",
            trigger: .oneTime(date: target),
            action: .mediaPlay,
            nextRunAt: target
        )
        let (serviceB, _, _) = await makeIsolatedService(
            initialAutomations: [autoConfirm],
            now: now,
            mediaController: mediaB
        )

        serviceB.actionEngine.registry.register(AmoraActionDefinition(
            identifier: "media.play",
            name: "Play Music",
            description: "Sensitive play action",
            isConfirmationRequiredByDefault: true,
            handler: { _, _ in
                mediaB.play()
                return .success(actionId: "media.play", message: "Playing.")
            }
        ))

        let resultsB = await serviceB.fireDueAutomations(now: target)
        XCTAssertEqual(resultsB.first?.status, .needsConfirmation)
        XCTAssertNotNil(serviceB.currentNotification)

        let updatedB = serviceB.get(id: autoConfirm.id)
        XCTAssertFalse(updatedB?.enabled ?? true, "One-time automation must be deactivated after triggering")
        XCTAssertNil(updatedB?.nextRunAt, "One-time automation must not remain overdue")

        // Future check: does not re-trigger or re-prompt
        let resultsFutureB = await serviceB.fireDueAutomations(now: target.addingTimeInterval(100))
        XCTAssertTrue(resultsFutureB.isEmpty)

        // Confirm pending prompt: executes successfully once with authorization
        await serviceB.executeCurrentNotificationAction()
        XCTAssertTrue(mediaB.played, "Pending confirmation on one-time automation must still be executable")
        XCTAssertNil(serviceB.currentNotification)
    }

    func testInvalidActionInput_advancesOrDeactivatesScheduleCorrectly() async throws {
        let now = Date()

        // 1. Recurring with invalid action (duration 0 is rejected by timer.start validator)
        let autoRecurring = AmoraAutomation(
            name: "Invalid Recurring",
            trigger: .interval(seconds: 300),
            action: .startTimer(duration: 0),
            nextRunAt: now
        )
        let (service, _, _) = await makeIsolatedService(
            initialAutomations: [autoRecurring],
            now: now.addingTimeInterval(-100)
        )

        let results1 = await service.fireDueAutomations(now: now)
        XCTAssertEqual(results1.count, 1)
        XCTAssertEqual(results1.first?.status, .invalidInput)

        let updatedRec = service.get(id: autoRecurring.id)
        XCTAssertEqual(updatedRec?.nextRunAt, now.addingTimeInterval(300), "Invalid recurring action must advance schedule to next slot")

        // 2. One-time with invalid action
        let target = now.addingTimeInterval(10)
        let autoOneTime = AmoraAutomation(
            name: "Invalid One-Time",
            trigger: .oneTime(date: target),
            action: .startTimer(duration: 0),
            nextRunAt: target
        )
        let (service2, _, _) = await makeIsolatedService(
            initialAutomations: [autoOneTime],
            now: now
        )

        let results2 = await service2.fireDueAutomations(now: target)
        XCTAssertEqual(results2.count, 1)
        XCTAssertEqual(results2.first?.status, .invalidInput)

        let updatedOne = service2.get(id: autoOneTime.id)
        XCTAssertFalse(updatedOne?.enabled ?? true, "Invalid one-time automation must be deactivated")
        XCTAssertNil(updatedOne?.nextRunAt, "Invalid one-time automation nextRunAt must be nil")

        // Future run does not execute
        let resultsFuture = await service2.fireDueAutomations(now: target.addingTimeInterval(50))
        XCTAssertTrue(resultsFuture.isEmpty)
    }
}
