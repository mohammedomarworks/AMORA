import Foundation
import LlamaSwift
#if canImport(llama)
import llama
#endif

/// In-process native llama.cpp runtime for AMORA Local Brain.
/// Operates natively inside the AMORA process with Metal GPU acceleration on Apple Silicon.
public final class AmoraLlamaCppRuntime: AmoraLocalModelRuntime, @unchecked Sendable {
    public static let shared = AmoraLlamaCppRuntime()

    private let lock = NSLock()
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var currentPath: String?
    private var currentConfig: AmoraModelRuntimeConfiguration?
    private var isBackendInitialized = false
    private var prewarmTask: Task<Void, Error>?

    public var isLoaded: Bool {
        lock.withLock { model != nil && context != nil }
    }

    public var loadedModelPath: String? {
        lock.withLock { currentPath }
    }

    public var isPrewarmed: Bool {
        lock.withLock { isBackendInitialized }
    }

    public init() {
        // Backend initialization is intentionally deferred to prewarm() or loadModelSync()
        // so instantiating this runtime never blocks callers or the main actor.
    }

    deinit {
        unloadSync()
        lock.withLock {
            if isBackendInitialized {
                llama_backend_free()
                isBackendInitialized = false
            }
        }
    }

    public func prewarm() async throws {
        try Task.checkCancellation()

        let task: Task<Void, Error>? = lock.withLock {
            if isBackendInitialized {
                return nil
            }
            if let existing = prewarmTask {
                return existing
            }
            let newTask = Task.detached(priority: .utility) { [weak self] in
                try Task.checkCancellation()
                self?.initBackendSync()
                try Task.checkCancellation()
            }
            self.prewarmTask = newTask
            return newTask
        }

        guard let task else { return }

        do {
            try await task.value
            lock.withLock {
                self.prewarmTask = nil
            }
        } catch {
            lock.withLock {
                self.prewarmTask = nil
            }
            throw error
        }
    }

    private func initBackendSync() {
        lock.withLock {
            guard !isBackendInitialized else { return }
            llama_backend_init()
            isBackendInitialized = true
        }
    }

    public func cancelPrewarm() {
        let task: Task<Void, Error>? = lock.withLock {
            let t = prewarmTask
            prewarmTask = nil
            return t
        }
        task?.cancel()
    }

    public func loadModel(from path: String, configuration: AmoraModelRuntimeConfiguration) async throws {
        try Task.checkCancellation()

        let existingPrewarm: Task<Void, Error>? = lock.withLock { prewarmTask }
        if let existingPrewarm {
            _ = try? await existingPrewarm.value
        }

        try Task.checkCancellation()

        try await Task.detached(priority: .userInitiated) { [self] in
            try self.loadModelSync(from: path, configuration: configuration)
        }.value
    }

    public func unloadModel() async {
        await Task.detached(priority: .utility) { [self] in
            self.unloadSync()
        }.value
    }

