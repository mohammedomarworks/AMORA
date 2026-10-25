using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>
/// Separated preview media service providing interactive preview playback.
/// Clearly designated as Preview state so users and tests are never misled.
/// </summary>
public class PreviewMediaService : IMediaService
{
    private MediaTrack _currentTrack;
    public MediaTrack CurrentTrack => _currentTrack;
    public bool IsConnected => true;
    public string ProviderName => "Preview Media (Simulated)";

    public event EventHandler<MediaTrack>? TrackChanged;

    public PreviewMediaService(MediaTrack? initial = null)
    {
        _currentTrack = initial ?? new MediaTrack(
            Title: "Midnight City (Orbit Mix)",
            Artist: "M83",
            Album: "Hurry Up, We're Dreaming",
            Source: MediaSourceType.Spotify,
            IsPlaying: true,
            IsAvailable: true,
            Elapsed: TimeSpan.FromSeconds(84),
            Duration: TimeSpan.FromSeconds(243)
        );
    }

    public Task TogglePlayPauseAsync()
    {
        _currentTrack = _currentTrack with { IsPlaying = !_currentTrack.IsPlaying };
        TrackChanged?.Invoke(this, _currentTrack);
        return Task.CompletedTask;
    }

    public Task PlayAsync()
    {
        _currentTrack = _currentTrack with { IsPlaying = true };
        TrackChanged?.Invoke(this, _currentTrack);
        return Task.CompletedTask;
    }

    public Task PauseAsync()
    {
        _currentTrack = _currentTrack with { IsPlaying = false };
        TrackChanged?.Invoke(this, _currentTrack);
        return Task.CompletedTask;
    }

    public Task NextTrackAsync()
    {
        _currentTrack = new MediaTrack(
            Title: "Starry Night",
            Artist: "Peggy Gou",
            Album: "Moment EP",
            Source: MediaSourceType.Spotify,
            IsPlaying: true,
            IsAvailable: true,
            Elapsed: TimeSpan.FromSeconds(12),
            Duration: TimeSpan.FromSeconds(398)
        );
        TrackChanged?.Invoke(this, _currentTrack);
        return Task.CompletedTask;
    }

    public Task PreviousTrackAsync()
    {
        _currentTrack = new MediaTrack(
            Title: "Solaris",
            Artist: "Photay",
            Album: "Waking Hours",
            Source: MediaSourceType.Spotify,
            IsPlaying: true,
            IsAvailable: true,
            Elapsed: TimeSpan.FromSeconds(5),
            Duration: TimeSpan.FromSeconds(215)
        );
        TrackChanged?.Invoke(this, _currentTrack);
        return Task.CompletedTask;
    }

    public Task SeekAsync(double seconds)
    {
        _currentTrack = _currentTrack with { Elapsed = TimeSpan.FromSeconds(Math.Clamp(seconds, 0, _currentTrack.Duration.TotalSeconds)) };
        TrackChanged?.Invoke(this, _currentTrack);
        return Task.CompletedTask;
    }

    public Task RefreshAsync()
    {
        TrackChanged?.Invoke(this, _currentTrack);
        return Task.CompletedTask;
    }
}
