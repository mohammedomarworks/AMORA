using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.ViewModels;
using Xunit;

namespace AMORA.Orbit.Tests;

public sealed class ViewModelShutdownTests
{
    [Fact]
    public async Task AssistantDisposalCancelsRequestAndSuppressesLateResultAndNotifications()
    {
        var engine = new PendingEngine();
        using var vm = new AssistantCommandViewModel(engine) { InputText = "Hello" };
        var request = vm.SubmitAsync();
        vm.Dispose();
        int notifications = 0, results = 0;
        vm.PropertyChanged += (_, _) => notifications++;
        vm.ResultReceived += (_, _) => results++;
        engine.Completion.SetResult(AssistantExecutionResult.Success("Late response"));
        await request;
        Assert.True(engine.Token.IsCancellationRequested);
        Assert.Equal(0, notifications);
        Assert.Equal(0, results);
        Assert.Single(vm.Transcript);
        Assert.False(vm.CanSubmit);
    }

    [Fact]
    public async Task AssistantQueuedCompletionIsDroppedWhenWindowClosesBeforeDispatch()
    {
        var queue = new Queue<Action>();
        var engine = new PendingEngine();
        using var vm = new AssistantCommandViewModel(engine, queue.Enqueue) { InputText = "Hello" };
        var request = vm.SubmitAsync();
        engine.Completion.SetResult(AssistantExecutionResult.Success("Queued response"));
        await request;
        Assert.NotEmpty(queue);
        vm.Dispose();
        int changes = 0;
        vm.PropertyChanged += (_, _) => changes++;
        while (queue.TryDequeue(out var action)) action();
        Assert.Equal(0, changes);
        Assert.Single(vm.Transcript);
    }

    [Fact]
    public async Task SettingsDisposalCancelsConnectionTestAndDropsLateProviderResult()
    {
        var provider = new PendingProvider();
        using var vm = new SettingsViewModel(new FakeSettings(), provider);
        var request = vm.TestConnectionAsync();
        vm.Dispose();
        int changes = 0;
        vm.PropertyChanged += (_, _) => changes++;
        provider.Completion.SetResult(ConnectionTestResult.Success("Late success"));
        await request;
        Assert.True(provider.Token.IsCancellationRequested);
        Assert.Equal(0, changes);
        Assert.DoesNotContain("Late success", vm.TestStatusMessage);
        Assert.False(vm.CanTest);
    }

    [Fact]
    public async Task SettingsCredentialReadQueuedBeforeDisposeCannotRestoreKeyDisplay()
    {
        var queue = new Queue<Action>();
        var settings = new FakeSettings();
        await settings.SetApiKeyAsync(AISettings.ProviderGemini, "test-synthetic-key");
        using var vm = new SettingsViewModel(settings, new PendingProvider(), queue.Enqueue)
        { SelectedProvider = AISettings.ProviderGemini };
        await vm.RefreshKeyStatusAsync();
        vm.Dispose();
        int changes = 0;
        vm.PropertyChanged += (_, _) => changes++;
        while (queue.TryDequeue(out var action)) action();
        Assert.Equal(0, changes);
        Assert.Empty(vm.MaskedApiKey);
        Assert.False(vm.HasSavedKey);
    }

    [Fact]
    public async Task ConnectionExceptionsDoNotExposeRawCredentialOrResponseText()
    {
        var provider = new PendingProvider();
        using var vm = new SettingsViewModel(new FakeSettings(), provider);
        var request = vm.TestConnectionAsync();
        provider.Completion.SetException(new IOException("private-key-and-response-body"));
        await request;
        Assert.Contains("connection test failed", vm.TestStatusMessage);
        Assert.DoesNotContain("private-key-and-response-body", vm.TestStatusMessage);
        Assert.False(vm.IsTesting);
    }

    [Fact]
    public async Task ProviderSwitchDuringSaveCannotStoreKeyUnderNewProvider()
    {
        var gate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var settings = new FakeSettings { PendingSave = gate.Task };
        using var vm = new SettingsViewModel(settings, new PendingProvider())
        { SelectedProvider = AISettings.ProviderGemini, ApiKeyInput = "synthetic-gemini-secret" };
        var save = vm.SaveAsync();
        vm.SelectedProvider = AISettings.ProviderAnthropic;
        vm.ModelName = "explicit-test-model";
        vm.ApiKeyInput = "new-unsaved-anthropic-secret";
        gate.SetResult();
        await save;
        Assert.Equal("synthetic-gemini-secret", await settings.GetApiKeyAsync(AISettings.ProviderGemini));
        Assert.Null(await settings.GetApiKeyAsync(AISettings.ProviderAnthropic));
        Assert.Equal("new-unsaved-anthropic-secret", vm.ApiKeyInput);
    }

    private sealed class PendingEngine : IAssistantEngine
    {
        public TaskCompletionSource<AssistantExecutionResult> Completion { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public CancellationToken Token { get; private set; }
        public bool HasPendingConfirmation => false;
        public string? PendingConfirmationPrompt => null;
        public Task<AssistantExecutionResult> ExecuteAsync(string input, CancellationToken cancellationToken = default)
        { Token = cancellationToken; return Completion.Task; }
        public Task<AssistantExecutionResult> ConfirmPendingActionAsync() => Completion.Task;
        public void CancelPendingAction() { }
    }

    private sealed class PendingProvider : IAIProvider
    {
        public TaskCompletionSource<ConnectionTestResult> Completion { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public CancellationToken Token { get; private set; }
        public string ProviderId => AISettings.ProviderGemini;
        public string DisplayName => "Test";
        public bool IsConfigured => true;
        public Task<string> GenerateResponseAsync(string prompt, CancellationToken cancellationToken = default) => Task.FromResult("Test");
        public Task<ConnectionTestResult> TestConnectionAsync(CancellationToken cancellationToken = default)
        { Token = cancellationToken; return Completion.Task; }
    }

    private sealed class FakeSettings : IAISettingsService
    {
        private readonly Dictionary<string, string> _keys = new();
        public AISettings CurrentSettings { get; private set; } = AISettings.Default;
        public Task? PendingSave { get; init; }
        public event EventHandler<AISettings>? SettingsChanged { add { } remove { } }
        public Task<AISettings> LoadSettingsAsync() => Task.FromResult(CurrentSettings);
        public async Task SaveSettingsAsync(AISettings settings) { if (PendingSave != null) await PendingSave; CurrentSettings = settings; }
        public Task<bool> HasApiKeyAsync(string providerId) => Task.FromResult(_keys.ContainsKey(providerId));
        public Task<string?> GetApiKeyAsync(string providerId) => Task.FromResult(_keys.GetValueOrDefault(providerId));
        public Task SetApiKeyAsync(string providerId, string apiKey) { _keys[providerId] = apiKey; return Task.CompletedTask; }
        public Task ClearApiKeyAsync(string providerId) { _keys.Remove(providerId); return Task.CompletedTask; }
    }
}
