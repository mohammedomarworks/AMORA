import Foundation
import Observation

@Observable @MainActor
final class VoiceCommandService {
    static let shared = VoiceCommandService()
    static var isAnyListening: Bool { activeListeningCount > 0 }
    private static var activeListeningCount: Int = 0

    private(set) var engine: any AmoraSpeechEngine
    private(set) var state: VoiceCommandState = .ready
    private(set) var currentTranscript: String = ""
    private(set) var audioLevel: Float = 0.0
    private(set) var lastErrorMessage: String?
    private(set) var lastResponseMessage: String?
    private(set) var isEngineOnDevice: Bool = false

    var assistant: AssistantManager
    var eventSink: any AmoraEventSinking

    // Configurable timeouts
    var silenceTimeoutSeconds: TimeInterval = 1.8
    var maxSessionDurationSeconds: TimeInterval = 30.0

    // Internal tasks
    private var silenceTask: Task<Void, Never>?
    private var maxSessionTask: Task<Void, Never>?
    private var feedbackResetTask: Task<Void, Never>?
    private var hasSubmittedCurrentSession: Bool = false
    private var activeSubmissionTask: Task<String, Never>?

    var isListening: Bool {
        if case .listening = state { return true }
        return false
    }

    var isProcessing: Bool {
        if case .processing = state { return true }
        return false
    }

    init(
        engine: (any AmoraSpeechEngine)? = nil,
        assistant: AssistantManager = .shared,
        eventSink: any AmoraEventSinking = MacOSAmoraEventSink()
    ) {
        self.engine = engine ?? AppleSpeechEngine()
        self.assistant = assistant
        self.eventSink = eventSink
    }

    func configure(engine: any AmoraSpeechEngine) {
        self.engine = engine
    }

    func startListening() async {
        guard !isListening && !isProcessing else { return }
        feedbackResetTask?.cancel()
        feedbackResetTask = nil
        lastErrorMessage = nil
        lastResponseMessage = nil
        currentTranscript = ""
        audioLevel = 0.0
        hasSubmittedCurrentSession = false

        // 1. Permission check & request
        let permission = await engine.requestPermissions()
        switch permission {
        case .authorized:
            break
        case .denied(let description):
            state = .permissionDenied(reason: description)
            lastErrorMessage = description
            eventSink.emit(.aiFailed)
            AMORARobot.shared.updateExpression(for: .concerned)
            return
        case .restricted(let description):
            state = .unavailable(reason: description)
            lastErrorMessage = description
            eventSink.emit(.aiFailed)
            AMORARobot.shared.updateExpression(for: .concerned)
            return
        case .speechUnavailable(let description):
            state = .unavailable(reason: description)
            lastErrorMessage = description
            eventSink.emit(.aiFailed)
            AMORARobot.shared.updateExpression(for: .concerned)
            return
        case .notDetermined:
            state = .ready
            return
        }

        // 2. Engine availability
        guard engine.isAvailable else {
            let msg = "Speech recognition is currently unavailable on this Mac."
            state = .unavailable(reason: msg)
            lastErrorMessage = msg
            eventSink.emit(.aiFailed)
            AMORARobot.shared.updateExpression(for: .concerned)
            return
        }

        // 3. Start recognition
        let preferOnDevice = AppState.shared.settings.preferOnDeviceRecognition
        do {
            try engine.startListening(
                preferOnDevice: preferOnDevice,
                onPartialResult: { [weak self] partial in
                    self?.handlePartialResult(partial)
                },
                onFinalResult: { [weak self] final in
                    self?.handleFinalResult(final)
                },
                onAudioLevel: { [weak self] level in
                    self?.handleAudioLevel(level)
                },
                onError: { [weak self] error in
                    self?.handleError(error)
                }
            )

            isEngineOnDevice = engine.supportsOnDeviceRecognition && preferOnDevice
            state = .listening(audioLevel: 0.0, partialTranscript: "")
            Self.activeListeningCount += 1

            AppState.shared.stateManager.transition(to: .listening)
            AMORARobot.shared.updateExpression(for: .listening)

            startMaxSessionTimer()
        } catch {
            let msg = error.localizedDescription
            state = .failed(message: msg)
            lastErrorMessage = msg
            eventSink.emit(.aiFailed)
            AMORARobot.shared.updateExpression(for: .concerned)
        }
    }

