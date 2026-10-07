import AppKit
import Foundation

/// Decoupled protocol for controlling media playback through existing services.
@MainActor
public protocol AmoraMediaControlling: Sendable {
    func play()
    func pause()
    func nextTrack()
    func previousTrack()
    var isPlaying: Bool { get }
    var isAvailable: Bool { get }
    var trackTitle: String { get }
    var sourceName: String { get }
}

/// Default implementation routing directly to `MusicService.shared`.
@MainActor
public struct DefaultAmoraMediaController: AmoraMediaControlling {
    public init() {}

    public func play() {
        MusicService.shared.play()
    }

    public func pause() {
        MusicService.shared.pause()
    }

    public func nextTrack() {
        MusicService.shared.nextTrack()
    }

    public func previousTrack() {
        MusicService.shared.previousTrack()
    }

    public var isPlaying: Bool {
        MusicService.shared.isPlaying
    }

    public var isAvailable: Bool {
        MusicService.shared.isAvailable
    }

    public var trackTitle: String {
        MusicService.shared.trackTitle
    }

    public var sourceName: String {
        MusicService.shared.source.displayName
    }
}

/// Decoupled protocol for safely launching applications on macOS.
public protocol AmoraApplicationLaunching: Sendable {
    func resolveApplicationURL(named name: String) -> URL?
    func openApplication(at url: URL) async throws
}

/// Production implementation resolving applications dynamically using native NSWorkspace APIs.
/// Shell commands (e.g. `open ...`) and arbitrary process executions are NOT used.
public struct NativeAmoraApplicationLauncher: AmoraApplicationLaunching {
    public init() {}

    private static let searchRoots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
        URL(fileURLWithPath: "/System/Library/CoreServices"),
        FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first
    ].compactMap { $0 }

    private static let commonAliases: [String: String] = [
        "vs code": "com.microsoft.VSCode",
        "vscode": "com.microsoft.VSCode",
        "visual studio code": "com.microsoft.VSCode",
        "xcode": "com.apple.dt.Xcode"
    ]

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedURLs: [URL]? = nil

    private static func discoverCandidateURLs() -> [URL] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cachedURLs {
            return cachedURLs
        }
        let fileManager = FileManager.default
        var urls: [URL] = []
        for root in searchRoots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.lowercased() == "app" {
                    urls.append(fileURL)
                }
            }
        }
        cachedURLs = urls
        return urls
    }

    public func resolveApplicationURL(named name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased()
        let cleanName = normalized.hasSuffix(".app") ? String(normalized.dropLast(4)) : normalized

        // 1. Direct bundle identifier lookup if already formatted like one (e.g. "com.apple.finder")
        if trimmed.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
            return url
        }

        // 2. Common developer tool / editor aliases
        if let bundleID = Self.commonAliases[cleanName],
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }

        // 3. Apple bundle ID convention (fast LaunchServices lookup for standard system apps)
        let appleBundleID = "com.apple.\(cleanName.replacingOccurrences(of: " ", with: ""))"
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appleBundleID) {
            return url
        }

        // 4. Dynamic discovery across standard macOS application directories
        let candidateURLs = Self.discoverCandidateURLs()

        // Pass A: Exact match on filename or name without .app
        for url in candidateURLs {
            let lastComponent = url.lastPathComponent.lowercased()
            let baseName = url.deletingPathExtension().lastPathComponent.lowercased()
            if lastComponent == "\(cleanName).app" || baseName == cleanName {
                return url
            }
        }

        // Pass B: Check CFBundleDisplayName and CFBundleName in Info.plist
        for url in candidateURLs {
            if let bundle = Bundle(url: url) {
                if let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?.lowercased(),
                   displayName == cleanName {
                    return url
                }
                if let bundleName = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)?.lowercased(),
                   bundleName == cleanName {
                    return url
                }
            }
        }

        // Pass C: Normalized alphanumeric match (ignores spaces, hyphens, and punctuation)
        let strippedQuery = cleanName.filter { $0.isLetter || $0.isNumber }
        if !strippedQuery.isEmpty {
            for url in candidateURLs {
                let baseName = url.deletingPathExtension().lastPathComponent.lowercased()
                let strippedBase = baseName.filter { $0.isLetter || $0.isNumber }
                if strippedBase == strippedQuery {
                    return url
                }
                if let bundle = Bundle(url: url) {
                    if let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?.lowercased() {
                        if displayName.filter({ $0.isLetter || $0.isNumber }) == strippedQuery { return url }
                    }
                    if let bundleName = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)?.lowercased() {
                        if bundleName.filter({ $0.isLetter || $0.isNumber }) == strippedQuery { return url }
                    }
                }
            }
        }

        // Pass D: Prefix match for query of 4 or more characters
        if cleanName.count >= 4 {
            for url in candidateURLs {
                let baseName = url.deletingPathExtension().lastPathComponent.lowercased()
                if baseName.hasPrefix(cleanName) {
                    return url
                }
            }
        }

        return nil
    }

    @MainActor
    public func openApplication(at url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}

/// Decoupled protocol for safely opening filesystem locations.
public protocol AmoraFolderOpening: Sendable {
    func resolveFolderURL(for location: String) -> URL?
    func openFolder(at url: URL) async throws
}

/// Production implementation resolving well-known folders using FileManager and opening via NSWorkspace.
public struct NativeAmoraFolderOpener: AmoraFolderOpening {
    public init() {}

    public func resolveFolderURL(for location: String) -> URL? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        switch trimmed {
        case "downloads", "download":
            return fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Downloads")
        case "documents", "document", "docs":
            return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Documents")
        case "desktop":
            return fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Desktop")
        case "home":
            return home
        default:
            return nil
        }
    }

    @MainActor
    public func openFolder(at url: URL) async throws {
        let success = NSWorkspace.shared.open(url)
        if !success {
            throw NSError(domain: "AmoraFolderOpening", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open folder at \(url.path)."])
        }
    }
}

/// Decoupled protocol for controlling the Workspace window state.
@MainActor
public protocol AmoraWorkspaceControlling: Sendable {
    func showWorkspace(section: String?)
}

/// Production implementation routing to `WindowManager.shared.showWorkspace(...)`.
@MainActor
public struct DefaultAmoraWorkspaceController: AmoraWorkspaceControlling {
    public init() {}

    public func showWorkspace(section: String?) {
        if let section, let matchedSection = DashboardView.DashboardSection.allCases.first(where: {
            $0.rawValue.lowercased() == section.lowercased()
        }) {
            WindowManager.shared.showWorkspace(section: matchedSection)
        } else {
            WindowManager.shared.showWorkspace()
        }
    }
}

/// Decoupled protocol for controlling the timer.
@MainActor
public protocol AmoraTimerControlling: Sendable {
    func startTimer(seconds: Int)
    func stopTimer()
    var isRunning: Bool { get }
    var isPaused: Bool { get }
    var remainingSeconds: Int { get }
}

/// Production implementation routing to `TimerService.shared`.
@MainActor
public struct DefaultAmoraTimerController: AmoraTimerControlling {
    public init() {}

    public func startTimer(seconds: Int) {
        TimerService.shared.startTimer(seconds: seconds)
    }

    public func stopTimer() {
        TimerService.shared.stopTimer()
    }

    public var isRunning: Bool {
        TimerService.shared.isRunning
    }

    public var isPaused: Bool {
        TimerService.shared.isPaused
    }

    public var remainingSeconds: Int {
        TimerService.shared.remainingSeconds
    }
}
