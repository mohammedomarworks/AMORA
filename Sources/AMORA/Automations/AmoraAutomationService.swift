import Foundation
import Observation

/// Main coordinator and runtime scheduling service for AMORA Automations V1.
/// Runs locally on this Mac, never transmits data to any network, and avoids unnecessary polling.
@Observable @MainActor
public final class AmoraAutomationService: Sendable {
    public static let shared = AmoraAutomationService()

    public private(set) var automations: [AmoraAutomation] = []
    public private(set) var currentNotification: AmoraAutomationNotification?
    public let store: any AmoraAutomationStoring
    public let actionEngine: AmoraActionEngine
    public let contextProvider: AmoraContextProvider
    public let clock: @Sendable () -> Date
    public let calendar: Calendar
    public var eventSink: any AmoraEventSinking

    private var activeTimer: Timer?
    private var inFlightAutomationIds: Set<UUID> = []
    private var executionChain: [UUID] = []
    private var firedBatteryAutomationIds: Set<UUID> = []
    private var eventExecutionCooldowns: [UUID: Date] = [:]
    private var consecutiveLoopCount: [UUID: Int] = [:]
    public var minimumEventCooldown: TimeInterval = 1.0
    public var maxExecutionChainDepth: Int = 5

    public init(
        store: (any AmoraAutomationStoring)? = nil,
        actionEngine: AmoraActionEngine? = nil,
        contextProvider: AmoraContextProvider? = nil,
        clock: (@Sendable () -> Date)? = nil,
        calendar: Calendar = .current,
        eventSink: any AmoraEventSinking = MacOSAmoraEventSink()
    ) {
        let chosenStore = store ?? AmoraAutomationStore()
        let chosenEngine = actionEngine ?? AmoraActionEngine.shared
        self.store = chosenStore
        self.actionEngine = chosenEngine
        self.contextProvider = contextProvider ?? .shared
        self.clock = clock ?? { Date() }
        self.calendar = calendar
        self.eventSink = eventSink

        // Register notification action in the action engine registry only if not already registered
        if chosenEngine.registry.definition(for: "amora.notification") == nil {
            AmoraActionEngine.registerNotificationAction(into: chosenEngine.registry)
        }
    }

    /// Loads automations from disk, performs relaunch recovery, and arms the timer.
    public func load() async {
        self.automations = await store.list()
        await recoverAfterRelaunch()
    }

    /// Refreshes the local in-memory automations list from storage.
    public func refresh() async {
        self.automations = await store.list()
    }

    // MARK: - Native Scheduling Engine (No Unnecessary Polling)

