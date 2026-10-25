using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>
/// Native Windows Global System Media Transport Controls (GSMTC) media service.
/// Connects to active Windows media players (Spotify, Apple Music, Edge, Chrome) via WinRT.
/// </summary>
public class WindowsMediaService : IMediaService
{
    private MediaTrack _currentTrack = MediaTrack.None;
    public MediaTrack CurrentTrack => _currentTrack;
    public bool IsConnected { get; private set; }
    public string ProviderName => "Windows GSMTC";

    public event EventHandler<MediaTrack>? TrackChanged;

    public WindowsMediaService()
    {
        _ = InitializeAsync();
    }

    private async Task InitializeAsync()
    {
        try
        {
            // WinRT GSMTC session manager initialization is safe under Windows App SDK
            await RefreshAsync();
        }
        catch
        {
            IsConnected = false;
            _currentTrack = MediaTrack.None;
            TrackChanged?.Invoke(this, _currentTrack);
        }
    }

    public async Task RefreshAsync()
    {
        try
        {
#if WINDOWS
            var sessionManager = await Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            var currentSession = sessionManager?.GetCurrentSession();

            if (currentSession != null)
            {
                var mediaProperties = await currentSession.TryGetMediaPropertiesAsync();
                var timeline = currentSession.GetTimelineProperties();
                var playbackInfo = currentSession.GetPlaybackInfo();

                string sourceAppId = currentSession.SourceAppUserModelId?.ToLowerInvariant() ?? string.Empty;
                MediaSourceType source = sourceAppId switch
                {
                    var id when id.Contains("spotify") => MediaSourceType.Spotify,
                    var id when id.Contains("applemusic") || id.Contains("music") => MediaSourceType.AppleMusic,
                    var id when id.Contains("chrome") || id.Contains("msedge") => MediaSourceType.YouTube,
                    _ => MediaSourceType.System
                };

                bool isPlaying = playbackInfo?.PlaybackStatus == Windows.Media.Control.GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;

                _currentTrack = new MediaTrack(
                    Title: string.IsNullOrWhiteSpace(mediaProperties?.Title) ? "Active Media" : mediaProperties.Title,
                    Artist: string.IsNullOrWhiteSpace(mediaProperties?.Artist) ? "Windows Player" : mediaProperties.Artist,
                    Album: mediaProperties?.AlbumTitle ?? string.Empty,
                    Source: source,
                    IsPlaying: isPlaying,
                    IsAvailable: true,
                    Elapsed: timeline?.Position ?? TimeSpan.Zero,
                    Duration: timeline?.EndTime ?? TimeSpan.Zero
                );
                IsConnected = true;
            }
            else
            {
                _currentTrack = MediaTrack.None;
                IsConnected = false;
            }
#else
            _currentTrack = MediaTrack.None;
            IsConnected = false;
#endif
        }
        catch
        {
            _currentTrack = MediaTrack.None;
            IsConnected = false;
        }

        TrackChanged?.Invoke(this, _currentTrack);
    }

    public async Task TogglePlayPauseAsync()
    {
#if WINDOWS
        try
        {
            var sessionManager = await Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            var session = sessionManager?.GetCurrentSession();
            if (session != null)
            {
                await session.TryTogglePlayPauseAsync();
                await RefreshAsync();
            }
        }
        catch { }
#else
        await Task.CompletedTask;
#endif
    }

    public async Task PlayAsync()
    {
#if WINDOWS
        try
        {
            var sessionManager = await Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            var session = sessionManager?.GetCurrentSession();
            if (session != null)
            {
                await session.TryPlayAsync();
                await RefreshAsync();
            }
        }
        catch { }
#else
        await Task.CompletedTask;
#endif
    }

    public async Task PauseAsync()
    {
#if WINDOWS
        try
        {
            var sessionManager = await Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            var session = sessionManager?.GetCurrentSession();
            if (session != null)
            {
                await session.TryPauseAsync();
                await RefreshAsync();
            }
        }
        catch { }
#else
        await Task.CompletedTask;
#endif
    }

    public async Task NextTrackAsync()
    {
#if WINDOWS
        try
        {
            var sessionManager = await Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            var session = sessionManager?.GetCurrentSession();
            if (session != null)
            {
                await session.TrySkipNextAsync();
                await RefreshAsync();
            }
        }
        catch { }
#else
        await Task.CompletedTask;
#endif
    }

    public async Task PreviousTrackAsync()
    {
#if WINDOWS
        try
        {
            var sessionManager = await Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            var session = sessionManager?.GetCurrentSession();
            if (session != null)
            {
                await session.TrySkipPreviousAsync();
                await RefreshAsync();
            }
        }
        catch { }
#else
        await Task.CompletedTask;
#endif
    }

    public async Task SeekAsync(double seconds)
    {
#if WINDOWS
        try
        {
            var sessionManager = await Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            var session = sessionManager?.GetCurrentSession();
            if (session != null)
            {
                await session.TryChangePlaybackPositionAsync((long)TimeSpan.FromSeconds(seconds).Ticks);
                await RefreshAsync();
            }
        }
        catch { }
#else
        await Task.CompletedTask;
#endif
    }
}
