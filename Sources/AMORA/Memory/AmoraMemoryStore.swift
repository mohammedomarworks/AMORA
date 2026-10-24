import Foundation

/// Protocol defining operations for storing, retrieving, and searching AMORA long-term memory.
public protocol AmoraMemoryStoring: Sendable {
    @discardableResult
    func save(key: String, value: String) async throws -> AmoraMemoryItem
    @discardableResult
    func update(id: UUID, key: String?, value: String) async throws -> AmoraMemoryItem?
    func get(id: UUID) async -> AmoraMemoryItem?
    func get(key: String) async -> AmoraMemoryItem?
    func list() async -> [AmoraMemoryItem]
    func search(query: String) async -> [AmoraMemoryItem]
    @discardableResult
    func delete(id: UUID) async throws -> Bool
    @discardableResult
    func deleteMatching(query: String) async throws -> [AmoraMemoryItem]
    func clearAll() async throws
    func relevantMemories(for query: String, limit: Int) async -> [AmoraMemoryItem]
    @discardableResult
    func updateMatching(query: String, newValue: String, newKey: String?) async throws -> AmoraMemoryItem?
}

private final class AsyncSerialQueue: @unchecked Sendable {
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let lock = NSLock()

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if !isBusy {
                isBusy = true
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func signal() {
        lock.lock()
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            lock.unlock()
            next.resume()
        } else {
            isBusy = false
            lock.unlock()
        }
    }
}

