import Foundation

/// A typed, privacy-first long-term memory item stored locally for AMORA.
/// Only contains explicit user-requested facts.
public struct AmoraMemoryItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var key: String
    public var value: String
    public let createdAt: Date
    public var updatedAt: Date

    /// Category alias for key to satisfy both key and category semantics.
    public var category: String {
        get { key }
        set { key = newValue }
    }

    public init(
        id: UUID = UUID(),
        key: String,
        value: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case key
        case category
        case value
        case createdAt
        case updatedAt
        case created_at
        case updated_at
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let decodedKey = try container.decodeIfPresent(String.self, forKey: .key)
            ?? container.decodeIfPresent(String.self, forKey: .category)
            ?? ""
        self.key = decodedKey
        self.value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? container.decodeIfPresent(Date.self, forKey: .created_at)
            ?? Date()
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? container.decodeIfPresent(Date.self, forKey: .updated_at)
            ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(key, forKey: .key)
        try container.encode(value, forKey: .value)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
