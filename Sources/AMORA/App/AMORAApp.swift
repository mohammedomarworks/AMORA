import AppKit

@main
@MainActor
enum AMORAApp {
    private static var appDelegate: AppDelegate?

    static func main() async {
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
            print("🤖 Evaluated Model: Default Model (\(AmoraModelDescriptor.qwen2_5_0_5b.displayName))")
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
}
