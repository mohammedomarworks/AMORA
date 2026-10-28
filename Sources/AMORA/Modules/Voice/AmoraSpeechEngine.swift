import Foundation
import Speech
import AVFoundation

@MainActor
protocol AmoraSpeechEngine: AnyObject {
    var isAvailable: Bool { get }
    var supportsOnDeviceRecognition: Bool { get }
    var isListening: Bool { get }
    var recognitionModeDescription: String { get }

    func checkPermissions() -> AmoraVoicePermissionState
    func requestPermissions() async -> AmoraVoicePermissionState

    func startListening(
        preferOnDevice: Bool,
        onPartialResult: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (String) -> Void,
        onAudioLevel: @escaping @MainActor (Float) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) throws

    func stopListening()
    func cancelListening()
}

// MARK: - Native Apple Speech Recognition Engine

@MainActor
final class AppleSpeechEngine: AmoraSpeechEngine {
    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private(set) var isListening: Bool = false

    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    var supportsOnDeviceRecognition: Bool {
        speechRecognizer?.supportsOnDeviceRecognition ?? false
    }

    var recognitionModeDescription: String {
        if supportsOnDeviceRecognition {
            return "On-Device (Private)"
        } else {
            return "Apple Speech"
        }
    }

    init(locale: Locale = .current) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func checkPermissions() -> AmoraVoicePermissionState {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let speech = SFSpeechRecognizer.authorizationStatus()

        if mic == .denied {
            return .denied(description: "Microphone permission is denied. Enable it in System Settings > Privacy & Security > Microphone.")
        }
        if speech == .denied {
            return .denied(description: "Speech Recognition permission is denied. Enable it in System Settings > Privacy & Security > Speech Recognition.")
        }
        if mic == .restricted || speech == .restricted {
            return .restricted(description: "Microphone or Speech Recognition access is restricted by system policy.")
        }
        if mic == .authorized && speech == .authorized {
            return .authorized
        }
        return .notDetermined
    }

    func requestPermissions() async -> AmoraVoicePermissionState {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let micGranted: Bool
        if micStatus == .notDetermined {
            micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            micGranted = (micStatus == .authorized)
        }

        guard micGranted else {
            return .denied(description: "Microphone permission is denied. Enable it in System Settings > Privacy & Security > Microphone.")
        }

        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let speechAuth: SFSpeechRecognizerAuthorizationStatus
        if speechStatus == .notDetermined {
            speechAuth = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        } else {
            speechAuth = speechStatus
        }

        switch speechAuth {
        case .authorized:
            return .authorized
        case .denied:
            return .denied(description: "Speech Recognition permission is denied. Enable it in System Settings > Privacy & Security > Speech Recognition.")
        case .restricted:
            return .restricted(description: "Speech Recognition access is restricted on this Mac.")
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .speechUnavailable(description: "Speech recognition is unavailable.")
        }
    }

    func startListening(
        preferOnDevice: Bool,
        onPartialResult: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (String) -> Void,
        onAudioLevel: @escaping @MainActor (Float) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) throws {
        cleanUp()

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw VoiceCommandError.recognizerUnavailable
        }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        self.recognitionRequest = request

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw VoiceCommandError.noAudioInputDevice
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
            let level = Self.computeAudioLevel(buffer: buffer)
            Task { @MainActor in
                onAudioLevel(level)
            }
        }

        engine.prepare()
        try engine.start()

        isListening = true

        self.recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            Task { @MainActor in
                if let result {
                    let formatted = result.bestTranscription.formattedString
                    if result.isFinal {
                        onFinalResult(formatted)
                    } else {
                        onPartialResult(formatted)
                    }
                }
                if let error {
                    onError(error)
                }
            }
        }
    }

    func stopListening() {
        guard isListening else { return }
        isListening = false
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        recognitionRequest?.endAudio()
    }

    func cancelListening() {
        isListening = false
        cleanUp()
    }

    private func cleanUp() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
        }
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private static func computeAudioLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0.0 }
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        return min(1.0, max(0.0, rms * 4.5))
    }
}

// MARK: - Mock Speech Engine for Deterministic Testing

@MainActor
final class MockSpeechEngine: AmoraSpeechEngine {
    var isAvailable: Bool = true
    var supportsOnDeviceRecognition: Bool = true
    var isListening: Bool = false
    var recognitionModeDescription: String = "Mock Engine (On-Device)"

    var permissionState: AmoraVoicePermissionState = .authorized
    var shouldThrowOnStart: Error? = nil

    var wasStartCalled: Bool = false
    var wasStopCalled: Bool = false
    var wasCancelCalled: Bool = false
    var lastPreferOnDevice: Bool?

    var onPartialResultHandler: ((String) -> Void)?
    var onFinalResultHandler: ((String) -> Void)?
    var onAudioLevelHandler: ((Float) -> Void)?
    var onErrorHandler: ((Error) -> Void)?

    init(permissionState: AmoraVoicePermissionState = .authorized) {
        self.permissionState = permissionState
    }

    func checkPermissions() -> AmoraVoicePermissionState {
        permissionState
    }

    func requestPermissions() async -> AmoraVoicePermissionState {
        permissionState
    }

    func startListening(
        preferOnDevice: Bool,
        onPartialResult: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (String) -> Void,
        onAudioLevel: @escaping @MainActor (Float) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) throws {
        if let err = shouldThrowOnStart { throw err }
        wasStartCalled = true
        isListening = true
        lastPreferOnDevice = preferOnDevice
        self.onPartialResultHandler = onPartialResult
        self.onFinalResultHandler = onFinalResult
        self.onAudioLevelHandler = onAudioLevel
        self.onErrorHandler = onError
    }

    func stopListening() {
        wasStopCalled = true
        isListening = false
    }

    func cancelListening() {
        wasCancelCalled = true
        isListening = false
    }

    func simulatePartialResult(_ text: String) {
        onPartialResultHandler?(text)
    }

    func simulateFinalResult(_ text: String) {
        isListening = false
        onFinalResultHandler?(text)
    }

    func simulateAudioLevel(_ level: Float) {
        onAudioLevelHandler?(level)
    }

    func simulateError(_ error: Error) {
        isListening = false
        onErrorHandler?(error)
    }
}
