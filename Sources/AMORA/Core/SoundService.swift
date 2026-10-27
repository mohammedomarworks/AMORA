import AppKit

/// Which event or emotion a sound belongs to.
/// Standard UI events map to built-in macOS alert sounds, while mascot emotions
/// use original synthesized audio data generated directly in-memory so AMORA
/// maintains an original, cohesive sound identity without external asset dependencies.
public enum AMORASound: String, CaseIterable, Equatable, Sendable {
    case open, close, click, timerComplete, success, notification, pop
    case love, grumpy, excited, sad

    var systemName: String {
        switch self {
        case .open:          return "Tink"
        case .close:         return "Tink"
        case .click:         return "Tink"
        case .timerComplete: return "Glass"
        case .success:       return "Glass"
        case .notification:  return "Ping"
        case .pop:           return "Pop"
        case .love:          return "Pop"
        case .grumpy:        return "Tink"
        case .excited:       return "Glass"
        case .sad:           return "Tink"
        }
    }

    /// Whether this sound uses AMORA's original synthesized acoustic engine.
    public var isSynthesizedEmotion: Bool {
        switch self {
        case .love, .grumpy, .excited, .sad:
            return true
        default:
            return false
        }
    }
}

/// A single, reusable place that plays AMORA's sound effects. Honors the user's
/// Sound Effects toggle + volume; silent by policy when disabled. Subtle by
/// design — meaningful moments only, never per-poll chatter.
@MainActor
final class SoundService {
    static let shared = SoundService()

    private var cachedSynthesizedData: [AMORASound: Data] = [:]
    private var lastPlayedTimes: [AMORASound: Date] = [:]
    private let cooldownThreshold: TimeInterval = 0.30

    private init() {
        prewarmSynthesizedSounds()
    }

    /// Pre-synthesizes emotion audio data in-memory for instant, zero-latency playback.
    private func prewarmSynthesizedSounds() {
        cachedSynthesizedData[.love] = Self.generateLoveAudioData()
        cachedSynthesizedData[.grumpy] = Self.generateGrumpyAudioData()
        cachedSynthesizedData[.excited] = Self.generateExcitedAudioData()
        cachedSynthesizedData[.sad] = Self.generateSadAudioData()
    }

    /// Returns synthesized WAV audio data for test inspection or direct playback.
    func audioData(for sound: AMORASound) -> Data? {
        if let data = cachedSynthesizedData[sound] {
            return data
        }
        let generated: Data?
        switch sound {
        case .love:    generated = Self.generateLoveAudioData()
        case .grumpy:  generated = Self.generateGrumpyAudioData()
        case .excited: generated = Self.generateExcitedAudioData()
        case .sad:     generated = Self.generateSadAudioData()
        default:       generated = nil
        }
        if let gen = generated {
            cachedSynthesizedData[sound] = gen
        }
        return generated
    }

    /// Resets cooldown timestamps for deterministic unit testing.
    func resetCooldownsForTesting() {
        lastPlayedTimes.removeAll()
    }

    /// Plays the requested sound if sound effects are enabled, respecting volume
    /// and per-sound cooldown limits to prevent overlapping clutter.
    func play(_ sound: AMORASound, now: Date = Date()) {
        let settings = AppState.shared.settings
        guard settings.soundEnabled else { return }

        // Cooldown check
        if let last = lastPlayedTimes[sound], now.timeIntervalSince(last) < cooldownThreshold {
            return
        }
        lastPlayedTimes[sound] = now

        let volume = Float(max(0.0, min(1.0, settings.soundVolume)))
        guard volume > 0 else { return }

        if sound.isSynthesizedEmotion, let data = audioData(for: sound) {
            if let ns = NSSound(data: data) {
                ns.volume = volume
                ns.play()
                return
            }
        }

        // Fallback to system alert sound
        if let ns = NSSound(named: NSSound.Name(sound.systemName)) {
            ns.volume = volume
            ns.play()
        }
    }

    // MARK: - Procedural Audio Synthesizer (16-bit 44.1kHz Mono PCM WAV)

