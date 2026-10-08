import Foundation

/// Protocol-driven storage backend for local memory persistence.
public protocol AmoraMemoryStorage: Sendable {
    func load() async -> [AmoraMemoryItem]
    func save(_ items: [AmoraMemoryItem]) async throws
}

/// Local file-based storage for AMORA memory in Application Support.
/// Handles missing directories, non-existent files, and corrupt data gracefully without crashing.
public actor AmoraFileMemoryStorage: AmoraMemoryStorage {
    public let fileURL: URL
    private let fileManager = FileManager.default

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let amoraDir = appSupport.appendingPathComponent("AMORA", isDirectory: true)
            self.fileURL = amoraDir.appendingPathComponent("memories.json")
        }
    }

    public func load() async -> [AmoraMemoryItem] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else { return [] }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([AmoraMemoryItem].self, from: data)
        } catch {
            // Corrupt storage recovery:
            // Safely recover by returning empty array rather than failing or crashing.
            return []
        }
    }

    public func save(_ items: [AmoraMemoryItem]) async throws {
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

/// Concurrency-safe in-memory storage for deterministic unit testing.
public actor AmoraInMemoryStorage: AmoraMemoryStorage {
    private var items: [AmoraMemoryItem]

    public init(initialItems: [AmoraMemoryItem] = []) {
        self.items = initialItems
    }

    public func load() async -> [AmoraMemoryItem] {
        return items
    }

    public func save(_ items: [AmoraMemoryItem]) async throws {
        self.items = items
    }
}
