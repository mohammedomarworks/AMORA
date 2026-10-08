import Foundation

/// Reference to media tracked in ephemeral conversational context.
/// Only stores high-level metadata (provider/source, track title, artist, playback state).
/// NEVER stores clipboard contents, file contents, keystrokes, or screen data.
public struct AmoraMediaReference: Equatable, Codable, Sendable {
    public let source: String?
    public let title: String?
    public let artist: String?
    public let isPlaying: Bool?

    public init(
        source: String? = nil,
        title: String? = nil,
        artist: String? = nil,
        isPlaying: Bool? = nil
    ) {
        self.source = source
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
    }

    public static func from(mediaContext: AmoraMediaContext) -> AmoraMediaReference {
        AmoraMediaReference(
            source: mediaContext.source.lowercased() == "none" ? nil : mediaContext.source,
            title: mediaContext.title,
            artist: mediaContext.artist,
            isPlaying: mediaContext.isPlaying
        )
    }
}

/// Reference to a timer tracked in ephemeral conversational context.
public struct AmoraTimerReference: Equatable, Codable, Sendable {
    public let duration: TimeInterval
    public let remainingSeconds: Int?
    public let isPaused: Bool?

    public init(
        duration: TimeInterval,
        remainingSeconds: Int? = nil,
        isPaused: Bool? = nil
    ) {
        self.duration = duration
        self.remainingSeconds = remainingSeconds
        self.isPaused = isPaused
    }
}

/// Ephemeral conversational context layer for short-term follow-up understanding.
/// Strictly in-memory: NEVER persisted to disk, UserDefaults, or files.
/// Strictly limited to minimal state:
/// - last relevant action
/// - last referenced app
/// - last referenced media
/// - active timer reference
/// - current Workspace section
/// NEVER contains clipboard contents, file contents, keystrokes, or screen data.
public struct AmoraConversationContext: Equatable, Sendable {
    public var lastRelevantAction: AmoraAction?
    public var lastReferencedApp: String?
    public var lastReferencedMedia: AmoraMediaReference?
    public var activeTimerReference: AmoraTimerReference?
    public var currentWorkspaceSection: String?
    public var lastUpdatedAt: Date
    public var ttl: TimeInterval

    public init(
        lastRelevantAction: AmoraAction? = nil,
        lastReferencedApp: String? = nil,
        lastReferencedMedia: AmoraMediaReference? = nil,
        activeTimerReference: AmoraTimerReference? = nil,
        currentWorkspaceSection: String? = nil,
        lastUpdatedAt: Date = Date(),
        ttl: TimeInterval = 300 // 5 minutes default TTL
    ) {
        self.lastRelevantAction = lastRelevantAction
        self.lastReferencedApp = lastReferencedApp
        self.lastReferencedMedia = lastReferencedMedia
        self.activeTimerReference = activeTimerReference
        self.currentWorkspaceSection = currentWorkspaceSection
        self.lastUpdatedAt = lastUpdatedAt
        self.ttl = ttl
    }

    public static let empty = AmoraConversationContext()

    public var isEmpty: Bool {
        lastRelevantAction == nil &&
        lastReferencedApp == nil &&
        lastReferencedMedia == nil &&
        activeTimerReference == nil &&
        currentWorkspaceSection == nil
    }

    public func isExpired(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(lastUpdatedAt) > ttl
    }

    public mutating func reset() {
        lastRelevantAction = nil
        lastReferencedApp = nil
        lastReferencedMedia = nil
        activeTimerReference = nil
        currentWorkspaceSection = nil
        lastUpdatedAt = Date()
    }
}

