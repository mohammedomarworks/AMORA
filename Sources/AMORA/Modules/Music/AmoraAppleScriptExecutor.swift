import Foundation
@preconcurrency import Dispatch

/// Result of an AppleScript execution attempt.
public enum AmoraAppleScriptResult: Equatable, Sendable {
    case success(String)
    case error(code: Int, message: String)
    case timedOut(TimeInterval)
    case cancelled
    case scriptCreationFailed
    case queryQuarantined
}

/// Abstract protocol for executing AppleScripts asynchronously on a background context.
public protocol AmoraAppleScriptExecuting: Sendable {
    /// Executes the given AppleScript source with a bounded timeout.
    /// - Parameters:
    ///   - source: AppleScript source code.
    ///   - timeout: Bounded timeout in seconds.
    ///   - isMutating: True for state-altering playback commands (which require strict serialization);
    ///                 false for read-only status queries (which can be safely quarantined on timeout).
    func execute(source: String, timeout: TimeInterval, isMutating: Bool) async -> AmoraAppleScriptResult
}

extension AmoraAppleScriptExecuting {
    /// Executes the given AppleScript source with a bounded timeout, defaulting to mutating serialization.
    public func execute(source: String, timeout: TimeInterval) async -> AmoraAppleScriptResult {
        await execute(source: source, timeout: timeout, isMutating: true)
    }

    /// Executes the given AppleScript source with a default timeout of 2.0 seconds.
    public func execute(source: String) async -> AmoraAppleScriptResult {
        await execute(source: source, timeout: 2.0, isMutating: true)
    }
}

/// Dedicated background executor that serializes AppleScript execution on private background queues,
/// enforcing bounded timeouts and preventing hung scripts from freezing AMORA's main thread or UI.
///
/// Mutating commands (play, pause, next, previous) are strictly serialized to prevent conflicting
/// duplicate actions. Read-only queries (track polling) run on an isolated query queue so that a slow
/// metadata fetch never blocks user playback commands.
public final class AmoraAppleScriptExecutor: AmoraAppleScriptExecuting, @unchecked Sendable {
    public static let shared = AmoraAppleScriptExecutor()

    private let queueLock = NSLock()
    private var commandQueue = DispatchQueue(label: "com.amora.applescript.command-worker", qos: .userInitiated)
    private var queryQueue = DispatchQueue(label: "com.amora.applescript.query-worker", qos: .userInitiated)
    private let timeoutQueue = DispatchQueue(label: "com.amora.applescript.timeout", qos: .userInitiated)
    private var isQueryExecuting = false

    public init() {}

    /// Whether a read-only query is currently in-flight on the query worker queue.
    public var isQueryOutstanding: Bool {
        queueLock.withLock { isQueryExecuting }
    }

    /// Recovers worker queues when an external application terminates or restarts.
    /// If `retireCommandQueue` is true, replaces the command queue with a fresh instance
    /// (safe when the target application process is confirmed terminated).
    public func recoverStuckWorker(retireCommandQueue: Bool = false) {
        queueLock.withLock {
            if retireCommandQueue {
                logDiagnostic("Retiring command queue due to external application termination")
                self.commandQueue = DispatchQueue(label: "com.amora.applescript.command-worker.\(UUID().uuidString.prefix(8))", qos: .userInitiated)
            }
            self.queryQueue = DispatchQueue(label: "com.amora.applescript.query-worker.\(UUID().uuidString.prefix(8))", qos: .userInitiated)
            self.isQueryExecuting = false
        }
    }

    public func execute(source: String, timeout: TimeInterval, isMutating: Bool) async -> AmoraAppleScriptResult {
        if Task.isCancelled {
            return .cancelled
        }

        // Bounded query protection: If a previous query execution is still outstanding on the query worker
        // (e.g. Apple Music is hung), quarantine the worker and suppress further queries until it finishes.
        // This prevents unbounded queue/thread creation while keeping the commandQueue completely responsive.
        if !isMutating {
            let quarantined: Bool = queueLock.withLock {
                if isQueryExecuting {
                    return true
                }
                isQueryExecuting = true
                return false
            }
            if quarantined {
                logDiagnostic("Suppressing AppleScript query: query worker is quarantined with an outstanding execution.")
                return .queryQuarantined
            }
        }

        let request = ScriptExecutionRequest(source: source, timeout: timeout, isMutating: isMutating)
        let continuationBox = ContinuationBox()

        let targetQueue: DispatchQueue = queueLock.withLock {
            isMutating ? self.commandQueue : self.queryQueue
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                continuationBox.set(continuation)

                // Schedule bounded timeout
                self.timeoutQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    if request.markTimedOut() {
                        self?.logDiagnostic("AppleScript timed out after \(timeout)s (id: \(request.id), mutating: \(isMutating))")
                        continuationBox.resume(returning: .timedOut(timeout))
                    }
                }

                // Enqueue work on serial background worker queue
                targetQueue.async { [weak self] in
                    defer {
                        if !isMutating {
                            self?.queueLock.withLock {
                                self?.isQueryExecuting = false
                            }
                        }
                    }

                    // If pre-empted by timeout or cancellation before starting, skip execution
                    if request.isDone {
                        self?.logDiagnostic("Skipping pre-empted AppleScript (id: \(request.id))")
                        return
                    }

                    var errorInfo: NSDictionary?
                    guard let script = NSAppleScript(source: request.source) else {
                        if request.markCompleted() {
                            continuationBox.resume(returning: .scriptCreationFailed)
                        }
                        return
                    }

                    let output = script.executeAndReturnError(&errorInfo)

                    let result: AmoraAppleScriptResult
                    if let errorInfo {
                        let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? -1
                        let msg = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript execution error"
                        result = .error(code: code, message: msg)
                    } else {
                        result = .success(output.stringValue ?? "")
                    }

                    if request.markCompleted() {
                        continuationBox.resume(returning: result)
                    } else {
                        self?.logDiagnostic("Late completion discarded for script (id: \(request.id), mutating: \(isMutating), result: \(result))")
                    }
                }
            }
        } onCancel: {
            if request.markCancelled() {
                continuationBox.resume(returning: .cancelled)
            }
        }
    }

    private func logDiagnostic(_ message: String) {
        #if DEBUG
        print("[AmoraAppleScriptExecutor] \(message)")
        #endif
    }
}

