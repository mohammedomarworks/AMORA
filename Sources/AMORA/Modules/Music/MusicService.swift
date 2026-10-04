import Foundation
import Observation

enum MediaSource: Equatable {
    case none
    case appleMusic
    case youtube
}

@Observable @MainActor
final class MusicService {
    static let shared = MusicService()

    var trackTitle: String = "Not Playing"
    var artist: String = ""
    var isPlaying: Bool = false
    var isAvailable: Bool = false
    var source: MediaSource = .none

    /// Playback position in seconds and total track length, polled alongside the
    /// title so the island can show a live progress bar.
    var elapsed: Double = 0
    var duration: Double = 0
    var browserMediaState: BrowserMediaState?
    private(set) var controlPending = false
    private(set) var controlError: String?
    private(set) var controlStatus: String?

    /// 0…1 fraction of the current track that has played.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, elapsed / duration))
    }

    private var pollTimer: Timer?
    private var browserStateObserver: NSObjectProtocol?
    /// Suppresses an event on the very first poll so we don't greet music that
    /// was already playing before AMORA launched.
    private var hasPolledOnce = false

    private init() {
        _ = ChromeMessageBridge.shared
        browserStateObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("com.amora.browser.mediaStateChanged"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkCurrentTrack() }
        }
        checkCurrentTrack()
        startPolling()
    }

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkCurrentTrack()
            }
        }
    }

    func checkCurrentTrack() {
        // Tracked Chrome media wins over local music, including a paused video
        // whose tab is no longer selected.
        if let browserMedia = BrowserMediaProvider.currentState() {
            let wasPlaying = isPlaying
            let previousTitle = trackTitle
            let previousSource = source
            trackTitle = browserMedia.title
            artist = browserMedia.artistOrChannel.isEmpty ? "YouTube" : browserMedia.artistOrChannel
            source = .youtube
            isAvailable = true
            isPlaying = browserMedia.isPlaying
            elapsed = browserMedia.currentTime
            duration = browserMedia.duration
            browserMediaState = browserMedia
            if hasPolledOnce {
                if isPlaying && !wasPlaying { AMORAEventCenter.shared.emit(.musicStarted) }
                else if !isPlaying && wasPlaying { AMORAEventCenter.shared.emit(.musicPaused) }
                else if source != previousSource || trackTitle != previousTitle { AMORAEventCenter.shared.emit(.musicChanged) }
            }
            hasPolledOnce = true
            return
        }

        browserMediaState = nil
        // Query Music.app. Fetch track info while playing *or* paused so the
        // card can keep showing the song and a resume button when paused.
        let script = """
        if application "Music" is running then
            tell application "Music"
                set pState to player state as string
                if pState is "playing" or pState is "paused" then
                    set trk to name of current track
                    set art to artist of current track
                    set dur to (duration of current track)
                    set pos to (player position)
                    return pState & "|||" & trk & "|||" & art & "|||" & dur & "|||" & pos
                else
                    return pState & "|||" & "" & "|||" & "" & "|||" & "0" & "|||" & "0"
                end if
            end tell
        else
            return "stopped|||" & "" & "|||" & "" & "|||" & "0" & "|||" & "0"
        end if
        """

        let wasPlaying = isPlaying
        var nowPlaying = false
        var gotTrack = false

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let output = appleScript.executeAndReturnError(&error)
            if let stringValue = output.stringValue {
                let parts = stringValue.components(separatedBy: "|||")
                if parts.count >= 3 {
                    let state = parts[0]
                    let title = parts[1]
                    let art = parts[2]
                    nowPlaying = (state == "playing")

                    if parts.count >= 5 {
                        self.duration = Double(parts[3]) ?? 0
                        self.elapsed = Double(parts[4]) ?? 0
                    }

                    if !title.isEmpty {
                        self.trackTitle = title
                        self.artist = art
                        self.isAvailable = true
                        gotTrack = true
                    }
                }
            }
        }

        self.isPlaying = nowPlaying
        if !gotTrack {
            self.trackTitle = "No Media Playing"
            self.artist = ""
            self.source = .none
            self.isAvailable = false
            self.isPlaying = false
            self.elapsed = 0
            self.duration = 0
        } else {
            self.source = .appleMusic
        }
        // Emit play/stop transitions after the first baseline poll, so AMORA
        // reacts when the user starts music, not to whatever was already going.
        if hasPolledOnce {
            if nowPlaying && !wasPlaying {
                AMORAEventCenter.shared.emit(.musicStarted)
            } else if !nowPlaying && wasPlaying {
                AMORAEventCenter.shared.emit(gotTrack ? .musicPaused : .musicStopped)
            } else if nowPlaying && wasPlaying && gotTrack {
                AMORAEventCenter.shared.emit(.musicChanged)
            }
        }
        hasPolledOnce = true
    }

    func togglePlayPause() {
        if source == .youtube {
            sendBrowserCommand(isPlaying ? .pause : .play)
            return
        }
        let script = """
        if application "Music" is running then
            tell application "Music" to playpause
        end if
        """
        runScript(script)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.checkCurrentTrack()
        }
    }

    func play() {
        if source == .youtube { sendBrowserCommand(.play); return }
        runScript("""
        if application "Music" is running then
            tell application "Music" to play
        end if
        """)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.checkCurrentTrack() }
    }

    func pause() {
        if source == .youtube { sendBrowserCommand(.pause); return }
        runScript("""
        if application "Music" is running then
            tell application "Music" to pause
        end if
        """)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.checkCurrentTrack() }
    }

    func nextTrack() {
        let script = """
        if application "Music" is running then
            tell application "Music" to next track
        end if
        """
        runScript(script)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.checkCurrentTrack()
        }
    }

    func previousTrack() {
        let script = """
        if application "Music" is running then
            tell application "Music" to previous track
        end if
        """
        runScript(script)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.checkCurrentTrack()
        }
    }

    private func runScript(_ source: String) {
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: source) {
            appleScript.executeAndReturnError(&error)
        }
    }

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

enum BrowserMediaBrowser: String, Equatable {
    case safari = "Safari"
    case chrome = "Chrome"
}

struct BrowserMediaState: Equatable {
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
        // The old Apple Events providers remain available as implementation
        // experiments but are not allowed to create a false active-media card.
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
