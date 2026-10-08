import Foundation
import Observation

/// Main coordinator and runtime scheduling service for AMORA Automations V1.
/// Runs locally on this Mac, never transmits data to any network, and avoids unnecessary polling.
@Observable @MainActor
public final class AmoraAutomationService: Sendable {
    public static let shared = AmoraAutomationService()

    public private(set) var automations: [AmoraAutomation] = []
    public let store: any AmoraAutomationStoring
    public let actionEngine: AmoraActionEngine
    public let clock: @Sendable () -> Date
    public let calendar: Calendar

    private var activeTimer: Timer?
    private var lastFiredBatteryLevel: Int?

    public init(
        store: (any AmoraAutomationStoring)? = nil,
        actionEngine: AmoraActionEngine? = nil,
        clock: (@Sendable () -> Date)? = nil,
        calendar: Calendar = .current
    ) {
        let chosenStore = store ?? AmoraAutomationStore()
        let chosenEngine = actionEngine ?? AmoraActionEngine.shared
        self.store = chosenStore
        self.actionEngine = chosenEngine
        self.clock = clock ?? { Date() }
        self.calendar = calendar

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

    /// Handles events emitted by `AMORAEventCenter`.
    func handleEvent(_ event: AMORAEvent) {
        switch event {
        case .timerCompleted:
            Task { @MainActor in
                let matching = automations.filter { $0.enabled && $0.trigger == .timerCompletion }
                for auto in matching {
                    await executeAutomation(auto, isManual: false)
                }
            }

        case .criticalBattery, .lowBattery, .charging, .chargedFull:
            Task { @MainActor in
                let currentLevel = BatteryService.shared.level
                let matching = automations.filter { auto in
                    guard auto.enabled, case .batteryThreshold(let threshold, let comp) = auto.trigger else {
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
                    await executeAutomation(auto, isManual: false)
                }
            }

        case .launched:
            Task { @MainActor in
                await self.load()
            }

        default:
            break
        }
    }

    // MARK: - Automation Execution & Safety Validation

    /// Executes an automation safely using the Action Engine.
    @discardableResult
    public func executeAutomation(
        _ automation: AmoraAutomation,
        isManual: Bool = false,
        now: Date? = nil
    ) async -> AmoraActionResult {
        let currentTime = now ?? clock()

        // 1. Condition evaluation (if condition is present)
        if let condition = automation.condition {
            let snapshot = AmoraContextProvider.shared.currentSnapshot
            guard condition.evaluate(snapshot: snapshot) else {
                return .unavailable(
                    actionId: automation.action.asAmoraAction.identifier,
                    message: "Automation condition was not met."
                )
            }
        }

        // 2. Action Engine safety and validation
        let amoraAction = automation.action.asAmoraAction
        let validation = actionEngine.validate(amoraAction)
        switch validation {
        case .invalid(let reason):
            return .invalidInput(actionId: amoraAction.identifier, message: reason)
        case .requiresConfirmation(let prompt) where !isManual:
            // Background automation cannot execute sensitive actions requiring confirmation
            return .needsConfirmation(actionId: amoraAction.identifier, prompt: prompt)
        case .valid, .requiresConfirmation:
            break
        }

        // 3. Sensitive action confirmation requirement
        if !isManual, let def = actionEngine.registry.definition(for: amoraAction.identifier) {
            if def.isConfirmationRequiredByDefault {
                return .needsConfirmation(
                    actionId: amoraAction.identifier,
                    prompt: "This action requires user confirmation before execution."
                )
            }
        }

        // 4. Execution via Action Engine
        let context = AmoraActionContext(
            isConfirmed: isManual,
            snapshot: AmoraContextProvider.shared.currentSnapshot
        )
        let result = await actionEngine.execute(amoraAction, context: context)

        // 5. Update lastRunAt, updatedAt, and deterministic nextRunAt
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
        self.lastFiredBatteryLevel = nil
    }
}
