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
    public var fileSize: Int64?
    public var isDirectory: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        bookmarkData: Data? = nil,
        isMissing: Bool = false,
        dateAdded: Date = Date(),
        fileSize: Int64? = nil,
        isDirectory: Bool? = nil
    ) {
        self.id = id
        self.url = url
        self.name = url.lastPathComponent
        self.bookmarkData = bookmarkData ?? Self.createBookmarkData(for: url)
        self.dateAdded = dateAdded
        let exists = FileManager.default.fileExists(atPath: url.path)
        self.isMissing = isMissing || !exists

        if exists {
            let meta = Self.fetchMetadata(for: url)
            self.fileSize = fileSize ?? meta.size
            self.isDirectory = isDirectory ?? meta.isDir
        } else {
            self.fileSize = fileSize
            self.isDirectory = isDirectory ?? false
        }
    }

    public static func fetchMetadata(for url: URL) -> (size: Int64?, isDir: Bool) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        let size = values?.fileSize.map { Int64($0) }
        let isDir = values?.isDirectory ?? false
        return (size, isDir)
    }

    public static func createBookmarkData(for url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // Attempt security-scoped bookmark first (valid in sandboxed environments)
        if let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            return data
        }
        // Fallback to standard bookmark (valid in non-sandboxed environments)
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public static func resolveURLWithStale(from bookmarkData: Data?, fallbackPath: String) -> (url: URL, isSecurityScoped: Bool, isStale: Bool) {
        if let bookmarkData {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                return (resolved, true, isStale)
            }
            if let resolved = try? URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                return (resolved, false, isStale)
            }
        }
        return (URL(fileURLWithPath: fallbackPath), false, false)
    }

    public static func resolveURL(from bookmarkData: Data?, fallbackPath: String) -> (url: URL, isSecurityScoped: Bool) {
        let (url, isSecurityScoped, _) = resolveURLWithStale(from: bookmarkData, fallbackPath: fallbackPath)
        return (url, isSecurityScoped)
    }

    public var systemIconName: String {
        if isMissing {
            return "exclamationmark.triangle.fill"
        }
        if isDirectory {
            return "folder.fill"
        }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return "doc.text.fill"
        case "txt", "md", "markdown", "rtf", "log":
            return "doc.plaintext.fill"
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "svg":
            return "photo.fill"
        case "mp4", "mov", "m4v", "avi", "mkv", "webm":
            return "film.fill"
        case "mp3", "m4a", "wav", "aac", "flac", "aiff":
            return "music.note"
        case "zip", "tar", "gz", "tgz", "bz2", "7z", "rar":
            return "doc.zipper"
        case "swift", "py", "js", "ts", "json", "html", "css", "c", "cpp", "h", "rs", "go", "sh", "rb":
            return "curlybraces"
        case "csv", "xlsx", "xls", "numbers":
            return "tablecells.fill"
        case "key", "pptx", "ppt":
            return "presentation"
        case "doc", "docx", "pages":
            return "doc.richtext.fill"
        default:
            return "doc.fill"
        }
    }

    public var contentTypeDescription: String {
        if isMissing { return "Missing file" }
        if isDirectory { return "Folder" }
        if let utType = UTType(filenameExtension: url.pathExtension), let desc = utType.localizedDescription {
            return desc
        }
        let ext = url.pathExtension.uppercased()
        return ext.isEmpty ? "File" : "\(ext) file"
    }

    public var fileSizeDescription: String? {
        if isMissing { return "Unavailable" }
        if isDirectory { return "Folder" }
        guard let size = fileSize, size >= 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public var metadataDescription: String {
        if isMissing { return "Missing file" }
        var parts: [String] = []
        if let sizeStr = fileSizeDescription {
            parts.append(sizeStr)
        } else {
            parts.append(contentTypeDescription)
        }
        return parts.joined(separator: " • ")
    }

    public var formattedDateAdded: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: dateAdded)
    }
}

struct PersistedShelfItem: Codable {
    let id: UUID
    let path: String
    let name: String
    let bookmarkData: Data?
    let dateAdded: Date
    let fileSize: Int64?
    let isDirectory: Bool?

    init(id: UUID, path: String, name: String, bookmarkData: Data?, dateAdded: Date, fileSize: Int64? = nil, isDirectory: Bool? = nil) {
        self.id = id
        self.path = path
        self.name = name
        self.bookmarkData = bookmarkData
        self.dateAdded = dateAdded
        self.fileSize = fileSize
        self.isDirectory = isDirectory
    }

    enum CodingKeys: String, CodingKey {
        case id, path, name, bookmarkData, dateAdded, fileSize, isDirectory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        name = try container.decode(String.self, forKey: .name)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        isDirectory = try container.decodeIfPresent(Bool.self, forKey: .isDirectory)
    }
}

