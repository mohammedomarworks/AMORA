import Foundation

enum AmoraVoicePermissionState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied(description: String)
    case restricted(description: String)
    case speechUnavailable(description: String)

    var isAuthorized: Bool {
        if case .authorized = self { return true }
        return false
    }

    var userFacingDescription: String {
        switch self {
        case .notDetermined:
            return "Microphone and speech recognition permissions not yet requested."
        case .authorized:
            return "Microphone and speech recognition authorized."
        case .denied(let description):
            return description
        case .restricted(let description):
            return description
        case .speechUnavailable(let description):
            return description
        }
    }
}

enum VoiceCommandState: Equatable, Sendable {
    case ready
    case listening(audioLevel: Float, partialTranscript: String)
    case processing(transcript: String)
    case completed(transcript: String, message: String)
    case permissionDenied(reason: String)
    case unavailable(reason: String)
    case failed(message: String)
    case cancelled

    var isListening: Bool {
        if case .listening = self { return true }
        return false
    }

    var isProcessing: Bool {
        if case .processing = self { return true }
        return false
    }
}

enum VoiceCommandError: LocalizedError, Equatable {
    case noAudioInputDevice
    case permissionDenied(String)
    case recognizerUnavailable
    case sessionInterrupted
    case audioEngineError(String)
    case timeout
    case alreadyListening

    var errorDescription: String? {
        switch self {
        case .noAudioInputDevice:
            return "No audio input hardware or microphone was detected on this Mac."
        case .permissionDenied(let reason):
            return reason
        case .recognizerUnavailable:
            return "Apple speech recognizer is currently unavailable."
        case .sessionInterrupted:
            return "Audio recording was interrupted."
        case .audioEngineError(let reason):
            return "Audio engine error: \(reason)"
        case .timeout:
            return "Voice command timed out."
        case .alreadyListening:
            return "Voice command session is already active."
        }
    }
}
