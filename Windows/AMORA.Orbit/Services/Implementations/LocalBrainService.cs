using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using AMORA.Orbit.Interop;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public sealed class LocalBrainService : ILocalBrainService
{
    private readonly ILocalBrainAssets _assets;
    private readonly ILocalBrainRuntime _runtime;
    private readonly Func<long> _availableMemory;
    private readonly SemaphoreSlim _operations = new(1, 1);
    private readonly object _gate = new();
    private readonly CancellationTokenSource _lifetime = new();
    private readonly CancellationToken _lifetimeToken;
    private CancellationTokenSource? _activeOperation;
    private bool _disposed;
    private LocalBrainSnapshot _snapshot = new(LocalBrainState.NotInstalled, "Install a verified model once to chat offline. Setup uses the internet; inference stays on this PC.");
    public LocalBrainService(string? rootDirectory = null, ILocalBrainAssets? assets = null,
        ILocalBrainRuntime? runtime = null, Func<long>? availableMemory = null)
    {
        _assets = assets ?? new LocalBrainAssetStore(rootDirectory);
        _runtime = runtime ?? new LlamaServerRuntime();
        _runtime.UnexpectedlyExited += OnRuntimeExited;
        _availableMemory = availableMemory ?? GetAvailableMemory;
        _lifetimeToken = _lifetime.Token;
    }
    public IReadOnlyList<LocalBrainModelDescriptor> Models => LocalBrainCatalog.Models;
    public LocalBrainSnapshot Snapshot { get { lock (_gate) return _snapshot; } }
    public event EventHandler<LocalBrainSnapshot>? StateChanged;
    public bool IsInstalled(string modelId) => !_disposed && _assets.IsInstalled(modelId);

    public Task RefreshAsync(string modelId, CancellationToken cancellationToken = default) => RunAsync(modelId, async token =>
    {
        if (!_assets.IsInstalled(modelId)) { Publish(new(LocalBrainState.NotInstalled, "This model or its runtime is not installed. Choose Install to set up offline intelligence.", modelId)); return; }
        await _assets.VerifyAsync(modelId, Publish, token);
        Publish(new(_runtime.IsRunning && _runtime.LoadedModelId == modelId ? LocalBrainState.Ready : LocalBrainState.Installed,
            "Official runtime and model checksums verified. Ready to start offline inference.", modelId));
    }, cancellationToken);

    public Task InstallAsync(string modelId, CancellationToken cancellationToken = default) => RunAsync(modelId, async token =>
    {
        _runtime.Stop();
        Publish(new(LocalBrainState.Downloading, "Preparing the verified runtime and selected model download…", modelId));
        await _assets.InstallAsync(modelId, Publish, token);
        token.ThrowIfCancellationRequested();
        Publish(new(LocalBrainState.Installed, "Verified local model installed. Select Use this model, then Start or send a message.", modelId));
    }, cancellationToken);

    public Task StartAsync(string modelId, CancellationToken cancellationToken = default) =>
        RunAsync(modelId, token => EnsureStartedAsync(modelId, token), cancellationToken);

    private async Task EnsureStartedAsync(string modelId, CancellationToken token)
    {
        if (_runtime.IsRunning && _runtime.LoadedModelId == modelId) return;
        var model = LocalBrainCatalog.Find(modelId);
        if (!_assets.IsInstalled(modelId)) throw new LocalBrainException("Local Brain is not installed for this model. Open Local Brain and choose Install; no cloud fallback will be used.");
        long available = _availableMemory();
        if (available <= 0) throw new LocalBrainException("Available memory could not be checked. Local Brain was not started.");
        if (available < model.EstimatedRamBytes)
            throw new LocalBrainException($"This model needs about {model.EstimatedRamBytes / 1024 / 1024:N0} MB of free RAM. Close other applications or select the compact model.");
        await _assets.VerifyAsync(modelId, Publish, token);
        Publish(new(LocalBrainState.Starting, "Loading the verified model on this PC…", modelId));
        await _runtime.StartAsync(_assets.RuntimeExecutable, _assets.ModelPath(modelId), model, token);
        token.ThrowIfCancellationRequested();
        Publish(new(LocalBrainState.Ready, "Local Brain is ready. Conversations run on this PC without cloud requests.", modelId));
    }

    public async Task<string> GenerateAsync(string modelId, string prompt, IReadOnlyList<ChatMessage>? history = null, CancellationToken cancellationToken = default)
    {
        string formatted = FormatPrompt(prompt, history);
        string answer = "";
        await RunAsync(modelId, async token =>
        {
            await EnsureStartedAsync(modelId, token);
            Publish(new(LocalBrainState.Generating, "AMORA is thinking locally…", modelId));
            answer = StripThinkingBlocks(await _runtime.GenerateAsync(formatted, LocalBrainCatalog.Find(modelId).ContextLength, token));
            token.ThrowIfCancellationRequested();
            if (string.IsNullOrWhiteSpace(answer)) throw new LocalBrainException("The local model returned an empty answer. Try a shorter question.");
            Publish(new(LocalBrainState.Ready, "Local response completed. No cloud service was used.", modelId));
        }, cancellationToken);
        return answer;
    }

    public Task DeleteModelAsync(string modelId, CancellationToken cancellationToken = default) => RunAsync(modelId, token =>
    {
        if (_runtime.LoadedModelId == modelId) _runtime.Stop();
        token.ThrowIfCancellationRequested();
        _assets.DeleteModel(modelId);
        Publish(new(LocalBrainState.NotInstalled, "The selected model was deleted. Your conversations and saved memory were not changed.", modelId));
        return Task.CompletedTask;
    }, cancellationToken);

    public void CancelOperation()
    {
        lock (_gate) { if (_disposed) return; _activeOperation?.Cancel(); }
        _runtime.Stop();
    }
    public async Task StopAsync()
    {
        CancelOperation();
        await _operations.WaitAsync();
        try { if (!_disposed) { _runtime.Stop(); Publish(new(LocalBrainState.Stopped, "Local inference stopped and model memory released. Installed files are retained.", Snapshot.ModelId)); } }
        finally { _operations.Release(); }
    }

    private async Task RunAsync(string modelId, Func<CancellationToken, Task> operation, CancellationToken cancellationToken)
    {
        _ = LocalBrainCatalog.Find(modelId);
        if (RuntimeInformation.ProcessArchitecture != Architecture.X64)
        { Publish(new(LocalBrainState.UnsupportedDevice, "The verified runtime currently supports Windows x64 only.", modelId)); throw new LocalBrainException(Snapshot.Message); }
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _lifetimeToken);
        await _operations.WaitAsync(linked.Token);
        try
        {
            lock (_gate) { ObjectDisposedException.ThrowIf(_disposed, this); _activeOperation = linked; }
            await operation(linked.Token);
        }
        catch (OperationCanceledException) when (linked.IsCancellationRequested)
        { _runtime.Stop(); Publish(new(LocalBrainState.Cancelled, "Local Brain operation cancelled. No cloud fallback was used.", modelId)); throw; }
        catch (LocalBrainException error)
        { Publish(new(LocalBrainState.Failed, error.Message, modelId)); throw; }
        catch (Exception)
        {
            _runtime.Stop();
            var error = new LocalBrainException("Local Brain could not complete this operation. Check storage access, available memory, or reinstall the verified runtime.");
            Publish(new(LocalBrainState.Failed, error.Message, modelId));
            throw error;
        }
        finally { lock (_gate) { if (ReferenceEquals(_activeOperation, linked)) _activeOperation = null; } _operations.Release(); }
    }

    public static string FormatPrompt(string prompt, IReadOnlyList<ChatMessage>? history)
    {
        if (string.IsNullOrWhiteSpace(prompt) || prompt.Length > 6000) throw new LocalBrainException("Enter a message of 6,000 characters or fewer for the local model.");
        static string Text(string value) => value.Replace("<|", "< |").Replace("|>", "| >");
        var turns = (history ?? Array.Empty<ChatMessage>()).Where(m => !string.IsNullOrWhiteSpace(m.Content)).TakeLast(8).ToList();
        while (turns.Count > 0 && turns.Sum(t => t.Content.Length) + prompt.Length > 8000) turns.RemoveAt(0);
        var output = new StringBuilder("<|im_start|>system\nYou are AMORA, a friendly, concise Windows companion running entirely on this PC. Answer questions directly and honestly. Never claim to have performed an action unless AMORA reports its result. Never invent shell commands, arbitrary paths, destructive actions, or automatic schedules. Do not claim internet access. For casual chat use natural text. AMORA handles explicit local commands through its bounded command engine.\n<|im_end|>\n");
        foreach (var turn in turns)
            output.Append("<|im_start|>").Append(turn.Role == ChatRole.User ? "user" : "assistant").Append('\n').Append(Text(turn.Content)).Append("<|im_end|>\n");
        return output.Append("<|im_start|>user\n").Append(Text(prompt)).Append("<|im_end|>\n<|im_start|>assistant\n").ToString();
    }
    public static string StripThinkingBlocks(string text)
    {
        string result = Regex.Replace(text, "<think>[\\s\\S]*?</think>", "", RegexOptions.None, TimeSpan.FromMilliseconds(100));
        int unclosed = result.IndexOf("<think>", StringComparison.Ordinal);
        if (unclosed >= 0) result = result[..unclosed];
        return result.Trim();
    }
    private static long GetAvailableMemory()
    {
        var status = new NativeMethods.MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf<NativeMethods.MEMORYSTATUSEX>() };
        return NativeMethods.GlobalMemoryStatusEx(ref status) ? (long)status.ullAvailPhys : 0;
    }
    private void Publish(LocalBrainSnapshot snapshot)
    { lock (_gate) { if (_disposed) return; _snapshot = snapshot; } StateChanged?.Invoke(this, snapshot); }
    private void OnRuntimeExited(object? sender, EventArgs args)
    {
        if (_runtime.IsRunning) return; // Ignore a delayed notification from a process already replaced.
        Publish(new(LocalBrainState.Failed,
            "The local inference process stopped unexpectedly. Try Start again; no cloud fallback was used.", Snapshot.ModelId));
    }
    public void Dispose()
    {
        lock (_gate) { if (_disposed) return; _disposed = true; _lifetime.Cancel(); _activeOperation?.Cancel(); }
        _runtime.UnexpectedlyExited -= OnRuntimeExited;
        _runtime.Dispose();
        _lifetime.Dispose();
    }
}
