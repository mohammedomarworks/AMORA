import Foundation
import Observation

/// MainActor observable service providing UI state and binding for AMORA Memory settings and management.
@Observable @MainActor
public final class AmoraMemoryService {
    public static let shared = AmoraMemoryService()

    public let store: any AmoraMemoryStoring
    public private(set) var memories: [AmoraMemoryItem] = []

    public init(store: (any AmoraMemoryStoring)? = nil) {
        self.store = store ?? AmoraMemoryStore.shared
    }

    public func refresh() async {
        self.memories = await store.list()
    }

    public func update(id: UUID, key: String, value: String) async throws -> AmoraMemoryItem? {
        let updated = try await store.update(id: id, key: key, value: value)
        await refresh()
        return updated
    }

    public func search(query: String) async -> [AmoraMemoryItem] {
        await store.search(query: query)
    }

    public func delete(id: UUID) async {
        _ = try? await store.delete(id: id)
        await refresh()
    }

    public func clearAll() async {
        try? await store.clearAll()
        await refresh()
    }
}
