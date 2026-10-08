import Foundation

/// Represents an explicit automation command parsed from natural language.
public enum AmoraAutomationCommand: Equatable, Sendable {
    case create(name: String, trigger: AmoraAutomationTrigger, action: AmoraAutomationAction)
    case list
    case turnOff(query: String)
    case turnOn(query: String)
    case delete(query: String)
    case clearAll(confirmed: Bool)
}

/// Natural language parser for explicit automation commands in AMORA.
public struct AmoraAutomationCommandParser: Sendable {
    public static let shared = AmoraAutomationCommandParser()

    public init() {}

    public func parse(_ input: String) -> AmoraAutomationCommand? {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.lowercased()

        // 1. Clear All (or confirmation of clear all)
        if isClearAllConfirmation(normalized) {
            return .clearAll(confirmed: true)
        }
        if isClearAllRequest(normalized) {
            return .clearAll(confirmed: false)
        }

        // 2. List / View Automations
        if isListRequest(normalized) {
            return .list
        }

        // 3. Turn Off / Disable
        if let query = parseTurnOffRequest(trimmed, normalized: normalized) {
            return .turnOff(query: query)
        }

        // 4. Turn On / Enable
        if let query = parseTurnOnRequest(trimmed, normalized: normalized) {
            return .turnOn(query: query)
        }

        // 5. Delete specific automation
        if let query = parseDeleteRequest(trimmed, normalized: normalized) {
            return .delete(query: query)
        }

        // 6. Create automation
        if let command = parseCreateRequest(trimmed, normalized: normalized) {
            return command
        }

        return nil
    }

    // MARK: - Private Parsers

    private func isClearAllConfirmation(_ normalized: String) -> Bool {
        let confirmPhrases = [
            "yes delete all automations",
            "yes delete all",
            "yes clear all automations",
            "yes clear automations",
            "yes delete automations",
            "confirm delete all automations",
            "confirm clear automations",
            "yes please delete all automations"
        ]
        return confirmPhrases.contains(normalized)
    }

    private func isClearAllRequest(_ normalized: String) -> Bool {
        let clearPhrases = [
            "delete all automations",
            "delete all my automations",
            "clear all automations",
            "clear all my automations",
            "wipe all automations",
            "remove all automations",
            "clear automations",
            "delete automations",
            "reset automations"
        ]
        return clearPhrases.contains(normalized)
    }

    private func isListRequest(_ normalized: String) -> Bool {
        let listPhrases = [
            "list my automations",
            "list automations",
            "show my automations",
            "show automations",
            "what automations do i have",
            "what are my automations",
            "view my automations",
            "view automations",
            "get automations"
        ]
        return listPhrases.contains(normalized)
    }

