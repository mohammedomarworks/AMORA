import Foundation

/// Strongly typed decision produced by an AI model in Local Agent V1.
public enum AmoraAgentDecision: Equatable, Sendable {
    /// A user-facing text answer with no tool execution.
    case finalAnswer(String)
    /// A request to invoke an approved tool with validated arguments.
    case toolCall(name: String, arguments: [String: String])
    /// A sequential batch of approved tool invocations (e.g. from compound action plans).
    case toolBatch([AmoraAgentToolCall])
}

/// A single structured tool call specification within a decision or batch.
public struct AmoraAgentToolCall: Equatable, Sendable {
    public let name: String
    public let arguments: [String: String]

    public init(name: String, arguments: [String: String] = [:]) {
        self.name = name
        self.arguments = arguments
    }
}

/// Errors raised when parsing or validating an agent decision.
public enum AmoraAgentDecisionError: Error, Equatable, Sendable {
    case emptyResponse
    case malformedJSON(String)
    case unknownDecisionType(String)
    case missingToolName
    case invalidArguments(String)

    public var localizedDescription: String {
        switch self {
        case .emptyResponse:
            return "The model returned an empty response."
        case .malformedJSON(let msg):
            return "Malformed JSON from model: \(msg)"
        case .unknownDecisionType(let type):
            return "Unknown decision type: '\(type)'."
        case .missingToolName:
            return "Tool call missing tool name."
        case .invalidArguments(let msg):
            return "Invalid tool arguments: \(msg)"
        }
    }
}

/// Parses and strictly validates model responses into typed `AmoraAgentDecision`s.
public struct AmoraAgentDecisionParser: Sendable {
    public init() {}

    /// Parses model output text into a validated `AmoraAgentDecision`.
    /// Rejects malformed JSON, unknown decision types, and unsupported schemas.
    public static func parse(_ rawText: String) throws -> AmoraAgentDecision {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AmoraAgentDecisionError.emptyResponse
        }

        // 1. Check if the text contains a JSON structure
        if let jsonObject = extractJSONObject(from: trimmed) {
            return try parseJSONObject(jsonObject)
        }

        // If the text contains braces or markdown JSON fences indicating a failed/malformed JSON attempt, reject it
        if trimmed.contains("```") || trimmed.contains("{") || trimmed.contains("}") {
            throw AmoraAgentDecisionError.malformedJSON("Unparseable JSON structure in model output.")
        }

