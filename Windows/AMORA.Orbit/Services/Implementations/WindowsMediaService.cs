using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using Windows.Media.Control;

namespace AMORA.Orbit.Services.Implementations;

public enum WindowsMediaAction { TogglePlayPause, Play, Pause, Next, Previous, Seek }

public sealed record WindowsMediaSnapshot(MediaTrack Track, bool CanPlay = false, bool CanPause = false,
    bool CanToggle = false, bool CanNext = false, bool CanPrevious = false, bool CanSeek = false)
{
    public static WindowsMediaSnapshot Empty { get; } = new(MediaTrack.None);
}

/// <summary>Native-session boundary, allowing failure and capability checks without a running player.</summary>
public interface IWindowsMediaSessionBackend
{
    Task<WindowsMediaSnapshot> ReadAsync(CancellationToken token);
    Task<bool> ExecuteAsync(WindowsMediaAction action, double seconds, CancellationToken token);
}

/// <summary>Polls the active Windows system-media session; never substitutes preview content.</summary>
public sealed class WindowsMediaService : IMediaService, IDisposable
{
    private readonly IWindowsMediaSessionBackend _backend;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly CancellationTokenSource _stop = new();
    private readonly CancellationToken _stopToken;
    private readonly Task _pollTask;
    private WindowsMediaSnapshot _snapshot = WindowsMediaSnapshot.Empty;
    private string _statusText = "Looking for Windows media…";
    private int _disposed;

    public WindowsMediaService() : this(new NativeWindowsMediaSessionBackend()) { }

    public WindowsMediaService(IWindowsMediaSessionBackend backend, bool startPolling = true)
    {
        _backend = backend ?? throw new ArgumentNullException(nameof(backend));
        _stopToken = _stop.Token;
        _pollTask = startPolling ? Task.Run(PollAsync) : Task.CompletedTask;
    }

    public MediaTrack CurrentTrack => Volatile.Read(ref _snapshot).Track;
    public bool IsConnected => CurrentTrack.IsAvailable;
    public string ProviderName => "Windows system media";
    public string StatusText => Volatile.Read(ref _statusText);
    public bool CanTogglePlayPause => IsConnected && SupportsAction(Volatile.Read(ref _snapshot), WindowsMediaAction.TogglePlayPause);
    public bool CanGoNext => IsConnected && Volatile.Read(ref _snapshot).CanNext;
    public bool CanGoPrevious => IsConnected && Volatile.Read(ref _snapshot).CanPrevious;
    public bool CanSeek => IsConnected && Volatile.Read(ref _snapshot).CanSeek;
    public event EventHandler<MediaTrack>? TrackChanged;

    private async Task PollAsync()
    {
        try
        {
            await RefreshAsync();
            using var timer = new PeriodicTimer(TimeSpan.FromSeconds(2));
            while (await timer.WaitForNextTickAsync(_stopToken)) await RefreshAsync();
        }
        catch (OperationCanceledException) when (_stopToken.IsCancellationRequested) { }
    }

