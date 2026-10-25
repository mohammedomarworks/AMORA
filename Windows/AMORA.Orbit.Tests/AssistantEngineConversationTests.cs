using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class AssistantEngineConversationTests : IDisposable
{
    private class RecordingMockAIProvider : IAIProvider
    {
        public string ProviderId => "recording_mock";
        public string DisplayName => "Recording Mock AI";
        public bool IsConfigured { get; set; } = true;

        public List<(string Prompt, IReadOnlyList<ChatMessage>? History)> Invocations { get; } = new();
        public Func<string, IReadOnlyList<ChatMessage>?, Task<string>> ResponseHandler { get; set; }

        public RecordingMockAIProvider(Func<string, IReadOnlyList<ChatMessage>?, Task<string>>? handler = null)
        {
            ResponseHandler = handler ?? ((prompt, _) => Task.FromResult($"Response to: {prompt}"));
        }

        public Task<string> GenerateResponseAsync(string prompt, CancellationToken cancellationToken = default) =>
            GenerateResponseAsync(prompt, null, cancellationToken);

        public async Task<string> GenerateResponseAsync(
            string prompt,
            IReadOnlyList<ChatMessage>? history,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Invocations.Add((prompt, history != null ? new List<ChatMessage>(history) : null));
            return await ResponseHandler(prompt, history);
        }
    }

    private readonly StandardTimerService _timerService;
    private readonly PreviewMediaService _mediaService;
    private readonly PreviewBatteryService _batteryService;
    private readonly PreviewSystemTelemetryService _telemetryService;
    private readonly DeterministicCommandRouter _router;

    public AssistantEngineConversationTests()
    {
        _timerService = new StandardTimerService();
        _mediaService = new PreviewMediaService();
        _batteryService = new PreviewBatteryService();
        _telemetryService = new PreviewSystemTelemetryService();
        _router = new DeterministicCommandRouter();
    }

    public void Dispose()
    {
        _timerService.Dispose();
    }

    [Fact]
    public async Task FollowUpConversation_PassesHistoryToAIProvider()
    {
        var mockAi = new RecordingMockAIProvider((prompt, history) =>
        {
            if (prompt.Contains("capital of France"))
            {
                return Task.FromResult("Paris is the capital of France.");
            }
            if (prompt.Contains("landmark"))
            {
                return Task.FromResult("The Eiffel Tower is its most famous landmark.");
            }
            return Task.FromResult("I am here to help.");
        });

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            mockAi
        );

        // Turn 1
        var result1 = await engine.ExecuteAsync("What is the capital of France?");
        Assert.Equal(AssistantResultStatus.Information, result1.Status);
        Assert.Equal(2, engine.ConversationHistory.Count);
        Assert.Equal("What is the capital of France?", engine.ConversationHistory[0].Content);
        Assert.Equal(ChatRole.User, engine.ConversationHistory[0].Role);
        Assert.Equal("Paris is the capital of France.", engine.ConversationHistory[1].Content);
        Assert.Equal(ChatRole.Model, engine.ConversationHistory[1].Role);

        // Turn 2: Follow-up question
        var result2 = await engine.ExecuteAsync("What is its most famous landmark?");
        Assert.Equal(AssistantResultStatus.Information, result2.Status);
        Assert.Equal(4, engine.ConversationHistory.Count);

        // Verify that the second AI call received Turn 1 in its history
        Assert.Equal(2, mockAi.Invocations.Count);
        var secondInvocation = mockAi.Invocations[1];
        Assert.Equal("What is its most famous landmark?", secondInvocation.Prompt);
        Assert.NotNull(secondInvocation.History);
        Assert.Equal(2, secondInvocation.History!.Count);
        Assert.Equal("What is the capital of France?", secondInvocation.History[0].Content);
        Assert.Equal("Paris is the capital of France.", secondInvocation.History[1].Content);
    }

    [Fact]
    public async Task AIRequestFailure_DoesNotAddToHistory()
    {
        bool shouldFail = false;

        var mockAi = new RecordingMockAIProvider((prompt, history) =>
        {
            if (shouldFail)
            {
                throw new HttpRequestException("Gemini service temporarily unavailable (HTTP 503)");
            }
            return Task.FromResult("Initial successful response.");
        });

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            mockAi
        );

        // Turn 1: Success
        var result1 = await engine.ExecuteAsync("Hello AMORA");
        Assert.Equal(AssistantResultStatus.Information, result1.Status);
        Assert.Equal(2, engine.ConversationHistory.Count);

        // Turn 2: AI failure
        shouldFail = true;
        var result2 = await engine.ExecuteAsync("How is the weather?");
        Assert.Equal(AssistantResultStatus.Failed, result2.Status);
        Assert.Contains("503", result2.Message);

        // Crucial requirement: failed turn must NOT be stored in history!
        Assert.Equal(2, engine.ConversationHistory.Count);
        Assert.Equal("Hello AMORA", engine.ConversationHistory[0].Content);
        Assert.Equal("Initial successful response.", engine.ConversationHistory[1].Content);
    }

    [Fact]
    public async Task Cancellation_DoesNotAddToHistory()
    {
        var mockAi = new RecordingMockAIProvider(async (prompt, history) =>
        {
            await Task.Delay(100);
            return "Late response";
        });

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            mockAi
        );

        using var cts = new CancellationTokenSource();
        cts.Cancel(); // Pre-cancelled

        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
        {
            await engine.ExecuteAsync("Cancel me immediately", cts.Token);
        });

        Assert.Empty(engine.ConversationHistory);
    }

    [Fact]
    public async Task ResetConversation_ExplicitMethod_ClearsHistoryForSubsequentRequests()
    {
        var mockAi = new RecordingMockAIProvider();
        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            mockAi
        );

        // Turn 1
        await engine.ExecuteAsync("Initial message");
        Assert.Equal(2, engine.ConversationHistory.Count);

        // Reset
        engine.ResetConversation();
        Assert.Empty(engine.ConversationHistory);

        // Turn 2 after reset: AI should receive empty history
        await engine.ExecuteAsync("Subsequent message after reset");
        Assert.Equal(2, engine.ConversationHistory.Count);

        var secondCallHistory = mockAi.Invocations[1].History;
        Assert.True(secondCallHistory == null || secondCallHistory.Count == 0);
    }

    [Theory]
    [InlineData("reset conversation")]
    [InlineData("clear conversation")]
    [InlineData("new conversation")]
    [InlineData("clear chat")]
    [InlineData("reset chat")]
    public async Task DeterministicResetCommand_ClearsHistoryDirectly(string resetCommand)
    {
        var mockAi = new RecordingMockAIProvider();
        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            mockAi
        );

        // Setup 1 turn
        await engine.ExecuteAsync("Some conversational query");
        Assert.Equal(2, engine.ConversationHistory.Count);

        // Execute deterministic reset command
        var resetResult = await engine.ExecuteAsync(resetCommand);

        Assert.Equal(AssistantResultStatus.Success, resetResult.Status);
        Assert.Contains("cleared", resetResult.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Empty(engine.ConversationHistory);

        // Mock AI was NOT invoked for the deterministic reset command!
        Assert.Single(mockAi.Invocations);
    }

    [Fact]
    public async Task DeterministicCommands_TakePrecedenceWithoutCallingAI()
    {
        var mockAi = new RecordingMockAIProvider();
        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            mockAi
        );

        var result = await engine.ExecuteAsync("start 15m timer");

        Assert.Equal(AssistantResultStatus.Success, result.Status);
        Assert.Equal(TimerStatus.Running, _timerService.CurrentTimer.Status);
        Assert.Empty(mockAi.Invocations);
        Assert.Empty(engine.ConversationHistory);
    }

    [Fact]
    public async Task ConcurrentRequests_AreProcessedSafelyWithoutRaceConditions()
    {
        var mockAi = new RecordingMockAIProvider(async (prompt, _) =>
        {
            await Task.Delay(20);
            return $"AI answer to {prompt}";
        });

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            mockAi
        );

        // Run two overlapping requests concurrently
        var task1 = engine.ExecuteAsync("Concurrent Question 1");
        var task2 = engine.ExecuteAsync("Concurrent Question 2");

        var results = await Task.WhenAll(task1, task2);

        Assert.Equal(AssistantResultStatus.Information, results[0].Status);
        Assert.Equal(AssistantResultStatus.Information, results[1].Status);

        // Both turns should be captured in history: 2 user + 2 model = 4 messages
        Assert.Equal(4, engine.ConversationHistory.Count);

        // Strict alternating roles must be maintained
        Assert.Equal(ChatRole.User, engine.ConversationHistory[0].Role);
        Assert.Equal(ChatRole.Model, engine.ConversationHistory[1].Role);
        Assert.Equal(ChatRole.User, engine.ConversationHistory[2].Role);
        Assert.Equal(ChatRole.Model, engine.ConversationHistory[3].Role);
    }

    [Fact]
    public async Task AIProposesAction_InFollowUpTurn_ExecutesRealActionAndRecordsTurn()
    {
        var mockAi = new RecordingMockAIProvider((prompt, history) =>
        {
            if (prompt.Contains("pause"))
            {
                return Task.FromResult("Pausing your music.\n[COMMAND: pause music]");
            }
            return Task.FromResult("I am listening to music with you.");
        });

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            mockAi
        );

        Assert.True(_mediaService.CurrentTrack.IsPlaying);

        // Turn 1: Conversational query
        await engine.ExecuteAsync("I like this song");
        Assert.Equal(2, engine.ConversationHistory.Count);

        // Turn 2: AI proposes action based on request
        var result2 = await engine.ExecuteAsync("Could you pause it for a second?");

        Assert.Equal(AssistantResultStatus.Success, result2.Status);
        Assert.False(_mediaService.CurrentTrack.IsPlaying);
        Assert.Contains("Pausing your music", result2.Message);
        Assert.Contains("Playback paused", result2.Message);

        // The turn should be recorded cleanly in conversation history
        Assert.Equal(4, engine.ConversationHistory.Count);
        Assert.Equal("Could you pause it for a second?", engine.ConversationHistory[2].Content);
        Assert.Equal("Pausing your music.", engine.ConversationHistory[3].Content);
    }
}
