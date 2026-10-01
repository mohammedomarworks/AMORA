import AppKit
import Foundation
import Observation

struct ClipboardItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let timestamp: Date

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 60 {
            return String(trimmed.prefix(60)) + "…"
        }
        return trimmed
    }
}

@Observable @MainActor
final class ClipboardService {
    static let shared = ClipboardService()

    var history: [ClipboardItem] = []
    private var lastChangeCount: Int = 0
    private var pollTimer: Timer?

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
        checkClipboard()
        startPolling()
    }

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkClipboard()
            }
        }
    }

    func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Avoid duplicate if identical to top item
            if let first = history.first, first.text == string {
                return
            }

            let newItem = ClipboardItem(text: string, timestamp: Date())
            history.insert(newItem, at: 0)

            // Keep max 15 items
            if history.count > 15 {
                history.removeLast()
            }
        }
    }

    func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func clearHistory() {
        history.removeAll()
    }
}
