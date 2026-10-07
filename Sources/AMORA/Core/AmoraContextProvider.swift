import AppKit
import Foundation
import Observation

// MARK: - Component Protocols

public protocol AmoraApplicationDetecting: Sendable {
    @MainActor func currentApplication() -> AmoraApplicationContext?
}

public protocol AmoraMediaContextProvider: Sendable {
    @MainActor func currentMediaContext() -> AmoraMediaContext
}

public protocol AmoraTimerContextProvider: Sendable {
    @MainActor func currentTimerContext() -> AmoraTimerContext
}

public protocol AmoraBatteryContextProvider: Sendable {
    @MainActor func currentBatteryContext() -> AmoraBatteryContext
}

public protocol AmoraUIContextProvider: Sendable {
    @MainActor func currentUIContext() -> AmoraUIContext
}

public protocol AmoraFileShelfContextProvider: Sendable {
    @MainActor func currentFileShelfContext() -> AmoraFileShelfContext
}

// MARK: - Native Application Detector

@MainActor
public final class NativeAmoraApplicationDetector: AmoraApplicationDetecting {
    public static let shared = NativeAmoraApplicationDetector()

    public init() {}

    private func isAmora(_ app: NSRunningApplication) -> Bool {
        if app.processIdentifier == NSRunningApplication.current.processIdentifier {
            return true
        }
        if let bundleId = app.bundleIdentifier, bundleId == Bundle.main.bundleIdentifier {
            return true
        }
        return false
    }

    private func isValidExternal(_ app: NSRunningApplication?) -> Bool {
        guard let app, !app.isTerminated else { return false }
        return !isAmora(app)
    }

    public func currentApplication() -> AmoraApplicationContext? {
        // 1. If an external application is currently frontmost:
        if let frontmost = NSWorkspace.shared.frontmostApplication, isValidExternal(frontmost) {
            return AmoraApplicationContext(
                name: frontmost.localizedName,
                bundleIdentifier: frontmost.bundleIdentifier
            )
        }

        // 2. If AMORA is frontmost (e.g. user clicked island / workspace), check the menu bar owning app:
        if let menuBarApp = NSWorkspace.shared.menuBarOwningApplication, isValidExternal(menuBarApp) {
            return AmoraApplicationContext(
                name: menuBarApp.localizedName,
                bundleIdentifier: menuBarApp.bundleIdentifier
            )
        }

        // 3. Fallback to frontmost app if AMORA itself is active and no external app is found:
        if let frontmost = NSWorkspace.shared.frontmostApplication, !frontmost.isTerminated {
            return AmoraApplicationContext(
                name: frontmost.localizedName ?? "AMORA",
                bundleIdentifier: frontmost.bundleIdentifier ?? Bundle.main.bundleIdentifier
            )
        }

        return nil
    }
}

// MARK: - Default Context Providers

@MainActor
public struct DefaultAmoraMediaContextProvider: AmoraMediaContextProvider {
    public init() {}

    public func currentMediaContext() -> AmoraMediaContext {
        let music = MusicService.shared
        guard music.source != .none else {
            return .inactive
        }

        let isPlaying = music.isPlaying
        let isAvailable = music.isAvailable
        let rawTitle = music.trackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasRealTitle = !rawTitle.isEmpty && rawTitle != "No Media Playing"
        let artist = music.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasRealArtist = !artist.isEmpty

        if !isPlaying && !isAvailable && !hasRealTitle {
            return .inactive
        }

        let stateString: String
        if isPlaying {
            stateString = "playing"
        } else if isAvailable {
            stateString = "paused"
        } else {
            stateString = "stopped"
        }

        return AmoraMediaContext(
            source: music.source.displayName,
            state: stateString,
            title: hasRealTitle ? rawTitle : nil,
            artist: hasRealArtist ? artist : nil
        )
    }
}

@MainActor
public struct DefaultAmoraTimerContextProvider: AmoraTimerContextProvider {
    public init() {}

    public func currentTimerContext() -> AmoraTimerContext {
        let timer = TimerService.shared
        guard timer.isRunning else {
            return .stopped
        }
        return AmoraTimerContext(
            running: true,
            remainingSeconds: timer.remainingSeconds,
            duration: timer.totalSeconds > 0 ? timer.totalSeconds : nil,
            isPaused: timer.isPaused
        )
    }
}