        // 2. Pure conversational prose (no JSON attempt) -> treated as final answer
        return .finalAnswer(trimmed)
    }

    private static func extractJSONObject(from text: String) -> [String: Any]? {
        let candidates = [
            extractFencedJSON(from: text),
            extractBracedJSON(from: text),
            extractBracketedJSON(from: text),
            cleanJSONString(text)
        ].compactMap { $0 }

        for candidate in candidates {
            if let data = candidate.data(using: .utf8),
               let raw = try? JSONSerialization.jsonObject(with: data) {
                if let obj = raw as? [String: Any] {
                    return obj
                }
                if let arr = raw as? [[String: Any]] {
                    return ["actions": arr]
                }
            }
        }
        return nil
    }

    private static func extractFencedJSON(from text: String) -> String? {
        if let startFence = text.range(of: "```json"),
           let endFence = text.range(of: "```", range: startFence.upperBound..<text.endIndex) {
            return cleanJSONString(String(text[startFence.upperBound..<endFence.lowerBound]))
        }
        if let startFence = text.range(of: "```"),
           let endFence = text.range(of: "```", range: startFence.upperBound..<text.endIndex) {
            return cleanJSONString(String(text[startFence.upperBound..<endFence.lowerBound]))
        }
        return nil
    }

    private static func extractBracedJSON(from text: String) -> String? {
        guard let firstOpen = text.firstIndex(of: "{"),
              let lastClose = text.lastIndex(of: "}"),
              firstOpen < lastClose else {
            return nil
        }
        return cleanJSONString(String(text[firstOpen...lastClose]))
    }

    private static func extractBracketedJSON(from text: String) -> String? {
        guard let firstOpen = text.firstIndex(of: "["),
              let lastClose = text.lastIndex(of: "]"),
              firstOpen < lastClose else {
            return nil
        }
        return cleanJSONString(String(text[firstOpen...lastClose]))
    }

    private static func cleanJSONString(_ str: String) -> String {
        var cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: #",([a-zA-Z0-9_]+)":"#, with: #",\"$1\":"#, options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\{([a-zA-Z0-9_]+)":"#, with: #"{\"$1\":"#, options: .regularExpression)
        return cleaned
    }

    private static func parseJSONObject(_ dict: [String: Any]) throws -> AmoraAgentDecision {
        // A. Check for standard typed decision: "type" or "decision"
        let rawType = (dict["type"] as? String ?? dict["decision"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let rawType {
            switch rawType {
            case "final_answer", "finalanswer", "answer", "response", "message":
                let answerText = dict["answer"] as? String
                    ?? dict["response"] as? String
                    ?? dict["message"] as? String
                    ?? dict["text"] as? String
                    ?? ""
                return .finalAnswer(answerText.trimmingCharacters(in: .whitespacesAndNewlines))

            case "tool_call", "toolcall", "tool", "call", "action":
                let toolName = dict["tool"] as? String
                    ?? dict["name"] as? String
                    ?? dict["action"] as? String
                guard let toolName = toolName?.trimmingCharacters(in: .whitespacesAndNewlines), !toolName.isEmpty else {
                    throw AmoraAgentDecisionError.missingToolName
                }

                var arguments: [String: String] = [:]
                if let rawArgs = dict["arguments"] as? [String: Any]
                    ?? dict["parameters"] as? [String: Any]
                    ?? dict["args"] as? [String: Any] {
                    for (k, v) in rawArgs {
                        arguments[k] = stringifyValue(v)
                    }
                } else if let rawArgs = dict["arguments"] as? [String: String] {
                    arguments = rawArgs
                }
                return .toolCall(name: toolName, arguments: arguments)

            default:
                throw AmoraAgentDecisionError.unknownDecisionType(rawType)
            }
        }

        // B. Check for explicit "answer" or "final_answer" top-level keys
        if let answer = dict["final_answer"] as? String ?? dict["answer"] as? String {
            return .finalAnswer(answer.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // C. Check for legacy `actions` array (e.g. `{"actions":[{"action":"app.open","name":"Spotify"}]}`)
        if let actions = dict["actions"] as? [[String: Any]], !actions.isEmpty {
            if actions.count == 1, let firstAction = actions.first {
                guard let actionName = (firstAction["action"] as? String ?? firstAction["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !actionName.isEmpty else {
                    throw AmoraAgentDecisionError.missingToolName
                }
                var arguments: [String: String] = [:]
                for (k, v) in firstAction where k != "action" {
                    arguments[k] = stringifyValue(v)
                }
                return .toolCall(name: actionName, arguments: arguments)
            } else {
                var batch: [AmoraAgentToolCall] = []
                for act in actions {
                    guard let actionName = (act["action"] as? String ?? act["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !actionName.isEmpty else { continue }
                    var args: [String: String] = [:]
                    for (k, v) in act where k != "action" {
                        args[k] = stringifyValue(v)
                    }
                    batch.append(AmoraAgentToolCall(name: actionName, arguments: args))
                }
                if !batch.isEmpty {
                    return .toolBatch(batch)
                }
            }
        }

        // D. Check for legacy `calls` array (e.g. `{"calls":[{"tool":"notes","action":"search","text":"..."}]}`)
        if let calls = dict["calls"] as? [[String: Any]], !calls.isEmpty {
            if calls.count == 1, let firstCall = calls.first {
                guard let tool = firstCall["tool"] as? String else {
                    throw AmoraAgentDecisionError.missingToolName
                }
                let action = firstCall["action"] as? String ?? ""
                let toolName = action.isEmpty ? tool : "\(tool).\(action)"
                var arguments: [String: String] = [:]
                for (k, v) in firstCall where k != "tool" && k != "action" {
                    arguments[k] = stringifyValue(v)
                }
                return .toolCall(name: toolName, arguments: arguments)
            } else {
                var batch: [AmoraAgentToolCall] = []
                for call in calls {
                    guard let tool = call["tool"] as? String else { continue }
                    let action = call["action"] as? String ?? ""
                    let toolName = action.isEmpty ? tool : "\(tool).\(action)"
                    var args: [String: String] = [:]
                    for (k, v) in call where k != "tool" && k != "action" {
                        args[k] = stringifyValue(v)
                    }
                    batch.append(AmoraAgentToolCall(name: toolName, arguments: args))
                }
                if !batch.isEmpty {
                    return .toolBatch(batch)
                }
            }
        }

        // E. Top-level direct tool call schema (e.g. `{"tool":"create_timer","arguments":{...}}`)
        if let tool = dict["tool"] as? String ?? dict["call"] as? String {
            let toolName = tool.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !toolName.isEmpty else { throw AmoraAgentDecisionError.missingToolName }
            var arguments: [String: String] = [:]
            if let rawArgs = dict["arguments"] as? [String: Any] ?? dict["parameters"] as? [String: Any] {
                for (k, v) in rawArgs {
                    arguments[k] = stringifyValue(v)
                }
            }
            return .toolCall(name: toolName, arguments: arguments)
        }

        // If unknown top-level dictionary structure without recognised schema
        throw AmoraAgentDecisionError.unknownDecisionType("Unrecognized dictionary structure")
    }

    private static func stringifyValue(_ value: Any) -> String {
        if let str = value as? String {
            return str
        }
        if let num = value as? NSNumber {
            // Check if it's boolean
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return num.boolValue ? "true" : "false"
            }
            if num.doubleValue == Double(num.intValue) {
                return "\(num.intValue)"
            }
            return "\(num.doubleValue)"
        }
        if let boolVal = value as? Bool {
            return boolVal ? "true" : "false"
        }
        return String(describing: value)
    }
}
