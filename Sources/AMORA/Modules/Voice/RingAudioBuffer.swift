import Foundation
import AVFoundation

/// A bounded, thread-safe in-memory ring buffer holding recent PCM audio buffers.
/// Used to preserve early audio frames when transitioning from wake-word detection
/// to full speech recognition during continuous utterances ("AMORA, set a timer...").
final class RingAudioBuffer: @unchecked Sendable {
    private let maxDurationSeconds: Double
    private var buffers: [AVAudioPCMBuffer] = []
    private var totalDurationSeconds: Double = 0.0
    private let lock = NSLock()

    init(maxDurationSeconds: Double = 2.5) {
        self.maxDurationSeconds = maxDurationSeconds
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let copy = Self.copyBuffer(buffer) else { return }
        let sampleRate = copy.format.sampleRate
        guard sampleRate > 0 else { return }
        let duration = Double(copy.frameLength) / sampleRate

        lock.lock()
        defer { lock.unlock() }

        buffers.append(copy)
        totalDurationSeconds += duration

        while totalDurationSeconds > maxDurationSeconds && !buffers.isEmpty {
            let removed = buffers.removeFirst()
            let removedDuration = Double(removed.frameLength) / removed.format.sampleRate
            totalDurationSeconds = max(0.0, totalDurationSeconds - removedDuration)
        }
    }

    func snapshot() -> [AVAudioPCMBuffer] {
        lock.lock()
        defer { lock.unlock() }
        return buffers
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffers.removeAll()
        totalDurationSeconds = 0.0
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffers.count
    }

    private static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return nil
        }
        copy.frameLength = buffer.frameLength

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<channelCount {
                memcpy(dst[ch], src[ch], frameLength * MemoryLayout<Float>.size)
            }
        } else if let src = buffer.int16ChannelData, let dst = copy.int16ChannelData {
            for ch in 0..<channelCount {
                memcpy(dst[ch], src[ch], frameLength * MemoryLayout<Int16>.size)
            }
        }
        return copy
    }
}