    public func generate(
        prompt: String,
        options: AmoraInferenceOptions,
        onToken: (@Sendable (String) -> Void)?
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) { [self] in
            try self.generateSync(prompt: prompt, options: options, onToken: onToken)
        }.value
    }

    private func loadModelSync(from path: String, configuration: AmoraModelRuntimeConfiguration) throws {
        lock.lock()
        defer { lock.unlock() }

        if !isBackendInitialized {
            llama_backend_init()
            isBackendInitialized = true
        }

        // If already loaded with the same path and config, reuse it
        if model != nil, context != nil, currentPath == path, currentConfig == configuration {
            return
        }

        unloadCurrentModelUnsafe()

        guard FileManager.default.fileExists(atPath: path) else {
            throw AmoraLocalRuntimeError.modelNotFound("Model file does not exist at path: \(path)")
        }

        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = Int32(configuration.gpuLayers)

        guard let loadedModel = llama_model_load_from_file(path, mparams) else {
            throw AmoraLocalRuntimeError.modelLoadFailed("llama.cpp failed to load model from '\(path)'. File may be corrupted or incompatible.")
        }

        guard let loadedVocab = llama_model_get_vocab(loadedModel) else {
            llama_model_free(loadedModel)
            throw AmoraLocalRuntimeError.modelLoadFailed("Failed to read vocabulary from model.")
        }

        var cparams = llama_context_default_params()
        cparams.n_ctx = UInt32(configuration.contextLength)
        cparams.n_batch = 512
        cparams.n_threads = Int32(configuration.threads)
        cparams.n_threads_batch = Int32(configuration.threads)

        guard let loadedContext = llama_init_from_model(loadedModel, cparams) else {
            llama_model_free(loadedModel)
            throw AmoraLocalRuntimeError.contextInitFailed
        }

        self.model = loadedModel
        self.vocab = loadedVocab
        self.context = loadedContext
        self.currentPath = path
        self.currentConfig = configuration
    }

    public func unloadSync() {
        lock.lock()
        defer { lock.unlock() }
        prewarmTask?.cancel()
        prewarmTask = nil
        unloadCurrentModelUnsafe()
    }

    private func unloadCurrentModelUnsafe() {
        if let ctx = context {
            if let mem = llama_get_memory(ctx) {
                llama_memory_clear(mem, true)
            }
            llama_free(ctx)
            context = nil
        }
        if let m = model {
            llama_model_free(m)
            model = nil
        }
        vocab = nil
        currentPath = nil
        currentConfig = nil
    }

    private func generateSync(
        prompt: String,
        options: AmoraInferenceOptions,
        onToken: (@Sendable (String) -> Void)?
    ) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        guard self.model != nil, let context = self.context, let vocab = self.vocab else {
            throw AmoraLocalRuntimeError.modelLoadFailed("Model is not loaded into memory.")
        }

        // Clear any previous KV memory before evaluating new prompt
        if let mem = llama_get_memory(context) {
            llama_memory_clear(mem, true)
        }

        let maxCtx = Int32(currentConfig?.contextLength ?? 2048)
        var promptTokens = [llama_token](repeating: 0, count: Int(maxCtx))
        let promptLen = Int32(prompt.utf8.count)

        let nTokens = llama_tokenize(vocab, prompt, promptLen, &promptTokens, maxCtx, true, true)
        guard nTokens > 0 else {
            throw AmoraLocalRuntimeError.tokenizationFailed
        }
        promptTokens.removeSubrange(Int(nTokens)..<promptTokens.count)

        // Initialize Sampler Chain
        let sparams = llama_sampler_chain_default_params()
        guard let smpl = llama_sampler_chain_init(sparams) else {
            throw AmoraLocalRuntimeError.inferenceFailed("Failed to initialize sampler.")
        }
        defer { llama_sampler_free(smpl) }

        if options.temperature <= 0.05 {
            llama_sampler_chain_add(smpl, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(smpl, llama_sampler_init_top_p(options.topP, 1))
            llama_sampler_chain_add(smpl, llama_sampler_init_temp(options.temperature))
            let seed = options.seed ?? UInt32.random(in: 1...1_000_000)
            llama_sampler_chain_add(smpl, llama_sampler_init_dist(seed))
        }

        var batch = llama_batch_init(512, 0, 1)
        defer { llama_batch_free(batch) }

        // Evaluate prompt in batches of up to 512 tokens
        var pos: Int32 = 0
        for chunkStart in stride(from: 0, to: promptTokens.count, by: 512) {
            try Task.checkCancellation()
            let chunkEnd = min(chunkStart + 512, promptTokens.count)
            batch.n_tokens = 0
            for i in chunkStart..<chunkEnd {
                let token = promptTokens[i]
                let isLastToken = (i == promptTokens.count - 1)
                let idx = Int(batch.n_tokens)
                batch.token[idx] = token
                batch.pos[idx] = pos
                batch.n_seq_id[idx] = 1
                if let seqIds = batch.seq_id[idx] {
                    seqIds[0] = 0
                }
                batch.logits[idx] = isLastToken ? 1 : 0
                batch.n_tokens += 1
                pos += 1
            }
            if llama_decode(context, batch) != 0 {
                throw AmoraLocalRuntimeError.inferenceFailed("Failed to decode prompt at token position \(pos).")
            }
        }

        var outputText = ""
        let maxNewTokens = min(options.maxTokens, Int(maxCtx) - promptTokens.count)

        for _ in 0..<maxNewTokens {
            try Task.checkCancellation()

            let nextToken = llama_sampler_sample(smpl, context, -1)
            llama_sampler_accept(smpl, nextToken)

            if llama_vocab_is_eog(vocab, nextToken) {
                break
            }

            var buf = [CChar](repeating: 0, count: 256)
            let nBytes = llama_token_to_piece(vocab, nextToken, &buf, Int32(buf.count), 0, false)
            if nBytes > 0 {
                let piece = buf.withUnsafeBufferPointer { ptr in
                    String(decoding: UnsafeRawBufferPointer(start: ptr.baseAddress, count: Int(nBytes)), as: UTF8.self)
                }
                outputText += piece
                onToken?(piece)
            }

            var shouldStop = false
            for stop in options.stopSequences {
                if outputText.hasSuffix(stop) {
                    outputText = String(outputText.dropLast(stop.count))
                    shouldStop = true
                    break
                }
            }
            if shouldStop { break }

            // Decode next single token
            batch.n_tokens = 0
            batch.token[0] = nextToken
            batch.pos[0] = pos
            batch.n_seq_id[0] = 1
            if let seqIds = batch.seq_id[0] {
                seqIds[0] = 0
            }
            batch.logits[0] = 1
            batch.n_tokens = 1
            pos += 1

            if llama_decode(context, batch) != 0 {
                break
            }
        }

        return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
