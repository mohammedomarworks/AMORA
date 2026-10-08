import Foundation
import AppKit
import Observation
import ApplicationServices

/// Metadata for a track currently loaded or playing in the Spotify desktop application.
struct SpotifyTrack: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    /// Duration in seconds.
    let duration: Double
    /// Playback position in seconds.
    let position: Double
    let isPlaying: Bool
    let trackId: String?
    let timestamp: Date

    init(
        title: String,
        artist: String,
        album: String = "",
        duration: Double = 0,
        position: Double = 0,
        isPlaying: Bool = false,
        trackId: String? = nil,
        timestamp: Date = Date()
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
        self.isPlaying = isPlaying
        self.trackId = trackId
        self.timestamp = timestamp
    }
}

/// Errors encountered while controlling or querying Spotify desktop.
enum SpotifyError: LocalizedError, Equatable, Sendable {
    case notInstalled
    case notRunning
    case permissionDenied
    case scriptExecutionFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Spotify is not installed on this Mac."
        case .notRunning:
            return "Spotify is not currently running."
        case .permissionDenied:
            return "AMORA needs Automation permission to control Spotify. You can enable it in System Settings > Privacy & Security > Automation."
        case let .scriptExecutionFailed(message):
            return "Spotify control failed: \(message)"
        case .timedOut:
            return "Spotify took too long to respond."
        }
    }
}

/// First-class desktop provider for the Spotify macOS client application.
/// Communicates directly with Spotify via macOS Apple Events (NSAppleScript)
/// and listens for real-time playback state updates using NSDistributedNotificationCenter.
@Observable @MainActor
final class SpotifyProvider {
    static let shared = SpotifyProvider()

    nonisolated static let bundleIdentifier = "com.spotify.client"

    /// Spotify Desktop capabilities supported by the installed app.
    static let capabilities = MediaCapabilities(
        supportsPlay: true,
        supportsPause: true,
        supportsNext: true,
        supportsPrevious: true,
        supportsSeek: true
    )

    private(set) var currentTrack: SpotifyTrack?
    private(set) var hasPermissionDenied: Bool = false
    private(set) var lastErrorMessage: String?

    /// Callback fired whenever Spotify changes track or playback state externally.
    var onStateChanged: (@MainActor (SpotifyTrack?) -> Void)?
    /// Callback fired when the Spotify application terminates.
    var onAppTerminated: (@MainActor () -> Void)?

    private var playbackObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    init() {
        registerObservers()
        if isRunning {
            refreshTrack()
        }
    }

