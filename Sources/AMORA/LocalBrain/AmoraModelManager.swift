import Foundation
import CryptoKit
import Observation

/// Thread-safe tracker to prevent trailing asynchronous progress updates from clobbering completed model states.
private final class VerificationProgressState: @unchecked Sendable {
    private var active: Bool = true
    private let lock = NSLock()

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func deactivate() {
        lock.lock()
        defer { lock.unlock() }
        active = false
    }
}

/// Downloader protocol allowing deterministic unit test injection without hitting the network.
public protocol AmoraModelDownloading: Sendable {
    func download(
        from url: URL,
        to destinationURL: URL,
        expectedSizeBytes: Int64,
        onProgress: @Sendable @escaping (Double, Int64, Int64) -> Void
    ) async throws
    func cancelCurrentDownload()
}

/// URLSession-based concrete downloader supporting real network downloads, live progress, and cancellation.
public final class URLSessionModelDownloader: NSObject, AmoraModelDownloading, @unchecked Sendable {
    private var downloadTask: URLSessionDownloadTask?
    private var progressContinuation: CheckedContinuation<Void, Error>?
    private var onProgressCallback: (@Sendable (Double, Int64, Int64) -> Void)?
    private var expectedTotalBytes: Int64 = 0
    private var targetDestination: URL?
    private let lock = NSLock()

    public func download(
        from url: URL,
        to destinationURL: URL,
        expectedSizeBytes: Int64,
        onProgress: @Sendable @escaping (Double, Int64, Int64) -> Void
    ) async throws {
        self.targetDestination = destinationURL
        self.onProgressCallback = onProgress
        self.expectedTotalBytes = expectedSizeBytes

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600 // Large models need time to download
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            self.progressContinuation = continuation
            let task = session.downloadTask(with: url)
            self.downloadTask = task
            lock.unlock()
            task.resume()
        }
    }

    public func cancelCurrentDownload() {
        lock.lock()
        defer { lock.unlock() }
        downloadTask?.cancel()
        downloadTask = nil
        progressContinuation?.resume(throwing: CancellationError())
        progressContinuation = nil
    }
}

extension URLSessionModelDownloader: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedTotalBytes
        let progress = total > 0 ? min(1.0, max(0.0, Double(totalBytesWritten) / Double(total))) : 0.0
        onProgressCallback?(progress, totalBytesWritten, total)
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let dest = targetDestination else {
            progressContinuation?.resume(throwing: NSError(domain: "AMORAModelDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Target destination missing"]))
            return
        }
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            progressContinuation?.resume()
        } catch {
            progressContinuation?.resume(throwing: error)
        }
        progressContinuation = nil
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            if (error as NSError).code == NSURLErrorCancelled {
                progressContinuation?.resume(throwing: CancellationError())
            } else {
                progressContinuation?.resume(throwing: error)
            }
            progressContinuation = nil
        }
    }
}

/// Protocol for model management allowing injection in tests and preview mocks.
@MainActor
public protocol AmoraModelManaging: AnyObject, Sendable {
    var status: AmoraModelStatus { get }
    var descriptor: AmoraModelDescriptor { get }
    var isReady: Bool { get }
    var modelFileURL: URL { get }

    func checkStatus() async -> AmoraModelStatus
    func checkStatusSync() -> AmoraModelStatus
    func startDownload() async throws
    func cancelDownload()
    func deleteModel() async throws
    func verifyIntegrity() async -> Bool
}

/// The production model manager responsible for model discovery, download, SHA-256 verification,
/// storage isolation in Application Support, and safe deletion.
@Observable @MainActor
public final class AmoraModelManager: AmoraModelManaging {
    public static let shared = AmoraModelManager()

    public let descriptor: AmoraModelDescriptor
    public private(set) var status: AmoraModelStatus = .notInstalled
    public var isReady: Bool { status.isReady }

    private let downloader: any AmoraModelDownloading
    private let modelsDirectory: URL
    private let explicitModelURL: URL?
    private var downloadTask: Task<Void, Error>?
    private var verificationTask: Task<Bool, Never>?

