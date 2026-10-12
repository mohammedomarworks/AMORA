import Foundation

/// Portable runtime configuration for local LLM inference engines.
public struct AmoraModelRuntimeConfiguration: Equatable, Sendable {
    public var contextLength: Int
    public var gpuLayers: Int
    public var threads: Int

    public init(
        contextLength: Int = 2048,
        gpuLayers: Int = 99,
        threads: Int = max(1, ProcessInfo.processInfo.processorCount / 2)
    ) {
        self.contextLength = contextLength
        self.gpuLayers = gpuLayers
        self.threads = threads
    }
}

/// Generation options for inference requests.
public struct AmoraInferenceOptions: Equatable, Sendable {
    public var temperature: Float
    public var topP: Float
    public var maxTokens: Int
    public var stopSequences: [String]
    public var seed: UInt32?

    public init(
        temperature: Float = 0.7,
        topP: Float = 0.8,
        maxTokens: Int = 512,
        stopSequences: [String] = ["<|im_end|>", "<|endoftext|>"],
        seed: UInt32? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.stopSequences = stopSequences
        self.seed = seed
    }
}

/// Typed errors produced by local model runtimes.
public enum AmoraLocalRuntimeError: Error, Equatable, Sendable {
    case modelNotFound(String)
    case modelLoadFailed(String)
    case contextInitFailed
    case tokenizationFailed
    case outOfMemory
    case inferenceFailed(String)
    case cancelled
}

/// Portable, platform-agnostic interface for local LLM inference engines.
/// Keeps low-level C/C++ libraries (llama.cpp, DirectML, ONNX, etc.) behind a clean Swift boundary.
public protocol AmoraLocalModelRuntime: Sendable {
    var isLoaded: Bool { get }
    var loadedModelPath: String? { get }

    func loadModel(from path: String, configuration: AmoraModelRuntimeConfiguration) async throws
    func unloadModel() async
    func generate(
        prompt: String,
        options: AmoraInferenceOptions,
        onToken: (@Sendable (String) -> Void)?
    ) async throws -> String
}

/// Mock runtime for deterministic tests and previews. Never requires native model files or I/O.
public final class MockLocalModelRuntime: AmoraLocalModelRuntime, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.amora.mockruntime")
    private var _isLoaded = false
    private var _loadedModelPath: String?
    public var responseToReturn: String
    public var shouldFailLoad: Bool
    public var loadErrorMessage: String
    public var shouldFailGeneration: Bool
    public var generationErrorMessage: String
    public var simulatedDelayNanoseconds: UInt64
    public var tokensToStream: [String]?
    public var responsesQueue: [String]?

    public var isLoaded: Bool {
        queue.sync { _isLoaded }
    }

    public var loadedModelPath: String? {
        queue.sync { _loadedModelPath }
    }

    public init(
        responseToReturn: String = "Hello from AMORA Local Brain!",
        responsesQueue: [String]? = nil,
        shouldFailLoad: Bool = false,
        loadErrorMessage: String = "Simulated model load failure",
        shouldFailGeneration: Bool = false,
        generationErrorMessage: String = "Simulated generation error",
        simulatedDelayNanoseconds: UInt64 = 0,
        tokensToStream: [String]? = nil
    ) {
        self.responseToReturn = responseToReturn
        self.responsesQueue = responsesQueue
        self.shouldFailLoad = shouldFailLoad
        self.loadErrorMessage = loadErrorMessage
        self.shouldFailGeneration = shouldFailGeneration
        self.generationErrorMessage = generationErrorMessage
        self.simulatedDelayNanoseconds = simulatedDelayNanoseconds
        self.tokensToStream = tokensToStream
    }

    public func loadModel(from path: String, configuration: AmoraModelRuntimeConfiguration) async throws {
        if simulatedDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: simulatedDelayNanoseconds)
        }
        try Task.checkCancellation()
        try queue.sync {
            if shouldFailLoad {
                throw AmoraLocalRuntimeError.modelLoadFailed(loadErrorMessage)
            }
            _isLoaded = true
            _loadedModelPath = path
        }
    }

    public func unloadModel() async {
        queue.sync {
            _isLoaded = false
            _loadedModelPath = nil
        }
    }

    public func generate(
        prompt: String,
        options: AmoraInferenceOptions,
        onToken: (@Sendable (String) -> Void)?
    ) async throws -> String {
        guard isLoaded else {
            throw AmoraLocalRuntimeError.modelLoadFailed("No model loaded in runtime.")
        }
        if simulatedDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: simulatedDelayNanoseconds)
        }
        try Task.checkCancellation()

        if shouldFailGeneration {
            throw AmoraLocalRuntimeError.inferenceFailed(generationErrorMessage)
        }

        if let tokens = tokensToStream {
            var full = ""
            for tok in tokens {
                try Task.checkCancellation()
                onToken?(tok)
                full += tok
            }
            return full
        }

        let textToReturn: String = queue.sync {
            if var currentQueue = self.responsesQueue, !currentQueue.isEmpty {
                let next = currentQueue.removeFirst()
                self.responsesQueue = currentQueue
                return next
            }
            return self.responseToReturn
        }

        onToken?(textToReturn)
        return textToReturn
    }
}
