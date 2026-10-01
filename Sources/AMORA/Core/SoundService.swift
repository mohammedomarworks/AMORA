import AppKit

/// Which event a sound belongs to. Each maps to a built-in macOS alert sound so
/// AMORA ships with zero audio assets and still sounds native, not cartoonish.
enum AMORASound {
    case open, close, click, timerComplete, success, notification, pop

    var systemName: String {
        switch self {
        case .open:         return "Tink"
        case .close:        return "Tink"
        case .click:        return "Tink"
        case .timerComplete: return "Glass"
        case .success:      return "Glass"
        case .notification: return "Ping"
        case .pop:          return "Pop"
        }
    }
}

/// A single, reusable place that plays AMORA's sound effects. Honors the user's
/// Sound Effects toggle + volume; silent by policy when disabled. Subtle by
/// design — meaningful moments only, never per-poll chatter.
@MainActor
final class SoundService {
    static let shared = SoundService()

    private init() {}

    func play(_ sound: AMORASound) {
        let settings = AppState.shared.settings
        guard settings.soundEnabled else { return }
        // Fresh instance each time so overlapping effects don't cut each other off.
        guard let ns = NSSound(named: NSSound.Name(sound.systemName)) else { return }
        ns.volume = Float(max(0.0, min(1.0, settings.soundVolume)))
        ns.play()
    }
}
