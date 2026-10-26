using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public sealed class AmoraAgentLoopTests : IDisposable
{
    private sealed class ScriptedAIProvider : IAIProvider
    {
        private readonly Queue<string> _responses;
        public List<string> ReceivedPrompts { get; } = new();
        public List<(string Prompt, IReadOnlyList<ChatMessage>? History)> Invocations { get; } = new();

        public string ProviderId => AISettings.ProviderLocalBrain;
        public string DisplayName => "Scripted AI Provider";
        public bool IsConfigured => true;

        public ScriptedAIProvider(IEnumerable<string> responses)
        {
            _responses = new Queue<string>(responses);
        }

        public Task<string> GenerateResponseAsync(string prompt, CancellationToken cancellationToken = default) =>
            GenerateResponseAsync(prompt, null, cancellationToken);

        public Task<string> GenerateResponseAsync(
            string prompt,
            IReadOnlyList<ChatMessage>? history,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            ReceivedPrompts.Add(prompt);
            Invocations.Add((prompt, history != null ? new List<ChatMessage>(history) : null));

            if (_responses.Count > 0)
            {
                return Task.FromResult(_responses.Dequeue());
            }

            return Task.FromResult("{\"action\": \"final_answer\", \"answer\": \"No further responses scripted.\"}");
        }

        public Task<ConnectionTestResult> TestConnectionAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult(ConnectionTestResult.Success("Ready"));
    }

    private sealed class TestMemoryService : IExplicitMemoryService
    {
        public List<ExplicitMemory> StoredMemories { get; } = new();

        public Task<IReadOnlyList<ExplicitMemory>> GetRelevantMemoriesAsync(
            string query,
            int limit = 3,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var relevant = StoredMemories
                .Where(m => query.Contains(m.Key, StringComparison.OrdinalIgnoreCase) ||
                            query.Contains(m.Value, StringComparison.OrdinalIgnoreCase))
                .Take(limit)
                .ToList();
            return Task.FromResult<IReadOnlyList<ExplicitMemory>>(relevant);
        }

        public Task<AssistantExecutionResult?> TryExecuteAsync(string input, CancellationToken cancellationToken = default) =>
            Task.FromResult<AssistantExecutionResult?>(null);

        public Task<IReadOnlyList<ExplicitMemory>> ListAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<ExplicitMemory>>(StoredMemories);

        public Task<bool> ClearAllAsync(CancellationToken cancellationToken = default)
        {
            StoredMemories.Clear();
            return Task.FromResult(true);
        }

        public bool HasPendingClear => false;
        public Task<AssistantExecutionResult> ConfirmClearAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult(AssistantExecutionResult.Success("Cleared", MascotMood.Idle));
        public void CancelPendingClear() { }
    }

    private readonly StandardTimerService _timerService;
    private readonly PreviewMediaService _mediaService;
    private readonly PreviewBatteryService _batteryService;
    private readonly PreviewSystemTelemetryService _telemetryService;

    public AmoraAgentLoopTests()
    {
        _timerService = new StandardTimerService();
        _mediaService = new PreviewMediaService();
        _batteryService = new PreviewBatteryService();
        _telemetryService = new PreviewSystemTelemetryService();
    }

    public void Dispose()
    {
        _timerService.Dispose();
    }

    [Fact]
    public async Task SingleToolCall_ExecutesAllowlistedTool_ReturnsFinalAnswer()
    {
        _timerService.Start(TimeSpan.FromMinutes(10), "TestTimer");

        var ai = new ScriptedAIProvider(new[]
        {
            "```json\n{\"action\": \"tool_call\", \"tool\": \"timer.status\"}\n```",
            "```json\n{\"action\": \"final_answer\", \"answer\": \"Your 10m timer is active.\"}\n```"
        });

        var loop = new AmoraAgentLoop(ai, _timerService, _mediaService, _batteryService, _telemetryService);
        var result = await loop.RunAsync("Check my timer");

        Assert.True(result.CompletedSuccessfully);
        Assert.Equal(1, result.ExecutedToolCount);
        Assert.Equal("timer.status", result.ExecutedTools[0].Tool);
        Assert.Equal("Your 10m timer is active.", result.FinalAnswer);
    }

    [Fact]
    public async Task MultiStepToolExecution_ExecutesMultipleToolsInSequence()
    {
        _timerService.Start(TimeSpan.FromMinutes(5), "Focus");

        var ai = new ScriptedAIProvider(new[]
        {
            "{\"action\": \"tool_call\", \"tool\": \"battery.status\"}",
            "{\"action\": \"tool_call\", \"tool\": \"timer.status\"}",
            "{\"action\": \"final_answer\", \"answer\": \"Battery and timer checked successfully.\"}"
        });

        var loop = new AmoraAgentLoop(ai, _timerService, _mediaService, _batteryService, _telemetryService);
        var result = await loop.RunAsync("Check system status and timer");

        Assert.True(result.CompletedSuccessfully);
        Assert.Equal(2, result.ExecutedToolCount);
        Assert.Equal("battery.status", result.ExecutedTools[0].Tool);
        Assert.Equal("timer.status", result.ExecutedTools[1].Tool);
        Assert.Equal("Battery and timer checked successfully.", result.FinalAnswer);
    }

    [Fact]
    public async Task MaximumToolExecutionsLimit_HaltsAfterFourCalls()
    {
        // Script 6 tool calls; loop should forcibly stop after 4
        var ai = new ScriptedAIProvider(new[]
        {
            "{\"action\": \"tool_call\", \"tool\": \"battery.status\"}",
            "{\"action\": \"tool_call\", \"tool\": \"timer.status\"}",
            "{\"action\": \"tool_call\", \"tool\": \"media.status\"}",
            "{\"action\": \"tool_call\", \"tool\": \"system.diagnostics\"}",
            "{\"action\": \"tool_call\", \"tool\": \"battery.status\"}",
            "{\"action\": \"final_answer\", \"answer\": \"Done.\"}"
        });

        var loop = new AmoraAgentLoop(ai, _timerService, _mediaService, _batteryService, _telemetryService);
        var result = await loop.RunAsync("Do everything");

        Assert.False(result.CompletedSuccessfully);
        Assert.Equal(4, result.ExecutedToolCount);
        Assert.Contains("maximum limit of 4 tool executions", result.FinalAnswer);
    }

    [Fact]
    public async Task InfiniteLoopPrevention_ConsecutiveDuplicateToolCall_StopsSafely()
    {
        var ai = new ScriptedAIProvider(new[]
        {
            "{\"action\": \"tool_call\", \"tool\": \"timer.status\"}",
            "{\"action\": \"tool_call\", \"tool\": \"timer.status\"}" // exact duplicate
        });

        var loop = new AmoraAgentLoop(ai, _timerService, _mediaService, _batteryService, _telemetryService);
        var result = await loop.RunAsync("Check timer repeatedly");

        Assert.True(result.CompletedSuccessfully);
        Assert.Equal(1, result.ExecutedToolCount);
        Assert.NotNull(result.FinalAnswer);
    }

    [Fact]
    public async Task ConsecutiveFailures_HaltsGracefully()
    {
        var ai = new ScriptedAIProvider(new[]
        {
            "{\"action\": \"tool_call\", \"tool\": \"unknown.nonexistent_1\"}",
            "{\"action\": \"tool_call\", \"tool\": \"unknown.nonexistent_2\"}"
        });

        var loop = new AmoraAgentLoop(ai, _timerService, _mediaService, _batteryService, _telemetryService);
        var result = await loop.RunAsync("Run invalid tools");

        Assert.False(result.CompletedSuccessfully);
        Assert.Contains("I could not complete your request", result.FinalAnswer);
        Assert.Contains("Unknown tool", result.FinalAnswer);
    }

    [Fact]
    public async Task ConsequentialAction_RequiresConfirmation_DoesNotExecuteImmediately()
    {
        bool actionExecuted = false;
        var ai = new ScriptedAIProvider(new[]
        {
            "{\"action\": \"tool_call\", \"tool\": \"system.confirm_test\", \"params\": {\"description\": \"reset test settings\"}}"
        });

        var loop = new AmoraAgentLoop(ai, _timerService, _mediaService, _batteryService, _telemetryService);
        var result = await loop.RunAsync("Reset my settings");

        Assert.True(result.RequiresConfirmation);
        Assert.NotNull(result.PendingAction);
        Assert.Contains("Are you sure you want to run Test Action?", result.ConfirmationPrompt);
        Assert.Equal("system.confirm_test", result.ActionId);
        Assert.False(actionExecuted);

        // Execute pending action after user confirmation
        var confirmResult = await result.PendingAction!();
        Assert.NotNull(confirmResult);
        Assert.Equal(AssistantResultStatus.Success, confirmResult.Status);
    }

    [Fact]
    public async Task CancellationRequested_HaltsPromptly()
    {
        using var cts = new CancellationTokenSource();
        cts.Cancel();

        var ai = new ScriptedAIProvider(new[]
        {
            "{\"action\": \"final_answer\", \"answer\": \"Cancelled.\"}"
        });

        var loop = new AmoraAgentLoop(ai, _timerService, _mediaService, _batteryService, _telemetryService);
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            loop.RunAsync("Hello", cancellationToken: cts.Token));
    }

    [Fact]
    public async Task MemoryContext_IncludedInPromptForLocalBrain()
    {
        var memoryService = new TestMemoryService();
        memoryService.StoredMemories.Add(new ExplicitMemory(Guid.NewGuid(), "coffee", "prefers oat milk flat white", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow));

        var ai = new ScriptedAIProvider(new[]
        {
            "{\"action\": \"final_answer\", \"answer\": \"You like oat milk flat whites.\"}"
        });

        var loop = new AmoraAgentLoop(
            ai,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            memoryService: memoryService);

        var result = await loop.RunAsync("What coffee do I prefer?");

        Assert.True(result.CompletedSuccessfully);
        Assert.Single(ai.Invocations);
        Assert.Contains(ai.Invocations[0].History!, m => m.Content.Contains("[Relevant user memories]") && m.Content.Contains("oat milk flat white"));
    }

    [Fact]
    public async Task MemoryContext_ExcludedWhenNoMemoriesMatch()
    {
        var memoryService = new TestMemoryService();
        memoryService.StoredMemories.Add(new ExplicitMemory(Guid.NewGuid(), "coffee", "prefers oat milk flat white", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow));

        var ai = new ScriptedAIProvider(new[]
        {
            "{\"action\": \"final_answer\", \"answer\": \"France is in Europe.\"}"
        });

        var loop = new AmoraAgentLoop(
            ai,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            memoryService: memoryService);

        var result = await loop.RunAsync("Where is France located?");

        Assert.True(result.CompletedSuccessfully);
        Assert.Single(ai.Invocations);
        Assert.DoesNotContain(ai.Invocations[0].History!, m => m.Content.Contains("[Relevant user memories]"));
    }
}
