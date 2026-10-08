import Foundation

/// Protocol defining asynchronous, thread-safe storage for AMORA automations.
public protocol AmoraAutomationStorage: Sendable {
    func load() async -> [AmoraAutomation]
    func save(_ items: [AmoraAutomation]) async throws
}

/// Local file-based storage for AMORA automations in Application Support.
/// Atomic writes guarantee corruption safety; corrupt data recovers gracefully without crashing.
public actor AmoraFileAutomationStorage: AmoraAutomationStorage {
    public let fileURL: URL
    private let fileManager = FileManager.default

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let amoraDir = appSupport.appendingPathComponent("AMORA", isDirectory: true)
            self.fileURL = amoraDir.appendingPathComponent("automations.json")
        }
    }

    public func load() async -> [AmoraAutomation] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else { return [] }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([AmoraAutomation].self, from: data)
        } catch {
            // Corruption-safe fallback: return empty array rather than failing or crashing
            return []
        }
    }

    public func save(_ items: [AmoraAutomation]) async throws {
        let parentDir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(items)
        try data.write(to: fileURL, options: .atomic)
    }
}

/// Concurrency-safe in-memory automation storage for deterministic unit testing.
public actor AmoraInMemoryAutomationStorage: AmoraAutomationStorage {
    private var items: [AmoraAutomation]

    public init(initialItems: [AmoraAutomation] = []) {
        self.items = initialItems
    }

    public func load() async -> [AmoraAutomation] {
        items
    }

    public func save(_ items: [AmoraAutomation]) async throws {
        self.items = items
    }
}
