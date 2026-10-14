import Foundation

/// Deterministic-first intent routing for Local Agent V1.
///
/// A small, bounded classifier that recognises *clear, unambiguous* single
/// requests AMORA already supports and maps them to a validated tool call that
/// runs against the real services. This keeps a weak local model (e.g. a 0.5B
/// Qwen) off the critical path for obvious commands, so it cannot echo the
/// instruction back, forget to call a tool, or mishandle units. Anything that is
/// not a clear local intent returns `nil`, and the caller falls back to the
/// model-driven agent loop.
///
/// It intentionally does NOT handle compound requests ("do X and Y") — those
/// stay on the existing model/compound path.
@MainActor
enum AmoraDeterministicRouter {

    /// Returns a validated tool-call decision for a clear supported request, or
    /// `nil` when the request should be handled by the model-driven loop.
    static func decision(for input: String) -> AmoraAgentDecision? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Compound requests keep the existing model/compound path.
        if AMORACommandGateway.isCompoundRequest(trimmed) { return nil }

        let n = AMORACommandParser.normalize(trimmed)
        guard !n.isEmpty else { return nil }

        // 0. Explicit memory commands (deterministic local routing)
        if let memoryCommand = AmoraMemoryCommandParser.shared.parse(trimmed) {
            switch memoryCommand {
            case .remember(let key, let value):
                return .toolCall(name: "remember_fact", arguments: ["key": key, "value": value])
            case .recall(let query):
                return .toolCall(name: "recall_memory", arguments: ["query": query])
            case .update(let target, let newValue):
                return .toolCall(name: "update_memory", arguments: ["key": target, "value": newValue])
            case .forget(let query):
                return .toolCall(name: "forget_memory", arguments: ["query": query])
            case .list:
                return .toolCall(name: "list_memories", arguments: [:])
            case .clearAll(let confirmed):
                return .toolCall(name: "clear_memories", arguments: ["confirmed": "\(confirmed)"])
            }
        }

        // 1. Note search ("find my notes about X") — before battery/app so that
        //    "...notes about battery" is treated as a search, not a battery read.
        if let query = noteSearchQuery(n) {
            return .toolCall(name: "search_notes", arguments: ["query": query])
        }

        // 2. Note creation ("add a note ..."). Uses the original text to preserve case.
        if let text = noteCreateText(original: trimmed) {
            return .toolCall(name: "notes.create", arguments: ["text": text])
        }

        // 3. Battery status question.
        if isBatteryStatusRequest(n) {
            return .toolCall(name: "get_battery_status", arguments: [:])
        }

        // 4. Known folder open ("open my downloads folder").
        if let location = folderLocation(n) {
            return .toolCall(name: "folder.open", arguments: ["location": location])
        }

        // 5. Reuse the existing single-action grammar for timer / media / app /
        //    workspace intents, mapping to the agent loop's tool names.
        if let action = AMORACommandGateway.parseSingleAction(from: trimmed) {
            return decision(from: action)
        }

