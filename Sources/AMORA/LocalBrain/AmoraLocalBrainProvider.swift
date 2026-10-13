import Foundation

/// Concrete offline AI provider for AMORA using local in-process model execution.
/// Conforms to `AIProvider` and communicates with the model via `AmoraLocalModelRuntime`.
final class AmoraLocalBrainProvider: AIProvider, @unchecked Sendable {
    static let shared = MainActor.assumeIsolated { AmoraLocalBrainProvider() }

    let kind: AIProviderKind = .local
    let runtime: any AmoraLocalModelRuntime
    let modelManager: any AmoraModelManaging

    init(
        runtime: (any AmoraLocalModelRuntime)? = nil,
        modelManager: (any AmoraModelManaging)? = nil
    ) {
        self.runtime = runtime ?? AmoraLlamaCppRuntime.shared
        if let modelManager {
            self.modelManager = modelManager
        } else {
            self.modelManager = MainActor.assumeIsolated { AmoraModelManager.shared }
        }
    }

    /// Comparison-only factory for loading a model from an explicit file path.
    static func forModelPath(_ path: String, descriptor: AmoraModelDescriptor? = nil) -> AmoraLocalBrainProvider {
        MainActor.assumeIsolated {
            let modelURL = URL(fileURLWithPath: path)
            let desc: AmoraModelDescriptor
            if let descriptor {
                desc = descriptor
            } else if path.localizedCaseInsensitiveContains("smollm") {
                desc = .smollm3_3b
            } else if path.contains("1.5b") || path.contains("1_5b") {
                desc = .qwen2_5_1_5b
            } else if path.contains("0.5b") || path.contains("0_5b") {
                desc = .qwen2_5_0_5b
            } else {
                desc = .explicitCandidate(path: path)
            }
            let manager = AmoraModelManager.forEvaluation(modelURL: modelURL, descriptor: desc)
            return AmoraLocalBrainProvider(modelManager: manager)
        }
    }

    var isAvailable: Bool {
        availability == .available
    }

    var availability: AIAvailability {
        let isReady = MainActor.assumeIsolated {
            _ = modelManager.checkStatusSync()
            return modelManager.isReady
        }
        return isReady ? .available : .modelNotReady
    }

    func send(messages: [AIMessage], model: String, apiKey: String?) async throws -> String {
        try Task.checkCancellation()

        let (isReady, modelPath, descriptor, isEvalMode) = await MainActor.run {
            _ = modelManager.checkStatusSync()
            return (modelManager.isReady, modelManager.modelFileURL.path, modelManager.descriptor, AMORAToolRegistry.isControlledEvaluationMode)
        }
        guard isReady else {
            throw AIProviderError.modelNotReady
        }

        // Ensure model is loaded in runtime
        if !runtime.isLoaded || runtime.loadedModelPath != modelPath {
            let config = AmoraModelRuntimeConfiguration(
                contextLength: descriptor.contextLength,
                gpuLayers: 99,
                threads: max(1, ProcessInfo.processInfo.processorCount / 2)
            )
            do {
                try await runtime.loadModel(from: modelPath, configuration: config)
            } catch is CancellationError {
                throw CancellationError()
            } catch let err as AmoraLocalRuntimeError {
                if case .outOfMemory = err {
                    throw AIProviderError.deviceNotEligible
                }
                throw AIProviderError.modelNotReady
            } catch {
                throw AIProviderError.modelNotReady
            }
        }

        try Task.checkCancellation()

        // Format prompt using descriptor's ChatML template
        let formattedPrompt = descriptor.formatPrompt(messages: messages)

        let options = AmoraInferenceOptions(
            temperature: isEvalMode ? 0.0 : 0.3,
            topP: isEvalMode ? 1.0 : 0.85,
            maxTokens: 256,
            stopSequences: descriptor.stopSequences,
            seed: isEvalMode ? 42 : nil
        )

        do {
            let result = try await runtime.generate(prompt: formattedPrompt, options: options, onToken: nil)
            try Task.checkCancellation()
            let stripped = Self.stripThinkingBlocks(result)
            let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AIProviderError.invalidResponse
            }
            return trimmed
        } catch is CancellationError {
            throw CancellationError()
        } catch let err as AIProviderError {
            throw err
        } catch {
            throw AIProviderError.generationFailure
        }
    }

    /// Strips `<think>...</think>` tags and content if present in model output.
    static func stripThinkingBlocks(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: []) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: (result as NSString).length), withTemplate: "")
        }
        if result.contains("<think>") && !result.contains("</think>") {
            if let openRange = result.range(of: "<think>") {
                result = String(result[..<openRange.lowerBound])
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