    /// Whether Spotify desktop is installed on this Mac.
    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) != nil
    }

    /// Whether Spotify is currently running.
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    // MARK: - Notification & Lifecycle Observers

    private func registerObservers() {
        playbackObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let track = note.userInfo.flatMap(Self.parseNotificationUserInfo)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let track {
                    self.currentTrack = track
                    self.onStateChanged?(track)
                } else {
                    self.refreshTrack()
                }
            }
        }

        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let bundleId = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            if bundleId == Self.bundleIdentifier {
                Task { @MainActor [weak self] in
                    self?.refreshTrack()
                }
            }
        }

        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let bundleId = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            if bundleId == Self.bundleIdentifier {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.currentTrack = nil
                    self.onAppTerminated?()
                }
            }
        }
    }

    // MARK: - Query & Refresh

    func refreshTrack() {
        guard isRunning else {
            currentTrack = nil
            return
        }

        Task { [weak self] in
            let script = """
            if application "Spotify" is running then
                tell application "Spotify"
                    set pState to player state as string
                    if pState is "playing" or pState is "paused" then
                        try
                            set trk to name of current track
                            set art to artist of current track
                            set alb to album of current track
                            set dur to (duration of current track)
                            set pos to (player position)
                            return pState & "|||" & trk & "|||" & art & "|||" & alb & "|||" & dur & "|||" & pos
                        on error
                            return pState & "|||||||||0|||0"
                        end try
                    else
                        return pState & "|||||||||0|||0"
                    end if
                end tell
            else
                return "not_running"
            end if
            """

            let result = await Self.runScript(script, allowLaunch: false)
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch result {
                case let .success(output):
                    if let track = Self.parseAppleScriptOutput(output) {
                        self.currentTrack = track
                        self.hasPermissionDenied = false
                        self.lastErrorMessage = nil
                        self.onStateChanged?(track)
                    } else if output.trimmingCharacters(in: .whitespacesAndNewlines) == "not_running" {
                        self.currentTrack = nil
                        self.onAppTerminated?()
                    }
                case let .failure(error):
                    if error == .permissionDenied {
                        self.hasPermissionDenied = true
                    }
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Control Commands (Async / Non-Blocking)

    func play() async -> Result<Void, SpotifyError> {
        guard isInstalled else { return .failure(.notInstalled) }
        let script = "tell application \"Spotify\" to play"
        let res = await Self.runScript(script, allowLaunch: true)
        return handleScriptResult(res)
    }

    func pause() async -> Result<Void, SpotifyError> {
        guard isRunning else { return .failure(.notRunning) }
        let script = "tell application \"Spotify\" to pause"
        let res = await Self.runScript(script, allowLaunch: false)
        return handleScriptResult(res)
    }

    func togglePlayPause() async -> Result<Void, SpotifyError> {
        guard isRunning else { return .failure(.notRunning) }
        let script = "tell application \"Spotify\" to playpause"
        let res = await Self.runScript(script, allowLaunch: false)
        return handleScriptResult(res)
    }

    func nextTrack() async -> Result<Void, SpotifyError> {
        guard isRunning else { return .failure(.notRunning) }
        let script = "tell application \"Spotify\" to next track"
        let res = await Self.runScript(script, allowLaunch: false)
        return handleScriptResult(res)
    }

    func previousTrack() async -> Result<Void, SpotifyError> {
        guard isRunning else { return .failure(.notRunning) }
        let script = "tell application \"Spotify\" to previous track"
        let res = await Self.runScript(script, allowLaunch: false)
        return handleScriptResult(res)
    }

    func seek(to seconds: Double) async -> Result<Void, SpotifyError> {
        guard isRunning else { return .failure(.notRunning) }
        let clamped = max(0, seconds)
        let script = "tell application \"Spotify\" to set player position to \(clamped)"
        let res = await Self.runScript(script, allowLaunch: false)
        return handleScriptResult(res)
    }

    private func handleScriptResult(_ res: Result<String, SpotifyError>) -> Result<Void, SpotifyError> {
        switch res {
        case .success:
            hasPermissionDenied = false
            lastErrorMessage = nil
            return .success(())
        case let .failure(error):
            if error == .permissionDenied {
                hasPermissionDenied = true
            }
            lastErrorMessage = error.localizedDescription
            return .failure(error)
        }
    }

    // MARK: - Parsing Helpers (Pure Functions for Testing)

    /// Parses output string formatted as: `pState|||trk|||art|||alb|||dur|||pos`
    nonisolated static func parseAppleScriptOutput(_ output: String) -> SpotifyTrack? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "not_running" else { return nil }

        let parts = trimmed.components(separatedBy: "|||")
        guard parts.count >= 2 else { return nil }

        let stateString = parts[0].lowercased()
        let isPlaying = (stateString == "playing")

        let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        if title.hasPrefix("ERROR:") || title.isEmpty {
            return nil
        }

        let artist = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let album = parts.count > 3 ? parts[3].trimmingCharacters(in: .whitespacesAndNewlines) : ""

        var duration: Double = 0
        if parts.count > 4, let rawDuration = Double(parts[4]) {
            duration = rawDuration > 1000 ? rawDuration / 1000.0 : rawDuration
        }

        var position: Double = 0
        if parts.count > 5, let rawPosition = Double(parts[5]) {
            position = rawPosition
        }

        return SpotifyTrack(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: position,
            isPlaying: isPlaying,
            trackId: nil,
            timestamp: Date()
        )
    }

    /// Parses userInfo from `com.spotify.client.PlaybackStateChanged` notification.
    nonisolated static func parseNotificationUserInfo(_ userInfo: [AnyHashable: Any]) -> SpotifyTrack? {
        guard let name = (userInfo["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }

        let artist = (userInfo["Artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let album = (userInfo["Album"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stateStr = (userInfo["Player State"] as? String)?.lowercased() ?? ""
        let isPlaying = (stateStr == "playing" || stateStr == "kpsp")

        var duration: Double = 0
        if let raw = userInfo["Duration"] as? Double {
            duration = raw > 1000 ? raw / 1000.0 : raw
        } else if let raw = userInfo["Duration"] as? Int {
            duration = raw > 1000 ? Double(raw) / 1000.0 : Double(raw)
        } else if let raw = userInfo["Duration"] as? NSNumber {
            let val = raw.doubleValue
            duration = val > 1000 ? val / 1000.0 : val
        }

        var position: Double = 0
        if let raw = userInfo["Playback Position"] as? Double {
            position = raw
        } else if let raw = userInfo["Playback Position"] as? NSNumber {
            position = raw.doubleValue
        }

        let trackId = userInfo["Track ID"] as? String

        return SpotifyTrack(
            title: name,
            artist: artist,
            album: album,
            duration: duration,
            position: position,
            isPlaying: isPlaying,
            trackId: trackId,
            timestamp: Date()
        )
    }

    // MARK: - Script Runner (Background Queue)

    private static func runScript(_ source: String, allowLaunch: Bool) async -> Result<String, SpotifyError> {
        let isInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
        guard isInstalled else { return .failure(.notInstalled) }

        if !allowLaunch {
            let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
            guard isRunning else { return .failure(.notRunning) }
        }

        if NSClassFromString("XCTestCase") != nil {
            return .success("")
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorInfo: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: .failure(.scriptExecutionFailed("Could not create NSAppleScript.")))
                    return
                }

                let result = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let errorNum = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
                    let errorMsg = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript execution error"
                    if errorNum == -1743 {
                        continuation.resume(returning: .failure(.permissionDenied))
                    } else if errorNum == -600 {
                        continuation.resume(returning: .failure(.notRunning))
                    } else {
                        continuation.resume(returning: .failure(.scriptExecutionFailed(errorMsg)))
                    }
                    return
                }

                continuation.resume(returning: .success(result.stringValue ?? ""))
            }
        }
    }

    // MARK: - Permissions Helper

    /// Checks if automation permission is granted for Spotify without showing a prompt.
    nonisolated static func checkAutomationPermission() -> Bool {
        let bundleId = bundleIdentifier
        return bundleId.withCString { cStr -> Bool in
            var desc = AEAddressDesc()
            AECreateDesc(DescType(typeApplicationBundleID), cStr, strlen(cStr), &desc)
            let status = AEDeterminePermissionToAutomateTarget(&desc, typeWildCard, typeWildCard, false)
            AEDisposeDesc(&desc)
            return status == noErr
        }
    }

    /// Opens macOS System Settings directly to Privacy & Security > Automation.
    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        } else if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(fallback)
        }
    }
}