@MainActor
public struct DefaultAmoraBatteryContextProvider: AmoraBatteryContextProvider {
    public init() {}

    public func currentBatteryContext() -> AmoraBatteryContext {
        let battery = BatteryService.shared
        guard battery.hasBattery else {
            return .unavailable
        }

        let estimate: String?
        if case let .estimated(minutes) = battery.estimateState, minutes > 0 {
            let hours = minutes / 60
            let mins = minutes % 60
            estimate = "\(hours)h \(mins)m remaining"
        } else {
            estimate = nil
        }

        return AmoraBatteryContext(
            percent: battery.level,
            charging: battery.isCharging,
            isPluggedIn: battery.isPluggedIn,
            estimate: estimate
        )
    }
}

@MainActor
public struct DefaultAmoraUIContextProvider: AmoraUIContextProvider {
    public init() {}

    public func currentUIContext() -> AmoraUIContext {
        let targetState = IslandModel.shared.targetState
        let stateString: String
        switch targetState {
        case .collapsed:
            stateString = "collapsed"
        case .quick:
            stateString = "quick island"
        case .workspace:
            stateString = "workspace"
        }
        return AmoraUIContext(state: stateString)
    }
}

@MainActor
public struct DefaultAmoraFileShelfContextProvider: AmoraFileShelfContextProvider {
    public init() {}

    public func currentFileShelfContext() -> AmoraFileShelfContext {
        let items = FileShelfService.shared.items
        let missing = items.filter(\.isMissing).count
        return AmoraFileShelfContext(
            itemCount: items.count,
            missingItemCount: missing > 0 ? missing : nil
        )
    }
}

// MARK: - Central Context Coordinator

@Observable @MainActor
public final class AmoraContextProvider {
    public static let shared = AmoraContextProvider()

    public var appDetector: any AmoraApplicationDetecting
    public var mediaProvider: any AmoraMediaContextProvider
    public var timerProvider: any AmoraTimerContextProvider
    public var batteryProvider: any AmoraBatteryContextProvider
    public var uiProvider: any AmoraUIContextProvider
    public var fileShelfProvider: any AmoraFileShelfContextProvider

    private var _cachedSnapshot: AmoraContextSnapshot?

    public var currentSnapshot: AmoraContextSnapshot {
        get {
            if let cached = _cachedSnapshot {
                return cached
            }
            return captureSnapshot()
        }
        set {
            _cachedSnapshot = newValue
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    public init(
        appDetector: any AmoraApplicationDetecting = NativeAmoraApplicationDetector.shared,
        mediaProvider: any AmoraMediaContextProvider = DefaultAmoraMediaContextProvider(),
        timerProvider: any AmoraTimerContextProvider = DefaultAmoraTimerContextProvider(),
        batteryProvider: any AmoraBatteryContextProvider = DefaultAmoraBatteryContextProvider(),
        uiProvider: any AmoraUIContextProvider = DefaultAmoraUIContextProvider(),
        fileShelfProvider: any AmoraFileShelfContextProvider = DefaultAmoraFileShelfContextProvider()
    ) {
        self.appDetector = appDetector
        self.mediaProvider = mediaProvider
        self.timerProvider = timerProvider
        self.batteryProvider = batteryProvider
        self.uiProvider = uiProvider
        self.fileShelfProvider = fileShelfProvider
        self._cachedSnapshot = nil
    }

    @discardableResult
    public func captureSnapshot() -> AmoraContextSnapshot {
        let now = Date()
        let snapshot = AmoraContextSnapshot(
            timestamp: now,
            currentApplication: appDetector.currentApplication(),
            media: mediaProvider.currentMediaContext(),
            timer: timerProvider.currentTimerContext(),
            battery: batteryProvider.currentBatteryContext(),
            amora: uiProvider.currentUIContext(),
            fileShelf: fileShelfProvider.currentFileShelfContext(),
            formattedLocalTime: Self.timeFormatter.string(from: now)
        )
        self._cachedSnapshot = snapshot
        return snapshot
    }

    func handleEvent(_ event: AMORAEvent) {
        // Invalidate cached snapshot on state change so subsequent context queries refresh freshly
        _cachedSnapshot = nil
    }
}