    public async Task RefreshAsync()
    {
        if (Volatile.Read(ref _disposed) != 0) return;
        await _gate.WaitAsync(_stopToken);
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(_stopToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(5));
            var snapshot = await _backend.ReadAsync(timeout.Token);
            Publish(snapshot, snapshot.Track.IsAvailable ? string.Empty : "No active Windows media session.");
        }
        catch (OperationCanceledException) when (_stopToken.IsCancellationRequested) { }
        catch
        {
            // Player/COM exceptions may contain private metadata. Present a bounded
            // error without logging or exposing the underlying exception content.
            Publish(WindowsMediaSnapshot.Empty, "Windows media is unavailable. Open a player and try again.");
        }
        finally { _gate.Release(); }
    }

    public Task TogglePlayPauseAsync() => ExecuteAsync(WindowsMediaAction.TogglePlayPause);
    public Task PlayAsync() => ExecuteAsync(WindowsMediaAction.Play);
    public Task PauseAsync() => ExecuteAsync(WindowsMediaAction.Pause);
    public Task NextTrackAsync() => ExecuteAsync(WindowsMediaAction.Next);
    public Task PreviousTrackAsync() => ExecuteAsync(WindowsMediaAction.Previous);
    public Task SeekAsync(double seconds) => ExecuteAsync(WindowsMediaAction.Seek, seconds);

    private async Task ExecuteAsync(WindowsMediaAction action, double seconds = 0)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref _disposed) != 0, this);
        if (action == WindowsMediaAction.Seek && (!double.IsFinite(seconds) || seconds < 0))
            throw new ArgumentOutOfRangeException(nameof(seconds), "Seek position must be a finite positive duration.");
        await _gate.WaitAsync(_stopToken);
        var error = string.Empty;
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(_stopToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(5));
            var state = await _backend.ReadAsync(timeout.Token);
            Publish(state, state.Track.IsAvailable ? string.Empty : "No active Windows media session.");
            if (!state.Track.IsAvailable) error = "No active Windows media session is available.";
            else if (action == WindowsMediaAction.Play && state.Track.IsPlaying) return;
            else if (action == WindowsMediaAction.Pause && !state.Track.IsPlaying) return;
            else if (!SupportsAction(state, action)) error = "This player does not support that control.";
            else
            {
                if (action == WindowsMediaAction.TogglePlayPause && !state.CanToggle)
                    action = state.Track.IsPlaying ? WindowsMediaAction.Pause : WindowsMediaAction.Play;
                if (action == WindowsMediaAction.Seek)
                    seconds = Math.Clamp(seconds, 0, state.Track.Duration.TotalSeconds);
                if (!await _backend.ExecuteAsync(action, seconds, timeout.Token))
                    error = "The player rejected the playback command.";
                else
                {
                    var updated = await _backend.ReadAsync(timeout.Token);
                    Publish(updated, updated.Track.IsAvailable ? string.Empty : "The media session ended.");
                }
            }
        }
        catch (OperationCanceledException) when (_stopToken.IsCancellationRequested) { throw; }
        catch { error = "Windows media did not respond. Try the player again."; }
        finally { _gate.Release(); }

        if (error.Length > 0)
        {
            Publish(Volatile.Read(ref _snapshot), error);
            throw new InvalidOperationException(error);
        }
    }

    private static bool SupportsAction(WindowsMediaSnapshot state, WindowsMediaAction action) => action switch
    {
        WindowsMediaAction.TogglePlayPause => state.CanToggle || (state.Track.IsPlaying ? state.CanPause : state.CanPlay),
        WindowsMediaAction.Play => state.CanPlay,
        WindowsMediaAction.Pause => state.CanPause,
        WindowsMediaAction.Next => state.CanNext,
        WindowsMediaAction.Previous => state.CanPrevious,
        WindowsMediaAction.Seek => state.CanSeek && state.Track.Duration > TimeSpan.Zero,
        _ => false
    };

    private void Publish(WindowsMediaSnapshot snapshot, string status)
    {
        if (Volatile.Read(ref _disposed) != 0) return;
        var changed = snapshot != Volatile.Read(ref _snapshot) || status != StatusText;
        Volatile.Write(ref _snapshot, snapshot);
        Volatile.Write(ref _statusText, status);
        if (changed) TrackChanged?.Invoke(this, snapshot.Track);
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
        _stop.Cancel();
        // Do not dispose a semaphore while an in-flight WinRT operation releases it.
        // Cancellation quiesces the polling task; the managed gate is then collected.
    }

    public static MediaSourceType ClassifySource(string? appId)
    {
        var id = appId?.ToLowerInvariant() ?? string.Empty;
        if (id.Contains("spotify")) return MediaSourceType.Spotify;
        if (id.Contains("applemusic") || id.Contains("appleinc.applemusic")) return MediaSourceType.AppleMusic;
        // Browser session identity does not reveal the website. Never label all
        // Chrome/Edge playback as YouTube, or every app containing 'music' as Apple.
        return MediaSourceType.System;
    }
}