/// Actor-isolated, thread-safe memory store managing long-term memory lifecycle and persistence.
public actor AmoraMemoryStore: AmoraMemoryStoring {
    public static let shared = AmoraMemoryStore()

    private let storage: any AmoraMemoryStorage
    private let serialQueue = AsyncSerialQueue()
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
        if self.cachedItems == nil {
            self.cachedItems = items
        }
        self.isLoaded = true
        return self.cachedItems ?? items
    }

    /// Saves a memory item. If an item with a matching or conflicting key/subject exists,
    /// updates its value and updatedAt timestamp. Exact duplicates refresh timestamp.
    /// Reverts in-memory cache if storage write fails.
    @discardableResult
    public func save(key: String, value: String) async throws -> AmoraMemoryItem {
        await serialQueue.wait()
        defer { serialQueue.signal() }

        var items = await ensureLoaded()
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousItems = items

        // 1. Exact duplicate (same key and value): touch updatedAt and return
        if let index = items.firstIndex(where: {
            $0.key.caseInsensitiveCompare(trimmedKey) == .orderedSame &&
            $0.value.caseInsensitiveCompare(trimmedValue) == .orderedSame
        }) {
            var existing = items[index]
            existing.updatedAt = Date()
            items[index] = existing
            do {
                try await storage.save(items)
                self.cachedItems = items
                return existing
            } catch {
                self.cachedItems = previousItems
                throw error
            }
        }

        // 2. Conflicting or matching key: update value and touch updatedAt
        if let index = items.firstIndex(where: { isConflictingOrMatching(newKey: trimmedKey, existingKey: $0.key) }) {
            var existing = items[index]
            existing.key = trimmedKey
            existing.value = trimmedValue
            existing.updatedAt = Date()
            items[index] = existing
            do {
                try await storage.save(items)
                self.cachedItems = items
                return existing
            } catch {
                self.cachedItems = previousItems
                throw error
            }
        }

        // 3. New memory item
        let newItem = AmoraMemoryItem(key: trimmedKey, value: trimmedValue)
        items.insert(newItem, at: 0)
        do {
            try await storage.save(items)
            self.cachedItems = items
            return newItem
        } catch {
            self.cachedItems = previousItems
            throw error
        }
    }

    /// Updates a specific memory item by ID.
    @discardableResult
    public func update(id: UUID, key: String? = nil, value: String) async throws -> AmoraMemoryItem? {
        await serialQueue.wait()
        defer { serialQueue.signal() }

        var items = await ensureLoaded()
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let previousItems = items
        var item = items[index]
        if let key {
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty { item.key = trimmedKey }
        }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        item.value = trimmedValue
        item.updatedAt = Date()
        items[index] = item

        do {
            try await storage.save(items)
            self.cachedItems = items
            return item
        } catch {
            self.cachedItems = previousItems
            throw error
        }
    }

    /// Updates a memory matching the user's query/topic with a new value.
    @discardableResult
    public func updateMatching(query: String, newValue: String, newKey: String? = nil) async throws -> AmoraMemoryItem? {
        await serialQueue.wait()
        defer { serialQueue.signal() }

        var items = await ensureLoaded()
        let normalizedQuery = normalizeForMatching(query)
        guard !normalizedQuery.isEmpty else { return nil }

        let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }

        let previousItems = items

        // 1. Exact key match (case-insensitive)
        if let index = items.firstIndex(where: {
            $0.key.caseInsensitiveCompare(query) == .orderedSame || normalizeForMatching($0.key) == normalizedQuery
        }) {
            var item = items[index]
            if let newKey {
                let trimmedKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedKey.isEmpty { item.key = trimmedKey }
            }
            item.value = trimmedValue
            item.updatedAt = Date()
            items[index] = item
            do {
                try await storage.save(items)
                self.cachedItems = items
                return item
            } catch {
                self.cachedItems = previousItems
                throw error
            }
        }

        // 2. Conflicting or matching key match (qualifiers & stems, e.g. "music preference" vs "music")
        if let index = items.firstIndex(where: { isConflictingOrMatching(newKey: query, existingKey: $0.key) }) {
            var item = items[index]
            if let newKey {
                let trimmedKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedKey.isEmpty { item.key = trimmedKey }
            }
            item.value = trimmedValue
            item.updatedAt = Date()
            items[index] = item
            do {
                try await storage.save(items)
                self.cachedItems = items
                return item
            } catch {
                self.cachedItems = previousItems
                throw error
            }
        }

        // 3. Substring match in key or value
        if let index = items.firstIndex(where: {
            let normKey = normalizeForMatching($0.key)
            let normVal = normalizeForMatching($0.value)
            return normKey.contains(normalizedQuery) || normalizedQuery.contains(normKey) || normVal.contains(normalizedQuery)
        }) {
            var item = items[index]
            if let newKey {
                let trimmedKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedKey.isEmpty { item.key = trimmedKey }
            }
            item.value = trimmedValue
            item.updatedAt = Date()
            items[index] = item
            do {
                try await storage.save(items)
                self.cachedItems = items
                return item
            } catch {
                self.cachedItems = previousItems
                throw error
            }
        }

        // 4. Token / stem overlap
        let queryTokens = tokenize(normalizedQuery)
        let queryStems = Set(queryTokens.map(Self.stem))
        var bestIndex: Int? = nil
        var bestScore = 0

        for (idx, item) in items.enumerated() {
            let keyTokens = tokenize(normalizeForMatching(item.key))
            let keyStems = Set(keyTokens.map(Self.stem))
            let valTokens = tokenize(normalizeForMatching(item.value))
            let valStems = Set(valTokens.map(Self.stem))

            var score = 0
            score += queryTokens.intersection(keyTokens).count * 4
            score += queryStems.intersection(keyStems).count * 3
            score += queryTokens.intersection(valTokens).count * 2
            score += queryStems.intersection(valStems).count * 1

            if score > bestScore {
                bestScore = score
                bestIndex = idx
            }
        }

        if let idx = bestIndex, bestScore > 0 {
            var item = items[idx]
            if let newKey {
                let trimmedKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedKey.isEmpty { item.key = trimmedKey }
            }
            item.value = trimmedValue
            item.updatedAt = Date()
            items[idx] = item
            do {
                try await storage.save(items)
                self.cachedItems = items
                return item
            } catch {
                self.cachedItems = previousItems
                throw error
            }
        }

        return nil
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

    /// Searches saved memories matching a query.
    public func search(query: String) async -> [AmoraMemoryItem] {
        await relevantMemories(for: query, limit: 20)
    }

    @discardableResult
    public func delete(id: UUID) async throws -> Bool {
        await serialQueue.wait()
        defer { serialQueue.signal() }

        var items = await ensureLoaded()
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let previousItems = items
        items.remove(at: index)
        do {
            try await storage.save(items)
            self.cachedItems = items
            return true
        } catch {
            self.cachedItems = previousItems
            throw error
        }
    }

    /// Recognized qualifier stems that represent modifier categories rather than specific entity topics.
    public static let qualifierStems: Set<String> = ["prefer", "favorit", "set", "choic", "app"]

    /// Deletes memories matching the user's forget query, preferring uniquely identified targets
    /// and rejecting ambiguous or overly broad queries to prevent collateral deletion.
    @discardableResult
    public func deleteMatching(query: String) async throws -> [AmoraMemoryItem] {
        await serialQueue.wait()
        defer { serialQueue.signal() }

        let items = await ensureLoaded()
        let normalizedQuery = normalizeForMatching(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let queryTokens = tokenize(normalizedQuery)
        let queryStems = Set(queryTokens.map(Self.stem))
        let qualifierStems = Self.qualifierStems

        // 1. Strict exact matches on key or value (Tier 1a)
        let tier1a = items.filter { item in
            let normKey = normalizeForMatching(item.key)
            let normVal = normalizeForMatching(item.value)
            return normKey == normalizedQuery ||
                   normVal == normalizedQuery ||
                   item.key.caseInsensitiveCompare(query) == .orderedSame ||
                   item.value.caseInsensitiveCompare(query) == .orderedSame
        }

        if tier1a.count == 1, let target = tier1a.first {
            return try await executeDeletion(of: [target], from: items)
        } else if tier1a.count > 1 {
            // Ambiguous exact matches: remove nothing
            return []
        }

        // 2. Key equivalence with qualifier stems (Tier 1b)
        // e.g. "favorite music" vs "music"
        let tier1b = items.filter { item in
            isConflictingOrMatching(newKey: query, existingKey: item.key)
        }

        if tier1b.count == 1, let target = tier1b.first {
            return try await executeDeletion(of: [target], from: items)
        } else if tier1b.count > 1 {
            // Ambiguous equivalent matches: remove nothing
            return []
        }

        // 3. Specific phrase or significant token overlap (Tier 2)
        let tier2 = items.filter { item in
            let normKey = normalizeForMatching(item.key)
            let normVal = normalizeForMatching(item.value)
            let keyTokens = tokenize(normKey)
            let valTokens = tokenize(normVal)
            let allItemTokens = keyTokens.union(valTokens)
            let allItemStems = Set(allItemTokens.map(Self.stem))

            // Disallow single generic qualifier word from matching via phrase/stem overlap
            if queryTokens.count == 1, let singleToken = queryTokens.first, qualifierStems.contains(Self.stem(singleToken)) {
                return false
            }

            // Must share at least one meaningful (non-qualifier) stem
            let meaningfulOverlap = queryStems.intersection(allItemStems).subtracting(qualifierStems)
            guard !meaningfulOverlap.isEmpty else { return false }

            let phraseMatch = (!normKey.isEmpty && (normKey.contains(normalizedQuery) || normalizedQuery.contains(normKey))) ||
                              (!normVal.isEmpty && (normVal.contains(normalizedQuery) || normalizedQuery.contains(normVal)))

            let tokenMatch = queryTokens.isSubset(of: allItemTokens) ||
                             keyTokens.isSubset(of: queryTokens) ||
                             queryStems.isSubset(of: allItemStems) ||
                             allItemStems.isSubset(of: queryStems)

            return phraseMatch || tokenMatch
        }

        if tier2.count == 1, let target = tier2.first {
            return try await executeDeletion(of: [target], from: items)
        } else {
            // Ambiguous (> 1) or no match (0): remove nothing
            return []
        }
    }

    private func executeDeletion(of targetItems: [AmoraMemoryItem], from currentItems: [AmoraMemoryItem]) async throws -> [AmoraMemoryItem] {
        guard !targetItems.isEmpty else { return [] }
        let targetIDs = Set(targetItems.map(\.id))
        var updatedItems = currentItems
        updatedItems.removeAll { targetIDs.contains($0.id) }
        let previousItems = self.cachedItems ?? currentItems
        do {
            try await storage.save(updatedItems)
            self.cachedItems = updatedItems
            return targetItems
        } catch {
            self.cachedItems = previousItems
            throw error
        }
    }

    public func clearAll() async throws {
        await serialQueue.wait()
        defer { serialQueue.signal() }

        _ = await ensureLoaded()
        let previousItems = cachedItems
        do {
            try await storage.save([])
            self.cachedItems = []
        } catch {
            self.cachedItems = previousItems
            throw error
        }
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
        let queryStems = Set(queryTokens.map(Self.stem))

        var scoredItems: [(item: AmoraMemoryItem, score: Int)] = []

        for item in items {
            let normKey = normalizeForMatching(item.key)
            let normVal = normalizeForMatching(item.value)

            var score = 0

            // Exact phrase match in key
            if normKey == normalizedQuery {
                score += 25
            } else if normKey.contains(normalizedQuery) || normalizedQuery.contains(normKey) {
                score += 12
            }

            // Exact phrase match in value
            if normVal.contains(normalizedQuery) {
                score += 10
            }

            let keyTokens = tokenize(normKey)
            let valTokens = tokenize(normVal)
            let keyStems = Set(keyTokens.map(Self.stem))
            let valStems = Set(valTokens.map(Self.stem))

            // Token overlap
            score += queryTokens.intersection(keyTokens).count * 6
            score += queryTokens.intersection(valTokens).count * 3

            // Stem overlap
            score += queryStems.intersection(keyStems).count * 4
            score += queryStems.intersection(valStems).count * 2

            // Semantic associations
            if queryStems.contains("music") || queryStems.contains("song") || queryStems.contains("track") {
                if normKey.contains("spotify") || normVal.contains("spotify") ||
                   normKey.contains("youtube") || normVal.contains("youtube") ||
                   normKey.contains("apple music") || normVal.contains("apple music") {
                    score += 6
                }
            }
            if queryStems.contains("prefer") {
                if normKey.contains("prefer") || normVal.contains("prefer") {
                    score += 8
                }
            }
            if queryStems.contains("program") || queryStems.contains("code") || queryStems.contains("project") {
                if normKey.contains("project") || normVal.contains("project") ||
                   normKey.contains("amora") || normVal.contains("amora") ||
                   normKey.contains("code") || normVal.contains("code") ||
                   normKey.contains("editor") || normVal.contains("editor") {
                    score += 6
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

    private func isConflictingOrMatching(newKey: String, existingKey: String) -> Bool {
        if newKey.caseInsensitiveCompare(existingKey) == .orderedSame {
            return true
        }
        let normNew = normalizeForMatching(newKey)
        let normExist = normalizeForMatching(existingKey)
        if normNew == normExist { return true }

        let newTokens = tokenize(normNew)
        let existTokens = tokenize(normExist)

        if !newTokens.isEmpty && !existTokens.isEmpty {
            let newStems = Set(newTokens.map(Self.stem))
            let existStems = Set(existTokens.map(Self.stem))
            if newStems == existStems {
                return true
            }

            // Check if one is just the other plus a qualifier word (preference, favorite, setting, app)
            let qualifierStems = Self.qualifierStems
            let diff1 = newStems.subtracting(existStems)
            let diff2 = existStems.subtracting(newStems)
            if (diff1.isEmpty && diff2.isSubset(of: qualifierStems)) ||
               (diff2.isEmpty && diff1.isSubset(of: qualifierStems)) {
                return true
            }
        }
        return false
    }

    public static func stem(_ word: String) -> String {
        let w = word.lowercased()
        if w.hasPrefix("prefer") { return "prefer" }
        if w.hasPrefix("programm") || w.hasPrefix("program") { return "program" }
        if w.hasPrefix("cod") { return "code" }
        if w.hasPrefix("favorit") { return "favorit" }
        if w.hasPrefix("sett") { return "set" }
        if w.hasPrefix("mus") { return "music" }
        if w.hasPrefix("work") { return "work" }
        if w.hasPrefix("project") { return "project" }
        if w.hasPrefix("edit") { return "editor" }
        if w.hasSuffix("ing") && w.count > 5 { return String(w.dropLast(3)) }
        if w.hasSuffix("ies") && w.count > 4 { return String(w.dropLast(3)) + "y" }
        if w.hasSuffix("es") && w.count > 4 { return String(w.dropLast(2)) }
        if w.hasSuffix("ed") && w.count > 4 { return String(w.dropLast(2)) }
        if w.hasSuffix("s") && w.count > 3 && !w.hasSuffix("ss") { return String(w.dropLast(1)) }
        return w
    }

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
        return Set(tokens.filter { !stopWords.contains($0) && !$0.isEmpty })
    }
}
