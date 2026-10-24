import Foundation
import Observation
import AppKit

enum BrowserConnectionStatus: String, Sendable {
    case connected = "Connected"
    case hostNotInstalled = "Host Not Installed"
    case permissionRequired = "Permission Required"
    case extensionDisconnected = "Extension Disconnected"
    case protocolError = "Protocol Error"
}

enum ChromeMediaAction: String, Codable, Sendable { case play, pause }

struct BrowserMediaCapabilities: Equatable, Sendable, Codable {
    let supportsPlay: Bool
    let supportsPause: Bool
    let supportsNext: Bool
    let supportsPrevious: Bool
    let supportsSeek: Bool

    static let youtube = BrowserMediaCapabilities(supportsPlay: true, supportsPause: true, supportsNext: false, supportsPrevious: false, supportsSeek: false)
    static let none = BrowserMediaCapabilities(supportsPlay: false, supportsPause: false, supportsNext: false, supportsPrevious: false, supportsSeek: false)
}

struct ChromeContentDiagnostic: Equatable, Sendable {
    var success = false
    var hasVideo = false
    var reason: String?
    var url = ""
}

struct ChromeCommandDiagnostic: Identifiable, Sendable {
    let id: String
    let requestId: String
    let action: ChromeMediaAction
    let tabId: Int?
    let provider: String
    let timestamp: Date
    var success: Bool?
    var failureReason: String?
}

private struct PendingChromeCommand {
    let action: ChromeMediaAction
    let tabId: Int
    let completion: (Bool, String?) -> Void
}

/// Local IPC endpoint for the Chrome Native Messaging host. It accepts only a
/// normalized YouTube mediaState message; no page content or tab inventory is
/// forwarded to AMORA.
@Observable @MainActor
final class ChromeMessageBridge {
    static let shared = ChromeMessageBridge()

    private(set) var state: BrowserMediaState?
    private(set) var status: BrowserConnectionStatus = .extensionDisconnected
    private(set) var contentDiagnostic: ChromeContentDiagnostic?
    private(set) var contentPingPending = false
    private(set) var commandDiagnostics: [ChromeCommandDiagnostic] = []
    var commandTimeoutSeconds: TimeInterval = 5.0
    var postDistributedNotifications: Bool = NSClassFromString("XCTestCase") == nil
    private var observer: NSObjectProtocol?
    private var workspaceLaunchObserver: NSObjectProtocol?
    private var workspaceTerminateObserver: NSObjectProtocol?
    private var pending: [String: PendingChromeCommand] = [:]

