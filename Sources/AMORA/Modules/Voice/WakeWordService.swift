import Foundation
import Observation
import AVFoundation

@Observable @MainActor
final class WakeWordService {
    static let shared = WakeWordService()

    private(set) var state: WakeWordState = .disabled
    private(set) var lastDetectionTime: Date?
    private(set) var lastErrorMessage: String?
    private(set) var activeEngine: any AmoraWakeWordEngine

    var eventSink: any AmoraEventSinking
    var onWakeWordActivated: (@MainActor (WakeWordDetectionResult) async -> Void)?
    private var isManuallyPaused: Bool = false

    var isStandby: Bool {
        if case .standby = state { return true }
        return false
    }

    var isCapturingAudio: Bool {
        state.isCapturingAudio
    }

    init(
        engine: (any AmoraWakeWordEngine)? = nil,
        eventSink: any AmoraEventSinking = MacOSAmoraEventSink(),
        onWakeWordActivated: (@MainActor (WakeWordDetectionResult) async -> Void)? = nil
    ) {
        self.activeEngine = engine ?? NativeAcousticWakeWordEngine()
        self.eventSink = eventSink
        self.onWakeWordActivated = onWakeWordActivated ?? { result in
            await VoiceCommandService.shared.startListening(
                initialBuffers: result.bufferedAudio,
                isWakeWordActivation: true
            )
        }
    }

    func configure(engine: any AmoraWakeWordEngine) {
        let wasRunning = isStandby
        if wasRunning {
            activeEngine.stop()
        }
        self.activeEngine = engine
        if wasRunning {
            startIfEnabled()
        }
    }

    func startIfEnabled() {
        let settings = AppState.shared.settings
        guard settings.wakeWordEnabled else {
            stop()
            return
        }

        guard !isManuallyPaused else {
            state = .paused
            return
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard micStatus == .authorized else {
            if micStatus == .denied {
                state = .unauthorized(description: "Microphone permission is denied. Enable access in System Settings > Privacy & Security > Microphone.")
            } else if micStatus == .restricted {
                state = .unauthorized(description: "Microphone access is restricted on this Mac.")
            } else {
                state = .unauthorized(description: "Microphone permission required for hands-free wake word.")
            }
            return
        }

        guard activeEngine.isAvailable else {
            state = .unavailable(reason: "\(activeEngine.engineName) is currently unavailable.")
            return
        }

        do {
            try activeEngine.start(
                onWakeWordDetected: { [weak self] result in
                    self?.handleWakeWordDetected(result)
                },
                onError: { [weak self] error in
                    self?.handleError(error)
                }
            )
            state = .standby(engineName: activeEngine.engineName)
            lastErrorMessage = nil
        } catch {
            state = .failed(message: error.localizedDescription)
            lastErrorMessage = error.localizedDescription
            eventSink.emit(.aiFailed)
        }
    }

    func stop() {
        activeEngine.stop()
        state = .disabled
        isManuallyPaused = false
    }

    func pause() {
        isManuallyPaused = true
        activeEngine.pause()
        state = .paused
    }

    func resume() {
        isManuallyPaused = false
        if AppState.shared.settings.wakeWordEnabled {
            activeEngine.resume()
            if activeEngine.isListening {
                state = .standby(engineName: activeEngine.engineName)
            } else {
                startIfEnabled()
            }
        } else {
            state = .disabled
        }
    }

    func handleWakeWordDetected(_ result: WakeWordDetectionResult) {
        guard isStandby else { return }
        lastDetectionTime = result.timestamp
        state = .detecting(timestamp: result.timestamp)

        AppState.shared.stateManager.transition(to: .listening)
        AMORARobot.shared.updateExpression(for: .listening)

        activeEngine.pause()
        state = .activeVoiceSession

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let onWakeWordActivated = self.onWakeWordActivated {
                await onWakeWordActivated(result)
            } else {
                await VoiceCommandService.shared.startListening(
                    initialBuffers: result.bufferedAudio,
                    isWakeWordActivation: true
                )
            }
        }
    }

    func notifyVoiceSessionEnded() {
        guard AppState.shared.settings.wakeWordEnabled, !isManuallyPaused else {
            if isManuallyPaused {
                state = .paused
            } else {
                state = .disabled
            }
            return
        }

        activeEngine.resume()
        if activeEngine.isListening {
            state = .standby(engineName: activeEngine.engineName)
        } else {
            startIfEnabled()
        }
    }

    func handleError(_ error: Error) {
        state = .failed(message: error.localizedDescription)
        lastErrorMessage = error.localizedDescription
    }
}
