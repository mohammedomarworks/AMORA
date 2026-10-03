import Foundation

/// Chrome Native Messaging host. Chrome frames each message as a uint32
/// little-endian length followed by UTF-8 JSON. The host forwards only the
/// allowlisted mediaState shape over local DistributedNotificationCenter.
final class NativeMessagingHost: NSObject, @unchecked Sendable {
    private let input = FileHandle.standardInput
    private let output = FileHandle.standardOutput
    private let outputLock = NSLock()
    private let hostVersion = "4.2"

    func run() {
        log("Started")
        DistributedNotificationCenter.default.addObserver(
            // The stdin loop occupies the main thread, so delivery cannot be
            // scheduled on .main or play/pause commands would never reach
            // Chrome.
            forName: Notification.Name("com.amora.browser.command"), object: nil, queue: nil
        ) { [weak self] note in
            guard let payload = note.userInfo?["payload"] as? String else { return }
            self?.write(payload)
        }

        while let data = readMessage() {
            guard let object = jsonObject(data) else {
                log("Malformed JSON message")
                write("{\"type\":\"error\",\"error\":\"malformed_message\"}")
                continue
            }
            log("Handshake received")
            if object["type"] as? String == "ping" {
                write("{\"type\":\"pong\"}")
            } else if object["type"] as? String == "hello" {
                write("{\"type\":\"hello\",\"app\":\"AMORA\",\"version\":\"\(hostVersion)\"}")
                postToApp("{\"type\":\"connectionState\",\"state\":\"connected\"}")
            } else if isValid(object) {
                postToApp(String(decoding: data, as: UTF8.self))
            } else {
                log("Rejected message")
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
        if object["type"] as? String == "clear" { return true }
        guard object["type"] as? String == "mediaState",
              object["provider"] as? String == "YouTube",
              object["browser"] as? String == "Chrome",
              let url = object["url"] as? String else { return false }
        return url.lowercased().contains("youtube.com/watch")
            || url.lowercased().contains("youtube.com/shorts")
            || url.lowercased().contains("youtu.be/")
    }

    private func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        var length = UInt32(data.count).littleEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(data)
        outputLock.lock(); defer { outputLock.unlock() }
        try? output.write(contentsOf: packet)
    }

    private func postToApp(_ payload: String) {
        DistributedNotificationCenter.default.post(
            name: Notification.Name("com.amora.browser.mediaState"), object: nil,
            userInfo: ["payload": payload]
        )
    }

    private func log(_ message: String) {
        let line = "[AMORA BrowserHost] \(message)\n"
        try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
    }
}

let host = NativeMessagingHost()
host.run()
