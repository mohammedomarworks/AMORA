import Foundation
import Observation

enum BrowserConnectionStatus: String, Sendable {
    case connected = "Connected"
    case hostNotInstalled = "Host Not Installed"
    case permissionRequired = "Permission Required"
    case extensionDisconnected = "Extension Disconnected"
    case protocolError = "Protocol Error"
}

/// Local IPC endpoint for the Chrome Native Messaging host. It accepts only a
/// normalized YouTube mediaState message; no page content or tab inventory is
/// forwarded to AMORA.
@Observable @MainActor
final class ChromeMessageBridge {
    static let shared = ChromeMessageBridge()

    private(set) var state: BrowserMediaState?
    private(set) var status: BrowserConnectionStatus = .extensionDisconnected
    private var observer: NSObjectProtocol?

    private init() {
        observer = DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("com.amora.browser.mediaState"), object: nil, queue: .main
        ) { [weak self] note in
            let payload = note.userInfo?["payload"] as? String
            Task { @MainActor [weak self] in
                self?.receive(payload)
            }
        }
    }

    func receive(_ payload: String?) {
        guard let payload, let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            state = nil
            status = .permissionRequired
            return
        }
        if type == "connectionState" {
            switch object["state"] as? String {
            case "connected": status = .connected
            case "disconnected": state = nil; status = .extensionDisconnected
            default: status = .protocolError
            }
            return
        }
        if type == "clear" {
            state = nil
            if status != .connected { status = .extensionDisconnected }
            return
        }
        guard type == "mediaState",
              object["provider"] as? String == "YouTube",
              object["browser"] as? String == "Chrome",
              let url = object["url"] as? String,
              BrowserMediaAppleScript.isSupportedYouTubeURL(url) else {
            state = nil
            status = .protocolError
            return
        }

        let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        state = BrowserMediaState(
            browser: .chrome,
            provider: .youtube,
            title: title.isEmpty ? "Metadata unavailable" : title,
            artistOrChannel: (object["channel"] as? String) ?? "",
            isPlaying: object["isPlaying"] as? Bool ?? false,
            currentTime: object["currentTime"] as? Double ?? 0,
            duration: object["duration"] as? Double ?? 0,
            url: url,
            thumbnailURL: nil,
            lastUpdated: Date(),
            controlAvailable: object["controlAvailable"] as? Bool ?? false
        )
        status = .connected
    }

    func sendPlayPause() {
        DistributedNotificationCenter.default.post(
            name: Notification.Name("com.amora.browser.command"), object: nil,
            userInfo: ["payload": "{\"type\":\"playPause\"}"]
        )
    }
}