internal sealed class NativeWindowsMediaSessionBackend : IWindowsMediaSessionBackend
{
    private GlobalSystemMediaTransportControlsSessionManager? _manager;
    private GlobalSystemMediaTransportControlsSession? _session;
    private TimeSpan _timelineStart;

    public async Task<WindowsMediaSnapshot> ReadAsync(CancellationToken token)
    {
        try { return await ReadCoreAsync(token); }
        catch
        {
            // A disconnected manager/session is retried on the next refresh.
            _session = null;
            _manager = null;
            throw;
        }
    }

    private async Task<WindowsMediaSnapshot> ReadCoreAsync(CancellationToken token)
    {
        _manager ??= await GlobalSystemMediaTransportControlsSessionManager.RequestAsync().AsTask(token);
        _session = _manager.GetCurrentSession();
        if (_session == null) return WindowsMediaSnapshot.Empty;
        var media = await _session.TryGetMediaPropertiesAsync().AsTask(token);
        var playback = _session.GetPlaybackInfo();
        var timeline = _session.GetTimelineProperties();
        var controls = playback?.Controls;
        _timelineStart = timeline?.StartTime ?? TimeSpan.Zero;
        var duration = (timeline?.EndTime ?? _timelineStart) - _timelineStart;
        if (duration < TimeSpan.Zero) duration = TimeSpan.Zero;
        var elapsed = (timeline?.Position ?? _timelineStart) - _timelineStart;
        elapsed = TimeSpan.FromTicks(Math.Clamp(elapsed.Ticks, 0, duration.Ticks));
        var track = new MediaTrack(
            string.IsNullOrWhiteSpace(media?.Title) ? "Active media" : media.Title,
            string.IsNullOrWhiteSpace(media?.Artist) ? "Windows media session" : media.Artist,
            media?.AlbumTitle ?? string.Empty,
            WindowsMediaService.ClassifySource(_session.SourceAppUserModelId),
            playback?.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing,
            true, elapsed, duration);
        var canToggle = controls?.IsPlayPauseToggleEnabled == true ||
            (track.IsPlaying ? controls?.IsPauseEnabled == true : controls?.IsPlayEnabled == true);
        return new WindowsMediaSnapshot(track, controls?.IsPlayEnabled == true,
            controls?.IsPauseEnabled == true, canToggle,
            controls?.IsNextEnabled == true, controls?.IsPreviousEnabled == true,
            controls?.IsPlaybackPositionEnabled == true && duration > TimeSpan.Zero);
    }

    public async Task<bool> ExecuteAsync(WindowsMediaAction action, double seconds, CancellationToken token)
    {
        var session = _session;
        if (session == null) return false;
        if (action == WindowsMediaAction.TogglePlayPause && session.GetPlaybackInfo() is { } playback &&
            !playback.Controls.IsPlayPauseToggleEnabled)
            action = playback.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing
                ? WindowsMediaAction.Pause : WindowsMediaAction.Play;
        return action switch
        {
            WindowsMediaAction.TogglePlayPause => await session.TryTogglePlayPauseAsync().AsTask(token),
            WindowsMediaAction.Play => await session.TryPlayAsync().AsTask(token),
            WindowsMediaAction.Pause => await session.TryPauseAsync().AsTask(token),
            WindowsMediaAction.Next => await session.TrySkipNextAsync().AsTask(token),
            WindowsMediaAction.Previous => await session.TrySkipPreviousAsync().AsTask(token),
            WindowsMediaAction.Seek => await session.TryChangePlaybackPositionAsync(
                (_timelineStart + TimeSpan.FromSeconds(seconds)).Ticks).AsTask(token),
            _ => false
        };
    }
}
