import Foundation
import AVFoundation

enum WakeWordState: Equatable, Sendable {
    case disabled
    case unauthorized(description: String)
    case standby(engineName: String)
    case paused
    case detecting(timestamp: Date)
    case activeVoiceSession
    case unavailable(reason: String)
    case failed(message: String)

    var isStandby: Bool {
        if case .standby = self { return true }
        return false
    }

    var isCapturingAudio: Bool {
        switch self {
        case .standby, .detecting, .activeVoiceSession:
            return true
        case .disabled, .unauthorized, .paused, .unavailable, .failed:
            return false
        }
    }

    var userFacingDescription: String {
        switch self {
        case .disabled:
            return "Wake word listening is turned off in Settings."
        case .unauthorized(let description):
            return description
        case .standby(let engine):
            return "Listening for 'AMORA' (\(engine))"
        case .paused:
            return "Wake word detection is paused."
        case .detecting:
            return "Wake word 'AMORA' detected!"
        case .activeVoiceSession:
            return "Processing voice command…"
        case .unavailable(let reason):
            return "Wake word unavailable: \(reason)"
        case .failed(let message):
            return "Wake word failed: \(message)"
        }
    }
}

enum WakeWordEngineKind: String, CaseIterable, Codable, Sendable {
    case nativeAcoustic = "nativeAcoustic"
    case porcupine = "porcupine"

    var displayName: String {
        switch self {
        case .nativeAcoustic:
            return "Native On-Device (Recommended, Private)"
        case .porcupine:
            return "Picovoice Porcupine (AccessKey Required)"
        }
    }

    var requiresAccessKey: Bool {
        switch self {
        case .nativeAcoustic: return false
        case .porcupine: return true
        }
    }
}

struct WakeWordDetectionResult: @unchecked Sendable {
    let wakePhrase: String
    let confidence: Float
    let timestamp: Date
    let bufferedAudio: [AVAudioPCMBuffer]
}

enum WakeWordError: LocalizedError, Equatable {
    case microphoneUnavailable
    case permissionDenied(String)
    case engineNotAvailable(String)
    case porcupineUnconfigured(String)
    case porcupineModelMissing(String)
    case audioEngineError(String)
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable:
            return "No microphone or audio input device found."
        case .permissionDenied(let reason):
            return reason
        case .engineNotAvailable(let reason):
            return "Wake word engine unavailable: \(reason)"
        case .porcupineUnconfigured(let reason):
            return reason
        case .porcupineModelMissing(let reason):
            return reason
        case .audioEngineError(let reason):
            return "Audio engine error: \(reason)"
        case .alreadyRunning:
            return "Wake word listener is already active."
        }
    }
}

import SwiftUI

extension WakeWordState {
    var statusTitle: String {
        switch self {
        case .disabled: return "Disabled"
        case .unauthorized: return "Unauthorized"
        case .standby: return "Active Standby"
        case .paused: return "Paused"
        case .detecting: return "AMORA Detected"
        case .activeVoiceSession: return "Voice Session Active"
        case .unavailable: return "Unavailable"
        case .failed: return "Error"
        }
    }

    var statusIcon: String {
        switch self {
        case .disabled: return "mic.slash"
        case .unauthorized: return "lock.shield.fill"
        case .standby: return "waveform"
        case .paused: return "pause.circle.fill"
        case .detecting, .activeVoiceSession: return "waveform.badge.mic"
        case .unavailable, .failed: return "exclamationmark.triangle.fill"
        }
    }

    var statusColor: Color {
        switch self {
        case .standby: return .green
        case .detecting, .activeVoiceSession: return .blue
        case .paused: return .orange
        case .unauthorized, .unavailable, .failed: return .red
        case .disabled: return .secondary
        }
    }
}
