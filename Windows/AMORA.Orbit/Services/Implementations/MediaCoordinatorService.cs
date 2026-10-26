using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>One media source for the UI, assistant and automations.</summary>
public sealed class MediaCoordinatorService : IMediaService, IDisposable
{
    private readonly IMediaService _system;
    private readonly BrowserMediaBridgeService _browser;
    private bool _disposed;
    public MediaCoordinatorService(IMediaService system, BrowserMediaBridgeService browser)
    {
        _system = system; _browser = browser;
        _system.TrackChanged += OnTrackChanged; _browser.TrackChanged += OnTrackChanged;
    }
    // Live YouTube playback wins; a playing native player wins over paused YouTube.
    // When both are paused, the explicitly enabled browser target can be resumed.
    private IMediaService Selected => _browser.IsConnected && _browser.CurrentTrack.IsAvailable &&
        (_browser.CurrentTrack.IsPlaying || !_system.CurrentTrack.IsPlaying) ? _browser : _system;
    public MediaTrack CurrentTrack => Selected.CurrentTrack;
    public bool IsConnected => Selected.IsConnected;
    public string ProviderName => Selected.ProviderName;
    public string StatusText => Selected.StatusText;
    public bool CanTogglePlayPause => Selected.CanTogglePlayPause;
    public bool CanGoNext => Selected.CanGoNext;
    public bool CanGoPrevious => Selected.CanGoPrevious;
    public bool CanSeek => Selected.CanSeek;
    public event EventHandler<MediaTrack>? TrackChanged;
    private void OnTrackChanged(object? sender, MediaTrack track) { if (!_disposed) TrackChanged?.Invoke(this, CurrentTrack); }
    public Task TogglePlayPauseAsync() => Selected.TogglePlayPauseAsync();
    public Task PlayAsync() => Selected.PlayAsync();
    public Task PauseAsync() => Selected.PauseAsync();
    public Task NextTrackAsync() => Selected.NextTrackAsync();
    public Task PreviousTrackAsync() => Selected.PreviousTrackAsync();
    public Task SeekAsync(double seconds) => Selected.SeekAsync(seconds);
    public async Task RefreshAsync() { await Task.WhenAll(_system.RefreshAsync(), _browser.RefreshAsync()); }
    public void Dispose()
    {
        if (_disposed) return; _disposed = true;
        _system.TrackChanged -= OnTrackChanged; _browser.TrackChanged -= OnTrackChanged;
        if (_system is IDisposable disposable) disposable.Dispose();
        _browser.Dispose();
    }
}
