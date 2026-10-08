import Foundation
import Observation
import AppKit

@Observable @MainActor
final class TimerService {
    static let shared = TimerService()

    var totalSeconds: Int = 0
    var remainingSeconds: Int = 0
    var isRunning: Bool = false
    var isPaused: Bool = false

    private var timer: Timer?

    private init() {}

    var progress: Double {
        guard totalSeconds > 0 else { return 0.0 }
        return Double(remainingSeconds) / Double(totalSeconds)
    }

    var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func startTimer(minutes: Int) {
        startTimer(seconds: minutes * 60)
    }

    func startTimer(seconds: Int) {
        stopTimer()
        self.totalSeconds = seconds
        self.remainingSeconds = seconds
        self.isRunning = true
        self.isPaused = false

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }

        AMORAEventCenter.shared.emit(.timerStarted)
    }

    func pauseTimer() {
        if isRunning && !isPaused {
            isPaused = true
            timer?.invalidate()
            timer = nil
            AMORAEventCenter.shared.emit(.timerPaused)
        }
    }

    func resumeTimer() {
        if isRunning && isPaused {
            isPaused = false
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.tick()
                }
            }
            AMORAEventCenter.shared.emit(.timerResumed)
        }
    }

    func addTime(seconds: Int) {
        guard seconds > 0, isRunning else { return }
        totalSeconds += seconds
        remainingSeconds += seconds
        AMORAContext.shared.refreshFromServices()
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isPaused = false
        remainingSeconds = 0
        totalSeconds = 0
    }

    private func tick() {
        if remainingSeconds > 0 {
            remainingSeconds -= 1
            if remainingSeconds == 60 {
                AMORAEventCenter.shared.emit(.timerNearlyFinished)
            }
            AMORAContext.shared.refreshFromServices()
        } else {
            timerFinished()
        }
    }

    private func timerFinished() {
        stopTimer()
        // Route the completion through the personality engine so the message,
        // sound, expression, and celebration bounce all stay in one place.
        AMORAEventCenter.shared.emit(.timerCompleted)
        AMORARobot.shared.playBounce()
    }
}