    private init() {
        observer = DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("com.amora.browser.mediaState"), object: nil, queue: .main
        ) { [weak self] note in
            let payload = note.userInfo?["payload"] as? String
            Task { @MainActor [weak self] in
                self?.receive(payload)
            }
        }
        setupWorkspaceObservers()
        probeConnectionIfChromeRunning()
    }

    func receive(_ payload: String?) {
        guard let payload, let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            print("[AMORA Control] rejected malformed bridge payload")
            state = nil
            status = .permissionRequired
            return
        }
        if type == "connectionState" {
            switch object["state"] as? String {
            case "connected":
                status = .connected
                notifyMediaStateChanged()
            case "disconnected":
                state = nil
                status = .extensionDisconnected
                failPendingCommands(reason: "bridge_disconnected")
                notifyMediaStateChanged()
            default:
                status = .protocolError
                notifyMediaStateChanged()
            }
            return
        }
        if type == "clear" {
            state = nil
            if object["trackedMediaTabCount"] != nil || status == .connected {
                status = .connected
            } else {
                status = .extensionDisconnected
            }
            notifyMediaStateChanged()
            return
        }
        if type == "mediaCommandResult" {
            guard let requestID = object["requestId"] as? String,
                  let actionValue = object["action"] as? String,
                  let success = object["success"] as? Bool else {
                status = .protocolError
                print("[AMORA Control] malformed command acknowledgement requestId=\(object["requestId"] as? String ?? "missing")")
                if let requestID = object["requestId"] as? String,
                   let request = pending.removeValue(forKey: requestID) {
                    recordCommandResult(requestId: requestID, success: false, reason: "ack_malformed")
                    request.completion(false, "ack_malformed")
                }
                return
            }
            guard let action = ChromeMediaAction(rawValue: actionValue.lowercased()) else {
                status = .protocolError
                if let request = pending.removeValue(forKey: requestID) {
                    recordCommandResult(requestId: requestID, success: false, reason: "ack_malformed")
                    request.completion(false, "ack_malformed")
                }
                return
            }
            let tabId = (object["tabId"] as? Int) ?? (object["targetTabId"] as? Int)
            guard let request = pending.removeValue(forKey: requestID) else {
                print("[AMORA Control] stale acknowledgement requestId=\(requestID) action=\(action.rawValue) tabId=\(tabId.map(String.init) ?? "missing")")
                return
            }
            guard request.action == action, (tabId == nil || request.tabId == tabId), !success || tabId != nil else {
                print("[AMORA Control] acknowledgement mismatch requestId=\(requestID) expectedAction=\(request.action.rawValue) actualAction=\(action.rawValue) expectedTabId=\(request.tabId) actualTabId=\(tabId.map(String.init) ?? "missing")")
                recordCommandResult(requestId: requestID, success: false, reason: "ack_mismatch")
                request.completion(false, "ack_mismatch")
                return
            }
            let failureReason = object["reason"] as? String
            recordCommandResult(requestId: requestID, success: success, reason: failureReason)
            if let state = object["state"] as? [String: Any] { updateState(state) }
            let now = ISO8601DateFormatter().string(from: Date())
            print("[AMORA Control][Diagnostics] event=command_completed requestId=\(requestID) action=\(action.rawValue) targetTabId=\(tabId.map(String.init) ?? "missing") provider=YouTube success=\(success) reason=\(failureReason ?? "none") timestamp=\(now)")
            notifyMediaStateChanged()
            request.completion(success, failureReason)
            return
        }
        if type == "contentPong" {
            guard let requestID = object["requestId"] as? String, let success = object["success"] as? Bool else {
                status = .protocolError
                notifyMediaStateChanged()
                return
            }
            contentDiagnostic = ChromeContentDiagnostic(success: success, hasVideo: object["hasVideo"] as? Bool ?? false, reason: object["reason"] as? String, url: object["url"] as? String ?? "")
            contentPingPending = false
            status = .connected
            print("[AMORA Control] content ping acknowledged requestId=\(requestID) success=\(success) hasVideo=\(object["hasVideo"] as? Bool ?? false)")
            notifyMediaStateChanged()
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

        updateState(object)
        status = .connected
        print("[AMORA Control] media state received provider=YouTube tabId=\(object["tabId"] as? Int ?? -1) isPlaying=\(object["isPlaying"] as? Bool ?? false)")
        notifyMediaStateChanged()
    }

    @discardableResult
    func sendMediaCommand(_ action: ChromeMediaAction, completion: @escaping (Bool, String?) -> Void) -> String? {
        guard status == .connected else {
            print("[AMORA Control] request rejected action=\(action.rawValue) reason=bridge_disconnected")
            completion(false, "bridge_disconnected")
            return nil
        }
        guard let state else {
            print("[AMORA Control] request rejected action=\(action.rawValue) reason=no_media_target")
            completion(false, "no_media_target")
            return nil
        }
        guard action == .play ? state.capabilities.supportsPlay : state.capabilities.supportsPause else {
            print("[AMORA Control] request rejected action=\(action.rawValue) targetTabId=\(state.tabId.map(String.init) ?? "missing") reason=unsupported")
            completion(false, "unsupported")
            return nil
        }
        guard let tabId = state.tabId else {
            print("[AMORA Control] request rejected action=\(action.rawValue) reason=missing_target_tab")
            completion(false, "missing_target_tab")
            return nil
        }
        let requestID = UUID().uuidString
        let timeoutSeconds: TimeInterval = commandTimeoutSeconds
        recordCommandCreated(requestId: requestID, action: action, tabId: tabId, provider: "YouTube")
        pending[requestID] = PendingChromeCommand(action: action, tabId: tabId, completion: completion)
        let payload: [String: Any] = ["type": "mediaCommand", "provider": "youtube", "action": action.rawValue, "requestId": requestID, "tabId": tabId]
        guard let data = try? JSONSerialization.data(withJSONObject: payload), let string = String(data: data, encoding: .utf8) else {
            pending.removeValue(forKey: requestID)
            recordCommandResult(requestId: requestID, success: false, reason: "encoding_failed")
            completion(false, "encoding_failed")
            return nil
        }
        if postDistributedNotifications {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.amora.browser.command"),
                object: nil,
                userInfo: ["payload": string],
                deliverImmediately: true
            )
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            guard let self, let request = self.pending.removeValue(forKey: requestID) else { return }
            self.recordCommandResult(requestId: requestID, success: false, reason: "command_timeout")
            let now = ISO8601DateFormatter().string(from: Date())
            print("[AMORA Control][Diagnostics] event=command_timeout requestId=\(requestID) action=\(action.rawValue) targetTabId=\(tabId) provider=YouTube timestamp=\(now) success=false reason=command_timeout")
            request.completion(false, "command_timeout")
        }
        return requestID
    }

    private func setupWorkspaceObservers() {
        guard postDistributedNotifications else { return }
        workspaceLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.google.Chrome" else { return }
            Task { @MainActor [weak self] in
                self?.handleChromeLaunched()
            }
        }

        workspaceTerminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.google.Chrome" else { return }
            Task { @MainActor [weak self] in
                self?.handleChromeTerminated()
            }
        }
    }

    func handleChromeLaunched() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.probeConnectionIfChromeRunning()
        }
    }

    func handleChromeTerminated() {
        state = nil
        status = .extensionDisconnected
        contentPingPending = false
        failPendingCommands(reason: "bridge_disconnected")
        notifyMediaStateChanged()
    }

    func probeConnectionIfChromeRunning() {
        guard postDistributedNotifications else { return }
        let isChromeRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty
        guard isChromeRunning else {
            if status != .extensionDisconnected {
                status = .extensionDisconnected
                state = nil
                notifyMediaStateChanged()
            }
            return
        }
        sendProbePing()
    }

    func sendProbePing() {
        sendContentPingInternal(timeoutSeconds: 2.0, userInitiated: false)
    }

    func runContentPing() {
        sendContentPingInternal(timeoutSeconds: 5.0, userInitiated: true)
    }

    private func sendContentPingInternal(timeoutSeconds: TimeInterval, userInitiated: Bool) {
        let requestID = UUID().uuidString
        if userInitiated {
            contentPingPending = true
            contentDiagnostic = nil
        }
        let payload: [String: Any] = ["type": "contentPing", "requestId": requestID]
        guard let data = try? JSONSerialization.data(withJSONObject: payload), let string = String(data: data, encoding: .utf8) else {
            if userInitiated {
                contentPingPending = false
                contentDiagnostic = ChromeContentDiagnostic(reason: "encoding_failed")
            }
            return
        }
        print("[AMORA] sending content ping \(requestID)")
        if postDistributedNotifications {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.amora.browser.command"),
                object: nil,
                userInfo: ["payload": string],
                deliverImmediately: true
            )
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            guard let self else { return }
            if userInitiated && self.contentPingPending {
                self.contentPingPending = false
                self.contentDiagnostic = ChromeContentDiagnostic(reason: "content_script_unavailable")
            }
        }
    }

    func sendPlayPause() {
        guard let state else { return }
        sendMediaCommand(state.isPlaying ? .pause : .play) { _, _ in }
    }

    private func recordCommandCreated(requestId: String, action: ChromeMediaAction, tabId: Int?, provider: String) {
        let entry = ChromeCommandDiagnostic(
            id: requestId,
            requestId: requestId,
            action: action,
            tabId: tabId,
            provider: provider,
            timestamp: Date(),
            success: nil,
            failureReason: nil
        )
        commandDiagnostics.append(entry)
        if commandDiagnostics.count > 50 { commandDiagnostics.removeFirst() }
        let now = ISO8601DateFormatter().string(from: entry.timestamp)
        print("[AMORA Control][Diagnostics] event=command_created requestId=\(requestId) action=\(action.rawValue) targetTabId=\(tabId.map(String.init) ?? "missing") provider=\(provider) timestamp=\(now)")
    }

    private func recordCommandResult(requestId: String, success: Bool, reason: String?) {
        if let index = commandDiagnostics.lastIndex(where: { $0.requestId == requestId }) {
            commandDiagnostics[index].success = success
            commandDiagnostics[index].failureReason = reason
        }
    }

    private func updateState(_ object: [String: Any]) {
        guard let url = object["url"] as? String, BrowserMediaAppleScript.isSupportedYouTubeURL(url) else { return }
        let capabilitiesObject = object["capabilities"] as? [String: Any]
        let capabilities = BrowserMediaCapabilities(
            supportsPlay: capabilitiesObject?["play"] as? Bool ?? true,
            supportsPause: capabilitiesObject?["pause"] as? Bool ?? true,
            supportsNext: capabilitiesObject?["next"] as? Bool ?? false,
            supportsPrevious: capabilitiesObject?["previous"] as? Bool ?? false,
            supportsSeek: capabilitiesObject?["seek"] as? Bool ?? false
        )
        let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isActive = object["isActive"] as? Bool ?? true
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
            controlAvailable: capabilities.supportsPlay || capabilities.supportsPause,
            capabilities: capabilities,
            tabId: object["tabId"] as? Int,
            windowId: object["windowId"] as? Int,
            isActive: isActive,
            isInBackground: object["isInBackground"] as? Bool ?? !isActive,
            trackedMediaTabCount: object["trackedMediaTabCount"] as? Int ?? 1,
            contentScriptReady: object["contentScriptReady"] as? Bool ?? true,
            hasVideo: object["hasVideo"] as? Bool ?? true
        )
    }

    private func notifyMediaStateChanged() {
        NotificationCenter.default.post(name: Notification.Name("com.amora.browser.mediaStateChanged"), object: nil)
    }

    private func failPendingCommands(reason: String) {
        let requests = pending
        pending.removeAll()
        for (reqId, request) in requests {
            recordCommandResult(requestId: reqId, success: false, reason: reason)
            print("[AMORA Control] pending command failed requestId=\(reqId) reason=\(reason)")
            request.completion(false, reason)
        }
    }

    func cancelCommand(requestId: String) {
        guard let request = pending.removeValue(forKey: requestId) else { return }
        recordCommandResult(requestId: requestId, success: false, reason: "command_cancelled")
        let now = ISO8601DateFormatter().string(from: Date())
        print("[AMORA Control][Diagnostics] event=command_cancelled requestId=\(requestId) action=\(request.action.rawValue) targetTabId=\(request.tabId) provider=YouTube timestamp=\(now) success=false reason=command_cancelled")
        request.completion(false, "command_cancelled")
    }

    func cancelPendingCommands() {
        failPendingCommands(reason: "command_cancelled")
    }

    func triggerTimeoutForTesting(requestId: String) {
        guard let request = pending.removeValue(forKey: requestId) else { return }
        recordCommandResult(requestId: requestId, success: false, reason: "command_timeout")
        let now = ISO8601DateFormatter().string(from: Date())
        print("[AMORA Control][Diagnostics] event=command_timeout requestId=\(requestId) action=\(request.action.rawValue) targetTabId=\(request.tabId) provider=YouTube timestamp=\(now) success=false reason=command_timeout")
        request.completion(false, "command_timeout")
    }

    func resetForTesting() {
        state = nil
        status = .extensionDisconnected
        contentDiagnostic = nil
        contentPingPending = false
        commandDiagnostics.removeAll()
        failPendingCommands(reason: "test_reset")
        commandTimeoutSeconds = 5.0
        postDistributedNotifications = false
    }
}
