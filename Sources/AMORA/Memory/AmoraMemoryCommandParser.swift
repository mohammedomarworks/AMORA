import Foundation

/// Represents an explicit memory command requested by the user.
public enum AmoraMemoryCommand: Equatable, Sendable {
    case remember(key: String, value: String)
    case recall(query: String)
    case list
    case forget(query: String)
    case clearAll(confirmed: Bool)
    case update(target: String, newValue: String)
}

/// Natural language parser for explicit long-term memory operations.
/// AMORA only saves memory when explicitly requested.
public struct AmoraMemoryCommandParser: Sendable {
    public static let shared = AmoraMemoryCommandParser()

    public init() {}

    /// Validates whether the user input contains explicit intent to remember/save a memory.
    private static func stripLeadingPoliteFluff(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        while changed {
            changed = false
            let lower = text.lowercased()
            for prefix in [
                "please ",
                "please, ",
                "hey amora, ",
                "hey amora ",
                "amora, ",
                "amora ",
                "can you please ",
                "could you please ",
                "i want you to ",
                "make sure to ",
                "be sure to "
            ] {
                if lower.hasPrefix(prefix) {
                    text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                    break
                }
            }
        }
        return text
    }

    /// Validates whether the user input contains explicit intent to remember/save a memory.
    /// Commands such as "Remember that I prefer YouTube" are accepted.
    /// Descriptive statements ("I remember that I prefer YouTube", "I can't remember"),
    /// queries ("What do you remember?"), and unrelated text are rejected.
    public static func hasExplicitRememberIntent(_ input: String) -> Bool {
        let cleaned = stripLeadingPoliteFluff(input)
        guard !cleaned.isEmpty else { return false }
        let lower = cleaned.lowercased()

        // 1. Reject first-person statements, opinions, or declarative recollections
        let nonImperativePrefixes = [
            "i remember",
            "i can't remember",
            "i cant remember",
            "i cannot remember",
            "i don't remember",
            "i dont remember",
            "i seem to remember",
            "as far as i remember",
            "as i remember",
            "if i remember",
            "we remember",
            "you remember"
        ]
        if nonImperativePrefixes.contains(where: { lower.hasPrefix($0) }) {
            return false
        }

        // 2. Reject questions or queries about memory / recall
        let queryPrefixes = [
            "what do you remember",
            "what do you recall",
            "what can you remember",
            "do you remember",
            "did you remember",
            "can you remember",
            "could you remember",
            "tell me what you remember",
            "how much do you remember",
            "what memories",
            "what are your memories",
            "show memories",
            "list memories",
            "search memory",
            "search memories"
        ]
        if queryPrefixes.contains(where: { lower.hasPrefix($0) }) {
            return false
        }

        // 3. Must start with an explicit, approved remember imperative prefix
        let approvedRememberPrefixes = [
            "remember that ",
            "remember my ",
            "remember i ",
            "remember to ",
            "remember: ",
            "remember:",
            "remember ",
            "don't forget that ",
            "dont forget that ",
            "don't forget my ",
            "dont forget my ",
            "don't forget i ",
            "dont forget i ",
            "don't forget to ",
            "dont forget to ",
            "don't forget: ",
            "dont forget: ",
            "don't forget ",
            "dont forget ",
            "save to memory that ",
            "save to memory: ",
            "save to memory ",
            "save memory that ",
            "save memory: ",
            "save memory ",
            "store in memory that ",
            "store in memory: ",
            "store in memory ",
            "keep in mind that ",
            "keep in mind: ",
            "keep in mind "
        ]

        return approvedRememberPrefixes.contains { lower.hasPrefix($0) }
    }

