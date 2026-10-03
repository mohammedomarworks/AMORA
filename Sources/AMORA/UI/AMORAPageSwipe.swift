import Foundation

enum AMORAPageSwipe: Sendable {
    case previous
    case next

    static let directionKey = "direction"
}

extension Notification.Name {
    static let amoraPageSwipe = Notification.Name("AMORA.pageSwipe")
    static let amoraPageKeyboard = Notification.Name("AMORA.pageKeyboard")
}
