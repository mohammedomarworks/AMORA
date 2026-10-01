import Foundation
import Observation

@Observable @MainActor
final class MusicService {
    static let shared = MusicService()

    var trackTitle: String = "Not Playing"
    var artist: String = ""
    var isPlaying: Bool = false
    var isAvailable: Bool = false

    private var pollTimer: Timer?

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
        // Query Music.app
        let script = """
        if application "Music" is running then
            tell application "Music"
                set pState to player state as string
                if pState is "playing" then
                    set trk to name of current track
                    set art to artist of current track
                    return pState & "|||" & trk & "|||" & art
                else
                    return pState & "||||||"
                end if
            end tell
        else
            return "stopped||||||"
        end if
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let output = appleScript.executeAndReturnError(&error)
            if let stringValue = output.stringValue {
                let parts = stringValue.components(separatedBy: "|||")
                if parts.count >= 3 {
                    let state = parts[0]
                    let title = parts[1]
                    let art = parts[2]

                    self.isPlaying = (state == "playing")
                    if !title.isEmpty {
                        self.trackTitle = title
                        self.artist = art
                        self.isAvailable = true
                        return
                    }
                }
            }
        }

        if !isPlaying {
            self.trackTitle = "No Music Playing"
            self.artist = ""
            self.isAvailable = false
        }
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
