import Foundation

/// Categories of evaluation scenarios in AMORA.
public enum EvaluationCategory: String, Codable, Sendable, CaseIterable {
    case conversationalAbility = "Conversational Ability"
    case toolSelection = "Tool Selection"
    case languageVariation = "Language Variation"
    case argumentAccuracy = "Argument Accuracy"
    case executionIntegrity = "Execution Integrity"
    case safetyAndPrivacy = "Safety and Privacy"
}

/// Taxonomical failure categories for failed evaluation scenarios.
public enum FailureCategory: String, Codable, Sendable, CaseIterable {
    case wrongToolSelection = "Wrong Tool Selection"
    case missingToolCall = "Missing Tool Call"
    case unexpectedToolCall = "Unexpected Tool Call"
    case argumentExtractionFailed = "Argument Extraction Failed"
    case falseSuccessClaim = "False Success Claim"
    case unauthorizedToolAttempt = "Unauthorized Tool Attempt"
    case safetyPolicyViolation = "Safety Policy Violation"
    case confirmationHandlingFailed = "Confirmation Handling Failed"
    case executionFailed = "Execution Failed"
    case inferenceOrTimeout = "Inference Error / Timeout"
    case malformedModelOutput = "Malformed Model Output"
    case conversationalFailure = "Conversational Failure"
    case untested = "Untested / Model Unavailable"
}

/// Execution mode for running scenarios.
public enum EvaluationRunnerMode: String, Codable, Sendable {
    case deterministicOnly = "Deterministic Router"
    case realModelOnly = "Real Local Model (Agent Loop)"
    case endToEndProduction = "End-to-End Production (AI Talk)"
    case mockBaseline = "Mock Agent Baseline"
}

/// Simulation behavior when confirmation is requested for sensitive actions.
public enum EvaluationConfirmationBehavior: Sendable {
    case autoConfirm
    case autoDeny
    case expectNoConfirmation
}

/// Expected agent decision for a scenario.
public enum ExpectedDecision: Sendable {
    /// Pure conversational response; no tool should be invoked.
    case finalAnswer(keywords: [String] = [], forbidden: [String] = [])
    /// Single tool call expected.
    case toolCall(name: String, requiredArguments: [String: String] = [:], argumentValidator: (@MainActor @Sendable ([String: String]) -> Bool)? = nil)
    /// Multiple tool calls expected in sequence.
    case toolBatch(names: [String])
    /// Request should be rejected or explained as unsupported in plain text (no tool call).
    case unsupportedOrExplanation(keywords: [String] = [])
    /// Ambiguous request that should ask for clarification rather than executing prematurely.
    case ambiguityClarification
}

/// Context passed to custom scenario validators.
public struct EvaluationRunContext: Sendable {
    public let scenario: EvaluationScenario
    public let finalAnswer: String
    public let executedToolCount: Int
    public let executedTools: [(name: String, args: [String: String])]
    public let completedSuccessfully: Bool
    public let deniedConfirmation: Bool
}

/// Definition of an individual evaluation test scenario.
public struct EvaluationScenario: Identifiable, Sendable {
    public let id: String
    public let category: EvaluationCategory
    public let title: String
    public let prompt: String
    public let expectedDecision: ExpectedDecision
    public let permittedTools: [String]
    public let syntheticNotes: [String]
    public let syntheticMemories: [(key: String, value: String)]
    public let confirmationBehavior: EvaluationConfirmationBehavior
    public let contextAwarenessEnabled: Bool
    public let memoryEnabled: Bool
    public let customOutcomeVerifier: (@MainActor @Sendable (EvaluationRunContext) -> (passed: Bool, failureReason: String?))?

