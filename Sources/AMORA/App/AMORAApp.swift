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

        print("🚀 Running AMORA Evaluation V1 in mode: \(mode.rawValue)...")
        let runner = AmoraEvaluationRunner(mode: mode)
        let report = await runner.run { current, total, scenario in
            print("[\(current)/\(total)] \(scenario.id) (\(scenario.category.rawValue))")
        }
        print("\n" + AmoraEvaluationRunner.formatMarkdownReport(report))
        AmoraLlamaCppRuntime.shared.unloadSync()
    }
}
