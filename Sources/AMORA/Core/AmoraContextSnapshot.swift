import Foundation

/// Structured snapshot of an active application.
public struct AmoraApplicationContext: Equatable, Codable, Sendable {
    public let name: String?
    public let bundleIdentifier: String?

    public init(name: String?, bundleIdentifier: String? = nil) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }

    public var summary: String {
        if let name, let bundleIdentifier {
            return "\(name) (\(bundleIdentifier))"
        } else if let name {
            return name
        } else if let bundleIdentifier {
            return bundleIdentifier
        } else {
            return "None"
        }
    }
}

/// Structured snapshot of media playback state.
public struct AmoraMediaContext: Equatable, Codable, Sendable {
    public let source: String
    public let state: String
    public let title: String?
    public let artist: String?

    public init(source: String, state: String, title: String? = nil, artist: String? = nil) {
        self.source = source
        self.state = state
        self.title = title
        self.artist = artist
    }

    public static let inactive = AmoraMediaContext(source: "None", state: "inactive", title: nil, artist: nil)

    public var isPlaying: Bool {
        state.lowercased() == "playing"
    }

    public var summary: String {
        guard state.lowercased() != "inactive" && source.lowercased() != "none" else {
            return "No active media"
        }
        var desc = "\(source) is \(state)"
        if let title {
            desc += " (\"\(title)\""
            if let artist {
                desc += " by \(artist)"
            }
            desc += ")"
        }
        return desc
    }
}

/// Structured snapshot of the focus timer state.
public struct AmoraTimerContext: Equatable, Codable, Sendable {
    public let running: Bool
    public let remainingSeconds: Int
    public let duration: Int?
    public let isPaused: Bool?

    public init(running: Bool, remainingSeconds: Int, duration: Int? = nil, isPaused: Bool? = nil) {
        self.running = running
        self.remainingSeconds = remainingSeconds
        self.duration = duration
        self.isPaused = isPaused
    }

    public static let stopped = AmoraTimerContext(running: false, remainingSeconds: 0, duration: 0, isPaused: false)

    public var summary: String {
        if !running {
            return "No timer running"
        }
        let pausedText = (isPaused == true) ? " (paused)" : ""
        let durationText = duration.map { " of \($0)s" } ?? ""
        return "\(remainingSeconds)s remaining\(durationText)\(pausedText)"
    }
}

/// Structured snapshot of the system battery state.
public struct AmoraBatteryContext: Equatable, Codable, Sendable {
    public let percent: Int?
    public let charging: Bool
    public let isPluggedIn: Bool?
    public let estimate: String?

    public init(percent: Int?, charging: Bool, isPluggedIn: Bool? = nil, estimate: String? = nil) {
        self.percent = percent
        self.charging = charging
        self.isPluggedIn = isPluggedIn
        self.estimate = estimate
    }

    public static let unavailable = AmoraBatteryContext(percent: nil, charging: false, isPluggedIn: nil, estimate: nil)

    public var summary: String {
        guard let percent else {
            return "Battery unavailable"
        }
        var parts: [String] = ["\(percent)%"]
        if charging {
            parts.append("charging")
        } else if isPluggedIn == true {
            parts.append("plugged in")
        }
        if let estimate {
            parts.append("(\(estimate))")
        }
        return parts.joined(separator: ", ")
    }
}

/// Structured snapshot of AMORA Dynamic Island / Workspace UI state.
public struct AmoraUIContext: Equatable, Codable, Sendable {
    public let state: String

    public init(state: String) {
        self.state = state
    }

    public var summary: String {
        state
    }
}

/// Minimal, privacy-first summary of the File Shelf.
/// Never exposes raw file paths, names, or file contents.
public struct AmoraFileShelfContext: Equatable, Codable, Sendable {
    public let itemCount: Int
    public let missingItemCount: Int?

    public init(itemCount: Int, missingItemCount: Int? = nil) {
        self.itemCount = itemCount
        self.missingItemCount = missingItemCount
    }

    public var summary: String {
        let itemsDesc = "\(itemCount) item\(itemCount == 1 ? "" : "s")"
        if let missing = missingItemCount, missing > 0 {
            return "\(itemsDesc) (\(missing) missing)"
        }
        return itemsDesc
    }
}

/// Complete, strongly typed, privacy-first local context snapshot for AMORA.
public struct AmoraContextSnapshot: Equatable, Codable, Sendable {
    public let timestamp: Date
    public let currentApplication: AmoraApplicationContext?
    public let media: AmoraMediaContext?
    public let timer: AmoraTimerContext?
    public let battery: AmoraBatteryContext?
    public let amora: AmoraUIContext?
    public let fileShelf: AmoraFileShelfContext?
    public let formattedLocalTime: String?

    public init(
        timestamp: Date = Date(),
        currentApplication: AmoraApplicationContext? = nil,
        media: AmoraMediaContext? = nil,
        timer: AmoraTimerContext? = nil,
        battery: AmoraBatteryContext? = nil,
        amora: AmoraUIContext? = nil,
        fileShelf: AmoraFileShelfContext? = nil,
        formattedLocalTime: String? = nil
    ) {
        self.timestamp = timestamp
        self.currentApplication = currentApplication
        self.media = media
        self.timer = timer
        self.battery = battery
        self.amora = amora
        self.fileShelf = fileShelf
        self.formattedLocalTime = formattedLocalTime
    }

    // Convenience properties for fast access
    public var frontmostApplication: String? { currentApplication?.name }
    public var frontmostApplicationBundleIdentifier: String? { currentApplication?.bundleIdentifier }

    /// Encodes snapshot to standard pretty JSON data.
    public func toJSONData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(self)
    }

    /// Encodes snapshot to standard JSON string.
    public func toJSONString() -> String? {
        guard let data = toJSONData() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decodes snapshot from JSON data.
    public static func fromJSONData(_ data: Data) throws -> AmoraContextSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AmoraContextSnapshot.self, from: data)
    }

    /// Decodes snapshot from JSON string.
    public static func fromJSONString(_ string: String) throws -> AmoraContextSnapshot {
        guard let data = string.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid UTF-8 string"))
        }
        return try fromJSONData(data)
    }
}
