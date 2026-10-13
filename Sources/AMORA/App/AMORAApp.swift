import AppKit

@main
@MainActor
enum AMORAApp {
    private static var appDelegate: AppDelegate?

    static func main() async {
        if CommandLine.arguments.contains("--smoke-test") {
            var explicitModelPath: String? = nil
            let args = CommandLine.arguments
            for (idx, arg) in args.enumerated() {
                if (arg == "--model-path" || arg == "--candidate-path") && idx + 1 < args.count {
                    explicitModelPath = args[idx + 1]
                    break
                }
            }
            await runSmokeTestCLI(explicitModelPath: explicitModelPath)
            return
        }

        if CommandLine.arguments.contains("--eval") || CommandLine.arguments.contains("eval") {
            await runEvaluationCLI()
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    private static func runEvaluationCLI() async {
        let args = CommandLine.arguments
        let mode: EvaluationRunnerMode
        if args.contains("--router") {
            mode = .deterministicOnly
        } else if args.contains("--real") {
            mode = .realModelOnly
        } else if args.contains("--mock") {
            mode = .mockBaseline
        } else {
            mode = .endToEndProduction
        }

        var explicitModelPath: String? = nil
        for (idx, arg) in args.enumerated() {
            if (arg == "--model-path" || arg == "--candidate-path") && idx + 1 < args.count {
                explicitModelPath = args[idx + 1]
                break
            }
        }

        let provider: AmoraLocalBrainProvider?
        if let path = explicitModelPath {
            provider = AmoraLocalBrainProvider.forModelPath(path)
        } else {
            provider = nil
        }

        print("🚀 Running AMORA Evaluation V1 in mode: \(mode.rawValue)...")
        if let provider {
            print("🤖 Evaluated Model: \(provider.modelManager.descriptor.displayName) (Path: \(provider.modelManager.modelFileURL.path))")
        } else {
            print("🤖 Evaluated Model: Default Model (\(AmoraModelDescriptor.defaultModel.displayName))")
        }

        let runner = AmoraEvaluationRunner(mode: mode, provider: provider)
        let report = await runner.run { current, total, scenario in
            print("[\(current)/\(total)] \(scenario.id) (\(scenario.category.rawValue))")
        }
        print("\n" + AmoraEvaluationRunner.formatMarkdownReport(report))
        AmoraLlamaCppRuntime.shared.unloadSync()
        fflush(stdout)
        exit(0)
    }

    private static func runSmokeTestCLI(explicitModelPath: String?) async {
        let path = explicitModelPath ?? AmoraModelManager.shared.modelFileURL.path
        print("🔍 Starting Runtime Smoke Test for: \(path)")
        let provider: AmoraLocalBrainProvider
        if let explicit = explicitModelPath {
            provider = AmoraLocalBrainProvider.forModelPath(explicit)
        } else {
            provider = AmoraLocalBrainProvider.shared
        }
        let desc = provider.modelManager.descriptor
        print("🤖 Model: \(desc.displayName)")
        print("🆔 ID: \(desc.id)")
        print("📁 Path: \(provider.modelManager.modelFileURL.path)")
        print("📏 Prefix: '\(desc.generationPrefix)'")

        // Test 1: Simple Question ("What is 2+2?")
        print("\n--- Test 1: Simple Question ('What is 2+2?') ---")
        do {
            let messages = [AIMessage(role: .user, content: "What is 2+2?")]
            let resp = try await provider.send(messages: messages, model: desc.id, apiKey: nil)
            print("Response text: \(resp)")
            let decision = try AmoraAgentDecisionParser.parse(resp)
            print("Parsed decision: \(decision)")
        } catch {
            print("Test 1 FAILED: \(error)")
        }

        // Test 2: AI Talk Note-Search Request through AssistantManager
        print("\n--- Test 2: AI Talk Note Search ('Find notes about budget') ---")
        NotesService.shared.useIsolatedStorage()
        NotesService.shared.clearAll()
        NotesService.shared.addNote("Quarterly budget review meeting on Friday")
        let assistant = AssistantManager(provider: provider)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)
        let noteAnswer = await assistant.submit("Find notes about budget", settings: settings)
        print("AI Talk Note Response: \(noteAnswer)")

        // Test 3: AI Talk 10-minute Timer through AssistantManager
        print("\n--- Test 3: AI Talk Timer ('Set a 10 minute timer') ---")
        TimerService.shared.isSimulationMode = true
        let timerAnswer = await assistant.submit("Set a 10 minute timer", settings: settings)
        print("AI Talk Timer Response: \(timerAnswer)")
        print("Timer Running State: \(TimerService.shared.isRunning), Remaining: \(TimerService.shared.remainingSeconds)s")

        AmoraLlamaCppRuntime.shared.unloadSync()
        fflush(stdout)
        exit(0)
    }
}