    /// Validates whether the user input contains explicit intent to forget or delete a memory.
    /// Commands such as "Forget that I prefer YouTube" are accepted.
    /// Remember commands ("Don't forget"), first-person statements ("I forgot", "I can't forget"),
    /// queries ("Did you forget?"), and unrelated text are rejected.
    public static func hasExplicitForgetIntent(_ input: String) -> Bool {
        let cleaned = stripLeadingPoliteFluff(input)
        guard !cleaned.isEmpty else { return false }
        let lower = cleaned.lowercased()

        // 1. "Don't forget" is a remember command, NOT a forget command
        if lower.hasPrefix("don't forget") || lower.hasPrefix("dont forget") {
            return false
        }

        // 2. Reject first-person statements, indicative descriptions, or queries
        let nonImperativePrefixes = [
            "i forgot",
            "i forget",
            "i've forgotten",
            "ive forgotten",
            "i can't forget",
            "i cant forget",
            "i cannot forget",
            "i never forget",
            "i always forget",
            "did you forget",
            "did i forget",
            "do you forget",
            "if you forget"
        ]
        if nonImperativePrefixes.contains(where: { lower.hasPrefix($0) }) {
            return false
        }

        // 3. Clear-all confirmations
        if lower == "yes forget everything" ||
           lower == "yes forget all" ||
           lower == "yes, forget everything" ||
           lower == "yes, forget all" ||
           lower == "confirm forget everything" ||
           lower == "confirm clear memories" {
            return true
        }

        // 4. Must start with an explicit, approved forget/delete imperative prefix
        let approvedForgetPrefixes = [
            "forget that ",
            "forget about ",
            "forget my ",
            "forget your ",
            "forget everything",
            "forget all",
            "forget: ",
            "forget:",
            "forget ",
            "delete memory that ",
            "delete memory about ",
            "delete memory for ",
            "delete memory: ",
            "delete memory:",
            "delete memory ",
            "delete my memory ",
            "delete all memories",
            "delete memories",
            "remove memory that ",
            "remove memory about ",
            "remove memory for ",
            "remove memory: ",
            "remove memory:",
            "remove memory ",
            "remove my memory ",
            "remove all memories",
            "remove memories",
            "erase memory",
            "erase all memories",
            "clear memory",
            "clear memories",
            "clear all memories",
            "wipe memory",
            "wipe memories",
            "wipe all memories",
            "reset memories",
            "reset memory"
        ]

        return approvedForgetPrefixes.contains { lower.hasPrefix($0) }
    }

    /// Validates whether the user input contains explicit intent to change, update, or modify a memory.
    public static func hasExplicitUpdateIntent(_ input: String) -> Bool {
        let cleaned = stripLeadingPoliteFluff(input)
        guard !cleaned.isEmpty else { return false }
        let lower = cleaned.lowercased()

        // 1. Reject first-person statements or questions
        let nonImperativePrefixes = [
            "i changed",
            "i updated",
            "i switched",
            "i modified",
            "did you change",
            "did you update",
            "can you change the track",
            "can you change the song"
        ]
        if nonImperativePrefixes.contains(where: { lower.hasPrefix($0) }) {
            return false
        }

        // Must have an update prefix and a separator like " to ", " = ", ": "
        let updatePrefixes = [
            "change my ",
            "change ",
            "update my ",
            "update ",
            "switch my ",
            "switch ",
            "modify my ",
            "modify "
        ]

        let hasPrefix = updatePrefixes.contains { lower.hasPrefix($0) }
        let hasSeparator = lower.contains(" to ") || lower.contains(" = ") || lower.contains(": ")

        return hasPrefix && hasSeparator
    }

