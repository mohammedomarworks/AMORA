using System.Collections.Concurrent;
using System.Text.Json;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.BrowserBridge;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public sealed class BrowserMediaBridgeService : IMediaService, IDisposable
{
    private sealed record Snapshot(MediaTrack Track, int TabId, bool Ready, DateTimeOffset ReceivedAt)
    { public static Snapshot Empty { get; } = new(MediaTrack.None, -1, false, DateTimeOffset.MinValue); }
    private sealed record Pending(string Action, int TabId, TaskCompletionSource<(bool Success, string? Reason)> Completion);
    private readonly IBrowserBridgeTransport _transport;
    private readonly object _stateGate = new();
    private readonly TimeProvider _clock;
    private readonly ConcurrentDictionary<string, Pending> _pending = new();
    private readonly CancellationTokenSource _stop = new();
    private readonly CancellationToken _stopToken;
    private Snapshot _snapshot = Snapshot.Empty;
    private string _status = "Browser media is off.";
    private volatile bool _enabled, _connected, _disposed;
    private long _lastProbeTicks;
    public TimeSpan CommandTimeout { get; init; } = TimeSpan.FromSeconds(5);

    public BrowserMediaBridgeService(Func<bool> enabled, IBrowserBridgeTransport? transport = null, TimeProvider? clock = null, bool startPolling = true)
    {
        ArgumentNullException.ThrowIfNull(enabled);
        _transport = transport ?? new NamedPipeBrowserTransport();
        _clock = clock ?? TimeProvider.System;
        _stopToken = _stop.Token;
        _transport.ConnectionChanged += OnConnection;
        _transport.MessageReceived += OnMessage;
        SetEnabled(enabled());
        if (startPolling) _ = Task.Run(PollAsync);
    }

    public bool IsEnabled => _enabled;
    public bool IsConnected => _enabled && _connected;
    public MediaTrack CurrentTrack => Volatile.Read(ref _snapshot).Track;
    public string ProviderName => "YouTube browser bridge";
    public string StatusText => Volatile.Read(ref _status);
    public bool CanTogglePlayPause => IsConnected && CurrentTrack.IsAvailable && Volatile.Read(ref _snapshot).Ready;
    public bool CanGoNext => false;
    public bool CanGoPrevious => false;
    public bool CanSeek => false;
    public event EventHandler<MediaTrack>? TrackChanged;
    public event EventHandler? ConnectionChanged;

    public void SetEnabled(bool enabled)
    {
        lock (_stateGate)
        {
        if (_disposed || _enabled == enabled) return;
        _enabled = enabled;
        if (!enabled)
        {
            _connected = false;
            FailPending("bridge_disabled");
            Publish(Snapshot.Empty, "Browser media is off.");
        }
        else Publish(Snapshot.Empty, "Waiting for the AMORA browser extension.");
        _transport.SetEnabled(enabled);
        ConnectionChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnConnection(object? sender, bool connected)
    {
        lock (_stateGate)
        {
        if (_disposed || !_enabled) return;
        _connected = connected;
        if (!connected) FailPending("bridge_disconnected");
        Publish(Snapshot.Empty, connected ? "Browser connected. Open a YouTube video." : "Browser extension disconnected. Reopen the browser or check host registration.");
        ConnectionChanged?.Invoke(this, EventArgs.Empty);
        if (connected) _ = RefreshAsync();
        }
    }

    private void OnMessage(object? sender, string message)
    {
        lock (_stateGate)
        {
        if (_disposed || !IsConnected) return;
        var normalized = BrowserWireProtocol.NormalizeBrowserMessage(message);
        if (normalized == null)
        {
            Publish(Snapshot.Empty, "Browser sent an invalid media message.");
            return;
        }
        using var doc = BrowserWireProtocol.Parse(normalized);
        var value = doc.RootElement;
        switch (BrowserWireProtocol.Text(value, "type"))
        {
            case "clear":
                FailPending("no_media_target");
                Publish(Snapshot.Empty, "Browser connected. No controllable YouTube video.");
                break;
            case "mediaState": ApplyState(value); break;
            case "mediaCommandResult":
                var id = BrowserWireProtocol.Text(value, "requestId")!;
                if (!_pending.TryRemove(id, out var request)) return; // Expired/duplicate acknowledgements are inert.
                var action = BrowserWireProtocol.Text(value, "action");
                var tab = BrowserWireProtocol.Integer(value, "tabId");
                BrowserWireProtocol.TryBool(value, "success", out var success);
                if (request.Action != action || tab != request.TabId)
                { request.Completion.TrySetResult((false, "ack_mismatch")); return; }
                if (success && value.TryGetProperty("state", out var state) && state.ValueKind == JsonValueKind.Object &&
                    BrowserWireProtocol.Integer(state, "tabId") == request.TabId) ApplyState(state);
                request.Completion.TrySetResult((success, BrowserWireProtocol.Text(value, "reason")));
                break;
        }
        }
    }

    private void ApplyState(JsonElement value)
    {
        BrowserWireProtocol.TryBool(value, "isPlaying", out var playing);
        BrowserWireProtocol.TryBool(value, "contentScriptReady", out var ready);
        var duration = TimeSpan.FromSeconds(value.GetProperty("duration").GetDouble());
        var elapsed = TimeSpan.FromSeconds(value.GetProperty("currentTime").GetDouble());
        if (duration > TimeSpan.Zero && elapsed > duration) elapsed = duration;
        var title = BrowserWireProtocol.Text(value, "title");
        var channel = BrowserWireProtocol.Text(value, "channel", 500);
        var track = new MediaTrack(string.IsNullOrWhiteSpace(title) ? "YouTube video" : title,
            string.IsNullOrWhiteSpace(channel) ? "YouTube" : channel, Source: MediaSourceType.YouTube,
            IsPlaying: playing, IsAvailable: true, Elapsed: elapsed, Duration: duration);
        Publish(new Snapshot(track, BrowserWireProtocol.Integer(value, "tabId")!.Value, ready, _clock.GetUtcNow()),
            ready ? string.Empty : "YouTube controls are not ready. Reload the video tab.");
    }

    private async Task PollAsync()
    {
        try
        {
            using var timer = new PeriodicTimer(TimeSpan.FromSeconds(5));
            while (await timer.WaitForNextTickAsync(_stopToken).ConfigureAwait(false)) await RefreshAsync().ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (_stopToken.IsCancellationRequested) { }
    }

    public async Task RefreshAsync()
    {
        if (_disposed || !IsConnected) return;
        var now = _clock.GetUtcNow();
        if (CurrentTrack.IsAvailable && now - Volatile.Read(ref _snapshot).ReceivedAt > TimeSpan.FromSeconds(30))
            Publish(Snapshot.Empty, "YouTube state is stale. Reload the video tab.");
        if (now.UtcTicks - Interlocked.Read(ref _lastProbeTicks) < TimeSpan.FromSeconds(2).Ticks) return;
        Interlocked.Exchange(ref _lastProbeTicks, now.UtcTicks);
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(_stopToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(2));
            await _transport.SendAsync(JsonSerializer.Serialize(new { type = "contentPing", requestId = Guid.NewGuid().ToString() }), timeout.Token).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or OperationCanceledException or ObjectDisposedException)
        { if (!_disposed && _enabled) OnConnection(this, false); }
    }

    public Task TogglePlayPauseAsync() => ExecuteAsync(CurrentTrack.IsPlaying ? "pause" : "play");
    public Task PlayAsync() => ExecuteAsync("play");
    public Task PauseAsync() => ExecuteAsync("pause");
    public Task NextTrackAsync() => Unsupported();
    public Task PreviousTrackAsync() => Unsupported();
    public Task SeekAsync(double seconds) => Unsupported();
    private Task Unsupported()
    {
        Publish(Volatile.Read(ref _snapshot), "The YouTube bridge supports play and pause only.");
        return Task.FromException(new InvalidOperationException(StatusText));
    }

    private async Task ExecuteAsync(string action)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var snapshot = Volatile.Read(ref _snapshot);
        if (!IsConnected || !snapshot.Track.IsAvailable || !snapshot.Ready)
            throw new InvalidOperationException("No controllable YouTube video is available.");
        if ((action == "play") == snapshot.Track.IsPlaying) return;
        var id = Guid.NewGuid().ToString();
        var request = new Pending(action, snapshot.TabId, new(TaskCreationOptions.RunContinuationsAsynchronously));
        _pending[id] = request;
        var failure = string.Empty;
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(_stopToken);
            timeout.CancelAfter(CommandTimeout);
            await _transport.SendAsync(JsonSerializer.Serialize(new { type = "mediaCommand", provider = "youtube", action, tabId = snapshot.TabId, requestId = id }), timeout.Token).ConfigureAwait(false);
            var result = await request.Completion.Task.WaitAsync(timeout.Token).ConfigureAwait(false);
            if (!result.Success) failure = result.Reason switch
            {
                "ack_mismatch" => "YouTube returned a mismatched acknowledgement. No success was confirmed.",
                "bridge_disconnected" or "bridge_disabled" => "The browser disconnected before the command was confirmed.",
                _ => "YouTube did not confirm the playback command. Check the video tab."
            };
            else Publish(Volatile.Read(ref _snapshot), string.Empty);
        }
        catch (OperationCanceledException) when (_stopToken.IsCancellationRequested) { throw; }
        catch (OperationCanceledException) { failure = "YouTube did not respond within five seconds. Check the video tab."; }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or ObjectDisposedException) { failure = "The browser bridge is unavailable. Check its connection."; }
        finally { _pending.TryRemove(id, out _); }
        if (failure.Length > 0) { Publish(Volatile.Read(ref _snapshot), failure); throw new InvalidOperationException(failure); }
    }

    private void Publish(Snapshot state, string status)
    {
        lock (_stateGate)
        {
            if (_disposed || state.Track.IsAvailable && !IsConnected) return;
            Volatile.Write(ref _snapshot, state); Volatile.Write(ref _status, status);
            TrackChanged?.Invoke(this, state.Track);
            ConnectionChanged?.Invoke(this, EventArgs.Empty);
        }
    }
    private void FailPending(string reason)
    { foreach (var id in _pending.Keys) if (_pending.TryRemove(id, out var request)) request.Completion.TrySetResult((false, reason)); }
    public void Dispose()
    {
        lock (_stateGate)
        {
        if (_disposed) return;
        _disposed = true; _enabled = _connected = false; _stop.Cancel();
        FailPending("bridge_disconnected");
        _transport.ConnectionChanged -= OnConnection; _transport.MessageReceived -= OnMessage; _transport.Dispose();
        }
    }
}