    public var modelFileURL: URL {
        if let explicitModelURL {
            return explicitModelURL
        }
        let defaultURL = modelsDirectory.appendingPathComponent(descriptor.filename)
        if FileManager.default.fileExists(atPath: defaultURL.path) {
            return defaultURL
        }
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: modelsDirectory.path) {
            if let matched = contents.first(where: { $0.caseInsensitiveCompare(descriptor.filename) == .orderedSame }) {
                return modelsDirectory.appendingPathComponent(matched)
            }
        }
        return defaultURL
    }

    private var temporaryDownloadURL: URL {
        modelsDirectory.appendingPathComponent(descriptor.filename + ".download")
    }

    public init(
        descriptor: AmoraModelDescriptor = .qwen2_5_0_5b,
        downloader: (any AmoraModelDownloading)? = nil,
        modelsDirectory: URL? = nil,
        explicitModelURL: URL? = nil
    ) {
        self.descriptor = descriptor
        self.downloader = downloader ?? URLSessionModelDownloader()
        self.explicitModelURL = explicitModelURL

        if let explicitModelURL {
            self.modelsDirectory = explicitModelURL.deletingLastPathComponent()
        } else if let modelsDirectory {
            self.modelsDirectory = modelsDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.modelsDirectory = appSupport.appendingPathComponent("AMORA/models", isDirectory: true)
        }

        ensureDirectoryExists()
        _ = checkStatusSync()
    }

    /// Factory for comparative evaluations loading an explicit model file URL without touching the default model.
    public static func forEvaluation(
        modelURL: URL,
        descriptor: AmoraModelDescriptor? = nil
    ) -> AmoraModelManager {
        let desc = descriptor ?? .explicitCandidate(path: modelURL.path)
        return AmoraModelManager(
            descriptor: desc,
            explicitModelURL: modelURL
        )
    }

    private func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    public func checkStatus() async -> AmoraModelStatus {
        checkStatusSync()
    }

    @discardableResult
    public func checkStatusSync() -> AmoraModelStatus {
        // If currently in an active running task, keep it
        if case .downloading = status {
            if downloadTask != nil { return status }
        }
        if case .verifying = status {
            if verificationTask != nil || downloadTask != nil { return status }
        }
        if case .loading = status { return status }

        let fileManager = FileManager.default
        let path = modelFileURL.path

        guard fileManager.fileExists(atPath: path) else {
            if fileManager.fileExists(atPath: temporaryDownloadURL.path) {
                // Incomplete download leftover
                try? fileManager.removeItem(at: temporaryDownloadURL)
            }
            status = .notInstalled
            return .notInstalled
        }

        // Check file size
        do {
            let attrs = try fileManager.attributesOfItem(atPath: path)
            let actualSize = attrs[.size] as? Int64 ?? 0
            if descriptor.expectedSizeBytes > 0 && actualSize < descriptor.expectedSizeBytes {
                let s = AmoraModelStatus.corrupt(reason: "File size mismatch (\(actualSize) bytes vs expected \(descriptor.expectedSizeBytes) bytes)")
                status = s
                return s
            }
        } catch {
            let s = AmoraModelStatus.corrupt(reason: error.localizedDescription)
            status = s
            return s
        }

        status = .ready
        return .ready
    }

    public func startDownload() async throws {
        guard !status.isBusy else { return }

        // 1. Reuse existing valid model if already present on disk
        if FileManager.default.fileExists(atPath: modelFileURL.path) {
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: modelFileURL.path)
                let actualSize = attrs[.size] as? Int64 ?? 0
                if actualSize >= descriptor.expectedSizeBytes {
                    let isValid = await verifyIntegrity()
                    if isValid {
                        return
                    }
                    try? FileManager.default.removeItem(at: modelFileURL)
                }
            } catch {}
        }

        // 2. Pre-flight checks: Disk Space
        let requiredDiskSpace = descriptor.expectedSizeBytes + 500 * 1024 * 1024 // Model size + 500 MB safety buffer
        if let availableDisk = getAvailableDiskSpace(), availableDisk < requiredDiskSpace {
            let errorMsg = "Not enough disk space. Requires ~\(requiredDiskSpace / (1024 * 1024)) MB, available ~\(availableDisk / (1024 * 1024)) MB."
            status = .failed(error: errorMsg)
            throw NSError(domain: "AMORAModelManager", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        // 3. Pre-flight checks: RAM
        let availableRAM = getAvailableRAM()
        if availableRAM < descriptor.estimatedRAMBytes {
            status = .outOfMemory(requiredBytes: descriptor.estimatedRAMBytes, availableBytes: availableRAM)
            throw NSError(domain: "AMORAModelManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Insufficient memory to run offline model."])
        }

        ensureDirectoryExists()
        if FileManager.default.fileExists(atPath: temporaryDownloadURL.path) {
            try? FileManager.default.removeItem(at: temporaryDownloadURL)
        }

        status = .downloading(progress: 0.0, bytesDownloaded: 0, totalBytes: descriptor.expectedSizeBytes)

        let currentDownloader = self.downloader
        let currentTempURL = self.temporaryDownloadURL
        let currentFinalURL = self.modelFileURL
        let expectedBytes = descriptor.expectedSizeBytes
        let expectedHash = descriptor.expectedSHA256
        let sourceURL = descriptor.sourceURL

        let downloadTask = Task { [weak self] in
            guard let manager = self else { return }
            do {
                try await currentDownloader.download(
                    from: sourceURL,
                    to: currentTempURL,
                    expectedSizeBytes: expectedBytes
                ) { [weak manager] progress, downloaded, total in
                    Task { @MainActor in
                        guard let manager else { return }
                        if case .downloading = manager.status {
                            manager.status = .downloading(progress: progress, bytesDownloaded: downloaded, totalBytes: total)
                        }
                    }
                }

                // Verify completed file with SHA-256
                let verificationState = VerificationProgressState()
                await MainActor.run {
                    manager.status = .verifying(progress: 0.0)
                }

                let progressHandler: @Sendable (Double) -> Void = { [weak manager] verifyProgress in
                    Task { @MainActor in
                        guard let manager, verificationState.isActive else { return }
                        if case .verifying = manager.status {
                            manager.status = .verifying(progress: verifyProgress)
                        }
                    }
                }

                let isValid = await Task.detached(priority: .userInitiated) { () -> Bool in
                    (try? await Self.verifyFileHash(
                        fileURL: currentTempURL,
                        expectedHex: expectedHash,
                        onProgress: progressHandler
                    )) ?? false
                }.value

                verificationState.deactivate()

                guard isValid else {
                    try? FileManager.default.removeItem(at: currentTempURL)
                    await MainActor.run {
                        manager.status = .corrupt(reason: "SHA-256 checksum verification failed.")
                    }
                    return
                }

                // Atomic move to final destination
                if FileManager.default.fileExists(atPath: currentFinalURL.path) {
                    try FileManager.default.removeItem(at: currentFinalURL)
                }
                try FileManager.default.moveItem(at: currentTempURL, to: currentFinalURL)

                await MainActor.run {
                    manager.status = .ready
                }
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: currentTempURL)
                await MainActor.run {
                    manager.status = .cancelled
                }
            } catch {
                try? FileManager.default.removeItem(at: currentTempURL)
                await MainActor.run {
                    manager.status = .failed(error: error.localizedDescription)
                }
                throw error
            }
        }

        self.downloadTask = downloadTask
        try await downloadTask.value
    }

    public func cancelDownload() {
        downloader.cancelCurrentDownload()
        downloadTask?.cancel()
        downloadTask = nil
        verificationTask?.cancel()
        verificationTask = nil
        try? FileManager.default.removeItem(at: temporaryDownloadURL)
        status = .cancelled
    }

    public func deleteModel() async throws {
        cancelDownload()
        verificationTask?.cancel()
        verificationTask = nil
        if FileManager.default.fileExists(atPath: modelFileURL.path) {
            try FileManager.default.removeItem(at: modelFileURL)
        }
        if FileManager.default.fileExists(atPath: temporaryDownloadURL.path) {
            try FileManager.default.removeItem(at: temporaryDownloadURL)
        }
        status = .notInstalled
    }

    public func verifyIntegrity() async -> Bool {
        if let existingTask = verificationTask {
            return await existingTask.value
        }

        guard FileManager.default.fileExists(atPath: modelFileURL.path) else {
            status = .notInstalled
            return false
        }

        status = .verifying(progress: 0.0)

        let targetURL = self.modelFileURL
        let expectedHash = self.descriptor.expectedSHA256
        let verificationState = VerificationProgressState()

        let task = Task<Bool, Never> { @MainActor [weak self] in
            guard let self else { return false }
            defer {
                verificationState.deactivate()
                self.verificationTask = nil
            }

            let progressHandler: @Sendable (Double) -> Void = { [weak self] p in
                Task { @MainActor in
                    guard let self, verificationState.isActive, self.verificationTask != nil else { return }
                    if case .verifying = self.status {
                        self.status = .verifying(progress: p)
                    }
                }
            }

            let isValid = await Task.detached(priority: .userInitiated) { () -> Bool in
                (try? await Self.verifyFileHash(
                    fileURL: targetURL,
                    expectedHex: expectedHash,
                    onProgress: progressHandler
                )) ?? false
            }.value

            verificationState.deactivate()

            if Task.isCancelled {
                if case .verifying = self.status {
                    self.status = .cancelled
                }
                return false
            }

            if isValid {
                self.status = .ready
                return true
            } else {
                self.status = .corrupt(reason: "SHA-256 checksum verification failed.")
                return false
            }
        }

        self.verificationTask = task
        return await task.value
    }

    public static func verifyFileHash(
        fileURL: URL,
        expectedHex: String,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }

        var hasher = SHA256()
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var readBytes: Int64 = 0
        let chunkSize = 4 * 1024 * 1024 // 4 MB chunks for high throughput
        var lastReportedProgress: Double = 0.0
        onProgress?(0.0)

        while true {
            try Task.checkCancellation()
            let data = handle.readData(ofLength: chunkSize)
            if data.isEmpty { break }
            hasher.update(data: data)
            readBytes += Int64(data.count)
            if fileSize > 0 {
                let progress = min(1.0, Double(readBytes) / Double(fileSize))
                if progress - lastReportedProgress >= 0.02 || progress >= 1.0 {
                    lastReportedProgress = progress
                    onProgress?(progress)
                }
            }
        }

        if lastReportedProgress < 1.0 {
            onProgress?(1.0)
        }

        let digest = hasher.finalize()
        let calculatedHex = digest.map { String(format: "%02x", $0) }.joined()
        return calculatedHex.caseInsensitiveCompare(expectedHex) == .orderedSame
    }

    private func getAvailableDiskSpace() -> Int64? {
        do {
            let values = try modelsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
            if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
                return important
            }
            if let avail = values.volumeAvailableCapacity, avail > 0 {
                return Int64(avail)
            }
        } catch {}
        var stat = statvfs()
        if statvfs(modelsDirectory.path, &stat) == 0 {
            return Int64(stat.f_bavail) * Int64(stat.f_frsize)
        }
        return nil
    }

    private func getAvailableRAM() -> Int64 {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStat = vm_statistics64()
        let host = mach_host_self()
        let ret = withUnsafeMutablePointer(to: &vmStat) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(host, HOST_VM_INFO64, intPtr, &count)
            }
        }
        if ret == KERN_SUCCESS {
            let freePages = Int64(vmStat.free_count) + Int64(vmStat.inactive_count)
            return freePages * Int64(pageSize)
        }
        return Int64(ProcessInfo.processInfo.physicalMemory / 2)
    }
}
