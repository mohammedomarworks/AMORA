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
    public private(set) var hasUnquarantinedCorruptOriginal: Bool = false
    public private(set) var hasQuarantinedCurrentCorruptFile: Bool = false
    public private(set) var lastQuarantineError: Error? = nil
    public private(set) var simulateQuarantineFailure: Bool = false

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let amoraDir = appSupport.appendingPathComponent("AMORA", isDirectory: true)
            self.fileURL = amoraDir.appendingPathComponent("memories.json")
        }
    }

    public func setSimulateQuarantineFailure(_ value: Bool) {
        self.simulateQuarantineFailure = value
    }

    /// Generates a collision-resistant quarantine file URL.
    public func generateQuarantineURL(timestamp: Int? = nil, uniqueSuffix: String? = nil) -> URL {
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let quarantineDir = fileURL.deletingLastPathComponent()
        let ts = timestamp ?? Int(Date().timeIntervalSince1970)
        let suffix = uniqueSuffix ?? UUID().uuidString.prefix(8).lowercased()
        var candidate = quarantineDir.appendingPathComponent("\(baseName).corrupt-\(ts)-\(suffix).json")
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = quarantineDir.appendingPathComponent("\(baseName).corrupt-\(ts)-\(suffix)-\(counter).json")
            counter += 1
        }
        return candidate
    }

    @discardableResult
    private func performQuarantine() -> Bool {
        guard fileManager.fileExists(atPath: fileURL.path) else { return true }
        if simulateQuarantineFailure {
            lastQuarantineError = NSError(
                domain: "AmoraMemoryStorage",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Simulated quarantine backup failure."]
            )
            return false
        }
        let quarantineDir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: quarantineDir.path) {
            try? fileManager.createDirectory(at: quarantineDir, withIntermediateDirectories: true)
        }
        let quarantineURL = generateQuarantineURL()
        do {
            try fileManager.copyItem(at: fileURL, to: quarantineURL)
            lastQuarantineError = nil
            return true
        } catch {
            lastQuarantineError = error
            return false
        }
    }

    public func load() async -> [AmoraMemoryItem] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            hasUnquarantinedCorruptOriginal = false
            hasQuarantinedCurrentCorruptFile = false
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else {
                hasUnquarantinedCorruptOriginal = false
                hasQuarantinedCurrentCorruptFile = false
                return []
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let items = try decoder.decode([AmoraMemoryItem].self, from: data)
            hasUnquarantinedCorruptOriginal = false
            hasQuarantinedCurrentCorruptFile = false
            return items
        } catch {
            // Corrupt storage recovery:
            // Quarantine corrupt file so user data is not silently destroyed on subsequent saves.
            if !hasQuarantinedCurrentCorruptFile {
                let quarantined = performQuarantine()
                if quarantined {
                    hasQuarantinedCurrentCorruptFile = true
                    hasUnquarantinedCorruptOriginal = false
                } else {
                    hasUnquarantinedCorruptOriginal = true
                }
            }
            return []
        }
    }

    /// Returns any quarantined backup files created during corrupt storage recovery.
    public static func quarantinedFiles(for fileURL: URL) -> [URL] {
        let dir = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.lastPathComponent.hasPrefix(baseName) && $0.lastPathComponent.contains(".corrupt") }
    }

    public func save(_ items: [AmoraMemoryItem]) async throws {
        if hasUnquarantinedCorruptOriginal {
            // Attempt to quarantine the corrupt original before proceeding
            let quarantined = performQuarantine()
            if quarantined {
                hasQuarantinedCurrentCorruptFile = true
                hasUnquarantinedCorruptOriginal = false
            } else {
                throw AmoraMemoryError.storageFailed(
                    "Cannot safely overwrite corrupt memories file because backup quarantine failed: \(lastQuarantineError?.localizedDescription ?? "backup failed")"
                )
            }
        }

        let parentDir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(items)
        try data.write(to: fileURL, options: .atomic)
        hasUnquarantinedCorruptOriginal = false
        hasQuarantinedCurrentCorruptFile = false
    }
}

/// Errors occurring during AMORA memory operations.
public enum AmoraMemoryError: Error, LocalizedError, Equatable, Sendable {
    case storageFailed(String)
    case sensitiveDataRejected(String)
    case memoryDisabled
    case notFound

    public var errorDescription: String? {
        switch self {
        case .storageFailed(let msg): return "Storage failed: \(msg)"
        case .sensitiveDataRejected(let reason): return reason
        case .memoryDisabled: return "Memory is turned off in Settings."
        case .notFound: return "Memory not found."
        }
    }
}

/// Concurrency-safe in-memory storage for deterministic unit testing.
public actor AmoraInMemoryStorage: AmoraMemoryStorage {
    private var items: [AmoraMemoryItem]
    public var shouldFailSave: Bool = false

    public init(initialItems: [AmoraMemoryItem] = [], shouldFailSave: Bool = false) {
        self.items = initialItems
        self.shouldFailSave = shouldFailSave
    }

    public func setShouldFailSave(_ fail: Bool) {
        self.shouldFailSave = fail
    }

    public func load() async -> [AmoraMemoryItem] {
        return items
    }

    public func save(_ items: [AmoraMemoryItem]) async throws {
        if shouldFailSave {
            throw AmoraMemoryError.storageFailed("Simulated storage write failure.")
        }
        self.items = items
    }
}
