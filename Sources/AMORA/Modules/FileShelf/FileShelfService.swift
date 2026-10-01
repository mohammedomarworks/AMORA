import Foundation
import Observation

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
    }
}

@Observable @MainActor
final class FileShelfService {
    static let shared = FileShelfService()

    var items: [ShelfItem] = []

    private init() {}

    func addFile(url: URL) {
        if !items.contains(where: { $0.url == url }) {
            items.insert(ShelfItem(url: url), at: 0)
        }
    }

    func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
    }

    func clearShelf() {
        items.removeAll()
    }
}