        return nil
    }

    /// Maps a resolved `AmoraAction` to the agent loop's validated tool name/args.
    private static func decision(from action: AmoraAction) -> AmoraAgentDecision? {
        switch action {
        case .startTimer(let duration):
            // parseSingleAction already converts minutes/hours to seconds, so emit
            // seconds explicitly and let the tool treat it as seconds (no re-conversion).
            return .toolCall(name: "create_timer", arguments: ["seconds": "\(Int(duration))"])
        case .cancelTimer:
            return .toolCall(name: "timer.cancel", arguments: [:])
        case .pauseTimer:
            return .toolCall(name: "timer.pause", arguments: [:])
        case .resumeTimer:
            return .toolCall(name: "timer.resume", arguments: [:])
        case .playMusic:
            return .toolCall(name: "media.play", arguments: [:])
        case .pauseMusic:
            return .toolCall(name: "media.pause", arguments: [:])
        case .nextTrack:
            return .toolCall(name: "media.next", arguments: [:])
        case .previousTrack:
            return .toolCall(name: "media.previous", arguments: [:])
        case .openApplication(let name):
            return .toolCall(name: "app.open", arguments: ["name": name])
        case .openFolder(let location):
            return .toolCall(name: "folder.open", arguments: ["location": location])
        case .openWorkspace(let section):
            var args: [String: String] = [:]
            if let section, !section.isEmpty { args["section"] = section }
            return .toolCall(name: "workspace.open", arguments: args)
        case .confirmTest(let name, let prompt):
            return .toolCall(name: "system.confirm_test", arguments: ["name": name, "prompt": prompt])
        case .showNotification:
            return nil
        case .saveMemory(let key, let value):
            return .toolCall(name: "remember_fact", arguments: ["key": key, "value": value])
        case .updateMemory(let target, let newValue):
            return .toolCall(name: "update_memory", arguments: ["key": target, "value": newValue])
        case .forgetMemory(let query):
            return .toolCall(name: "forget_memory", arguments: ["query": query])
        case .clearMemories(let confirmed):
            return .toolCall(name: "clear_memories", arguments: ["confirmed": "\(confirmed)"])
        }
    }

    // MARK: - Battery

    private static func isBatteryStatusRequest(_ n: String) -> Bool {
        guard n.contains("battery") else { return false }
        if n == "battery" { return true }
        let cues = ["how much", "how is", "how s", "what", "whats", "what s",
                    "is my", "do i", "does", "show", "check", "tell me",
                    "left", "remaining", "status", "level", "percent",
                    "percentage", "charged", "charging", "power"]
        return cues.contains { n.contains($0) }
    }

    // MARK: - Folder (word-boundary matched to avoid "documentation" etc.)

    private static func folderLocation(_ n: String) -> String? {
        let verbs = ["open", "show", "go to", "reveal", "take me to", "navigate to", "browse", "bring up"]
        let hasVerb = verbs.contains { n.hasPrefix($0 + " ") || n == $0 }
        guard hasVerb else { return nil }
        let words = Set(n.split(separator: " ").map(String.init))
        if words.contains("downloads") || words.contains("download") { return "downloads" }
        if words.contains("documents") || words.contains("document") || words.contains("docs") { return "documents" }
        if words.contains("desktop") { return "desktop" }
        if n.contains("home folder") || n.contains("home directory") { return "home" }
        return nil
    }

    // MARK: - Note search

    private static func noteSearchQuery(_ n: String) -> String? {
        guard n.contains("note") else { return nil }
        let verbs = ["find", "search", "look up", "look for", "show me", "get"]
        let isSearch = verbs.contains { n.hasPrefix($0 + " ") } || n.contains("search notes") || n.contains("search my notes")
        guard isSearch else { return nil }

        let connectors = [" about ", " containing ", " contains ", " regarding ",
                          " mentioning ", " related to ", " matching ", " with ",
                          " for ", " on ", " that mention ", " that say ", " that says ", " saying "]
        for c in connectors {
            if let r = n.range(of: c) {
                let q = cleanupQuery(String(n[r.upperBound...]))
                if !q.isEmpty { return q }
            }
        }

        // "<query> notes" pattern (e.g. "find my meeting notes").
        if let notesRange = n.range(of: #"\bnotes?\b"#, options: .regularExpression) {
            var words = String(n[..<notesRange.lowerBound]).split(separator: " ").map(String.init)
            let leadStrips = ["find", "search", "look", "up", "for", "show", "me", "get", "my", "the", "all", "any"]
            while let first = words.first, leadStrips.contains(first) { words.removeFirst() }
            let before = cleanupQuery(words.joined(separator: " "))
            if !before.isEmpty { return before }
            let after = cleanupQuery(String(n[notesRange.upperBound...]))
            if !after.isEmpty { return after }
        }
        return nil
    }

    private static func cleanupQuery(_ raw: String) -> String {
        var q = raw.trimmingCharacters(in: .whitespaces)
        for t in ["notes", "note"] where q.hasSuffix(" " + t) {
            q = String(q.dropLast(t.count + 1)).trimmingCharacters(in: .whitespaces)
        }
        return q
    }

    // MARK: - Note creation (operates on original text to preserve case)

    private static func noteCreateText(original: String) -> String? {
        let lowered = original.lowercased()
        // Longest, most specific prefixes first so connectors are consumed.
        let prefixes = [
            "add a note that", "add a note saying", "add a note to say", "add a note:", "add a note",
            "add note that", "add note:", "add note",
            "save a note that", "save a note saying", "save a note:", "save a note",
            "save note that", "save note:", "save note",
            "create a note that", "create a note saying", "create a note:", "create a note",
            "create note:", "create note",
            "make a note that", "make a note saying", "make a note:", "make a note",
            "take a note that", "take a note:", "take a note",
            "write a note that", "write a note:", "write a note",
            "jot down that", "jot down", "new note:", "new note",
            "note to self that", "note to self:", "note to self", "note that", "note:"
        ]
        for p in prefixes where lowered.hasPrefix(p) {
            var remainder = String(original.dropFirst(p.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " :-\t"))
            let low = remainder.lowercased()
            for lc in ["that ", "saying ", "to say ", "about "] where low.hasPrefix(lc) {
                remainder = String(remainder.dropFirst(lc.count)).trimmingCharacters(in: .whitespaces)
                break
            }
            if !remainder.isEmpty { return remainder }
        }
        return nil
    }
}
