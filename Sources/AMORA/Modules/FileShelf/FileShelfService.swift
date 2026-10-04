import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

public struct ShelfItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let bookmarkData: Data?
    public var isMissing: Bool
    public let dateAdded: Date

    public init(id: UUID = UUID(), url: URL, bookmarkData: Data? = nil, isMissing: Bool = false, dateAdded: Date = Date()) {
        self.id = id
        self.url = url
        self.name = url.lastPathComponent
        self.bookmarkData = bookmarkData ?? Self.createBookmarkData(for: url)
        self.isMissing = isMissing || !FileManager.default.fileExists(atPath: url.path)
        self.dateAdded = dateAdded
    }

    public static func createBookmarkData(for url: URL) -> Data? {
        // Attempt security-scoped bookmark first (valid in sandboxed environments)
        if let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            return data
        }
        // Fallback to standard bookmark (valid in non-sandboxed environments)
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public static func resolveURL(from bookmarkData: Data?, fallbackPath: String) -> (url: URL, isSecurityScoped: Bool) {
        if let bookmarkData {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                return (resolved, true)
            }
            if let resolved = try? URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                return (resolved, false)
            }
        }
        return (URL(fileURLWithPath: fallbackPath), false)
    }
}

struct PersistedShelfItem: Codable {
    let id: UUID
    let path: String
    let name: String
    let bookmarkData: Data?
    let dateAdded: Date
}

@Observable @MainActor
public final class FileShelfService {
    public static let shared = FileShelfService()

    public var items: [ShelfItem] = []
    public var lastErrorMessage: String? = nil

    private let fileManager = FileManager.default
    private let storageURL: URL

