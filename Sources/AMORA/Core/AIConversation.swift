import Foundation

struct AIConversation: Sendable {
    let id = UUID()
    private(set) var messages: [AIMessage] = []
    private let maximumMessages = 12

    mutating func append(_ message: AIMessage) {
        messages.append(message)
        if messages.count > maximumMessages {
            messages.removeFirst(messages.count - maximumMessages)
        }
    }

    mutating func reset() { messages.removeAll() }
}

public enum AIContextComposer {
    /// Only attach facts that are clearly relevant to the request.
    @MainActor
    public static func relevantContext(
        for input: String,
        snapshot: AmoraContextSnapshot? = nil,
        conversationContext: AmoraConversationContext? = nil
    ) -> String? {
        let actualSnapshot = snapshot ?? AmoraContextProvider.shared.captureSnapshot()
        return composeRelevantContext(for: input, from: actualSnapshot, conversationContext: conversationContext)
    }

    public static func composeRelevantContext(
        for input: String,
        from snapshot: AmoraContextSnapshot,
        conversationContext: AmoraConversationContext? = nil
    ) -> String? {
        let normalized = AMORACommandParser.normalize(input)
        var facts: [String] = []

        // 0. Ephemeral Conversational Context (Follow-up understanding)
        if let conv = conversationContext, !conv.isEmpty {
            if let lastAction = conv.lastRelevantAction {
                facts.append("Last action: \(lastAction.humanReadableName)")
            }
            if let app = conv.lastReferencedApp {
                facts.append("Last referenced app: \(app)")
            }
            if let media = conv.lastReferencedMedia {
                var desc = media.source ?? "Media"
                if let title = media.title { desc += " (\"\(title)\")" }
                facts.append("Last referenced media: \(desc)")
            }
            if let timer = conv.activeTimerReference {
                let pausedStr = timer.isPaused == true ? " (paused)" : ""
                facts.append("Active timer reference: \(Int(timer.duration))s\(pausedStr)")
            }
            if let section = conv.currentWorkspaceSection {
                facts.append("Current Workspace section: \(section)")
            }
        }

        // 1. Current Application Context
        let asksApp = normalized.contains("what app") ||
            normalized.contains("what application") ||
            normalized.contains("which app") ||
            normalized.contains("active app") ||
            normalized.contains("current app") ||
            normalized.contains("frontmost") ||
            normalized.contains("what am i using") ||
            normalized.contains("what am i in") ||
            normalized.contains("what am i on") ||
            normalized.contains("what program") ||
            normalized.contains("active program") ||
            normalized.contains("what window")

        if asksApp, let app = snapshot.currentApplication {
            if let name = app.name, !name.isEmpty {
                let bundleStr = app.bundleIdentifier.map { " (bundleIdentifier: \($0))" } ?? ""
                facts.append("Current application: \(name)\(bundleStr)")
            } else if let bundle = app.bundleIdentifier, !bundle.isEmpty {
                facts.append("Current application: \(bundle)")
            }
        }

        // 2. Battery Context
        let asksBattery = normalized.contains("battery") ||
            normalized.contains("charge") ||
            normalized.contains("charging") ||
            normalized.contains("how much power") ||
            normalized.contains("power level")

        if asksBattery, let battery = snapshot.battery {
            if let percent = battery.percent {
                var desc = "\(percent)%"
                if battery.charging {
                    desc += ", charging"
                } else if battery.isPluggedIn == true {
                    desc += ", plugged in"
                }
                if let est = battery.estimate {
                    desc += ", \(est)"
                }
                facts.append("Current battery: \(desc)")
            } else {
                facts.append("Battery: Unavailable on this Mac")
            }
        }

        // 3. Timer Context
        let asksTimer = normalized.contains("timer") ||
            normalized.contains("time left") ||
            normalized.contains("time is left") ||
            normalized.contains("how much time") ||
            normalized.contains("remaining time") ||
            normalized.contains("study") ||
            normalized.contains("focus") ||
            normalized.contains("pomodoro")

        if asksTimer, let timer = snapshot.timer {
            if timer.running {
                let pausedStr = (timer.isPaused == true) ? ", paused" : ""
                let durationStr = timer.duration.map { " of \($0)s" } ?? ""
                facts.append("Active timer: \(timer.remainingSeconds) seconds remaining\(durationStr)\(pausedStr)")
            } else {
                facts.append("Active timer: None (timer is stopped)")
            }
        }

        // 4. Media Context
        let asksMedia = normalized.contains("music") ||
            normalized.contains("song") ||
            normalized.contains("track") ||
            normalized.contains("spotify") ||
            normalized.contains("apple music") ||
            normalized.contains("youtube") ||
            normalized.contains("playing") ||
            normalized.contains("media") ||
            normalized.contains("audio") ||
            normalized.contains("play") ||
            normalized.contains("pause")

        if asksMedia, let media = snapshot.media {
            if media.isPlaying {
                var desc = "Playing on \(media.source)"
                if let title = media.title {
                    desc += ": \"\(title)\""
                    if let artist = media.artist {
                        desc += " by \(artist)"
                    }
                }
                facts.append("Current music: \(desc)")
            } else if media.state.lowercased() == "paused" {
                var desc = "Paused on \(media.source)"
                if let title = media.title {
                    desc += ": \"\(title)\""
                }
                facts.append("Current music: \(desc)")
            } else {
                facts.append("Current music: None / inactive")
            }
        }

        // 5. AMORA UI Context
        let asksUI = normalized.contains("what state") ||
            normalized.contains("state are you in") ||
            normalized.contains("island state") ||
            normalized.contains("workspace state") ||
            normalized.contains("dynamic island") ||
            normalized.contains("amora state") ||
            normalized.contains("workspace") ||
            normalized.contains("dashboard")

        if asksUI, let amora = snapshot.amora {
            facts.append("AMORA Dynamic Island state: \(amora.state)")
        }

        // 6. File Shelf Context
        let asksShelf = normalized.contains("file shelf") ||
            normalized.contains("pinned files") ||
            normalized.contains("shelf count") ||
            normalized.contains("how many files")

        if asksShelf, let shelf = snapshot.fileShelf {
            let missingStr = shelf.missingItemCount.map { " (\($0) missing)" } ?? ""
            facts.append("File Shelf: \(shelf.itemCount) item\(shelf.itemCount == 1 ? "" : "s")\(missingStr)")
        }

        // 7. Date / Time Context
        let asksTime = normalized.contains("what time") ||
            normalized.contains("what date") ||
            normalized.contains("what day") ||
            normalized.contains("current time") ||
            normalized.contains("today's date")

        if asksTime, let time = snapshot.formattedLocalTime {
            facts.append("Current local time: \(time)")
        }

        // 8. General / Overview Context
        let asksOverview = normalized == "status" ||
            normalized == "overview" ||
            normalized == "summary" ||
            normalized == "what's going on" ||
            normalized == "whats going on" ||
            normalized == "system status"

        if asksOverview {
            if let app = snapshot.currentApplication?.name {
                facts.append("Frontmost app: \(app)")
            }
            if let battery = snapshot.battery?.percent {
                facts.append("Battery: \(battery)%")
            }
            if let timer = snapshot.timer, timer.running {
                facts.append("Timer: \(timer.remainingSeconds)s remaining")
            }
            if let media = snapshot.media, media.isPlaying {
                facts.append("Music: \(media.source) is playing")
            }
            if let amora = snapshot.amora {
                facts.append("AMORA state: \(amora.state)")
            }
        }

        return facts.isEmpty ? nil : "Relevant local context (use only if helpful):\n" + facts.joined(separator: "\n")
    }
}
