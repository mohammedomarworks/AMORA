import Foundation

/// Protocol defining operations for storing, retrieving, and searching AMORA long-term memory.
public protocol AmoraMemoryStoring: Sendable {
    func save(key: String, value: String) async -> AmoraMemoryItem
    func get(id: UUID) async -> AmoraMemoryItem?
    func get(key: String) async -> AmoraMemoryItem?
    func list() async -> [AmoraMemoryItem]
    func delete(id: UUID) async -> Bool
    func deleteMatching(query: String) async -> [AmoraMemoryItem]
    func clearAll() async
    func relevantMemories(for query: String, limit: Int) async -> [AmoraMemoryItem]
}

/// Actor-isolated, thread-safe memory store managing long-term memory lifecycle and persistence.
public actor AmoraMemoryStore: AmoraMemoryStoring {
    private let storage: any AmoraMemoryStorage
    private var cachedItems: [AmoraMemoryItem]?
    private var isLoaded: Bool = false

    public init(storage: (any AmoraMemoryStorage)? = nil) {
        self.storage = storage ?? AmoraFileMemoryStorage()
    }

    private func ensureLoaded() async -> [AmoraMemoryItem] {
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

    /// Saves a memory item. If an item with a matching key exists (case-insensitive),
    /// updates its value and updatedAt timestamp. Otherwise, creates a new item.
    public func save(key: String, value: String) async -> AmoraMemoryItem {
        var items = await ensureLoaded()
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let index = items.firstIndex(where: { $0.key.caseInsensitiveCompare(trimmedKey) == .orderedSame }) {
            var existing = items[index]
            existing.value = trimmedValue
            existing.updatedAt = Date()
            items[index] = existing
            self.cachedItems = items
            await persist()
            return existing
        } else {
            let newItem = AmoraMemoryItem(key: trimmedKey, value: trimmedValue)
            items.insert(newItem, at: 0)
            self.cachedItems = items
            await persist()
            return newItem
        }
    }

    public func get(id: UUID) async -> AmoraMemoryItem? {
        let items = await ensureLoaded()
        return items.first { $0.id == id }
    }

    public func get(key: String) async -> AmoraMemoryItem? {
        let items = await ensureLoaded()
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.first { $0.key.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    public func list() async -> [AmoraMemoryItem] {
        await ensureLoaded()
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

    /// Deletes memories matching the user's forget query (by key or value similarity/overlap).
    public func deleteMatching(query: String) async -> [AmoraMemoryItem] {
        var items = await ensureLoaded()
        let normalizedQuery = normalizeForMatching(query)
        guard !normalizedQuery.isEmpty else { return [] }

        var matchedIDs: Set<UUID> = []
        var deletedItems: [AmoraMemoryItem] = []

        for item in items {
            let normKey = normalizeForMatching(item.key)
            let normVal = normalizeForMatching(item.value)

            // Direct substring matches
            if normKey.contains(normalizedQuery) || normalizedQuery.contains(normKey) ||
               normVal.contains(normalizedQuery) || normalizedQuery.contains(normVal) {
                matchedIDs.insert(item.id)
                deletedItems.append(item)
                continue
            }

            // Word overlap check
            let queryTokens = tokenize(normalizedQuery)
            let keyTokens = tokenize(normKey)
            let valTokens = tokenize(normVal)

            let keyOverlap = queryTokens.intersection(keyTokens)
            let valOverlap = queryTokens.intersection(valTokens)

            if !keyOverlap.isEmpty || !valOverlap.isEmpty {
                matchedIDs.insert(item.id)
                deletedItems.append(item)
            }
        }

        if !matchedIDs.isEmpty {
            items.removeAll { matchedIDs.contains($0.id) }
            self.cachedItems = items
            await persist()
        }

        return deletedItems
    }

    public func clearAll() async {
        _ = await ensureLoaded()
        self.cachedItems = []
        await persist()
    }

    /// Retrieves relevant memories for an input query without injecting the whole store.
    /// Returns up to `limit` items scoring above 0, sorted by relevance score.
    public func relevantMemories(for query: String, limit: Int = 3) async -> [AmoraMemoryItem] {
        let items = await ensureLoaded()
        guard !items.isEmpty else { return [] }

        let normalizedQuery = normalizeForMatching(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let queryTokens = tokenize(normalizedQuery)
        guard !queryTokens.isEmpty else { return [] }

        var scoredItems: [(item: AmoraMemoryItem, score: Int)] = []

        for item in items {
            let normKey = normalizeForMatching(item.key)
            let normVal = normalizeForMatching(item.value)

            var score = 0

            // Exact phrase match in key
            if normKey == normalizedQuery {
                score += 20
            } else if normKey.contains(normalizedQuery) || normalizedQuery.contains(normKey) {
                score += 10
            }

            // Exact phrase match in value
            if normVal.contains(normalizedQuery) {
                score += 8
            }

            let keyTokens = tokenize(normKey)
            let valTokens = tokenize(normVal)

            // Token overlap with key
            let keyOverlap = queryTokens.intersection(keyTokens)
            score += keyOverlap.count * 4

            // Token overlap with value
            let valOverlap = queryTokens.intersection(valTokens)
            score += valOverlap.count * 2

            // Semantic associations
            if queryTokens.contains("music") || queryTokens.contains("song") || queryTokens.contains("track") {
                if normKey.contains("spotify") || normVal.contains("spotify") || normKey.contains("apple music") || normVal.contains("apple music") {
                    score += 5
                }
            }
            if queryTokens.contains("editor") || queryTokens.contains("code") || queryTokens.contains("coding") {
                if normKey.contains("vscode") || normKey.contains("vs code") || normVal.contains("vs code") || normVal.contains("cursor") {
                    score += 5
                }
            }

            if score > 0 {
                scoredItems.append((item, score))
            }
        }

        // Sort by score descending, then by updatedAt descending
        scoredItems.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.item.updatedAt > rhs.item.updatedAt
        }

        return Array(scoredItems.prefix(limit).map(\.item))
    }

    // MARK: - Helpers

    private func normalizeForMatching(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func tokenize(_ text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "a", "an", "the", "in", "on", "at", "to", "for", "of", "with", "is", "are", "was", "were",
            "be", "been", "have", "has", "had", "do", "does", "did", "can", "could", "would", "should",
            "will", "i", "you", "he", "she", "it", "we", "they", "me", "my", "your", "what", "which",
            "who", "whom", "this", "that", "there", "here", "about", "like"
        ]
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return Set(tokens.filter { !stopWords.contains($0) && $0.count > 1 })
    }
}
