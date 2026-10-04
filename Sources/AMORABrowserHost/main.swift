import Foundation

/// Chrome Native Messaging host. Chrome frames each message as a uint32
/// little-endian length followed by UTF-8 JSON. The host forwards only
/// allowlisted YouTube media state and command acknowledgements over local IPC.
final class NativeMessagingHost: NSObject, @unchecked Sendable {
    private let input = FileHandle.standardInput
    private let output = FileHandle.standardOutput
    private let outputLock = NSLock()
    private let commandQueue = OperationQueue()
    private let hostVersion = "4.4"

    func run() {
        log("Started")
        commandQueue.maxConcurrentOperationCount = 1
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.amora.browser.command"), object: nil, queue: commandQueue
        ) { [weak self] note in
            guard let payload = note.userInfo?["payload"] as? String else { return }
            guard let self else { return }
            let object = self.jsonObject(Data(payload.utf8)) ?? [:]
            let now = ISO8601DateFormatter().string(from: Date())
            if object["type"] as? String == "mediaCommand" {
                let requestId = object["requestId"] as? String ?? "missing"
                let action = object["action"] as? String ?? "unknown"
                let tabId = object["tabId"] as? Int
                let provider = object["provider"] as? String ?? "youtube"
                self.log("[Diagnostics] event=command_received requestId=\(requestId) action=\(action) targetTabId=\(tabId.map(String.init) ?? "missing") provider=\(provider) timestamp=\(now)")
                let forwarded = self.write(payload)
                self.log("[Diagnostics] event=\(forwarded ? "command_forwarded" : "command_forward_failed") requestId=\(requestId) action=\(action) targetTabId=\(tabId.map(String.init) ?? "missing") provider=\(provider) success=\(forwarded) timestamp=\(now)")
                if !forwarded {
                    let failureObject: [String: Any] = [
                        "type": "mediaCommandResult",
                        "provider": provider,
                        "action": action,
                        "requestId": requestId,
                        "tabId": tabId as Any,
                        "targetTabId": tabId as Any,
                        "success": false,
                        "reason": "native_host_forward_failed"
                    ]
                    if let failData = try? JSONSerialization.data(withJSONObject: failureObject),
                       let failStr = String(data: failData, encoding: .utf8) {
                        self.postToApp(failStr)
                    }
                }
            } else {
                self.write(payload)
            }
        }

        while let data = readMessage() {
            guard let object = jsonObject(data) else {
                log("Malformed JSON message")
                write("{\"type\":\"error\",\"error\":\"malformed_message\"}")
                continue
            }
            let type = object["type"] as? String ?? "unknown"
            log("Received message type=\(type)")
            if type == "ping" {
                write("{\"type\":\"pong\"}")
            } else if type == "hello" {
                write("{\"type\":\"hello\",\"app\":\"AMORA\",\"version\":\"\(hostVersion)\"}")
                postToApp("{\"type\":\"connectionState\",\"state\":\"connected\"}")
            } else if isValid(object) {
                if type == "mediaCommandResult" {
                    let now = ISO8601DateFormatter().string(from: Date())
                    let reqId = (object["requestId"] as? String) ?? "missing"
                    let act = (object["action"] as? String) ?? "unknown"
                    let tId = ((object["tabId"] as? Int) ?? (object["targetTabId"] as? Int)).map(String.init) ?? "missing"
                    let succ = (object["success"] as? Bool).map(String.init) ?? "missing"
                    let rsn = (object["reason"] as? String) ?? "none"
                    log("[Diagnostics] event=response_from_chrome requestId=\(reqId) action=\(act) targetTabId=\(tId) success=\(succ) reason=\(rsn) timestamp=\(now)")
                }
                postToApp(String(decoding: data, as: UTF8.self))
                if type == "mediaCommandResult" {
                    let reqId = (object["requestId"] as? String) ?? "missing"
                    log("[Diagnostics] event=forwarded_to_amora requestId=\(reqId)")
                }
            } else {
                log("Rejected message: \(object)")
                write("{\"type\":\"error\",\"error\":\"invalid_message\"}")
            }
        }
        postToApp("{\"type\":\"connectionState\",\"state\":\"disconnected\"}")
        postToApp("{\"type\":\"clear\"}")
    }

    private func readMessage() -> Data? {
        guard let header = readExactly(4) else { return nil }
        let length = UInt32(header[0]) | UInt32(header[1]) << 8 | UInt32(header[2]) << 16 | UInt32(header[3]) << 24
        guard length > 0, length < 1_048_576 else { return nil }
        return readExactly(Int(length))
    }

    private func readExactly(_ count: Int) -> Data? {
        var result = Data()
        while result.count < count {
            guard let chunk = try? input.read(upToCount: count - result.count),
                  !chunk.isEmpty else { return nil }
            result.append(chunk)
        }
        return result
    }

    private func jsonObject(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func isValid(_ object: [String: Any]) -> Bool {
        switch object["type"] as? String {
        case "clear": return true
        case "mediaState":
            guard object["provider"] as? String == "YouTube",
                  object["browser"] as? String == "Chrome",
                  object["tabId"] as? Int != nil,
                  object["windowId"] as? Int != nil,
                  object["trackedMediaTabCount"] as? Int != nil,
                  object["isPlaying"] as? Bool != nil,
                  object["contentScriptReady"] as? Bool != nil,
                  object["hasVideo"] as? Bool == true,
                  let url = object["url"] as? String else { return false }
            return isYouTubeURL(url)
        case "mediaCommandResult":
            guard object["requestId"] as? String != nil,
                  ["play", "pause"].contains((object["action"] as? String)?.lowercased()),
                  object["success"] as? Bool != nil else { return false }
            if let provider = object["provider"] as? String {
                guard provider.lowercased() == "youtube" else { return false }
            }
            return true
        case "contentPong":
            guard object["requestId"] as? String != nil, object["success"] as? Bool != nil, object["url"] as? String != nil, object["hasVideo"] as? Bool != nil else { return false }
            return true
        case "error": return object["error"] as? String != nil
        default: return false
        }
    }

    private func isYouTubeURL(_ url: String) -> Bool {
        guard let components = URLComponents(string: url),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased() else { return false }
        if host == "youtube.com" || host == "www.youtube.com" {
            return components.path == "/watch" || components.path.hasPrefix("/shorts/")
        }
        return host == "youtu.be" && components.path.count > 1
    }

    @discardableResult
    private func write(_ string: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        var length = UInt32(data.count).littleEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(data)
        outputLock.lock(); defer { outputLock.unlock() }
        do {
            try output.write(contentsOf: packet)
            return true
        } catch {
            log("Native Messaging stdout write failed: \(error.localizedDescription)")
            return false
        }
    }

    private func postToApp(_ payload: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.amora.browser.mediaState"),
            object: nil,
            userInfo: ["payload": payload],
            deliverImmediately: true
        )
    }

    private func log(_ message: String) {
        let line = "[AMORA BrowserHost] \(message)\n"
        try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
    }
}

let host = NativeMessagingHost()
host.run()
