import Foundation
import Observation

/// MainActor observable service providing UI state and binding for AMORA Memory settings and management.
@Observable @MainActor
public final class AmoraMemoryService {
    public static let shared = AmoraMemoryService()

    public let store: any AmoraMemoryStoring
    public private(set) var memories: [AmoraMemoryItem] = []

    public init(store: (any AmoraMemoryStoring)? = nil) {
        self.store = store ?? AmoraMemoryStore()
    }

    public func refresh() async {
        self.memories = await store.list()
    }

    public func delete(id: UUID) async {
        _ = await store.delete(id: id)
        await refresh()
    }

    public func clearAll() async {
        await store.clearAll()
        await refresh()
    }
}
