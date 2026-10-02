import Foundation
import Observation

@Observable @MainActor
final class MusicService {
    static let shared = MusicService()

    var trackTitle: String = "Not Playing"
    var artist: String = ""
    var isPlaying: Bool = false
    var isAvailable: Bool = false

    /// Playback position in seconds and total track length, polled alongside the
    /// title so the island can show a live progress bar.
    var elapsed: Double = 0
    var duration: Double = 0

    /// 0…1 fraction of the current track that has played.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, elapsed / duration))
    }

    private var pollTimer: Timer?
    /// Suppresses an event on the very first poll so we don't greet music that
    /// was already playing before AMORA launched.
    private var hasPolledOnce = false

    private init() {
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
            self.trackTitle = "No Music Playing"
            self.artist = ""
            self.isAvailable = false
            self.elapsed = 0
            self.duration = 0
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
        runScript("""
        if application "Music" is running then
            tell application "Music" to play
        end if
        """)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.checkCurrentTrack() }
    }

    func pause() {
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
}