/// Protocol-driven manager for ephemeral conversational context.
public protocol AmoraConversationContextManaging: AnyObject, Sendable {
    @MainActor var currentContext: AmoraConversationContext { get }
    @MainActor func recordAction(_ action: AmoraAction, date: Date?)
    @MainActor func recordCommand(_ command: AMORACommand, date: Date?)
    @MainActor func recordApp(_ app: String, date: Date?)
    @MainActor func recordMedia(_ media: AmoraMediaReference, date: Date?)
    @MainActor func recordTimer(_ timer: AmoraTimerReference?, date: Date?)
    @MainActor func recordWorkspaceSection(_ section: String?, date: Date?)
    @MainActor func reset()
    @MainActor func isExpired(at date: Date?) -> Bool
    @MainActor func validContext(at date: Date?) -> AmoraConversationContext?
}

/// Production implementation of ephemeral conversation context management.
/// Strictly in-memory, zero disk persistence.
@MainActor
public final class AmoraConversationContextManager: AmoraConversationContextManaging {
    public static let shared = AmoraConversationContextManager()

    public var ttl: TimeInterval
    public var dateProvider: @Sendable () -> Date

    private var _context: AmoraConversationContext

    public init(
        ttl: TimeInterval = 300,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.ttl = ttl
        self.dateProvider = dateProvider
        self._context = AmoraConversationContext(ttl: ttl)
    }

    public var currentContext: AmoraConversationContext {
        _context
    }

    public func isExpired(at date: Date? = nil) -> Bool {
        let checkDate = date ?? dateProvider()
        return _context.isExpired(at: checkDate)
    }

    public func validContext(at date: Date? = nil) -> AmoraConversationContext? {
        let checkDate = date ?? dateProvider()
        if _context.isEmpty { return nil }
        if _context.isExpired(at: checkDate) {
            _context.reset()
            return nil
        }
        return _context
    }

    public func recordAction(_ action: AmoraAction, date: Date? = nil) {
        let recordDate = date ?? dateProvider()
        _context.lastRelevantAction = action
        _context.lastUpdatedAt = recordDate

        switch action {
        case .openApplication(let name):
            _context.lastReferencedApp = name
        case .playMusic:
            _context.lastReferencedMedia = AmoraMediaReference(source: "Music", isPlaying: true)
        case .pauseMusic:
            _context.lastReferencedMedia = AmoraMediaReference(source: "Music", isPlaying: false)
        case .nextTrack, .previousTrack:
            _context.lastReferencedMedia = AmoraMediaReference(source: "Music", isPlaying: true)
        case .startTimer(let duration):
            _context.activeTimerReference = AmoraTimerReference(duration: duration, remainingSeconds: Int(duration), isPaused: false)
        case .cancelTimer:
            _context.activeTimerReference = nil
        case .pauseTimer:
            if let existing = _context.activeTimerReference {
                _context.activeTimerReference = AmoraTimerReference(duration: existing.duration, remainingSeconds: existing.remainingSeconds, isPaused: true)
            }
        case .resumeTimer:
            if let existing = _context.activeTimerReference {
                _context.activeTimerReference = AmoraTimerReference(duration: existing.duration, remainingSeconds: existing.remainingSeconds, isPaused: false)
            }
        case .openWorkspace(let section):
            if let section, !section.isEmpty {
                _context.currentWorkspaceSection = section
            }
        default:
            break
        }
    }

