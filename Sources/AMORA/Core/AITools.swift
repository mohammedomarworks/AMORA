import Foundation

enum AMORATool: String, CaseIterable, Sendable {
    case battery
    case timer
    case music
    case notes
    case clipboard
    case file
    case system
    case application
}

enum AMORAToolOperation: Equatable, Sendable {
    case readBattery
    case startTimer(seconds: Int)
    case pauseTimer
    case openFolder(name: String)
}

struct AMORAToolRequest: Equatable, Sendable {
    let tool: AMORATool
    let operation: AMORAToolOperation
}

enum AMORAToolValidation: Equatable, Sendable {
    case allowed
    case needsConfirmation(prompt: String)
    case rejected(reason: String)
}

/// This is deliberately only validation architecture. AI cannot turn a tool
/// request into a shell command or select an operation outside this allowlist.
struct AMORAToolValidator: Sendable {
    func validate(_ request: AMORAToolRequest) -> AMORAToolValidation {
        switch request.operation {
        case .readBattery, .pauseTimer: return .allowed
        case let .startTimer(seconds):
            guard (1...86_400).contains(seconds) else { return .rejected(reason: "Timer duration is outside the supported range.") }
            return .allowed
        case let .openFolder(name):
            let allowed = ["downloads", "documents", "desktop"]
            guard allowed.contains(AMORACommandParser.normalize(name)) else { return .rejected(reason: "That folder is not available through AMORA.") }
            return .needsConfirmation(prompt: "Would you like me to open \(name.capitalized)?")
        }
    }
}
