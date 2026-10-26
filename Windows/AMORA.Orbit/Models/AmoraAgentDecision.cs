using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace AMORA.Orbit.Models;

/// <summary>Strongly typed decision produced by an AI model in Local Agent planning.</summary>
public abstract record AmoraAgentDecision
{
    public sealed record FinalAnswer(string Text) : AmoraAgentDecision;
    public sealed record ToolCall(string Tool, IReadOnlyDictionary<string, string> Arguments) : AmoraAgentDecision;
    public sealed record ToolBatch(IReadOnlyList<ToolCall> Calls) : AmoraAgentDecision;
}

/// <summary>Exception raised when model output violates decision format or contains malformed JSON.</summary>
public class AmoraAgentDecisionException : Exception
{
    public AmoraAgentDecisionException(string message) : base(message) { }
}

/// <summary>Record of an executed tool call within the agent loop.</summary>
public sealed record ExecutedToolCall(string Name, IReadOnlyDictionary<string, string> Arguments)
{
    public string Tool => Name;
}

/// <summary>Result returned by the bounded agent loop.</summary>
public sealed record AgentLoopResult(
    string FinalAnswer,
    int ExecutedToolCount,
    bool CompletedSuccessfully,
    IReadOnlyList<string> AttemptedTools,
    IReadOnlyList<ExecutedToolCall> ExecutedTools,
    bool UsedMemory,
    bool RequiresConfirmation = false,
    string? ConfirmationPrompt = null,
    string? ActionId = null,
    Func<Task<AssistantExecutionResult>>? PendingAction = null);
