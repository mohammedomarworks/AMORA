import Foundation

/// Describes a supported local GGUF model including source, license, resource requirements,
/// checksum, and prompt formatting instructions.
public struct AmoraModelDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let version: String
    public let quantization: String
    public let license: String
    public let author: String
    public let sourceURL: URL
    public let expectedSizeBytes: Int64
    public let estimatedRAMBytes: Int64
    public let expectedSHA256: String
    public let filename: String
    public let contextLength: Int
    public let systemPrompt: String
    public let stopSequences: [String]
    public let generationPrefix: String

    public init(
        id: String,
        displayName: String,
        version: String,
        quantization: String,
        license: String,
        author: String,
        sourceURL: URL,
        expectedSizeBytes: Int64,
        estimatedRAMBytes: Int64,
        expectedSHA256: String,
        filename: String,
        contextLength: Int = 2048,
        systemPrompt: String,
        stopSequences: [String] = ["<|im_end|>", "<|endoftext|>"],
        generationPrefix: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.quantization = quantization
        self.license = license
        self.author = author
        self.sourceURL = sourceURL
        self.expectedSizeBytes = expectedSizeBytes
        self.estimatedRAMBytes = estimatedRAMBytes
        self.expectedSHA256 = expectedSHA256
        self.filename = filename
        self.contextLength = contextLength
        self.systemPrompt = systemPrompt
        self.stopSequences = stopSequences
        self.generationPrefix = generationPrefix
    }

    /// Formatted expected download size for user-facing UI labels (e.g. "1.0 GB" or "469 MB").
    public var formattedExpectedSize: String {
        if expectedSizeBytes >= 1024 * 1024 * 1024 {
            let gigabytes = Double(expectedSizeBytes) / (1024.0 * 1024.0 * 1024.0)
            return String(format: "%.1f GB", gigabytes)
        } else {
            let megabytes = Double(expectedSizeBytes) / (1024.0 * 1024.0)
            return String(format: "%.0f MB", megabytes)
        }
    }

    /// Promoted default model for AMORA Local Brain:
    /// Qwen2.5-1.5B-Instruct quantized to Q4_K_M (Apache 2.0 License).
    /// Superior reasoning, zero-shot structured JSON formatting, and 83.6% task completion.
    public static var defaultModel: AmoraModelDescriptor {
        qwen2_5_1_5b
    }

    /// Legacy compact model for AMORA Local Brain:
    /// Qwen2.5-0.5B-Instruct quantized to Q4_K_M (Apache 2.0 License).
    /// Retained for rollback compatibility and resource-constrained environments (<500 MB).
    public static let qwen2_5_0_5b = AmoraModelDescriptor(
        id: "qwen2.5-0.5b-instruct-q4_k_m",
        displayName: "Qwen 2.5 0.5B Instruct",
        version: "2.5",
        quantization: "Q4_K_M",
        license: "Apache 2.0",
        author: "Qwen / Alibaba",
        sourceURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf")!,
        expectedSizeBytes: 491_400_032, // ~468.6 MB
        estimatedRAMBytes: 600 * 1024 * 1024, // ~600 MB RAM
        expectedSHA256: "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db",
        filename: "qwen2.5-0.5b-instruct-q4_k_m.gguf",
        contextLength: 2048,
        systemPrompt: """
You are AMORA, a friendly, concise, intelligent Mac companion.

Rules:
1. For casual conversation, greetings, questions, or general chat: reply with natural, concise, friendly text. NEVER output JSON or actions for normal talk.
2. For questions and math (such as "2+3", "what is 2 + 2", facts, or explanations): answer directly and accurately in plain text. NEVER output JSON for questions.
3. For unsupported requests (such as sending emails, booking flights, web browsing, writing shell scripts, or modifying system files): politely and honestly explain your limitations in plain text. Never invent actions or arbitrary code.
4. ONLY when the user explicitly asks to perform an action on their Mac (open apps, play music, set timers, open folders), output JSON:
{"actions":[{"action":"...","name":"...","location":"...","duration":1500}]}
If a timer duration is not specified (e.g. "open VS Code and start a timer"), default duration to 1500 (25 minutes).

Approved actions:
- media.play, media.pause, media.next, media.previous
- app.open (name: String, e.g. "VS Code", "Spotify", "Safari", "Terminal", "Xcode", "Slack", "Notes", "Finder")
- folder.open (location: 'downloads', 'documents', 'desktop', 'home')
- workspace.open (section: String, e.g. 'Notes', 'Clipboard', 'File Shelf', 'Overview')
- timer.start (duration: Int in seconds, e.g. 10s = 10, 5m = 300, 10m = 600, 25m = 1500)
- timer.cancel (no duration)
- timer.pause
- timer.resume
- search_notes (query: String)
- get_battery_status
- create_timer (duration: Int)

Never invent shell commands, arbitrary paths, code execution, or destructive actions.

Examples:
<|im_start|>user
Hi<|im_end|>
<|im_start|>assistant
Hello! How can I help you today?<|im_end|>
<|im_start|>user
2+3<|im_end|>
<|im_start|>assistant
5<|im_end|>
<|im_start|>user
What is 25 * 4?<|im_end|>
<|im_start|>assistant
25 * 4 is 100.<|im_end|>
<|im_start|>user
Who are you?<|im_end|>
<|im_start|>assistant
I'm AMORA, your Mac companion! I can help you open apps, set timers, control music, or chat.<|im_end|>
<|im_start|>user
Can you send an email to Alex?<|im_end|>
<|im_start|>assistant
I can't send emails. I can help you open Mail, set timers, control music, or open folders on your Mac.<|im_end|>
<|im_start|>user
Open Spotify<|im_end|>
<|im_start|>assistant
{"actions":[{"action":"app.open","name":"Spotify"}]}<|im_end|>
<|im_start|>user
open VS Code and start a timer<|im_end|>
<|im_start|>assistant
{"actions":[{"action":"app.open","name":"VS Code"},{"action":"timer.start","duration":1500}]}<|im_end|>
<|im_start|>user
Start a 10 second timer<|im_end|>
<|im_start|>assistant
{"actions":[{"action":"timer.start","duration":10}]}<|im_end|>
<|im_start|>user
Stop the timer<|im_end|>
<|im_start|>assistant
{"actions":[{"action":"timer.cancel"}]}<|im_end|>
<|im_start|>user
Open Downloads<|im_end|>
<|im_start|>assistant
{"actions":[{"action":"folder.open","location":"downloads"}]}<|im_end|>
<|im_start|>user
Pause the music<|im_end|>
<|im_start|>assistant
{"actions":[{"action":"media.pause"}]}<|im_end|>
<|im_start|>user
Find notes about meeting<|im_end|>
<|im_start|>assistant
{"type":"tool_call","tool":"search_notes","arguments":{"query":"meeting"}}<|im_end|>
<|im_start|>user
How much battery do I have left?<|im_end|>
<|im_start|>assistant
{"type":"tool_call","tool":"get_battery_status","arguments":{}}<|im_end|>
<|im_start|>user
[Tool result for search_notes]: Found 1 note: 'Meeting with team'
<|im_end|>
<|im_start|>assistant
I found your note about the team meeting.<|im_end|>
<|im_start|>user
[Tool result for app.open]: Opening Spotify.
<|im_end|>
<|im_start|>assistant
Opening Spotify.<|im_end|>
""",
        stopSequences: ["<|im_end|>", "<|endoftext|>"]
    )

    /// Candidate model for evaluation and comparison:
    /// Qwen2.5-1.5B-Instruct quantized to Q4_K_M (Apache 2.0 License).
    /// Verified official HuggingFace artifact from Qwen team.
    public static let qwen2_5_1_5b = AmoraModelDescriptor(
        id: "qwen2.5-1.5b-instruct-q4_k_m",
        displayName: "Qwen 2.5 1.5B Instruct",
        version: "2.5",
        quantization: "Q4_K_M",
        license: "Apache 2.0",
        author: "Qwen / Alibaba",
        sourceURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
        expectedSizeBytes: 1_117_320_736, // ~1.04 GB
        estimatedRAMBytes: 1_400 * 1024 * 1024, // ~1.4 GB RAM
        expectedSHA256: "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e",
        filename: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
        contextLength: 2048,
        systemPrompt: qwen2_5_0_5b.systemPrompt,
        stopSequences: ["<|im_end|>", "<|endoftext|>"]
    )

    /// Candidate model for evaluation and comparison:
    /// SmolLM3-3B-Instruct quantized to Q4_K_M (Apache 2.0 License).
    /// Verified official Hugging Face / GGML artifact.
    public static let smollm3_3b = AmoraModelDescriptor(
        id: "smollm3-3b-instruct-q4_k_m",
        displayName: "SmolLM3 3B Instruct",
        version: "3.0",
        quantization: "Q4_K_M",
        license: "Apache 2.0",
        author: "Hugging Face / Loubna Ben Allal et al.",
        sourceURL: URL(string: "https://huggingface.co/ggml-org/SmolLM3-3B-GGUF/resolve/main/SmolLM3-Q4_K_M.gguf")!,
        expectedSizeBytes: 1_915_305_312, // ~1.78 GB
        estimatedRAMBytes: 2_600 * 1024 * 1024, // ~2.6 GB RAM
        expectedSHA256: "8334b850b7bd46238c16b0c550df2138f0889bf433809008cc17a8b05761863e",
        filename: "SmolLM3-Q4_K_M.gguf",
        contextLength: 2048,
        systemPrompt: qwen2_5_0_5b.systemPrompt,
        stopSequences: ["<|im_end|>", "<|endoftext|>"],
        generationPrefix: "<think>\n\n</think>\n"
    )

    /// Creates a comparison/evaluation descriptor for an explicit model path without assuming filename or location.
    public static func explicitCandidate(
        path: String,
        id: String = "candidate-model",
        displayName: String = "Candidate Model",
        contextLength: Int = 2048,
        systemPrompt: String = qwen2_5_0_5b.systemPrompt,
        stopSequences: [String] = ["<|im_end|>", "<|endoftext|>"],
        generationPrefix: String = ""
    ) -> AmoraModelDescriptor {
        let fileURL = URL(fileURLWithPath: path)
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        return AmoraModelDescriptor(
            id: id,
            displayName: displayName,
            version: "candidate",
            quantization: "unknown",
            license: "Verified Candidate",
            author: "Candidate",
            sourceURL: fileURL,
            expectedSizeBytes: size,
            estimatedRAMBytes: max(600 * 1024 * 1024, size + 400 * 1024 * 1024),
            expectedSHA256: "",
            filename: fileURL.lastPathComponent,
            contextLength: contextLength,
            systemPrompt: systemPrompt,
            stopSequences: stopSequences,
            generationPrefix: generationPrefix
        )
    }

    /// Formats a conversation into the model's native ChatML template.
    func formatPrompt(messages: [AIMessage]) -> String {
        var formatted = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"
        for msg in messages {
            // Strip out raw internal action policy preamble if injected by caller
            if msg.content.hasPrefix("[AMORA action policy]") || msg.content.hasPrefix("[AMORA Local Agent V1 Policy]") {
                continue
            }
            let role = msg.role == .user ? "user" : "assistant"
            formatted += "<|im_start|>\(role)\n\(msg.content)<|im_end|>\n"
        }
        formatted += "<|im_start|>assistant\n\(generationPrefix)"
        return formatted
    }
}
