import Foundation

/// Represents an explicit memory command requested by the user.
public enum AmoraMemoryCommand: Equatable, Sendable {
    case remember(key: String, value: String)
    case list
    case forget(query: String)
    case clearAll(confirmed: Bool)
}

/// Natural language parser for explicit long-term memory operations.
/// AMORA only saves memory when explicitly requested.
public struct AmoraMemoryCommandParser: Sendable {
    public static let shared = AmoraMemoryCommandParser()

    public init() {}

    public func parse(_ input: String) -> AmoraMemoryCommand? {
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

        // 2. List / View Memories
        if isListRequest(normalized) {
            return .list
        }

        // 3. Forget specific memory
        if let query = parseForgetRequest(trimmed, normalized: normalized) {
            return .forget(query: query)
        }

        // 4. Remember / Save explicit memory
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

    private func parseForgetRequest(_ original: String, normalized: String) -> String? {
        let prefixes = [
            "forget that ",
            "forget about ",
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

        // 1. Colon pattern: "favorite editor: VS Code"
        if let colonRange = body.range(of: ": ") {
            let left = String(body[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(body[colonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !left.isEmpty && !right.isEmpty {
                return (key: cleanSubject(left), value: right)
            }
        }

        // 2. "is" pattern: "my favorite editor is VS Code"
        if let isRange = body.range(of: " is ", options: .caseInsensitive) {
            let left = String(body[..<isRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(body[isRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !left.isEmpty && !right.isEmpty {
                return (key: cleanSubject(left), value: right)
            }
        }

        // 3. Verbs: "I use Spotify", "I love dark mode", "I prefer Chrome"
        let lower = body.lowercased()
        for verb in [" use ", " like ", " love ", " prefer "] {
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