    /// Schedules a native macOS Timer for the earliest nextRunAt among enabled automations.
    /// Completely avoids CPU polling while AMORA is waiting.
    public func scheduleNextRunTimer() {
        activeTimer?.invalidate()
        activeTimer = nil

        let now = clock()
        let upcomingDates = automations
            .filter { $0.enabled }
            .compactMap { $0.nextRunAt }
            .filter { $0 > now }

        guard let earliestDate = upcomingDates.min() else {
            return
        }

        let delay = max(0.1, earliestDate.timeIntervalSince(now))
        activeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fireDueAutomations()
            }
        }
    }

    /// Evaluates and fires all automations that are due at or before the given reference time.
    @discardableResult
    public func fireDueAutomations(now: Date? = nil) async -> [AmoraActionResult] {
        let currentTime = now ?? clock()
        let due = automations.filter { $0.enabled && ($0.nextRunAt.map { $0 <= currentTime } ?? false) }
        guard !due.isEmpty else {
            scheduleNextRunTimer()
            return []
        }

        var results: [AmoraActionResult] = []
        for automation in due {
            let result = await executeAutomation(automation, isManual: false, now: currentTime)
            results.append(result)
        }
        scheduleNextRunTimer()
        return results
    }

    /// Recovers from offline downtime after AMORA relaunches.
    /// Catches up missed scheduled runs and deterministically advances nextRunAt.
    public func recoverAfterRelaunch(now: Date? = nil) async {
        if automations.isEmpty {
            self.automations = await store.list()
        }
        let currentTime = now ?? clock()
        let missed = automations.filter {
            $0.enabled && ($0.nextRunAt.map { $0 <= currentTime } ?? false)
        }

        for automation in missed {
            await executeAutomation(automation, isManual: false, now: currentTime)
        }
        scheduleNextRunTimer()
    }

    // MARK: - Event-Driven Triggers (Battery & Timer Completion)

    /// Handles events emitted by `AMORAEventCenter` asynchronously.
    func handleEventAsync(_ event: AMORAEvent) async {
        switch event {
        case .timerCompleted:
            let matching = automations.filter { $0.enabled && $0.trigger == .timerCompletion }
            for auto in matching {
                await executeAutomation(auto, isManual: false)
            }

        case .timerStarted:
            // When a new timer is started (e.g. by user), reset loop counter for timer completion automations
            consecutiveLoopCount.removeAll()

        case .criticalBattery, .lowBattery:
            let currentLevel = BatteryService.shared.level
            let matching = automations.filter { auto in
                guard auto.enabled, case .batteryThreshold(let threshold, let comp) = auto.trigger else {
                    return false
                }
                if firedBatteryAutomationIds.contains(auto.id) {
                    return false
                }
                switch comp {
                case .dropsBelow, .lessThanOrEqual:
                    return currentLevel <= threshold
                case .risesAbove, .greaterThanOrEqual:
                    return currentLevel >= threshold
                }
            }
            for auto in matching {
                firedBatteryAutomationIds.insert(auto.id)
                await executeAutomation(auto, isManual: false)
            }

        case .charging, .chargedFull:
            // Reset low battery fired states when power is reconnected
            firedBatteryAutomationIds.removeAll()

        case .launched:
            await self.load()

        default:
            break
        }
    }

    /// Handles events emitted by `AMORAEventCenter`.
    func handleEvent(_ event: AMORAEvent) {
        Task { @MainActor in
            await handleEventAsync(event)
        }
    }

    // MARK: - Notification Presentation & User Interaction

    /// Presents a user-facing automation notification in the Dynamic Island.
    public func presentNotification(_ notification: AmoraAutomationNotification) {
        // Duplicate suppression: if current notification has identical message and automation within cooldown, ignore
        if let current = currentNotification,
           current.message == notification.message,
           current.automationId == notification.automationId,
           clock().timeIntervalSince(current.createdAt) < minimumEventCooldown {
            return
        }

        self.currentNotification = notification
        eventSink.emit(.automationNotificationPresented)
        if IslandModel.shared.displayState == .collapsed {
            WindowManager.shared.expandIsland()
        }
    }

    /// Dismisses the active automation notification.
    public func dismissNotification() {
        self.currentNotification = nil
        eventSink.emit(.automationNotificationDismissed)
    }

    /// Executes the optional action attached to the active automation notification.
    /// Consequential actions run with explicit user authorization (isConfirmed: true) because
    /// the user clicked the action button.
    public func executeCurrentNotificationAction() async {
        guard let current = currentNotification, let action = current.action else { return }
        dismissNotification()
        if let autoId = current.automationId, var auto = get(id: autoId) {
            auto.lastRunAt = clock()
            auto.updatedAt = clock()
            _ = try? await store.update(auto)
            if let idx = automations.firstIndex(where: { $0.id == auto.id }) {
                automations[idx] = auto
            }
        }
        _ = await actionEngine.execute(action, context: AmoraActionContext(isConfirmed: true))
    }

    // MARK: - Automation Execution & Safety Validation

    /// Advances schedule and persists state after an automation evaluation attempt.
    /// Recurring automations advance nextRunAt to the next slot.
    /// One-time automations clear nextRunAt and disable.
    @discardableResult
    private func advanceSchedule(
        for automation: AmoraAutomation,
        at currentTime: Date
    ) async -> AmoraAutomation {
        var updated = automation
        updated.lastRunAt = currentTime
        updated.updatedAt = currentTime

        if case .oneTime = updated.trigger {
            updated.enabled = false
            updated.nextRunAt = nil
        } else {
            updated.updateNextRunAt(from: currentTime, calendar: calendar)
        }

        _ = try? await store.update(updated)
        if let idx = automations.firstIndex(where: { $0.id == updated.id }) {
            automations[idx] = updated
        }
        return updated
    }

    /// Executes an automation safely using the Action Engine.
    @discardableResult
    public func executeAutomation(
        _ automation: AmoraAutomation,
        isManual: Bool = false,
        now: Date? = nil
    ) async -> AmoraActionResult {
        let currentTime = now ?? clock()
        let amoraAction = automation.action.asAmoraAction

        // 1. Enabled check: Non-manual execution must only run enabled automations
        guard automation.enabled || isManual else {
            return .unavailable(
                actionId: amoraAction.identifier,
                message: "Automation '\(automation.name)' is disabled."
            )
        }

        // 2. Loop prevention: In-flight recursion and cycle detection
        guard !inFlightAutomationIds.contains(automation.id) else {
            return .unavailable(
                actionId: amoraAction.identifier,
                message: "Loop prevented: Automation '\(automation.name)' is currently executing."
            )
        }
        guard !executionChain.contains(automation.id) else {
            return .unavailable(
                actionId: amoraAction.identifier,
                message: "Loop detected: Automation '\(automation.name)' forms a cycle in the active execution chain."
            )
        }
        guard executionChain.count < maxExecutionChainDepth else {
            return .unavailable(
                actionId: amoraAction.identifier,
                message: "Execution chain depth limit reached (\(maxExecutionChainDepth))."
            )
        }

        // 3. Loop prevention: Timer completion self-loop guard
        if !isManual, automation.trigger == .timerCompletion, case .startTimer = automation.action {
            if consecutiveLoopCount[automation.id, default: 0] >= 1 {
                return .unavailable(
                    actionId: amoraAction.identifier,
                    message: "Loop prevented: Automation '\(automation.name)' attempted repeated timer completion self-triggering."
                )
            }
            consecutiveLoopCount[automation.id, default: 0] += 1
        }

        // 4. Duplicate suppression / cooldown for automated event triggers
        let isBatteryTrigger: Bool
        if case .batteryThreshold = automation.trigger {
            isBatteryTrigger = true
        } else {
            isBatteryTrigger = false
        }
        if !isManual && !isBatteryTrigger, let lastFired = eventExecutionCooldowns[automation.id] {
            if currentTime.timeIntervalSince(lastFired) < minimumEventCooldown {
                return .unavailable(
                    actionId: amoraAction.identifier,
                    message: "Suppressed: Automation '\(automation.name)' fired too recently."
                )
            }
        }

        // 5. Condition evaluation (if condition is present)
        if let condition = automation.condition {
            let snapshot = contextProvider.currentSnapshot
            guard condition.evaluate(snapshot: snapshot) else {
                if !isManual {
                    await advanceSchedule(for: automation, at: currentTime)
                }
                return .unavailable(
                    actionId: amoraAction.identifier,
                    message: "Automation condition was not met."
                )
            }
        }

        // 6. Action Engine safety and validation
        let validation = actionEngine.validate(amoraAction)
        switch validation {
        case .invalid(let reason):
            if !isManual {
                await advanceSchedule(for: automation, at: currentTime)
            }
            return .invalidInput(actionId: amoraAction.identifier, message: reason)
        case .requiresConfirmation(let prompt) where !isManual:
            // Background automation cannot execute sensitive actions requiring confirmation
            let isAwaitingDecision = currentNotification?.automationId == automation.id
            if !isAwaitingDecision {
                let notif = AmoraAutomationNotification(
                    automationId: automation.id,
                    automationName: automation.name,
                    triggerIcon: automation.trigger.systemImage,
                    triggerName: automation.trigger.displayName,
                    message: prompt,
                    action: amoraAction,
                    actionTitle: amoraAction.humanReadableName
                )
                self.presentNotification(notif)
            }
            await advanceSchedule(for: automation, at: currentTime)
            return .needsConfirmation(actionId: amoraAction.identifier, prompt: prompt)
        case .valid, .requiresConfirmation:
            break
        }

        // 7. Sensitive action confirmation requirement
        if !isManual, let def = actionEngine.registry.definition(for: amoraAction.identifier) {
            if def.isConfirmationRequiredByDefault {
                let isAwaitingDecision = currentNotification?.automationId == automation.id
                if !isAwaitingDecision {
                    let notif = AmoraAutomationNotification(
                        automationId: automation.id,
                        automationName: automation.name,
                        triggerIcon: automation.trigger.systemImage,
                        triggerName: automation.trigger.displayName,
                        message: "This action requires user confirmation before execution.",
                        action: amoraAction,
                        actionTitle: amoraAction.humanReadableName
                    )
                    self.presentNotification(notif)
                }
                await advanceSchedule(for: automation, at: currentTime)
                return .needsConfirmation(
                    actionId: amoraAction.identifier,
                    prompt: "This action requires user confirmation before execution."
                )
            }
        }

        // 8. Execution via Action Engine with in-flight & chain tracking
        inFlightAutomationIds.insert(automation.id)
        executionChain.append(automation.id)
        eventExecutionCooldowns[automation.id] = currentTime

        defer {
            inFlightAutomationIds.remove(automation.id)
            if !executionChain.isEmpty {
                executionChain.removeLast()
            }
        }

        var metadata: [String: String] = [
            "automationId": automation.id.uuidString,
            "automationName": automation.name,
            "triggerIcon": automation.trigger.systemImage,
            "triggerName": automation.trigger.displayName
        ]
        let defaultAction: AmoraAction?
        let defaultActionTitle: String?
        if automation.trigger == .timerCompletion {
            defaultAction = .startTimer(duration: 300)
            defaultActionTitle = "5m Break"
            metadata["actionId"] = "timer.start"
            metadata["actionTitle"] = "5m Break"
            metadata["actionDuration"] = "300"
        } else {
            defaultAction = nil
            defaultActionTitle = nil
        }
        let context = AmoraActionContext(
            isConfirmed: isManual,
            metadata: metadata,
            snapshot: contextProvider.currentSnapshot
        )

        // For showNotification action, present notification directly on this service
        if case .showNotification(let msg) = automation.action {
            let notification = AmoraAutomationNotification(
                automationId: automation.id,
                automationName: automation.name,
                triggerIcon: automation.trigger.systemImage,
                triggerName: automation.trigger.displayName,
                message: msg,
                action: defaultAction,
                actionTitle: defaultActionTitle
            )
            self.presentNotification(notification)
        }

        let result = await actionEngine.execute(amoraAction, context: context)

        // 9. Update lastRunAt, updatedAt, and deterministic nextRunAt
        await advanceSchedule(for: automation, at: currentTime)

        return result
    }

    // MARK: - User Control Operations

    /// Creates and persists a new automation.
    @discardableResult
    public func create(
        name: String,
        trigger: AmoraAutomationTrigger,
        condition: AmoraAutomationCondition? = nil,
        action: AmoraAutomationAction,
        schedule: AmoraAutomationSchedule? = nil,
        enabled: Bool = true,
        allowDuplicate: Bool = false
    ) async throws -> AmoraAutomation {
        let automation = AmoraAutomation(
            name: name,
            trigger: trigger,
            condition: condition,
            action: action,
            schedule: schedule,
            enabled: enabled,
            createdAt: clock(),
            updatedAt: clock(),
            calendar: calendar
        )

        let saved = try await store.save(automation, allowDuplicate: allowDuplicate)
        await refresh()
        scheduleNextRunTimer()
        return saved
    }

    /// Retrieves an automation by id.
    public func get(id: UUID) -> AmoraAutomation? {
        automations.first { $0.id == id }
    }

    /// Lists all current automations.
    public func list() -> [AmoraAutomation] {
        automations
    }

    /// Updates an existing automation.
    @discardableResult
    public func update(_ automation: AmoraAutomation) async throws -> AmoraAutomation {
        var updated = automation
        updated.updatedAt = clock()
        if updated.enabled {
            updated.updateNextRunAt(from: clock(), calendar: calendar)
        } else {
            updated.nextRunAt = nil
        }

        let saved = try await store.update(updated)
        await refresh()
        scheduleNextRunTimer()
        return saved
    }

    /// Toggles the enabled state of an automation.
    @discardableResult
    public func toggleEnabled(id: UUID) async throws -> AmoraAutomation? {
        guard let auto = automations.first(where: { $0.id == id }) else { return nil }
        var updated = auto
        updated.enabled.toggle()
        return try await update(updated)
    }

    /// Deletes an automation by id.
    @discardableResult
    public func delete(id: UUID) async -> Bool {
        let deleted = await store.delete(id: id)
        if deleted {
            await refresh()
            scheduleNextRunTimer()
        }
        return deleted
    }

    /// Clears all automations with mandatory user confirmation.
    @discardableResult
    public func clearAll(confirmed: Bool) async -> Bool {
        guard confirmed else { return false }
        activeTimer?.invalidate()
        activeTimer = nil
        await store.clearAll()
        self.automations = []
        return true
    }

    /// Runs an automation manually on user demand for testing.
    @discardableResult
    public func runManually(id: UUID) async -> AmoraActionResult? {
        guard let auto = automations.first(where: { $0.id == id }) else { return nil }
        return await executeAutomation(auto, isManual: true)
    }

    /// Resets all in-memory and timer state (for test isolation).
    public func reset() {
        activeTimer?.invalidate()
        activeTimer = nil
        self.automations = []
        self.inFlightAutomationIds.removeAll()
        self.executionChain.removeAll()
        self.firedBatteryAutomationIds.removeAll()
        self.eventExecutionCooldowns.removeAll()
        self.consecutiveLoopCount.removeAll()
        self.currentNotification = nil
    }
}