    private static func createWAV(sampleRate: Int = 44100, samples: [Float]) -> Data {
        var data = Data()
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
        let subchunk2Size: UInt32 = UInt32(samples.count * 2)
        let chunkSize: UInt32 = 36 + subchunk2Size

        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // "fmt " subchunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        let subchunk1Size: UInt32 = 16
        data.append(contentsOf: withUnsafeBytes(of: subchunk1Size.littleEndian) { Array($0) })
        let audioFormat: UInt16 = 1 // PCM
        data.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        let sampleRateU32: UInt32 = UInt32(sampleRate)
        data.append(contentsOf: withUnsafeBytes(of: sampleRateU32.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // "data" subchunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: withUnsafeBytes(of: subchunk2Size.littleEndian) { Array($0) })

        // PCM samples
        for s in samples {
            let clamped = max(-1.0, min(1.0, s))
            let intSample = Int16(clamped * 32767.0)
            data.append(contentsOf: withUnsafeBytes(of: intSample.littleEndian) { Array($0) })
        }

        return data
    }

    /// Love / Affection: Warm 4-note ascending major arpeggio chime (C5-E5-G5-C6) with soft exponential decay.
    static func generateLoveAudioData() -> Data {
        let sampleRate = 44100
        let duration = 0.42
        let totalSamples = Int(Double(sampleRate) * duration)
        var samples = [Float](repeating: 0, count: totalSamples)

        let notes: [(freq: Double, start: Double, end: Double)] = [
            (523.25, 0.00, 0.14), // C5
            (659.25, 0.08, 0.22), // E5
            (783.99, 0.16, 0.32), // G5
            (1046.50, 0.24, 0.42) // C6
        ]

        for note in notes {
            let startIdx = Int(note.start * Double(sampleRate))
            let endIdx = min(totalSamples, Int(note.end * Double(sampleRate)))
            let noteDuration = note.end - note.start

            for i in startIdx..<endIdx {
                let t = Double(i - startIdx) / Double(sampleRate)
                let envelope = sin(min(1.0, t / 0.015) * .pi / 2.0) * exp(-t * 8.0 / noteDuration)
                let wave = sin(2.0 * .pi * note.freq * t) * 0.70 + sin(4.0 * .pi * note.freq * t) * 0.18
                samples[i] += Float(wave * envelope * 0.45)
            }
        }

        return createWAV(sampleRate: sampleRate, samples: samples)
    }

    /// Grumpy: Short playful robo-grumble descending in pitch (240Hz -> 130Hz) with cute frequency modulation.
    static func generateGrumpyAudioData() -> Data {
        let sampleRate = 44100
        let duration = 0.28
        let totalSamples = Int(Double(sampleRate) * duration)
        var samples = [Float](repeating: 0, count: totalSamples)

        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            let progress = t / duration
            let freq = 240.0 - 110.0 * progress
            let envelope = sin(min(1.0, t / 0.02) * .pi / 2.0) * (1.0 - progress * 0.85)
            // Modulated with 16Hz electronic grumble vibrato
            let phase = 2.0 * .pi * freq * t + 0.35 * sin(2.0 * .pi * 16.0 * t)
            let wave = sin(phase) * 0.65 + sin(phase * 2.0) * 0.20
            samples[i] = Float(wave * envelope * 0.45)
        }

        return createWAV(sampleRate: sampleRate, samples: samples)
    }

    /// Excited: Energetic, cheerful rising chirp (D5 -> A5 -> D6) with bright sparkling harmonics.
    static func generateExcitedAudioData() -> Data {
        let sampleRate = 44100
        let duration = 0.36
        let totalSamples = Int(Double(sampleRate) * duration)
        var samples = [Float](repeating: 0, count: totalSamples)

        let notes: [(freq: Double, start: Double, end: Double)] = [
            (587.33, 0.00, 0.12), // D5
            (880.00, 0.09, 0.22), // A5
            (1174.66, 0.18, 0.36) // D6
        ]

        for note in notes {
            let startIdx = Int(note.start * Double(sampleRate))
            let endIdx = min(totalSamples, Int(note.end * Double(sampleRate)))
            let noteDuration = note.end - note.start

            for i in startIdx..<endIdx {
                let t = Double(i - startIdx) / Double(sampleRate)
                let envelope = sin(min(1.0, t / 0.01) * .pi / 2.0) * exp(-t * 6.0 / noteDuration)
                let wave = sin(2.0 * .pi * note.freq * t) * 0.60
                    + sin(4.0 * .pi * note.freq * t) * 0.22
                    + sin(6.0 * .pi * note.freq * t) * 0.08
                samples[i] += Float(wave * envelope * 0.45)
            }
        }

        return createWAV(sampleRate: sampleRate, samples: samples)
    }

    /// Sad: Soft, gentle melancholy descending sigh (A4 -> F4) with soft tapering decay.
    static func generateSadAudioData() -> Data {
        let sampleRate = 44100
        let duration = 0.40
        let totalSamples = Int(Double(sampleRate) * duration)
        var samples = [Float](repeating: 0, count: totalSamples)

        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            let progress = t / duration
            // Smoothly descends from A4 (440Hz) to F4 (349.23Hz) with subtle 4.5Hz vibrato
            let freq = 440.0 - 90.77 * pow(progress, 0.8) + sin(2.0 * .pi * 4.5 * t) * 2.0
            let envelope = sin(min(1.0, t / 0.035) * .pi / 2.0) * pow(max(0.0, 1.0 - progress), 1.15)
            let wave = sin(2.0 * .pi * freq * t) * 0.70 + sin(4.0 * .pi * freq * t) * 0.15
            samples[i] = Float(wave * envelope * 0.40)
        }

        return createWAV(sampleRate: sampleRate, samples: samples)
    }
}
