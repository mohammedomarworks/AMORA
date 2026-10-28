import Foundation
import Observation
import AVFoundation

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
    private(set) var isWakeWordActivation: Bool = false

    var assistant: AssistantManager
    var eventSink: any AmoraEventSinking
    var onVoiceSessionEnded: (@MainActor () -> Void)? = {
        WakeWordService.shared.notifyVoiceSessionEnded()
    }

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
        await startListening(initialBuffers: [], isWakeWordActivation: false)
    }

    func startListening(
        initialBuffers: [AVAudioPCMBuffer],
        isWakeWordActivation: Bool
    ) async {
        guard !isListening && !isProcessing else { return }
        self.isWakeWordActivation = isWakeWordActivation
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
                initialBuffers: initialBuffers,
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

        let trimmed = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let processed = isWakeWordActivation ? Self.stripLeadingWakeWord(from: trimmed) : trimmed

        // If triggered by wake-word and user hasn't said their command yet, stay listening
        if isWakeWordActivation && processed.isEmpty {
            return
        }

        decrementListeningCount()
        silenceTask?.cancel()
        silenceTask = nil
        maxSessionTask?.cancel()
        maxSessionTask = nil

        engine.stopListening()

        if processed.isEmpty {
            state = .ready
            isWakeWordActivation = false
            PersonalityEngine.shared.restoreAmbientState()
            onVoiceSessionEnded?()
            return
        }

        submitUtterance(processed)
    }

    func cancelListening() {
        if isListening {
            decrementListeningCount()
        }
        isWakeWordActivation = false
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
        onVoiceSessionEnded?()

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
        let processed = isWakeWordActivation ? Self.stripLeadingWakeWord(from: currentTranscript) : currentTranscript
        if isWakeWordActivation && processed.isEmpty {
            decrementListeningCount()
            engine.stopListening()
            state = .ready
            isWakeWordActivation = false
            PersonalityEngine.shared.restoreAmbientState()
            onVoiceSessionEnded?()
            return
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
        isWakeWordActivation = false
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
                self?.onVoiceSessionEnded?()
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTask?.cancel()
        let trimmed = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let processed = isWakeWordActivation ? Self.stripLeadingWakeWord(from: trimmed) : trimmed
        guard !processed.isEmpty else { return }

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
        let processed = isWakeWordActivation ? Self.stripLeadingWakeWord(from: trimmed) : trimmed

        guard !processed.isEmpty else {
            if isListening {
                return
            }
            state = .ready
            isWakeWordActivation = false
            PersonalityEngine.shared.restoreAmbientState()
            onVoiceSessionEnded?()
            return
        }

        guard !hasSubmittedCurrentSession else { return }
        hasSubmittedCurrentSession = true
        isWakeWordActivation = false

        state = .processing(transcript: processed)
        AppState.shared.stateManager.transition(to: .aiThinking)
        AMORARobot.shared.updateExpression(for: .aiThinking)

        activeSubmissionTask = Task { @MainActor [weak self] in
            guard let self else { return "" }
            let answer = await self.assistant.submit(processed, settings: AppState.shared.settings.aiSettingsSnapshot)
            self.lastResponseMessage = answer
            self.state = .completed(transcript: processed, message: answer)

            self.feedbackResetTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                if case .completed = self?.state {
                    self?.state = .ready
                    PersonalityEngine.shared.restoreAmbientState()
                    self?.onVoiceSessionEnded?()
                }
            }
            return answer
        }
    }

    static func stripLeadingWakeWord(from transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let pattern = "^(?i)(?:(?:hey|ok|okay|hi)\\s+)?amora[\\s,\\.\\!\\?\\:\\-]*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return trimmed
        }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let stripped = regex.stringByReplacingMatches(in: trimmed, options: [], range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