    public init(
        id: String,
        category: EvaluationCategory,
        title: String,
        prompt: String,
        expectedDecision: ExpectedDecision,
        permittedTools: [String] = [],
        syntheticNotes: [String] = [],
        syntheticMemories: [(key: String, value: String)] = [],
        confirmationBehavior: EvaluationConfirmationBehavior = .expectNoConfirmation,
        contextAwarenessEnabled: Bool = true,
        memoryEnabled: Bool = true,
        customOutcomeVerifier: (@MainActor @Sendable (EvaluationRunContext) -> (passed: Bool, failureReason: String?))? = nil
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.prompt = prompt
        self.expectedDecision = expectedDecision
        self.permittedTools = permittedTools
        self.syntheticNotes = syntheticNotes
        self.syntheticMemories = syntheticMemories
        self.confirmationBehavior = confirmationBehavior
        self.contextAwarenessEnabled = contextAwarenessEnabled
        self.memoryEnabled = memoryEnabled
        self.customOutcomeVerifier = customOutcomeVerifier
    }
}

/// Metric result for an evaluated scenario.
public struct ScenarioMetricResult: Identifiable, Codable, Sendable {
    public var id: String { scenarioId }
    public let scenarioId: String
    public let category: EvaluationCategory
    public let title: String
    public let prompt: String
    public let passed: Bool
    public let failureCategory: FailureCategory?
    public let failureReason: String?
    public let toolSelectionCorrect: Bool
    public let argumentExtractionCorrect: Bool
    public let taskCompletionCorrect: Bool
    public let unauthorizedToolAttempt: Bool
    public let falseSuccessClaimed: Bool
    public let ambiguityOrDenialHandledCorrectly: Bool
    public let latencyMs: Double
    public let inferenceFailed: Bool
    public let executedToolCount: Int
    public let finalAnswer: String
    public let observedTools: [String]
}

/// Explicitly documented formula and counting details for an evaluation metric.
public struct EvaluationMetricFormula: Codable, Sendable {
    public let name: String
    public let description: String
    public let formulaText: String
    public let numeratorDescription: String
    public let numeratorValue: Int
    public let denominatorDescription: String
    public let denominatorValue: Int
    public let percentage: Double

    public init(
        name: String,
        description: String,
        formulaText: String,
        numeratorDescription: String,
        numeratorValue: Int,
        denominatorDescription: String,
        denominatorValue: Int,
        percentage: Double
    ) {
        self.name = name
        self.description = description
        self.formulaText = formulaText
        self.numeratorDescription = numeratorDescription
        self.numeratorValue = numeratorValue
        self.denominatorDescription = denominatorDescription
        self.denominatorValue = denominatorValue
        self.percentage = percentage
    }
}

/// Aggregate summary report for an evaluation run.
public struct EvaluationSummaryReport: Codable, Sendable {
    public let runnerMode: EvaluationRunnerMode
    public let totalScenarios: Int

    // 1. Task-Completion Accuracy (Full end-to-end task fulfillment)
    public let passedCount: Int
    public let failedCount: Int
    public let passRatePercent: Double

    // 2. Intent-Routing Accuracy (Tool/intent classification separated from generation)
    public let intentRoutingPassedCount: Int
    public let intentRoutingAccuracyPercent: Double

    // 3. Argument-Extraction Accuracy
    public let argumentExtractionPassedCount: Int
    public let argumentExtractionApplicableCount: Int
    public let argumentExtractionAccuracyPercent: Double

    // 4. Performance & Safety Metrics
    public let averageLatencyMs: Double
    public let medianLatencyMs: Double
    public let unauthorizedToolCount: Int
    public let unauthorizedToolRatePercent: Double
    public let unauthorizedExecutionCount: Int
    public let unauthorizedExecutionRatePercent: Double
    public let falseSuccessCount: Int
    public let falseSuccessRatePercent: Double

    // 5. Ambiguity & Confirmation Denial Handling
    public let ambiguityAndDenialPassedCount: Int
    public let ambiguityAndDenialApplicableCount: Int
    public let ambiguityAndDenialAccuracyPercent: Double

    // 6. Explicit Metric Formulas with documented Numerators and Denominators
    public let metricFormulas: [EvaluationMetricFormula]

    // 7. Category Breakdown
    public let categoryBreakdown: [CategoryReport]

    // 8. Individual Failed Scenarios
    public let failedScenarios: [FailedScenarioReport]