    func stopAndSubmit() {
        guard isListening else { return }
        decrementListeningCount()
        silenceTask?.cancel()
        silenceTask = nil
        maxSessionTask?.cancel()
        maxSessionTask = nil

        engine.stopListening()

        let trimmed = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            state = .ready
            PersonalityEngine.shared.restoreAmbientState()
            return
        }

        submitUtterance(trimmed)
    }

    func cancelListening() {
        if isListening {
            decrementListeningCount()
        }
        silenceTask?.cancel()
        silenceTask = nil
        maxSessionTask?.cancel()
        maxSessionTask = nil
        activeSubmissionTask?.cancel()
        activeSubmissionTask = nil

        engine.cancelListening()

        state = .cancelled
        currentTranscript = ""
        audioLevel = 0.0
        PersonalityEngine.shared.restoreAmbientState()

        feedbackResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if self?.state == .cancelled {
                self?.state = .ready
            }
        }
    }

    private func decrementListeningCount() {
        Self.activeListeningCount = max(0, Self.activeListeningCount - 1)
    }

    func handlePartialResult(_ partial: String) {
        guard isListening else { return }
        currentTranscript = partial
        state = .listening(audioLevel: audioLevel, partialTranscript: partial)
        resetSilenceTimer()
    }

    func handleFinalResult(_ final: String) {
        silenceTask?.cancel()
        silenceTask = nil
        maxSessionTask?.cancel()
        maxSessionTask = nil

        let trimmed = final.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            currentTranscript = trimmed
        }
        submitUtterance(currentTranscript)
    }

    func handleAudioLevel(_ level: Float) {
        guard isListening else { return }
        audioLevel = level
        state = .listening(audioLevel: level, partialTranscript: currentTranscript)
    }

    func handleError(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 209) {
            return
        }
        if nsError.domain == "kLSRErrorDomain" && nsError.code == 201 {
            return
        }

        guard isListening else { return }
        decrementListeningCount()
        silenceTask?.cancel()
        silenceTask = nil
        maxSessionTask?.cancel()
        maxSessionTask = nil

        let msg = error.localizedDescription
        state = .failed(message: msg)
        lastErrorMessage = msg
        eventSink.emit(.aiFailed)
        AMORARobot.shared.updateExpression(for: .concerned)

        feedbackResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if case .failed = self?.state {
                self?.state = .ready
                PersonalityEngine.shared.restoreAmbientState()
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTask?.cancel()
        guard !currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        silenceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.silenceTimeoutSeconds * 1_000_000_000))
            if !Task.isCancelled && self.isListening {
                self.stopAndSubmit()
            }
        }
    }

    private func startMaxSessionTimer() {
        maxSessionTask?.cancel()
        maxSessionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.maxSessionDurationSeconds * 1_000_000_000))
            if !Task.isCancelled && self.isListening {
                if !self.currentTranscript.isEmpty {
                    self.stopAndSubmit()
                } else {
                    self.cancelListening()
                }
            }
        }
    }

    func submitUtterance(_ utterance: String) {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .ready
            PersonalityEngine.shared.restoreAmbientState()
            return
        }

        guard !hasSubmittedCurrentSession else { return }
        hasSubmittedCurrentSession = true

        state = .processing(transcript: trimmed)
        AppState.shared.stateManager.transition(to: .aiThinking)
        AMORARobot.shared.updateExpression(for: .aiThinking)

        activeSubmissionTask = Task { @MainActor [weak self] in
            guard let self else { return "" }
            let answer = await self.assistant.submit(trimmed, settings: AppState.shared.settings.aiSettingsSnapshot)
            self.lastResponseMessage = answer
            self.state = .completed(transcript: trimmed, message: answer)

            self.feedbackResetTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                if case .completed = self?.state {
                    self?.state = .ready
                    PersonalityEngine.shared.restoreAmbientState()
                }
            }
            return answer
        }
    }
}