    public func recordCommand(_ command: AMORACommand, date: Date? = nil) {
        let recordDate = date ?? dateProvider()
        _context.lastUpdatedAt = recordDate

        switch command {
        case .startTimer(let duration):
            _context.lastRelevantAction = .startTimer(duration: duration)
            _context.activeTimerReference = AmoraTimerReference(duration: duration, remainingSeconds: Int(duration), isPaused: false)
        case .addTimerTime(let duration):
            if let existing = _context.activeTimerReference {
                let newDur = existing.duration + duration
                let newRem = (existing.remainingSeconds ?? Int(existing.duration)) + Int(duration)
                _context.activeTimerReference = AmoraTimerReference(duration: newDur, remainingSeconds: newRem, isPaused: existing.isPaused)
            } else {
                _context.activeTimerReference = AmoraTimerReference(duration: duration, remainingSeconds: Int(duration), isPaused: false)
            }
        case .stopTimer:
            _context.lastRelevantAction = .cancelTimer
            _context.activeTimerReference = nil
        case .pauseTimer:
            _context.lastRelevantAction = .pauseTimer
            if let existing = _context.activeTimerReference {
                _context.activeTimerReference = AmoraTimerReference(duration: existing.duration, remainingSeconds: existing.remainingSeconds, isPaused: true)
            }
        case .resumeTimer:
            _context.lastRelevantAction = .resumeTimer
            if let existing = _context.activeTimerReference {
                _context.activeTimerReference = AmoraTimerReference(duration: existing.duration, remainingSeconds: existing.remainingSeconds, isPaused: false)
            }
        case .playSpotify:
            _context.lastRelevantAction = .playMusic
            _context.lastReferencedApp = "Spotify"
            _context.lastReferencedMedia = AmoraMediaReference(source: "Spotify", isPlaying: true)
        case .pauseSpotify:
            _context.lastRelevantAction = .pauseMusic
            _context.lastReferencedApp = "Spotify"
            _context.lastReferencedMedia = AmoraMediaReference(source: "Spotify", isPlaying: false)
        case .nextSpotify, .previousSpotify:
            _context.lastReferencedApp = "Spotify"
            _context.lastReferencedMedia = AmoraMediaReference(source: "Spotify", isPlaying: true)
        case .playAppleMusic:
            _context.lastRelevantAction = .playMusic
            _context.lastReferencedApp = "Music"
            _context.lastReferencedMedia = AmoraMediaReference(source: "Apple Music", isPlaying: true)
        case .pauseAppleMusic:
            _context.lastRelevantAction = .pauseMusic
            _context.lastReferencedApp = "Music"
            _context.lastReferencedMedia = AmoraMediaReference(source: "Apple Music", isPlaying: false)
        case .playMusic:
            _context.lastRelevantAction = .playMusic
            _context.lastReferencedMedia = AmoraMediaReference(source: "Music", isPlaying: true)
        case .pauseMusic:
            _context.lastRelevantAction = .pauseMusic
            _context.lastReferencedMedia = AmoraMediaReference(source: "Music", isPlaying: false)
        case .nextTrack, .previousTrack:
            _context.lastReferencedMedia = AmoraMediaReference(source: "Music", isPlaying: true)
        case .openApplication(let name):
            _context.lastRelevantAction = .openApplication(name: name)
            _context.lastReferencedApp = name
        case .showDashboard:
            _context.lastRelevantAction = .openWorkspace(section: nil)
        case .showClipboard:
            _context.lastRelevantAction = .openWorkspace(section: "Clipboard")
            _context.currentWorkspaceSection = "Clipboard"
        case .showNotes:
            _context.lastRelevantAction = .openWorkspace(section: "Notes")
            _context.currentWorkspaceSection = "Notes"
        case .showFileShelf:
            _context.lastRelevantAction = .openWorkspace(section: "File Shelf")
            _context.currentWorkspaceSection = "File Shelf"
        case .showSystem:
            _context.lastRelevantAction = .openWorkspace(section: "Overview")
            _context.currentWorkspaceSection = "Overview"
        default:
            break
        }
    }

    public func recordApp(_ app: String, date: Date? = nil) {
        let recordDate = date ?? dateProvider()
        _context.lastReferencedApp = app
        _context.lastUpdatedAt = recordDate
    }

    public func recordMedia(_ media: AmoraMediaReference, date: Date? = nil) {
        let recordDate = date ?? dateProvider()
        _context.lastReferencedMedia = media
        _context.lastUpdatedAt = recordDate
    }

    public func recordTimer(_ timer: AmoraTimerReference?, date: Date? = nil) {
        let recordDate = date ?? dateProvider()
        _context.activeTimerReference = timer
        _context.lastUpdatedAt = recordDate
    }

    public func recordWorkspaceSection(_ section: String?, date: Date? = nil) {
        let recordDate = date ?? dateProvider()
        _context.currentWorkspaceSection = section
        _context.lastUpdatedAt = recordDate
    }

    public func reset() {
        _context.reset()
    }
}
