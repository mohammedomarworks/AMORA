import Foundation

/// Lifecycle status of the local offline brain model.
public enum AmoraModelStatus: Equatable, Sendable {
    case notInstalled
    case readyToDownload
    case downloading(progress: Double, bytesDownloaded: Int64, totalBytes: Int64)
    case cancelling
    case verifying(progress: Double)
    case loading
    case ready
    case outOfMemory(requiredBytes: Int64, availableBytes: Int64)
    case corrupt(reason: String)
    case failed(error: String)
    case cancelled

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var isBusy: Bool {
        switch self {
        case .downloading, .cancelling, .verifying, .loading:
            return true
        default:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .notInstalled:
            return "Not Installed"
        case .readyToDownload:
            return "Ready to Download"
        case .downloading(let progress, _, _):
            return "Downloading (\(Int(progress * 100))%)"
        case .cancelling:
            return "Cancelling…"
        case .verifying:
            return "Verifying Checksum…"
        case .loading:
            return "Loading into Memory…"
        case .ready:
            return "Ready"
        case .outOfMemory:
            return "Out of Memory"
        case .corrupt:
            return "Corrupted Model File"
        case .failed:
            return "Setup Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    public var detailedDescription: String {
        switch self {
        case .notInstalled:
            return "Offline intelligence is not installed. Download the local model to think offline without API keys."
        case .readyToDownload:
            return "Ready to download offline model."
        case .downloading(let progress, let downloaded, let total):
            let mbDown = Double(downloaded) / (1024 * 1024)
            let mbTotal = Double(total) / (1024 * 1024)
            return String(format: "Downloading: %.1f MB of %.1f MB (%.0f%%)", mbDown, mbTotal, progress * 100)
        case .cancelling:
            return "Cancelling download and cleaning up temporary files…"
        case .verifying:
            return "Verifying SHA-256 integrity checksum…"
        case .loading:
            return "Loading model into memory with Metal GPU acceleration…"
        case .ready:
            return "Local Brain is ready for offline conversations and action planning."
        case .outOfMemory(let req, let avail):
            let reqMB = req / (1024 * 1024)
            let availMB = avail / (1024 * 1024)
            return "Insufficient memory. Requires ~\(reqMB) MB RAM, but only ~\(availMB) MB is available."
        case .corrupt(let reason):
            return "Model file is corrupt or invalid: \(reason). Please delete and re-download."
        case .failed(let err):
            return "Download or setup error: \(err)."
        case .cancelled:
            return "Download was cancelled."
        }
    }
}
