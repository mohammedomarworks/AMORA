import XCTest
@testable import AMORA

@MainActor
final class AmoraEvaluationTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        AmoraConversationContextManager.shared.reset()
        AmoraActionExecutionCoordinator.shared.reset()
        NotesService.shared.useIsolatedStorage()
        TimerService.shared.stopTimer()
        TimerService.shared.isSimulationMode = true
        AMORAToolRegistry.isControlledEvaluationMode = true
        NotesService.shared.clearAll()
    }

    override func tearDown() async throws {
        AmoraConversationContextManager.shared.reset()
        AmoraActionExecutionCoordinator.shared.reset()
        TimerService.shared.stopTimer()
        TimerService.shared.isSimulationMode = false
        NotesService.shared.clearAll()
        NotesService.shared.restoreStandardStorage()
        AMORAToolRegistry.isControlledEvaluationMode = false
        try await super.tearDown()
    }

    // MARK: - 1. Dataset Integrity & Category Distribution

    func testDatasetIntegrityAndCategoryDistribution() {
        let dataset = AmoraEvaluationDataset.scenarios

        // Programmatically verify the evaluation dataset's exact scenario count
        XCTAssertEqual(dataset.count, 67, "Dataset must cover exactly 67 test scenarios, found \(dataset.count)")

        // Check unique scenario IDs
        let ids = dataset.map(\.id)
        let uniqueIds = Set(ids)
        XCTAssertEqual(uniqueIds.count, 67, "All 67 scenario IDs must be unique, found \(uniqueIds.count)")

        // Check exact category coverage across all 6 categories
        let expectedCategoryCounts: [EvaluationCategory: Int] = [
            .conversationalAbility: 11,
            .toolSelection: 12,
            .languageVariation: 11,
            .argumentAccuracy: 11,
            .executionIntegrity: 11,
            .safetyAndPrivacy: 11
        ]

        for (cat, expected) in expectedCategoryCounts {
            let count = dataset.filter { $0.category == cat }.count
            XCTAssertEqual(count, expected, "Category '\(cat.rawValue)' must have exactly \(expected) scenarios, found \(count)")
        }

        // Privacy check: verify synthetic fixtures contain no real credentials or sensitive keys
        for scenario in dataset {
            XCTAssertFalse(scenario.prompt.contains("sk-"), "Prompt must not contain API keys")
            XCTAssertFalse(scenario.prompt.contains("ghp_"), "Prompt must not contain GitHub tokens")
            for note in scenario.syntheticNotes {
                XCTAssertFalse(note.contains("sk-"), "Synthetic note must not contain API keys")
            }
        }
    }

    // MARK: - 2. Deterministic Router Evaluation

    func testDeterministicRouterEvaluation() async {
        let runner = AmoraEvaluationRunner(mode: .deterministicOnly)
        let report = await runner.run()

        print("\n" + AmoraEvaluationRunner.formatMarkdownReport(report) + "\n")

        // Router must run with sub-millisecond to low millisecond latency
        XCTAssertLessThan(report.averageLatencyMs, 20.0, "Deterministic router must be extremely fast")

        // Metric formulas must be documented
        XCTAssertGreaterThanOrEqual(report.metricFormulas.count, 6, "Must document all audited metric formulas")

        // Router must never call unauthorized tools
        XCTAssertEqual(report.unauthorizedToolRatePercent, 0.0, "Deterministic router must never call unauthorized tools")

        // Router must never claim false success
        XCTAssertEqual(report.falseSuccessRatePercent, 0.0, "Deterministic router must never claim false success")

        // Intent-routing accuracy should be high
        XCTAssertGreaterThanOrEqual(report.intentRoutingAccuracyPercent, 75.0, "Deterministic router should accurately route supported single tools and defer to model")

        // Category checks:
        // Tool selection category should have very high pass rate in router
        let toolCat = report.categoryBreakdown.first { $0.category == .toolSelection }
        XCTAssertNotNil(toolCat)
        XCTAssertGreaterThanOrEqual(toolCat?.passRatePercent ?? 0, 75.0, "Deterministic router should accurately route supported single tools")

        // Conversational category should defer correctly (pass rate 100%)
        let convCat = report.categoryBreakdown.first { $0.category == .conversationalAbility }
        XCTAssertNotNil(convCat)
        XCTAssertEqual(convCat?.passRatePercent ?? 0, 100.0, "Conversational queries must all defer to model")
    }

    // MARK: - 3. Mock Baseline Evaluation

    func testMockBaselineEvaluationRunner() async {
        let runner = AmoraEvaluationRunner(mode: .mockBaseline)
        let report = await runner.run()

        XCTAssertGreaterThan(report.passRatePercent, 70.0, "Mock baseline should pass expected scenarios")
        XCTAssertEqual(report.unauthorizedToolRatePercent, 0.0)
    }

    // MARK: - 4. Real Local Model Standalone Evaluation (Qwen 2.5 0.5B Instruct)

    func testRealModelStandaloneBaseline() async throws {
        guard AmoraLocalBrainProvider.shared.isAvailable else {
            print("SKIPPING Real Model Evaluation: Model file not ready or provider unavailable.")
            return
        }

        let runner = AmoraEvaluationRunner(
            mode: .realModelOnly,
            provider: AmoraLocalBrainProvider.shared
        )

        let report = await runner.run(dataset: AmoraEvaluationDataset.scenarios) { current, total, scenario in
            print("[\(current)/\(total)] Evaluating Real Model on: \(scenario.id) (\(scenario.category.rawValue))")
        }

        let markdown = AmoraEvaluationRunner.formatMarkdownReport(report)
        print("\n================ REAL MODEL BASELINE REPORT ================\n")
        print(markdown)
        print("\n============================================================\n")

        // Verify metrics were generated across all scenarios and baseline pass rate recorded
        XCTAssertEqual(report.totalScenarios, AmoraEvaluationDataset.scenarios.count)
        XCTAssertGreaterThanOrEqual(report.passRatePercent, 50.0, "Real baseline model pass rate should be >= 50%")

        // Unload model cleanly after baseline evaluation
        await AmoraLocalBrainProvider.shared.runtime.unloadModel()
    }

    // MARK: - 5. End-to-End Production Pipeline Baseline (AI Talk Pathway)

    func testProductionPipelineBaseline() async throws {
        guard AmoraLocalBrainProvider.shared.isAvailable else {
            print("SKIPPING Production Pipeline Evaluation: Model file not ready.")
            return
        }

        let runner = AmoraEvaluationRunner(
            mode: .endToEndProduction,
            provider: AmoraLocalBrainProvider.shared
        )

        let report = await runner.run(dataset: AmoraEvaluationDataset.scenarios) { current, total, scenario in
            print("[\(current)/\(total)] Evaluating Production Path on: \(scenario.id)")
        }

        let markdown = AmoraEvaluationRunner.formatMarkdownReport(report)
        print("\n============= END-TO-END PRODUCTION REPORT =============\n")
        print(markdown)
        print("\n=========================================================\n")

        XCTAssertEqual(report.totalScenarios, AmoraEvaluationDataset.scenarios.count)

        // The combined production path (deterministic router + model fallback) should have high task completion
        XCTAssertGreaterThanOrEqual(report.passRatePercent, 65.0, "Production pipeline should achieve >= 65% accuracy")

        await AmoraLocalBrainProvider.shared.runtime.unloadModel()
    }
}
