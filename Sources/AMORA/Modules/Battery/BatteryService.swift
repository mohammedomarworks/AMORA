import Foundation
import IOKit.ps
import Observation

@Observable @MainActor
final class BatteryService {
    static let shared = BatteryService()

    var level: Int = 100
    var isCharging: Bool = false
    var isPluggedIn: Bool = true
    var timeRemainingFormatted: String = ""
    var hasBattery: Bool = true

    private var timer: Timer?
    /// The first `refresh()` only establishes a baseline; events fire on the
    /// transitions detected on subsequent refreshes so we never alarm on launch.
    private var hasBaseline = false

    private init() {
        refresh()
        startMonitoring()
    }

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    func refresh() {
        let oldLevel = level
        let oldCharging = isCharging
        let hadBaseline = hasBaseline

        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            hasBattery = false
            level = 100
            isPluggedIn = true
            isCharging = false
            hasBaseline = true
            return
        }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            if let current = desc[kIOPSCurrentCapacityKey as String] as? Int,
               let max = desc[kIOPSMaxCapacityKey as String] as? Int, max > 0 {
                hasBattery = true
                level = Int((Double(current) / Double(max)) * 100)
            }

            if let charging = desc[kIOPSIsChargingKey as String] as? Bool {
                isCharging = charging
            }

            if let state = desc[kIOPSPowerSourceStateKey as String] as? String {
                isPluggedIn = (state == (kIOPSACPowerValue as String))
            }

            if let timeRemaining = desc[kIOPSTimeToEmptyKey as String] as? Int, timeRemaining > 0 {
                let hours = timeRemaining / 60
                let minutes = timeRemaining % 60
                timeRemainingFormatted = "\(hours)h \(minutes)m remaining"
            } else if isCharging {
                timeRemainingFormatted = "Charging"
            } else {
                timeRemainingFormatted = isPluggedIn ? "On AC Power" : "On Battery"
            }
            break
        }

        detectBatteryEvents(oldLevel: oldLevel, oldCharging: oldCharging, hadBaseline: hadBaseline)
        hasBaseline = true
    }

    /// Fire personality events only on meaningful threshold crossings, so AMORA
    /// reacts once when something changes rather than nagging on every poll.
    private func detectBatteryEvents(oldLevel: Int, oldCharging: Bool, hadBaseline: Bool) {
        guard hadBaseline, hasBattery else { return }
        let engine = PersonalityEngine.shared

        if isCharging && !oldCharging {
            engine.react(to: .charging)
        }
        if isPluggedIn && level >= 100 && oldLevel < 100 {
            engine.react(to: .chargedFull)
        }
        if !isCharging && !isPluggedIn {
            if level <= 10 && oldLevel > 10 {
                engine.react(to: .criticalBattery)
            } else if level <= 20 && oldLevel > 20 {
                engine.react(to: .lowBattery)
            }
        }
    }
}
