import Foundation

/// Protocol defining operations for storing, retrieving, and managing persistent automations.
public protocol AmoraAutomationStoring: Sendable {
    func list() async -> [AmoraAutomation]
    func get(id: UUID) async -> AmoraAutomation?
    func save(_ automation: AmoraAutomation, allowDuplicate: Bool) async throws -> AmoraAutomation
    func update(_ automation: AmoraAutomation) async throws -> AmoraAutomation
    func delete(id: UUID) async -> Bool
    func clearAll() async
    func isDuplicate(name: String, trigger: AmoraAutomationTrigger, action: AmoraAutomationAction, excludingId: UUID?) async -> Bool
    func reload() async -> [AmoraAutomation]
}

/// Actor-isolated, thread-safe automation store managing lifecycle, persistence, and duplicate checks.
public actor AmoraAutomationStore: AmoraAutomationStoring {
    private let storage: any AmoraAutomationStorage
    private var cachedItems: [AmoraAutomation]?
    private var isLoaded: Bool = false

    public init(storage: (any AmoraAutomationStorage)? = nil) {
        self.storage = storage ?? AmoraFileAutomationStorage()
    }

    private func ensureLoaded() async -> [AmoraAutomation] {
        if let cached = cachedItems, isLoaded {
            return cached
        }
        let items = await storage.load()
        self.cachedItems = items
        self.isLoaded = true
        return items
    }

    private func persist() async {
        guard let items = cachedItems else { return }
        try? await storage.save(items)
    }

    public func reload() async -> [AmoraAutomation] {
        let items = await storage.load()
        self.cachedItems = items
        self.isLoaded = true
        return items
    }

    public func list() async -> [AmoraAutomation] {
        await ensureLoaded()
    }

    public func get(id: UUID) async -> AmoraAutomation? {
        let items = await ensureLoaded()
        return items.first { $0.id == id }
    }

    public func isDuplicate(
        name: String,
        trigger: AmoraAutomationTrigger,
        action: AmoraAutomationAction,
        excludingId: UUID? = nil
    ) async -> Bool {
        let items = await ensureLoaded()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.contains { item in
            if let excludingId, item.id == excludingId { return false }
            // Duplicate condition 1: Identical name (case-insensitive)
            if item.name.caseInsensitiveCompare(trimmedName) == .orderedSame {
                return true
            }
            // Duplicate condition 2: Identical trigger and identical action
            if item.trigger == trigger && item.action == action {
                return true
            }
            return false
        }
    }

    public func save(_ automation: AmoraAutomation, allowDuplicate: Bool = false) async throws -> AmoraAutomation {
        var items = await ensureLoaded()

        if !allowDuplicate {
            let isDup = await isDuplicate(name: automation.name, trigger: automation.trigger, action: automation.action, excludingId: automation.id)
            if isDup {
                throw AmoraAutomationError.duplicateAutomation("An automation with the name '\(automation.name)' or identical trigger and action already exists.")
            }
        }

        if let index = items.firstIndex(where: { $0.id == automation.id }) {
            items[index] = automation
        } else {
            items.insert(automation, at: 0)
        }

        self.cachedItems = items
        await persist()
        return automation
    }

    public func update(_ automation: AmoraAutomation) async throws -> AmoraAutomation {
        var items = await ensureLoaded()
        guard let index = items.firstIndex(where: { $0.id == automation.id }) else {
            throw AmoraAutomationError.notFound(automation.id)
        }

        // Prevent renaming into an existing duplicate name
        let isDup = await isDuplicate(name: automation.name, trigger: automation.trigger, action: automation.action, excludingId: automation.id)
        if isDup {
            throw AmoraAutomationError.duplicateAutomation("Another automation with the name '\(automation.name)' or identical trigger and action already exists.")
        }

        items[index] = automation
        self.cachedItems = items
        await persist()
        return automation
    }

    public func delete(id: UUID) async -> Bool {
        var items = await ensureLoaded()
        if let index = items.firstIndex(where: { $0.id == id }) {
            items.remove(at: index)
            self.cachedItems = items
            await persist()
            return true
        }
        return false
    }

    public func clearAll() async {
        self.cachedItems = []
        self.isLoaded = true
        await persist()
    }
}