    private func isNonAutomationTarget(_ query: String) -> Bool {
        let lower = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return true }
        let nonAutomationKeywords = [
            "music", "audio", "sound", "song", "track", "media", "playback", "video", "youtube", "spotify",
            "timer", "pomodoro", "alarm", "stopwatch",
            "note", "notes", "file", "files", "item", "items", "shelf",
            "memory", "memories",
            "wifi", "bluetooth", "display", "screen", "lights", "light"
        ]
        if nonAutomationKeywords.contains(lower) { return true }
        for keyword in nonAutomationKeywords {
            if lower == keyword || lower.hasPrefix(keyword + " ") || lower.hasSuffix(" " + keyword) {
                if !lower.contains("reminder") && !lower.contains("automation") {
                    return true
                }
            }
        }
        return false
    }

    private func parseTurnOffRequest(_ original: String, normalized: String) -> String? {
        let prefixes = [
            "turn off my ",
            "turn off the ",
            "turn off ",
            "disable my ",
            "disable the ",
            "disable ",
            "deactivate my ",
            "deactivate the ",
            "deactivate "
        ]
        for prefix in prefixes {
            if normalized.hasPrefix(prefix) {
                let query = String(original.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty && !isNonAutomationTarget(query) {
                    return query
                }
            }
        }
        return nil
    }

    private func parseTurnOnRequest(_ original: String, normalized: String) -> String? {
        let prefixes = [
            "turn on my ",
            "turn on the ",
            "turn on ",
            "enable my ",
            "enable the ",
            "enable ",
            "activate my ",
            "activate the ",
            "activate "
        ]
        for prefix in prefixes {
            if normalized.hasPrefix(prefix) {
                let query = String(original.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty && !isNonAutomationTarget(query) {
                    return query
                }
            }
        }
        return nil
    }

    private func parseDeleteRequest(_ original: String, normalized: String) -> String? {
        if normalized.contains("delete all") || normalized.contains("clear all") {
            return nil
        }
        let prefixes = [
            "delete my ",
            "delete the ",
            "delete ",
            "remove my ",
            "remove the ",
            "remove "
        ]
        for prefix in prefixes {
            if normalized.hasPrefix(prefix) {
                let query = String(original.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty && !isNonAutomationTarget(query) {
                    return query
                }
            }
        }
        return nil
    }

    private func parseCreateRequest(_ original: String, normalized: String) -> AmoraAutomationCommand? {
        // Pattern 1: Weekday triggers: "every weekday at 10 AM, start a 25 minute timer"
        if normalized.contains("every weekday") || normalized.contains("weekdays at") || normalized.contains("on weekdays") {
            if let time = extractTime(from: normalized) {
                let trigger = AmoraAutomationTrigger.weekdays(hour: time.hour, minute: time.minute)
                let action = extractAction(from: original, normalized: normalized, fallbackTime: time)
                let name = extractName(from: original, normalized: normalized, defaultName: "Weekday \(formatTime(hour: time.hour, minute: time.minute))")
                return .create(name: name, trigger: trigger, action: action)
            }
        }

        // Pattern 2: Daily triggers: "remind me every day at 9 PM" / "every day at 9 PM..." / "daily at 9 PM..."
        if normalized.contains("every day") || normalized.contains("daily at") || normalized.contains("daily") {
            if let time = extractTime(from: normalized) {
                let trigger = AmoraAutomationTrigger.daily(hour: time.hour, minute: time.minute)
                let action = extractAction(from: original, normalized: normalized, fallbackTime: time)
                let name = extractName(from: original, normalized: normalized, defaultName: "Daily \(formatTime(hour: time.hour, minute: time.minute))")
                return .create(name: name, trigger: trigger, action: action)
            }
        }

        // Pattern 3: Interval triggers: "every 30 minutes, play music" / "every 2 hours..."
        if let intervalSeconds = extractInterval(from: normalized) {
            let trigger = AmoraAutomationTrigger.interval(seconds: intervalSeconds)
            let action = extractAction(from: original, normalized: normalized, fallbackTime: nil)
            let mins = Int(intervalSeconds / 60)
            let name = mins >= 60 ? "Every \(mins / 60) Hours" : "Every \(mins) Mins"
            return .create(name: name, trigger: trigger, action: action)
        }

        // Pattern 4: Battery triggers: "when battery drops below 20%..."
        if normalized.contains("battery") && (normalized.contains("drop") || normalized.contains("below") || normalized.contains("reach")) {
            if let level = extractBatteryPercentage(from: normalized) {
                let trigger = AmoraAutomationTrigger.batteryThreshold(level: level, comparison: .dropsBelow)
                let action = extractAction(from: original, normalized: normalized, fallbackTime: nil)
                return .create(name: "Battery Below \(level)%", trigger: trigger, action: action)
            }
        }

        // Pattern 5: Timer completion: "when timer completes..." / "when timer finishes..."
        if normalized.contains("timer") && (normalized.contains("complete") || normalized.contains("finish") || normalized.contains("done") || normalized.contains("end")) {
            let trigger = AmoraAutomationTrigger.timerCompletion
            let action = extractAction(from: original, normalized: normalized, fallbackTime: nil)
            return .create(name: "On Timer Completion", trigger: trigger, action: action)
        }

        return nil
    }

    // MARK: - Helpers

    public func extractTime(from text: String) -> (hour: Int, minute: Int)? {
        // Matches e.g. "at 9 PM", "at 9:30 PM", "9:00 AM", "10am", "9 pm", "21:00"
        let pattern = #"(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }

        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let hourStr = nsString.substring(with: match.range(at: 1))
            guard var hour = Int(hourStr), hour >= 0 && hour <= 24 else { continue }

            var minute = 0
            if match.numberOfRanges >= 3 && match.range(at: 2).location != NSNotFound {
                let minStr = nsString.substring(with: match.range(at: 2))
                minute = Int(minStr) ?? 0
            }

            var isPM = false
            var isAM = false
            if match.numberOfRanges >= 4 && match.range(at: 3).location != NSNotFound {
                let meridiem = nsString.substring(with: match.range(at: 3)).lowercased()
                isPM = meridiem == "pm"
                isAM = meridiem == "am"
            }

            if isPM {
                if hour < 12 { hour += 12 }
            } else if isAM {
                if hour == 12 { hour = 0 }
            }

            return (hour, minute)
        }
        return nil
    }

    public func extractInterval(from text: String) -> TimeInterval? {
        let pattern = #"every\s+(\d+)\s*(minute|min|second|sec|hour|hr)s?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsString = text as NSString
        if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsString.length)) {
            let countStr = nsString.substring(with: match.range(at: 1))
            let unitStr = nsString.substring(with: match.range(at: 2)).lowercased()
            guard let count = Double(countStr), count > 0 else { return nil }
            if unitStr.hasPrefix("sec") {
                return count
            } else if unitStr.hasPrefix("hour") || unitStr.hasPrefix("hr") {
                return count * 3600
            } else {
                return count * 60
            }
        }
        return nil
    }

    public func extractBatteryPercentage(from text: String) -> Int? {
        let pattern = #"(\d{1,3})\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsString = text as NSString
        if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsString.length)) {
            let numStr = nsString.substring(with: match.range(at: 1))
            if let val = Int(numStr), val >= 1 && val <= 100 {
                return val
            }
        }
        return nil
    }

    public func extractAction(
        from original: String,
        normalized: String,
        fallbackTime: (hour: Int, minute: Int)?
    ) -> AmoraAutomationAction {
        // 1. Timer action: "start a 25 minute timer"
        let timerPattern = #"start\s+(?:a\s+)?(\d+)\s*(?:-| )?(minute|min|second|sec|hour|hr)s?\s+timer"#
        if let regex = try? NSRegularExpression(pattern: timerPattern, options: .caseInsensitive) {
            let nsString = normalized as NSString
            if let match = regex.firstMatch(in: normalized, range: NSRange(location: 0, length: nsString.length)) {
                let countStr = nsString.substring(with: match.range(at: 1))
                let unitStr = nsString.substring(with: match.range(at: 2)).lowercased()
                if let count = Double(countStr) {
                    let seconds: TimeInterval
                    if unitStr.hasPrefix("sec") {
                        seconds = count
                    } else if unitStr.hasPrefix("hour") || unitStr.hasPrefix("hr") {
                        seconds = count * 3600
                    } else {
                        seconds = count * 60
                    }
                    return .startTimer(duration: seconds)
                }
            }
        }

        // 2. Open Application: "open Spotify", "open Finder", etc.
        let openAppPattern = #"open\s+([a-zA-Z0-9 ]+)"#
        if let regex = try? NSRegularExpression(pattern: openAppPattern, options: .caseInsensitive) {
            let nsString = original as NSString
            if let match = regex.firstMatch(in: original, range: NSRange(location: 0, length: nsString.length)) {
                let appName = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !appName.isEmpty && appName.lowercased() != "workspace" {
                    return .openApp(name: appName)
                }
            }
        }

        // 3. Open Workspace: "open workspace"
        if normalized.contains("open workspace") {
            return .openWorkspace(section: nil)
        }

        // 4. Media playback
        if normalized.contains("play music") || normalized.contains("play song") {
            return .mediaPlay
        }
        if normalized.contains("pause music") || normalized.contains("pause song") {
            return .mediaPause
        }
        if normalized.contains("next track") || normalized.contains("next song") || normalized.contains("skip track") {
            return .mediaNext
        }
        if normalized.contains("previous track") || normalized.contains("previous song") {
            return .mediaPrevious
        }

        // 5. Default / Notification action
        if let reminderMsg = extractReminderMessage(from: original) {
            return .showNotification(message: reminderMsg)
        }

        if let time = fallbackTime {
            return .showNotification(message: "Reminder for \(formatTime(hour: time.hour, minute: time.minute))")
        }

        return .showNotification(message: "Scheduled automation alert")
    }

    private func extractReminderMessage(from text: String) -> String? {
        let lower = text.lowercased()
        let prefixes = ["remind me to ", "remind me that ", "remind me "]
        for prefix in prefixes {
            if let range = lower.range(of: prefix) {
                var message = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                // If message contains "every day at ..." or similar trigger suffix, clean it
                let suffixes = [" every day", " daily", " on weekdays", " every weekday"]
                for s in suffixes {
                    if let sRange = message.lowercased().range(of: s) {
                        message = String(message[..<sRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                if !message.isEmpty {
                    return message.prefix(1).uppercased() + message.dropFirst()
                }
            }
        }
        return nil
    }

    private func extractName(from original: String, normalized: String, defaultName: String) -> String {
        if let msg = extractReminderMessage(from: original) {
            return "\(defaultName) Reminder: \(msg)"
        }
        if normalized.contains("timer") {
            return "\(defaultName) Timer"
        }
        if normalized.contains("open ") {
            return "\(defaultName) App"
        }
        if normalized.contains("music") {
            return "\(defaultName) Music"
        }
        return "\(defaultName) Reminder"
    }

    private func formatTime(hour: Int, minute: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        if minute == 0 {
            return "\(hour12) \(period)"
        }
        return String(format: "%d:%02d %@", hour12, minute, period)
    }
}