@Observable @MainActor
public final class FileShelfService {
    public static let shared = FileShelfService()

    public var items: [ShelfItem] = []
    public var lastErrorMessage: String? = nil
    public var isProcessingDrop: Bool = false
    public var eventSink: any AmoraEventSinking = MacOSAmoraEventSink()
    public var fileOpener: any AmoraFileOpening = NativeAmoraFileOpener()

    private let fileManager = FileManager.default
    private let storageURL: URL

    public init(storageURL: URL? = nil, fileOpener: any AmoraFileOpening = NativeAmoraFileOpener()) {
        self.fileOpener = fileOpener
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

    public struct DropResult: Equatable, Sendable {
        public let totalRequested: Int
        public let newlyAdded: [ShelfItem]
        public let existingReordered: [ShelfItem]
        public let failedCount: Int

        public init(totalRequested: Int, newlyAdded: [ShelfItem], existingReordered: [ShelfItem], failedCount: Int) {
            self.totalRequested = totalRequested
            self.newlyAdded = newlyAdded
            self.existingReordered = existingReordered
            self.failedCount = failedCount
        }

        public var isFullSuccess: Bool {
            failedCount == 0 && (!newlyAdded.isEmpty || !existingReordered.isEmpty)
        }

        public var isPartialSuccess: Bool {
            !newlyAdded.isEmpty && failedCount > 0
        }
    }

    public static func extractURLs(from pasteboard: NSPasteboard) -> [URL] {
        var extracted: [URL] = []
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls where url.isFileURL {
                extracted.append(url)
            }
        }
        if extracted.isEmpty, let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            for path in paths {
                let url = URL(fileURLWithPath: path)
                if url.isFileURL {
                    extracted.append(url)
                }
            }
        }
        return extracted
    }

    @discardableResult
    public func addFile(url: URL) -> ShelfItem? {
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        guard fileManager.fileExists(atPath: standardized.path) else {
            lastErrorMessage = "File not found or inaccessible: \(standardized.lastPathComponent)"
            return nil
        }
        if let existingIndex = items.firstIndex(where: { $0.url.path == standardized.path }) {
            let existing = items.remove(at: existingIndex)
            items.insert(existing, at: 0)
            saveItems()
            return existing
        }
        let item = ShelfItem(url: standardized)
        items.insert(item, at: 0)
        saveItems()
        eventSink.emit(.fileReceived)
        return item
    }

    @discardableResult
    public func addFilesDetailed(urls: [URL]) -> DropResult {
        guard !urls.isEmpty else {
            return DropResult(totalRequested: 0, newlyAdded: [], existingReordered: [], failedCount: 0)
        }
        var newlyAdded: [ShelfItem] = []
        var reordered: [ShelfItem] = []
        var failedCount = 0
        var changed = false

        for rawURL in urls {
            let standardized = rawURL.standardizedFileURL.resolvingSymlinksInPath()
            guard fileManager.fileExists(atPath: standardized.path) else {
                lastErrorMessage = "File not found or inaccessible: \(standardized.lastPathComponent)"
                failedCount += 1
                continue
            }

            if let existingIndex = items.firstIndex(where: { $0.url.path == standardized.path }) {
                let existing = items.remove(at: existingIndex)
                items.insert(existing, at: 0)
                reordered.append(existing)
                changed = true
            } else {
                let item = ShelfItem(url: standardized)
                items.insert(item, at: 0)
                newlyAdded.append(item)
                changed = true
            }
        }

        if changed {
            saveItems()
            if !newlyAdded.isEmpty {
                eventSink.emit(.fileReceived)
            }
        }

        return DropResult(
            totalRequested: urls.count,
            newlyAdded: newlyAdded,
            existingReordered: reordered,
            failedCount: failedCount
        )
    }

    @discardableResult
    public func addFiles(urls: [URL]) -> [ShelfItem] {
        addFilesDetailed(urls: urls).newlyAdded
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

        do {
            let opened = try fileOpener.openFile(at: item.url)
            if !opened {
                lastErrorMessage = "Could not open \(item.name)"
            }
            return opened
        } catch {
            lastErrorMessage = "Could not open \(item.name): \(error.localizedDescription)"
            return false
        }
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

        do {
            let revealed = try fileOpener.revealFile(at: item.url)
            if !revealed {
                lastErrorMessage = "Could not reveal \(item.name)"
            }
            return revealed
        } catch {
            lastErrorMessage = "Could not reveal \(item.name): \(error.localizedDescription)"
            return false
        }
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
            let item = items[i]
            var currentURL = item.url

            if let bookmark = item.bookmarkData {
                let (resolvedURL, _, isStale) = ShelfItem.resolveURLWithStale(from: bookmark, fallbackPath: item.url.path)
                let exists = fileManager.fileExists(atPath: resolvedURL.path)
                if isStale && exists, let refreshedBookmark = ShelfItem.createBookmarkData(for: resolvedURL) {
                    items[i] = ShelfItem(
                        id: item.id,
                        url: resolvedURL,
                        bookmarkData: refreshedBookmark,
                        isMissing: false,
                        dateAdded: item.dateAdded
                    )
                    changed = true
                    continue
                }
                currentURL = resolvedURL
            }

            let exists = fileManager.fileExists(atPath: currentURL.path)
            if item.isMissing == exists || item.url != currentURL {
                items[i].isMissing = !exists
                changed = true
            }
        }
        if changed {
            saveItems()
        }
    }

    public func findItem(named name: String) -> ShelfItem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // 1. Exact case-insensitive match on full filename
        if let exact = items.first(where: { $0.name.lowercased() == trimmed }) {
            return exact
        }

        // 2. Exact match without extension
        if let baseMatch = items.first(where: { $0.url.deletingPathExtension().lastPathComponent.lowercased() == trimmed }) {
            return baseMatch
        }

        // 3. Substring match
        if let subMatch = items.first(where: { $0.name.lowercased().contains(trimmed) }) {
            return subMatch
        }

        return nil
    }

    public func presentAddFilesPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Pin to Shelf"
        panel.message = "Select files or folders to pin to AMORA File Shelf."

        panel.begin { [weak self] response in
            guard let self, response == .OK, !panel.urls.isEmpty else { return }
            self.addFiles(urls: panel.urls)
        }
    }

    @discardableResult
    public func handleDrop(
        providers: [NSItemProvider],
        onFileAdded: (@MainActor (URL) -> Void)? = nil,
        onFilesAdded: (@MainActor ([URL]) -> Void)? = nil
    ) -> Bool {
        guard !providers.isEmpty else { return false }
        isProcessingDrop = true

        Task { @MainActor in
            defer { self.isProcessingDrop = false }
            var extractedURLs: [URL] = []

            for provider in providers {
                if let extractedURL = await self.extractURL(from: provider), extractedURL.isFileURL {
                    extractedURLs.append(extractedURL)
                }
            }

            // Fallback to active drag pasteboard if providers didn't yield any URLs directly
            if extractedURLs.isEmpty {
                if let pasteboardURLs = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
                    for url in pasteboardURLs where url.isFileURL {
                        extractedURLs.append(url)
                    }
                }
            }

            guard !extractedURLs.isEmpty else {
                self.lastErrorMessage = "No supported files found in drop."
                return
            }

            let added = self.addFiles(urls: extractedURLs)
            let urlsAdded = added.map { $0.url }
            if !urlsAdded.isEmpty {
                onFilesAdded?(urlsAdded)
                if let first = urlsAdded.first {
                    onFileAdded?(first)
                }
            }
        }
        return true
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

        // Priority 4: Search all registered identifiers directly via loadItem (covers custom UTI types)
        for identifier in provider.registeredTypeIdentifiers {
            let directItemURL: URL? = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                    continuation.resume(returning: Self.extractFileURL(from: item))
                }
            }
            if let directItemURL, directItemURL.isFileURL { return directItemURL }
        }

        // Priority 5: Load in-place file representation if available
        for identifier in provider.registeredTypeIdentifiers {
            let inPlaceURL: URL? = await withCheckedContinuation { continuation in
                provider.loadInPlaceFileRepresentation(forTypeIdentifier: identifier) { url, isInPlace, _ in
                    continuation.resume(returning: isInPlace ? url : nil)
                }
            }
            if let inPlaceURL, inPlaceURL.isFileURL { return inPlaceURL }
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
                dateAdded: item.dateAdded,
                fileSize: item.fileSize,
                isDirectory: item.isDirectory
            )
        }
        do {
            try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
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

        var needsSave = false
        self.items = loaded.map { persisted in
            let (resolvedURL, _, isStale) = ShelfItem.resolveURLWithStale(from: persisted.bookmarkData, fallbackPath: persisted.path)
            let exists = fileManager.fileExists(atPath: resolvedURL.path)
            let bookmark = (isStale && exists) ? (ShelfItem.createBookmarkData(for: resolvedURL) ?? persisted.bookmarkData) : persisted.bookmarkData
            if isStale && exists {
                needsSave = true
            }
            return ShelfItem(
                id: persisted.id,
                url: resolvedURL,
                bookmarkData: bookmark,
                isMissing: !exists,
                dateAdded: persisted.dateAdded,
                fileSize: persisted.fileSize,
                isDirectory: persisted.isDirectory
            )
        }

        if needsSave {
            saveItems()
        }
    }
}