    public func parse(_ input: String) -> AmoraMemoryCommand? {
        if let direct = parseDirect(input) {
            return direct
        }
        // Also attempt after stripping conversational conversational prefixes
        var stripped = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["please ", "hey amora, ", "amora, ", "can you please ", "could you please "] {
            if stripped.lowercased().hasPrefix(prefix) {
                stripped = String(stripped.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = parseDirect(stripped) {
                    return parsed
                }
            }
        }
        return nil
    }

    private func parseDirect(_ input: String) -> AmoraMemoryCommand? {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else { return nil }

        let normalized = normalize(trimmed)

        // 1. Clear All (or confirmation of clear all)
        if isClearAllConfirmation(normalized) {
            return .clearAll(confirmed: true)
        }
        if isClearAllRequest(normalized) {
            return .clearAll(confirmed: false)
        }

        // 2. Targeted Recall / Search before generic listing
        // e.g. "What do you remember about my preferences?"
        if let query = parseRecallRequest(trimmed, normalized: normalized) {
            return .recall(query: query)
        }

        // 3. List / View all memories
        if isListRequest(normalized) {
            return .list
        }

        // 4. Update memory (e.g. "Change my music preference to Spotify")
        if let (target, newValue) = parseUpdateRequest(trimmed, normalized: normalized) {
            return .update(target: target, newValue: newValue)
        }

        // 5. Forget specific memory
        if let query = parseForgetRequest(trimmed, normalized: normalized) {
            return .forget(query: query)
        }

        // 6. Remember / Save explicit memory
        if let (key, value) = parseRememberRequest(trimmed) {
            return .remember(key: key, value: value)
        }

        return nil
    }

    // MARK: - Private Parsers

    private func isClearAllConfirmation(_ normalized: String) -> Bool {
        let confirmPhrases = [
            "yes forget everything",
            "yes forget all",
            "yes forget all memories",
            "yes clear all memories",
            "yes clear memories",
            "confirm clear memories",
            "confirm forget everything",
            "yes please forget everything",
            "yes delete all memories"
        ]
        return confirmPhrases.contains(normalized)
    }

    private func isClearAllRequest(_ normalized: String) -> Bool {
        let clearPhrases = [
            "forget everything you remember",
            "forget everything",
            "forget all memories",
            "forget all my memories",
            "forget all",
            "clear all memories",
            "clear my memories",
            "clear all my memories",
            "clear memories",
            "delete all memories",
            "delete all my memories",
            "erase all memories",
            "wipe all memories",
            "reset memories"
        ]
        return clearPhrases.contains(normalized)
    }

    private func parseRecallRequest(_ original: String, normalized: String) -> String? {
        let prefixes = [
            "what do you remember about ",
            "what do you remember regarding ",
            "what do you recall about ",
            "what memories do you have about ",
            "tell me what you remember about ",
            "search memory for ",
            "search memories for ",
            "search memory about ",
            "search memories about ",
            "recall memory about ",
            "recall memory for ",
            "recall memories about ",
            "recall memories for ",
            "recall "
        ]

        let lower = original.lowercased()
        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                let remainder = String(original.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                let cleaned = Self.cleanSubject(remainder)
                let normCleaned = normalize(cleaned)
                // Filter out clear-all or list-all phrases
                if normCleaned == "me" || normCleaned == "all" || normCleaned == "everything" || normCleaned == "all memories" || normCleaned.isEmpty {
                    return nil
                }
                return cleaned
            }
        }

        // Pattern: "what [subject] am i working on" / "which [subject] am i working on"
        if (normalized.hasPrefix("what ") || normalized.hasPrefix("which ")) &&
            (normalized.hasSuffix(" am i working on") || normalized.hasSuffix(" am i working on?")) {
            let startDrop = normalized.hasPrefix("what ") ? 5 : 6
            let endDrop = normalized.hasSuffix(" am i working on?") ? 18 : 17
            let sub = String(normalized.dropFirst(startDrop).dropLast(endDrop)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sub.isEmpty {
                return sub
            }
        }

        return nil
    }

    private func isListRequest(_ normalized: String) -> Bool {
        let listPhrases = [
            "what do you remember about me",
            "what do you remember",
            "what memories do you have",
            "what are my memories",
            "what are your memories",
            "show memories",
            "show my memories",
            "list memories",
            "list my memories",
            "my memories",
            "view memories",
            "view my memories",
            "tell me what you remember",
            "tell me what you remember about me"
        ]
        return listPhrases.contains(normalized)
    }

    private func parseUpdateRequest(_ original: String, normalized: String) -> (target: String, newValue: String)? {
        let lower = original.lowercased()

        // Disallow timer and system action modifications that might start with "change" / "update"
        if lower.contains("timer") || lower.contains("alarm") {
            return nil
        }
        if lower.contains("volume") || lower.contains("brightness") {
            return nil
        }
        // Media tracks: "change track", "change song", "change the track", "change the song"
        if normalized == "change track" || normalized == "change the track" || normalized == "change song" || normalized == "change the song" {
            return nil
        }

        let updatePrefixes = [
            "change my memory that ",
            "change my memory about ",
            "change my memory: ",
            "change my memory ",
            "change memory that ",
            "change memory about ",
            "change memory: ",
            "change memory ",
            "change my preference for ",
            "change my preferences for ",
            "change my ",
            "change ",
            "update my memory that ",
            "update my memory about ",
            "update my memory: ",
            "update my memory ",
            "update memory that ",
            "update memory about ",
            "update memory: ",
            "update memory ",
            "update my preference for ",
            "update my preferences for ",
            "update my ",
            "update ",
            "switch my preference for ",
            "switch my ",
            "switch ",
            "modify my preference for ",
            "modify my ",
            "modify "
        ]

        for prefix in updatePrefixes {
            if lower.hasPrefix(prefix) {
                let remainder = String(original.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !remainder.isEmpty else { return nil }

                // Check for " to " separator (e.g. "music preference to Spotify")
                if let toRange = remainder.range(of: " to ", options: .caseInsensitive) {
                    let rawTarget = String(remainder[..<toRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    var rawValue = String(remainder[toRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

                    // Strip any trailing "instead of ..."
                    if let insteadRange = rawValue.range(of: " instead of ", options: .caseInsensitive) {
                        rawValue = String(rawValue[..<insteadRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    var target = Self.cleanSubject(rawTarget)
                    if target.lowercased().hasPrefix("preference for ") {
                        target = String(target.dropFirst(15)).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if target.lowercased().hasPrefix("preferences for ") {
                        target = String(target.dropFirst(16)).trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    if !target.isEmpty && !rawValue.isEmpty {
                        return (target: target, newValue: rawValue)
                    }
                }

                // Check for " = " separator
                if let eqRange = remainder.range(of: " = ") {
                    let rawTarget = String(remainder[..<eqRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let rawValue = String(remainder[eqRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let target = Self.cleanSubject(rawTarget)
                    if !target.isEmpty && !rawValue.isEmpty {
                        return (target: target, newValue: rawValue)
                    }
                }

                // Check for ": " separator
                if let colonRange = remainder.range(of: ": ") {
                    let rawTarget = String(remainder[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let rawValue = String(remainder[colonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let target = Self.cleanSubject(rawTarget)
                    if !target.isEmpty && !rawValue.isEmpty {
                        return (target: target, newValue: rawValue)
                    }
                }
            }
        }

        return nil
    }

    private func parseForgetRequest(_ original: String, normalized: String) -> String? {
        let prefixes = [
            "forget that ",
            "forget about ",
            "forget my preference for ",
            "forget my preferences for ",
            "forget my ",
            "forget ",
            "delete memory that ",
            "delete memory about ",
            "delete memory ",
            "remove memory that ",
            "remove memory about ",
            "remove memory "
        ]

        let lower = original.lowercased()
        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                let remainder = String(original.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                // Filter out clear-all phrases
                let normRemainder = normalize(remainder)
                if normRemainder == "everything" || normRemainder == "all" || normRemainder == "all memories" {
                    return nil
                }
                if !remainder.isEmpty {
                    return remainder
                }
            }
        }
        return nil
    }

    private func parseRememberRequest(_ original: String) -> (key: String, value: String)? {
        let lower = original.lowercased()
        let prefixes = [
            "remember that ",
            "remember my ",
            "remember i ",
            "remember: ",
            "remember ",
            "don't forget that ",
            "dont forget that ",
            "don't forget my ",
            "dont forget my ",
            "don't forget i ",
            "dont forget i ",
            "don't forget: ",
            "dont forget: ",
            "don't forget ",
            "dont forget ",
            "save memory: ",
            "save memory that ",
            "save memory ",
            "save to memory: ",
            "save to memory that ",
            "save to memory "
        ]

        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                let body = String(original.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else { return nil }
                return Self.extractKeyAndValue(from: body)
            }
        }

        return nil
    }

    public static func extractKeyAndValue(from rawBody: String) -> (key: String, value: String) {
        var body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        while body.hasSuffix(".") || body.hasSuffix("!") || body.hasSuffix("?") {
            body = String(body.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if body.lowercased().hasPrefix("that ") {
            body = String(body.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let lower = body.lowercased()

        // 1. Colon pattern: "favorite editor: VS Code"
        if let colonRange = body.range(of: ": ") {
            let left = String(body[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(body[colonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !left.isEmpty && !right.isEmpty {
                return (key: cleanSubject(left), value: right)
            }
        }

        // 2. Preferences pattern: "I prefer YouTube over Apple Music" or "I prefer dark mode"
        if lower.contains(" prefer ") || lower.hasPrefix("prefer ") {
            if lower.contains("youtube") || lower.contains("spotify") || lower.contains("apple music") || lower.contains("music") || lower.contains("song") {
                return (key: "music preference", value: body)
            }
            if lower.contains("dark mode") || lower.contains("light mode") || lower.contains("theme") {
                return (key: "theme preference", value: body)
            }
            if lower.contains("vscode") || lower.contains("vs code") || lower.contains("xcode") || lower.contains("cursor") || lower.contains("sublime") || lower.contains("editor") {
                return (key: "editor preference", value: body)
            }
            if lower.contains("chrome") || lower.contains("safari") || lower.contains("firefox") || lower.contains("browser") {
                return (key: "browser preference", value: body)
            }
            if let range = lower.range(of: " prefer ") {
                let right = String(body[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !right.isEmpty {
                    return (key: "preference: \(right)", value: body)
                }
            }
            return (key: "preferences", value: body)
        }

        // 3. Projects pattern: "I am working on the Amora project" or "my project is Amora"
        if lower.contains("working on ") || lower.contains("project is ") {
            return (key: "programming project", value: body)
        }

        // 4. "is" pattern: "my favorite editor is VS Code"
        if let isRange = body.range(of: " is ", options: .caseInsensitive) {
            let left = String(body[..<isRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(body[isRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !left.isEmpty && !right.isEmpty {
                return (key: cleanSubject(left), value: right)
            }
        }

        // 5. Verbs: "I use Spotify", "I love dark mode"
        for verb in [" use ", " like ", " love "] {
            if let range = lower.range(of: verb) {
                let right = String(body[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !right.isEmpty {
                    return (key: right, value: body)
                }
            }
        }

        return (key: cleanSubject(body), value: body)
    }

    private static func cleanSubject(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["my ", "the ", "our "] {
            if cleaned.lowercased().hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return cleaned
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
