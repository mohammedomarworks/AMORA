import Foundation
import Observation
import AppKit

enum MediaSource: String, CaseIterable, Equatable, Sendable {
    case none = "None"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtube = "YouTube"

    var displayName: String { rawValue }
}

struct MediaCapabilities: Equatable, Sendable, Codable {
    let supportsPlay: Bool
    let supportsPause: Bool
    let supportsNext: Bool
    let supportsPrevious: Bool
    let supportsSeek: Bool

    init(
        supportsPlay: Bool,
        supportsPause: Bool,
        supportsNext: Bool,
        supportsPrevious: Bool,
        supportsSeek: Bool
    ) {
        self.supportsPlay = supportsPlay
        self.supportsPause = supportsPause
        self.supportsNext = supportsNext
        self.supportsPrevious = supportsPrevious
        self.supportsSeek = supportsSeek
    }

    static let none = MediaCapabilities(supportsPlay: false, supportsPause: false, supportsNext: false, supportsPrevious: false, supportsSeek: false)
    static let appleMusic = MediaCapabilities(supportsPlay: true, supportsPause: true, supportsNext: true, supportsPrevious: true, supportsSeek: true)
    static let spotify = MediaCapabilities(supportsPlay: true, supportsPause: true, supportsNext: true, supportsPrevious: true, supportsSeek: true)
    static let youtube = MediaCapabilities(supportsPlay: true, supportsPause: true, supportsNext: false, supportsPrevious: false, supportsSeek: false)
}

struct AppleMusicTrack: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let position: Double
    let isPlaying: Bool

    init(
        title: String,
        artist: String,
        album: String = "",
        duration: Double = 0,
        position: Double = 0,
        isPlaying: Bool = false
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
        self.isPlaying = isPlaying
    }
}

struct SelectedMediaState: Equatable, Sendable {
    let source: MediaSource
    let isPlaying: Bool
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let elapsed: Double
    let isAvailable: Bool

    static let none = SelectedMediaState(
        source: .none,
        isPlaying: false,
        title: "No Media Playing",
        artist: "",
        album: "",
        duration: 0,
        elapsed: 0,
        isAvailable: false
    )

    static func spotify(_ track: SpotifyTrack) -> SelectedMediaState {
        SelectedMediaState(
            source: .spotify,
            isPlaying: track.isPlaying,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            elapsed: track.position,
            isAvailable: true
        )
    }

    static func youtube(_ media: BrowserMediaState) -> SelectedMediaState {
        SelectedMediaState(
            source: .youtube,
            isPlaying: media.isPlaying,
            title: media.title,
            artist: media.artistOrChannel.isEmpty ? "YouTube" : media.artistOrChannel,
            album: "",
            duration: media.duration,
            elapsed: media.currentTime,
            isAvailable: true
        )
    }

    static func appleMusic(_ track: AppleMusicTrack) -> SelectedMediaState {
        SelectedMediaState(
            source: .appleMusic,
            isPlaying: track.isPlaying,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            elapsed: track.position,
            isAvailable: true
        )
    }
}

@Observable @MainActor
final class MusicService {
    static let shared = MusicService()

    var trackTitle: String = "No Media Playing"
    var artist: String = ""
    var album: String = ""
    var isPlaying: Bool = false
    var isAvailable: Bool = false
    var source: MediaSource = .none

    /// Playback position in seconds and total track length, polled alongside the
    /// title so the island can show a live progress bar.
    var elapsed: Double = 0
    var duration: Double = 0
    var browserMediaState: BrowserMediaState?
    var unavailableMessage: String?
    var preferredSource: MediaSource?

    private(set) var controlPending = false
    private(set) var controlError: String?
    private(set) var controlStatus: String?