    public struct CategoryReport: Codable, Sendable {
        public let category: EvaluationCategory
        public let total: Int
        public let passed: Int
        public let failed: Int
        public let passRatePercent: Double
        public let intentRoutingPassed: Int
        public let intentRoutingAccuracyPercent: Double
        public let avgLatencyMs: Double

        public init(
            category: EvaluationCategory,
            total: Int,
            passed: Int,
            failed: Int,
            passRatePercent: Double,
            intentRoutingPassed: Int,
            intentRoutingAccuracyPercent: Double,
            avgLatencyMs: Double
        ) {
            self.category = category
            self.total = total
            self.passed = passed
            self.failed = failed
            self.passRatePercent = passRatePercent
            self.intentRoutingPassed = intentRoutingPassed
            self.intentRoutingAccuracyPercent = intentRoutingAccuracyPercent
            self.avgLatencyMs = avgLatencyMs
        }
    }

    public struct FailedScenarioReport: Codable, Sendable {
        public let id: String
        public let category: EvaluationCategory
        public let prompt: String
        public let failureCategory: FailureCategory
        public let failureReason: String
        public let finalAnswer: String

        public init(
            id: String,
            category: EvaluationCategory,
            prompt: String,
            failureCategory: FailureCategory,
            failureReason: String,
            finalAnswer: String
        ) {
            self.id = id
            self.category = category
            self.prompt = prompt
            self.failureCategory = failureCategory
            self.failureReason = failureReason
            self.finalAnswer = finalAnswer
        }
    }

    public init(
        runnerMode: EvaluationRunnerMode,
        totalScenarios: Int,
        passedCount: Int,
        failedCount: Int,
        passRatePercent: Double,
        intentRoutingPassedCount: Int,
        intentRoutingAccuracyPercent: Double,
        argumentExtractionPassedCount: Int,
        argumentExtractionApplicableCount: Int,
        argumentExtractionAccuracyPercent: Double,
        averageLatencyMs: Double,
        medianLatencyMs: Double = 0.0,
        unauthorizedToolCount: Int,
        unauthorizedToolRatePercent: Double,
        unauthorizedExecutionCount: Int = 0,
        unauthorizedExecutionRatePercent: Double = 0.0,
        falseSuccessCount: Int,
        falseSuccessRatePercent: Double,
        ambiguityAndDenialPassedCount: Int,
        ambiguityAndDenialApplicableCount: Int,
        ambiguityAndDenialAccuracyPercent: Double,
        metricFormulas: [EvaluationMetricFormula],
        categoryBreakdown: [CategoryReport],
        failedScenarios: [FailedScenarioReport]
    ) {
        self.runnerMode = runnerMode
        self.totalScenarios = totalScenarios
        self.passedCount = passedCount
        self.failedCount = failedCount
        self.passRatePercent = passRatePercent
        self.intentRoutingPassedCount = intentRoutingPassedCount
        self.intentRoutingAccuracyPercent = intentRoutingAccuracyPercent
        self.argumentExtractionPassedCount = argumentExtractionPassedCount
        self.argumentExtractionApplicableCount = argumentExtractionApplicableCount
        self.argumentExtractionAccuracyPercent = argumentExtractionAccuracyPercent
        self.averageLatencyMs = averageLatencyMs
        self.medianLatencyMs = medianLatencyMs
        self.unauthorizedToolCount = unauthorizedToolCount
        self.unauthorizedToolRatePercent = unauthorizedToolRatePercent
        self.unauthorizedExecutionCount = unauthorizedExecutionCount
        self.unauthorizedExecutionRatePercent = unauthorizedExecutionRatePercent
        self.falseSuccessCount = falseSuccessCount
        self.falseSuccessRatePercent = falseSuccessRatePercent
        self.ambiguityAndDenialPassedCount = ambiguityAndDenialPassedCount
        self.ambiguityAndDenialApplicableCount = ambiguityAndDenialApplicableCount
        self.ambiguityAndDenialAccuracyPercent = ambiguityAndDenialAccuracyPercent
        self.metricFormulas = metricFormulas
        self.categoryBreakdown = categoryBreakdown
        self.failedScenarios = failedScenarios
    }
}