// MARK: - Internal Concurrency Helpers

private final class ScriptExecutionRequest: @unchecked Sendable {
    let id: UUID
    let source: String
    let timeout: TimeInterval
    let isMutating: Bool
    let queuedAt: Date

    private let lock = NSLock()
    private var _completed = false
    private var _timedOut = false
    private var _cancelled = false

    init(id: UUID = UUID(), source: String, timeout: TimeInterval, isMutating: Bool = true) {
        self.id = id
        self.source = source
        self.timeout = timeout
        self.isMutating = isMutating
        self.queuedAt = Date()
    }

    var isDone: Bool {
        lock.withLock { _completed || _timedOut || _cancelled }
    }

    func markTimedOut() -> Bool {
        lock.withLock {
            if _completed || _timedOut || _cancelled { return false }
            _timedOut = true
            return true
        }
    }

    func markCancelled() -> Bool {
        lock.withLock {
            if _completed || _timedOut || _cancelled { return false }
            _cancelled = true
            return true
        }
    }

    func markCompleted() -> Bool {
        lock.withLock {
            if _completed || _timedOut || _cancelled { return false }
            _completed = true
            return true
        }
    }
}

private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<AmoraAppleScriptResult, Never>?
    private var pendingResult: AmoraAppleScriptResult?

    func set(_ continuation: CheckedContinuation<AmoraAppleScriptResult, Never>) {
        let toResume: (CheckedContinuation<AmoraAppleScriptResult, Never>, AmoraAppleScriptResult)? = lock.withLock {
            if let result = self.pendingResult {
                self.pendingResult = nil
                return (continuation, result)
            } else {
                self.continuation = continuation
                return nil
            }
        }
        toResume?.0.resume(returning: toResume!.1)
    }

    func resume(returning result: AmoraAppleScriptResult) {
        let cont = lock.withLock { () -> CheckedContinuation<AmoraAppleScriptResult, Never>? in
            if let continuation = self.continuation {
                self.continuation = nil
                return continuation
            } else {
                if self.pendingResult == nil {
                    self.pendingResult = result
                }
                return nil
            }
        }
        cont?.resume(returning: result)
    }
}

// MARK: - Mock Implementation for Unit Tests

public final class MockAppleScriptExecutor: AmoraAppleScriptExecuting, @unchecked Sendable {
    public struct ExecutionRecord: Equatable, Sendable {
        public let source: String
        public let timeout: TimeInterval
        public let isMutating: Bool
        public let timestamp: Date

        public init(source: String, timeout: TimeInterval, isMutating: Bool = true, timestamp: Date = Date()) {
            self.source = source
            self.timeout = timeout
            self.isMutating = isMutating
            self.timestamp = timestamp
        }
    }

    private let lock = NSLock()
    private var _history: [ExecutionRecord] = []
    private var _defaultResult: AmoraAppleScriptResult
    private var _delay: TimeInterval
    private var _scriptResponses: [String: AmoraAppleScriptResult] = [:]
    private var _customHandler: (@Sendable (String, TimeInterval) async -> AmoraAppleScriptResult)?

    public init(
        defaultResult: AmoraAppleScriptResult = .success(""),
        delay: TimeInterval = 0
    ) {
        self._defaultResult = defaultResult
        self._delay = delay
    }

    public var history: [ExecutionRecord] {
        lock.withLock { _history }
    }

    public var executionCount: Int {
        lock.withLock { _history.count }
    }

    public func setResponse(forScriptContaining substring: String, result: AmoraAppleScriptResult) {
        lock.withLock {
            _scriptResponses[substring] = result
        }
    }

    public func setCustomHandler(_ handler: (@Sendable (String, TimeInterval) async -> AmoraAppleScriptResult)?) {
        lock.withLock {
            _customHandler = handler
        }
    }

    public func setDefaultResult(_ result: AmoraAppleScriptResult) {
        lock.withLock {
            _defaultResult = result
        }
    }

    public func setDelay(_ delay: TimeInterval) {
        lock.withLock {
            _delay = delay
        }
    }

    public func reset() {
        lock.withLock {
            _history.removeAll()
            _scriptResponses.removeAll()
            _customHandler = nil
            _delay = 0
            _defaultResult = .success("")
        }
    }

    public func execute(source: String, timeout: TimeInterval, isMutating: Bool) async -> AmoraAppleScriptResult {
        let (handler, delay, result): ((@Sendable (String, TimeInterval) async -> AmoraAppleScriptResult)?, TimeInterval, AmoraAppleScriptResult) = lock.withLock {
            _history.append(ExecutionRecord(source: source, timeout: timeout, isMutating: isMutating))
            let d = _delay
            if let custom = _customHandler {
                return (custom, d, _defaultResult)
            }
            for (pattern, res) in _scriptResponses {
                if source.contains(pattern) {
                    return (nil, d, res)
                }
            }
            return (nil, d, _defaultResult)
        }

        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        if Task.isCancelled {
            return .cancelled
        }

        if let handler = handler {
            return await handler(source, timeout)
        }

        return result
    }
}