    /// 0…1 fraction of the current track that has played.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, elapsed / duration))
    }

    /// Exposes capability model based on current source.
    var capabilities: MediaCapabilities {
        switch source {
        case .spotify:
            return SpotifyProvider.capabilities
        case .appleMusic:
            return .appleMusic
        case .youtube:
            if let caps = browserMediaState?.capabilities {
                return MediaCapabilities(
                    supportsPlay: caps.supportsPlay,
                    supportsPause: caps.supportsPause,
                    supportsNext: caps.supportsNext,
                    supportsPrevious: caps.supportsPrevious,
                    supportsSeek: caps.supportsSeek
                )
            }
            return .youtube
        case .none:
            return .none
        }
    }

    private var pollTimer: Timer?
    private var browserStateObserver: NSObjectProtocol?
    /// Suppresses an event on the very first poll so we don't greet music that
    /// was already playing before AMORA launched.
    private var hasPolledOnce = false

    private init() {
        _ = ChromeMessageBridge.shared
        _ = SpotifyProvider.shared

        browserStateObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("com.amora.browser.mediaStateChanged"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkCurrentTrack() }
        }

        SpotifyProvider.shared.onStateChanged = { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkCurrentTrack() }
        }
        SpotifyProvider.shared.onAppTerminated = { [weak self] in
            Task { @MainActor [weak self] in self?.checkCurrentTrack() }
        }

        checkCurrentTrack()
        startPolling()
    }

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkCurrentTrack()
            }
        }
    }

    // MARK: - Provider Selection & State Resolution

    /// Deterministic Provider Selection Policy:
    /// 1. Actively Playing Provider Wins:
    ///    - If only one provider is currently playing (Spotify, Apple Music, or YouTube), it takes precedence.
    ///    - If multiple are playing simultaneously, stability stickiness favors the current source, then preferred source, then Spotify > Apple Music > YouTube.
    /// 2. Paused State Continuity:
    ///    - If no provider is actively playing, stickiness preserves the previously active provider (so user can view track & resume).
    ///    - If neither was previously active, deterministic precedence is applied: Spotify (if running with track) > Apple Music (if running with track) > YouTube.
    /// 3. Targeted User Intent:
    ///    - Explicit commands ("play spotify", "play apple music") set `preferredSource`.
    /// 4. Graceful Fallback:
    ///    - When no tracks are active, state reverts cleanly to `.none` ("No Media Playing").
    static func selectActiveProvider(
        browserMedia: BrowserMediaState?,
        spotifyTrack: SpotifyTrack?,
        isSpotifyRunning: Bool,
        appleMusicTrack: AppleMusicTrack?,
        previousSource: MediaSource,
        preferredSource: MediaSource?
    ) -> SelectedMediaState {
        let isYouTubePlaying = browserMedia?.isPlaying == true
        let isSpotifyPlaying = isSpotifyRunning && spotifyTrack?.isPlaying == true
        let isAppleMusicPlaying = appleMusicTrack?.isPlaying == true

        // Priority 1: Single actively playing provider
        if isSpotifyPlaying && !isYouTubePlaying && !isAppleMusicPlaying {
            return .spotify(spotifyTrack!)
        }
        if isYouTubePlaying && !isSpotifyPlaying && !isAppleMusicPlaying {
            return .youtube(browserMedia!)
        }
        if isAppleMusicPlaying && !isSpotifyPlaying && !isYouTubePlaying {
            return .appleMusic(appleMusicTrack!)
        }

        // Priority 1b: Multiple actively playing providers simultaneously
        if isSpotifyPlaying || isYouTubePlaying || isAppleMusicPlaying {
            if previousSource == .spotify && isSpotifyPlaying { return .spotify(spotifyTrack!) }
            if previousSource == .youtube && isYouTubePlaying { return .youtube(browserMedia!) }
            if previousSource == .appleMusic && isAppleMusicPlaying { return .appleMusic(appleMusicTrack!) }

            if preferredSource == .spotify && isSpotifyPlaying { return .spotify(spotifyTrack!) }
            if preferredSource == .appleMusic && isAppleMusicPlaying { return .appleMusic(appleMusicTrack!) }
            if preferredSource == .youtube && isYouTubePlaying { return .youtube(browserMedia!) }

            if isSpotifyPlaying { return .spotify(spotifyTrack!) }
            if isAppleMusicPlaying { return .appleMusic(appleMusicTrack!) }
            if isYouTubePlaying { return .youtube(browserMedia!) }
        }

        // Priority 2: None actively playing — maintain sticky active provider if still running & loaded
        if previousSource == .spotify, isSpotifyRunning, let track = spotifyTrack, !track.title.isEmpty {
            return .spotify(track)
        }
        if previousSource == .youtube, let media = browserMedia, !media.title.isEmpty {
            return .youtube(media)
        }
        if previousSource == .appleMusic, let track = appleMusicTrack, !track.title.isEmpty {
            return .appleMusic(track)
        }

        // Priority 3: Explicit preferred source
        if preferredSource == .spotify, isSpotifyRunning, let track = spotifyTrack, !track.title.isEmpty {
            return .spotify(track)
        }
        if preferredSource == .appleMusic, let track = appleMusicTrack, !track.title.isEmpty {
            return .appleMusic(track)
        }
        if preferredSource == .youtube, let media = browserMedia, !media.title.isEmpty {
            return .youtube(media)
        }

        // Priority 4: Deterministic fallback among paused providers with tracks
        if isSpotifyRunning, let track = spotifyTrack, !track.title.isEmpty {
            return .spotify(track)
        }
        if let track = appleMusicTrack, !track.title.isEmpty {
            return .appleMusic(track)
        }
        if let media = browserMedia, !media.title.isEmpty {
            return .youtube(media)
        }

        return .none
    }

    func checkCurrentTrack() {
        let browserMedia = BrowserMediaProvider.currentState()
        let isSpotifyRunning = SpotifyProvider.shared.isRunning
        let spotifyTrack = SpotifyProvider.shared.currentTrack
        let appleMusicTrack = fetchAppleMusicTrackIfRunning()

        let wasPlaying = isPlaying
        let previousTitle = trackTitle
        let previousSource = source

        let selected = Self.selectActiveProvider(
            browserMedia: browserMedia,
            spotifyTrack: spotifyTrack,
            isSpotifyRunning: isSpotifyRunning,
            appleMusicTrack: appleMusicTrack,
            previousSource: previousSource,
            preferredSource: preferredSource
        )

        source = selected.source
        isPlaying = selected.isPlaying
        trackTitle = selected.title
        artist = selected.artist
        album = selected.album
        duration = selected.duration
        elapsed = selected.elapsed
        isAvailable = selected.isAvailable
        browserMediaState = selected.source == .youtube ? browserMedia : nil

        if source != .none {
            unavailableMessage = nil
        }

        // Emit personality events
        if hasPolledOnce {
            if isPlaying && !wasPlaying {
                AMORAEventCenter.shared.emit(.musicStarted)
            } else if !isPlaying && wasPlaying {
                AMORAEventCenter.shared.emit(isAvailable ? .musicPaused : .musicStopped)
            } else if (source != previousSource || trackTitle != previousTitle) && isAvailable {
                AMORAEventCenter.shared.emit(.musicChanged)
            }
        }
        hasPolledOnce = true
    }

    // MARK: - Playback Controls (Non-Blocking Dispatch)

    func togglePlayPause() {
        switch source {
        case .spotify:
            toggleSpotify()
        case .youtube:
            sendBrowserCommand(isPlaying ? .pause : .play)
        case .appleMusic:
            toggleAppleMusic()
        case .none:
            if SpotifyProvider.shared.isRunning {
                toggleSpotify()
            } else if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
                toggleAppleMusic()
            } else if SpotifyProvider.shared.isInstalled {
                playSpotify()
            }
        }
    }

    func play(preferredSource target: MediaSource? = nil) {
        let resolved = target ?? (source == .none ? (preferredSource ?? .none) : source)
        switch resolved {
        case .spotify:
            playSpotify()
        case .youtube:
            sendBrowserCommand(.play)
        case .appleMusic:
            playAppleMusic()
        case .none:
            if SpotifyProvider.shared.isRunning {
                playSpotify()
            } else if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
                playAppleMusic()
            } else if SpotifyProvider.shared.isInstalled {
                playSpotify()
            }
        }
    }

    func pause(preferredSource target: MediaSource? = nil) {
        let resolved = target ?? source
        switch resolved {
        case .spotify:
            pauseSpotify()
        case .youtube:
            sendBrowserCommand(.pause)
        case .appleMusic:
            pauseAppleMusic()
        case .none:
            if SpotifyProvider.shared.isRunning {
                pauseSpotify()
            } else if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
                pauseAppleMusic()
            }
        }
    }

    func nextTrack(preferredSource target: MediaSource? = nil) {
        let resolved = target ?? source
        switch resolved {
        case .spotify:
            nextSpotify()
        case .appleMusic:
            nextAppleMusic()
        default:
            if SpotifyProvider.shared.isRunning {
                nextSpotify()
            } else {
                nextAppleMusic()
            }
        }
    }

    func previousTrack(preferredSource target: MediaSource? = nil) {
        let resolved = target ?? source
        switch resolved {
        case .spotify:
            previousSpotify()
        case .appleMusic:
            previousAppleMusic()
        default:
            if SpotifyProvider.shared.isRunning {
                previousSpotify()
            } else {
                previousAppleMusic()
            }
        }
    }

    func seek(to seconds: Double) {
        if source == .spotify {
            seekSpotify(to: seconds)
        }
    }

    // MARK: - Spotify Controls

    private func playSpotify() {
        controlPending = true
        controlError = nil
        controlStatus = "Playing…"
        preferredSource = .spotify
        Task { [weak self] in
            let result = await SpotifyProvider.shared.play()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.controlPending = false
                switch result {
                case .success:
                    self.controlStatus = "Playing"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.controlStatus = nil }
                case let .failure(error):
                    self.controlStatus = nil
                    self.controlError = error.localizedDescription
                }
                self.checkCurrentTrack()
            }
        }
    }

    private func pauseSpotify() {
        controlPending = true
        controlError = nil
        controlStatus = "Pausing…"
        Task { [weak self] in
            let result = await SpotifyProvider.shared.pause()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.controlPending = false
                switch result {
                case .success:
                    self.controlStatus = "Paused"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.controlStatus = nil }
                case let .failure(error):
                    self.controlStatus = nil
                    self.controlError = error.localizedDescription
                }
                self.checkCurrentTrack()
            }
        }
    }

    private func toggleSpotify() {
        controlPending = true
        controlError = nil
        controlStatus = isPlaying ? "Pausing…" : "Playing…"
        Task { [weak self] in
            let result = await SpotifyProvider.shared.togglePlayPause()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.controlPending = false
                switch result {
                case .success:
                    self.controlStatus = self.isPlaying ? "Paused" : "Playing"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.controlStatus = nil }
                case let .failure(error):
                    self.controlStatus = nil
                    self.controlError = error.localizedDescription
                }
                self.checkCurrentTrack()
            }
        }
    }

    private func nextSpotify() {
        controlPending = true
        controlError = nil
        controlStatus = "Next…"
        Task { [weak self] in
            let result = await SpotifyProvider.shared.nextTrack()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.controlPending = false
                switch result {
                case .success:
                    self.controlStatus = nil
                case let .failure(error):
                    self.controlStatus = nil
                    self.controlError = error.localizedDescription
                }
                self.checkCurrentTrack()
            }
        }
    }

    private func previousSpotify() {
        controlPending = true
        controlError = nil
        controlStatus = "Previous…"
        Task { [weak self] in
            let result = await SpotifyProvider.shared.previousTrack()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.controlPending = false
                switch result {
                case .success:
                    self.controlStatus = nil
                case let .failure(error):
                    self.controlStatus = nil
                    self.controlError = error.localizedDescription
                }
                self.checkCurrentTrack()
            }
        }
    }

    private func seekSpotify(to seconds: Double) {
        Task { [weak self] in
            _ = await SpotifyProvider.shared.seek(to: seconds)
            await MainActor.run { [weak self] in
                self?.elapsed = seconds
            }
        }
    }

    // MARK: - Apple Music Integration

    private func fetchAppleMusicTrackIfRunning() -> AppleMusicTrack? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            return nil
        }

        let script = """
        if application "Music" is running then
            tell application "Music"
                set pState to player state as string
                if pState is "playing" or pState is "paused" then
                    set trk to name of current track
                    set art to artist of current track
                    set alb to album of current track
                    set dur to (duration of current track)
                    set pos to (player position)
                    return pState & "|||" & trk & "|||" & art & "|||" & alb & "|||" & dur & "|||" & pos
                else
                    return pState & "|||||||||0|||0"
                end if
            end tell
        else
            return "stopped|||||||||0|||0"
        end if
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return nil }
        let output = appleScript.executeAndReturnError(&error)
        guard let stringValue = output.stringValue else { return nil }

        let parts = stringValue.components(separatedBy: "|||")
        guard parts.count >= 3 else { return nil }
        let state = parts[0]
        let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let art = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let alb = parts.count > 3 ? parts[3].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let dur = parts.count > 4 ? (Double(parts[4]) ?? 0) : 0
        let pos = parts.count > 5 ? (Double(parts[5]) ?? 0) : 0

        return AppleMusicTrack(
            title: title,
            artist: art,
            album: alb,
            duration: dur,
            position: pos,
            isPlaying: state == "playing"
        )
    }

    private func playAppleMusic() {
        controlPending = true
        controlStatus = "Playing…"
        preferredSource = .appleMusic
        Task.detached(priority: .userInitiated) { [weak self] in
            let script = """
            if application "Music" is running then
                tell application "Music" to play
            end if
            """
            var error: NSDictionary?
            _ = NSAppleScript(source: script)?.executeAndReturnError(&error)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.controlPending = false
                self.controlStatus = "Playing"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.controlStatus = nil }
                self.checkCurrentTrack()
            }
        }
    }

    private func pauseAppleMusic() {
        controlPending = true
        controlStatus = "Pausing…"
        Task.detached(priority: .userInitiated) { [weak self] in
            let script = """
            if application "Music" is running then
                tell application "Music" to pause
            end if
            """
            var error: NSDictionary?
            _ = NSAppleScript(source: script)?.executeAndReturnError(&error)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.controlPending = false
                self.controlStatus = "Paused"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.controlStatus = nil }
                self.checkCurrentTrack()
            }
        }
    }

    private func toggleAppleMusic() {
        controlPending = true
        controlStatus = isPlaying ? "Pausing…" : "Playing…"
        Task.detached(priority: .userInitiated) { [weak self] in
            let script = """
            if application "Music" is running then
                tell application "Music" to playpause
            end if
            """
            var error: NSDictionary?
            _ = NSAppleScript(source: script)?.executeAndReturnError(&error)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.controlPending = false
                self.controlStatus = self.isPlaying ? "Paused" : "Playing"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.controlStatus = nil }
                self.checkCurrentTrack()
            }
        }
    }

    private func nextAppleMusic() {
        Task.detached(priority: .userInitiated) { [weak self] in
            let script = """
            if application "Music" is running then
                tell application "Music" to next track
            end if
            """
            var error: NSDictionary?
            _ = NSAppleScript(source: script)?.executeAndReturnError(&error)
            await MainActor.run { [weak self] in
                self?.checkCurrentTrack()
            }
        }
    }

    private func previousAppleMusic() {
        Task.detached(priority: .userInitiated) { [weak self] in
            let script = """
            if application "Music" is running then
                tell application "Music" to previous track
            end if
            """
            var error: NSDictionary?
            _ = NSAppleScript(source: script)?.executeAndReturnError(&error)
            await MainActor.run { [weak self] in
                self?.checkCurrentTrack()
            }
        }
    }

    // MARK: - Browser / YouTube Integration

    private func sendBrowserCommand(_ action: ChromeMediaAction) {
        guard source == .youtube, browserMediaState?.browser == .chrome else {
            print("[AMORA Control] UI dispatch rejected action=\(action.rawValue) reason=browser_not_selected")
            return
        }
        print("[AMORA Control] UI dispatch action=\(action.rawValue) provider=YouTube targetTabId=\(browserMediaState?.tabId.map(String.init) ?? "missing")")
        controlError = nil
        controlPending = true
        controlStatus = action == .pause ? "Pausing…" : "Playing…"
        ChromeMessageBridge.shared.sendMediaCommand(action) { [weak self] success, reason in
            guard let self else { return }
            self.controlPending = false
            if success {
                print("[AMORA Control] UI completion action=\(action.rawValue) success=true")
                self.controlStatus = action == .pause ? "Paused" : "Playing"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.controlStatus = nil }
            } else {
                print("[AMORA Control] UI completion action=\(action.rawValue) success=false reason=\(reason ?? "unknown")")
                self.controlStatus = nil
                self.controlError = Self.friendlyControlError(reason)
            }
            self.checkCurrentTrack()
        }
    }

    private static func friendlyControlError(_ reason: String?) -> String {
        switch reason {
        case "target_tab_does_not_exist", "target_tab_not_found": return "The selected tab is no longer open."
        case "target_tab_not_youtube": return "The selected tab is not playing a YouTube video."
        case "youtube_tab_unavailable", "no_media_target": return "No controllable YouTube video is available."
        case "content_script_unavailable", "content_script_injection_failed", "content_script_injection_timeout", "content_ping_timeout": return "YouTube's control script is unavailable. Try reloading the YouTube tab."
        case "content_video_unavailable", "video_unavailable": return "No video player is loaded in the YouTube tab."
        case "video_play_failed", "play_failed", "play_rejected": return "YouTube did not allow playback to start."
        case "video_pause_failed", "pause_failed": return "YouTube did not pause the video."
        case "acknowledgement_not_returned", "content_response_timeout", "worker_command_deadline_exceeded": return "Chrome did not complete the YouTube control request in time."
        case "tabs_send_message_failed": return "Chrome could not deliver the command to YouTube. Try reloading the YouTube tab."
        case "native_host_forward_failed": return "AMORA could not communicate with Chrome."
        case "content_ack_mismatch", "content_ping_ack_mismatch", "ack_mismatch": return "Chrome returned a mismatched YouTube control response."
        case "ack_malformed": return "Chrome returned an incomplete YouTube control response."
        case "target_changed": return "The selected YouTube tab changed. Please try the control again."
        case "missing_target_tab": return "AMORA could not identify the selected YouTube tab."
        case "bridge_disconnected": return "Chrome is disconnected."
        case "command_timeout": return "Chrome did not respond in time."
        case "unsupported": return "This media action is not supported here."
        default: return "Chrome could not control this video."
        }
    }
}

enum BrowserMediaBrowser: String, Equatable, Sendable {
    case safari = "Safari"
    case chrome = "Chrome"
}

struct BrowserMediaState: Equatable, Sendable {
    let browser: BrowserMediaBrowser
    let provider: MediaSource
    let title: String
    let artistOrChannel: String
    let isPlaying: Bool
    let currentTime: Double
    let duration: Double
    let url: String
    let thumbnailURL: String?
    let lastUpdated: Date
    let controlAvailable: Bool
    let capabilities: BrowserMediaCapabilities
    let tabId: Int?
    let windowId: Int?
    let isActive: Bool
    let isInBackground: Bool
    let trackedMediaTabCount: Int
    let contentScriptReady: Bool
    let hasVideo: Bool

    var hasReliableProgress: Bool { duration > 0 && currentTime >= 0 }
}

protocol BrowserMediaProviderProtocol: Sendable {
    var browser: BrowserMediaBrowser { get }
    func currentState() -> BrowserMediaState?
    func togglePlayPause()
}

/// Browser media state comes from the Chrome extension's minimal tracked-tab
/// snapshots. No page body or browsing history is collected.
@MainActor
enum BrowserMediaProvider {
    static let providers: [any BrowserMediaProviderProtocol] = [SafariYouTubeProvider(), ChromeYouTubeProvider()]

    static func currentState() -> BrowserMediaState? {
        // Browser state is accepted only from the explicit native bridge.
        return ChromeMessageBridge.shared.state
    }

    static func currentYouTubeTab() -> BrowserMediaState? { currentState() }

    static func togglePlayPause() {
        currentState().map { state in
            providers.first { $0.browser == state.browser }?.togglePlayPause()
        }
    }
}

struct SafariYouTubeProvider: BrowserMediaProviderProtocol {
    let browser: BrowserMediaBrowser = .safari

    init() {}

    func currentState() -> BrowserMediaState? {
        let script = """
        if application "Safari" is running then
            tell application "Safari"
                if (count of windows) > 0 then
                    set t to current tab of front window
                    set pageURL to URL of t
                    if pageURL contains "youtube.com/watch" or pageURL contains "youtube.com/shorts" or pageURL contains "youtu.be/" then
                        try
                            set mediaState to do JavaScript "(function(){var v=document.querySelector('video');if(!v)return '';var title=(document.querySelector('meta[name=\\\"title\\\"]')||{}).content||document.title||'';var channel=((document.querySelector('ytd-channel-name a')||{}).textContent||'').trim();return [v.paused?'0':'1',v.currentTime,isFinite(v.duration)?v.duration:0,title,channel].join(String.fromCharCode(31));})()" in t
                            return pageURL & String.fromCharCode(30) & mediaState
                        on error
                            return pageURL & String.fromCharCode(30) & ""
                        end try
                    end if
                end if
            end tell
        end if
        return ""
        """
        return BrowserMediaAppleScript.parse(script, browser: browser)
    }

    func togglePlayPause() {
        BrowserMediaAppleScript.run("""
        if application "Safari" is running then
            tell application "Safari"
                if (count of windows) > 0 then
                    do JavaScript "(function(){var v=document.querySelector('video');if(v){v.paused?v.play():v.pause();}})()" in current tab of front window
                end if
            end tell
        end if
        """)
    }
}

struct ChromeYouTubeProvider: BrowserMediaProviderProtocol {
    let browser: BrowserMediaBrowser = .chrome

    init() {}

    func currentState() -> BrowserMediaState? {
        let script = """
        if application "Google Chrome" is running then
            tell application "Google Chrome"
                if (count of windows) > 0 then
                    set t to active tab of front window
                    set pageURL to URL of t
                    if pageURL contains "youtube.com/watch" or pageURL contains "youtube.com/shorts" or pageURL contains "youtu.be/" then
                        try
                            set mediaState to execute javascript "(function(){var v=document.querySelector('video');if(!v)return '';var title=(document.querySelector('meta[name=\\\"title\\\"]')||{}).content||document.title||'';var channel=((document.querySelector('ytd-channel-name a')||{}).textContent||'').trim();return [v.paused?'0':'1',v.currentTime,isFinite(v.duration)?v.duration:0,title,channel].join(String.fromCharCode(31));})()" in t
                            return pageURL & String.fromCharCode(30) & mediaState
                        on error
                            return pageURL & String.fromCharCode(30) & ""
                        end try
                    end if
                end if
            end tell
        end if
        return ""
        """
        return BrowserMediaAppleScript.parse(script, browser: browser)
    }

    func togglePlayPause() {
        BrowserMediaAppleScript.run("""
        if application "Google Chrome" is running then
            tell application "Google Chrome"
                if (count of windows) > 0 then
                    execute javascript "(function(){var v=document.querySelector('video');if(v){v.paused?v.play():v.pause();}})()" in active tab of front window
                end if
            end tell
        end if
        """)
    }
}

enum BrowserMediaAppleScript {
    static func parse(_ source: String, browser: BrowserMediaBrowser) -> BrowserMediaState? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source),
              let value = script.executeAndReturnError(&error).stringValue,
              !value.isEmpty else { return nil }
        let outer = value.components(separatedBy: String(UnicodeScalar(30)))
        guard outer.count == 2, isSupportedYouTubeURL(outer[0]) else { return nil }
        let fields = outer[1].components(separatedBy: String(UnicodeScalar(31)))
        guard fields.count >= 5 else { return nil }
        let title = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return BrowserMediaState(
            browser: browser,
            provider: .youtube,
            title: title,
            artistOrChannel: fields[4].trimmingCharacters(in: .whitespacesAndNewlines),
            isPlaying: fields[0] == "1",
            currentTime: Double(fields[1]) ?? 0,
            duration: Double(fields[2]) ?? 0,
            url: outer[0],
            thumbnailURL: nil,
            lastUpdated: Date(),
            controlAvailable: false,
            capabilities: .none,
            tabId: nil,
            windowId: nil,
            isActive: true,
            isInBackground: false,
            trackedMediaTabCount: 0,
            contentScriptReady: false,
            hasVideo: true
        )
    }

    static func isSupportedYouTubeURL(_ url: String) -> Bool {
        guard let components = URLComponents(string: url),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased() else { return false }
        let path = components.path.lowercased()
        if host == "youtube.com" || host == "www.youtube.com" {
            return path == "/watch" || path.hasPrefix("/shorts/")
        }
        return host == "youtu.be" && path.count > 1
    }

    static func run(_ source: String) {
        var error: NSDictionary?
        _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
