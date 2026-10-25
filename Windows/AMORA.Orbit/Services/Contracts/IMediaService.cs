using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface IMediaService
{
    MediaTrack CurrentTrack { get; }
    bool IsConnected { get; }
    string ProviderName { get; }
    bool IsPlaying => CurrentTrack.IsPlaying;

    event EventHandler<MediaTrack>? TrackChanged;

    Task TogglePlayPauseAsync();
    Task PlayAsync() => TogglePlayPauseAsync();
    Task PauseAsync() => TogglePlayPauseAsync();
    Task NextTrackAsync();
    Task PreviousTrackAsync();
    Task SeekAsync(double seconds);
    Task SeekToAsync(TimeSpan target) => SeekAsync(target.TotalSeconds);
    Task RefreshAsync();
}