    public init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("AMORA", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.storageURL = dir.appendingPathComponent("file_shelf.json")
        }
        loadItems()
    }

    public func addFile(url: URL) {
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        print("[FILESHELF] addFile called")
        let countBefore = items.count
        print("[FILESHELF] items count before = \(countBefore)")

        // Deduplicate: remove if already exists, then re-insert at top
        items.removeAll { $0.url.path == standardized.path }

        let item = ShelfItem(url: standardized)
        items.insert(item, at: 0)
        let countAfter = items.count
        print("[FILESHELF] items count after = \(countAfter)")

        print("[FILESHELF] saveItems called")
        print("[FILESHELF] actual storage path = \(storageURL.path)")
        let writeSucceeded = saveItems()
        print("[FILESHELF] saveItems result = \(writeSucceeded)")
        AMORAEventCenter.shared.emit(.fileReceived)
    }

    public func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
        saveItems()
    }

    public func clearShelf() {
        items.removeAll()
        saveItems()
    }

    @discardableResult
    public func openFile(_ item: ShelfItem) -> Bool {
        guard fileManager.fileExists(atPath: item.url.path) else {
            markItemMissing(id: item.id)
            lastErrorMessage = "File not found: \(item.name)"
            return false
        }
        let scoped = item.url.startAccessingSecurityScopedResource()
        defer { if scoped { item.url.stopAccessingSecurityScopedResource() } }

        let opened = NSWorkspace.shared.open(item.url)
        if !opened {
            lastErrorMessage = "Could not open \(item.name)"
        }
        return opened
    }

    @discardableResult
    public func revealFile(_ item: ShelfItem) -> Bool {
        guard fileManager.fileExists(atPath: item.url.path) else {
            markItemMissing(id: item.id)
            lastErrorMessage = "File not found: \(item.name)"
            return false
        }
        let scoped = item.url.startAccessingSecurityScopedResource()
        defer { if scoped { item.url.stopAccessingSecurityScopedResource() } }

        NSWorkspace.shared.activateFileViewerSelecting([item.url])
        return true
    }

    public func markItemMissing(id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isMissing = true
            saveItems()
        }
    }

    public func removeMissingItems() {
        items.removeAll { !fileManager.fileExists(atPath: $0.url.path) }
        saveItems()
    }

    public func refreshItemStates() {
        var changed = false
        for i in items.indices {
            let exists = fileManager.fileExists(atPath: items[i].url.path)
            if items[i].isMissing == exists {
                items[i].isMissing = !exists
                changed = true
            }
        }
        if changed {
            saveItems()
        }
    }

    @discardableResult
    public func handleDrop(providers: [NSItemProvider], onFileAdded: (@MainActor (URL) -> Void)? = nil) -> Bool {
        print("[FILESHELF] handleDrop started")
        var accepted = false

        for provider in providers {
            accepted = true
            Task { @MainActor in
                print("[FILESHELF] extraction started")
                if let extractedURL = await self.extractURL(from: provider), extractedURL.isFileURL {
                    print("[FILESHELF] extraction result = success")
                    print("[FILESHELF] extracted URL = \(extractedURL.path)")
                    self.addFile(url: extractedURL)
                    onFileAdded?(extractedURL)
                } else {
                    print("[FILESHELF] extraction result = failed")
                    // Fallback to active drag pasteboard
                    if let pasteboardURLs = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
                        for url in pasteboardURLs where url.isFileURL {
                            print("[FILESHELF] extracted URL = \(url.path)")
                            self.addFile(url: url)
                            onFileAdded?(url)
                            return
                        }
                    }
                }
            }
        }
        return accepted || !providers.isEmpty
    }

    private func extractURL(from provider: NSItemProvider) async -> URL? {
        // Priority 1: loadItem for UTType.fileURL
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let itemURL: URL? = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    continuation.resume(returning: Self.extractFileURL(from: item))
                }
            }
            if let itemURL, itemURL.isFileURL { return itemURL }

            // Priority 1b: loadDataRepresentation for UTType.fileURL
            let dataURL: URL? = await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    continuation.resume(returning: data.flatMap { Self.extractFileURL(from: $0) })
                }
            }
            if let dataURL, dataURL.isFileURL { return dataURL }
        }

        // Priority 2: Generic URL item
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            let urlItem: URL? = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    continuation.resume(returning: Self.extractFileURL(from: item))
                }
            }
            if let urlItem, urlItem.isFileURL { return urlItem }
        }

        // Priority 3: Object loading (URL.self)
        if provider.canLoadObject(ofClass: URL.self) {
            let objectURL: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: (url?.isFileURL == true) ? url : nil)
                }
            }
            if let objectURL, objectURL.isFileURL { return objectURL }
        }

        // Priority 4: Search all registered identifiers directly via loadItem (covers com.adobe.pdf, public.mpeg-4, etc.)
        for identifier in provider.registeredTypeIdentifiers {
            let directItemURL: URL? = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                    continuation.resume(returning: Self.extractFileURL(from: item))
                }
            }
            if let directItemURL, directItemURL.isFileURL { return directItemURL }
        }

        // Priority 5: Load file representation / in-place file representation
        for identifier in provider.registeredTypeIdentifiers {
            let repURL: URL? = await withCheckedContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
                    continuation.resume(returning: url)
                }
            }
            if let repURL, repURL.isFileURL { return repURL }
        }

        return nil
    }

    public nonisolated static func extractFileURL(from item: Any?) -> URL? {
        if let url = item as? URL {
            return url.isFileURL ? url : nil
        }
        if let nsURL = item as? NSURL {
            let url = nsURL as URL
            return url.isFileURL ? url : nil
        }
        if let data = item as? Data {
            if let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
                return url
            }
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale), url.isFileURL {
                return url
            }
            if let string = String(data: data, encoding: .utf8), let url = parseFileURL(from: string) {
                return url
            }
            if let string = String(data: data, encoding: .utf16), let url = parseFileURL(from: string) {
                return url
            }
        }
        if let string = item as? String, let url = parseFileURL(from: string) {
            return url
        }
        if let array = item as? [Any] {
            for element in array {
                if let url = extractFileURL(from: element) {
                    return url
                }
            }
        }
        return nil
    }

    public nonisolated static func parseFileURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("file://") {
            if let url = URL(string: trimmed), url.isFileURL {
                return url
            }
            let stripped = String(trimmed.dropFirst(7))
            let pathPart: String
            if stripped.hasPrefix("localhost/") {
                pathPart = String(stripped.dropFirst(9))
            } else {
                pathPart = stripped
            }
            let decoded = pathPart.removingPercentEncoding ?? pathPart
            let url = URL(fileURLWithPath: decoded)
            return url.isFileURL ? url : nil
        }

        if trimmed.hasPrefix("/") {
            let url = URL(fileURLWithPath: trimmed)
            return url.isFileURL ? url : nil
        }

        if trimmed.hasPrefix("~") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            if expanded.hasPrefix("/") {
                let url = URL(fileURLWithPath: expanded)
                return url.isFileURL ? url : nil
            }
        }

        return nil
    }

    public nonisolated func extractFileURL(from item: Any?) -> URL? {
        Self.extractFileURL(from: item)
    }

    @discardableResult
    private func saveItems() -> Bool {
        let persisted = items.map { item in
            PersistedShelfItem(
                id: item.id,
                path: item.url.path,
                name: item.name,
                bookmarkData: item.bookmarkData,
                dateAdded: item.dateAdded
            )
        }
        do {
            let data = try JSONEncoder().encode(persisted)
            try data.write(to: storageURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func loadItems() {
        guard fileManager.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let loaded = try? JSONDecoder().decode([PersistedShelfItem].self, from: data) else {
            return
        }

        self.items = loaded.map { persisted in
            let (resolvedURL, _) = ShelfItem.resolveURL(from: persisted.bookmarkData, fallbackPath: persisted.path)
            let exists = fileManager.fileExists(atPath: resolvedURL.path)
            return ShelfItem(
                id: persisted.id,
                url: resolvedURL,
                bookmarkData: persisted.bookmarkData,
                isMissing: !exists,
                dateAdded: persisted.dateAdded
            )
        }
    }
}
