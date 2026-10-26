using AMORA.Orbit.ViewModels;
using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.Storage;
namespace AMORA.Orbit.Services.Implementations;

/// <summary>Windows-owned sounds; no bundled third-party audio, polling or per-keystroke effects.</summary>
public sealed class WindowsFeedbackSoundService : IDisposable
{
    private readonly PresentationViewModel _preferences;
    private MediaPlayer? _player;
    private bool _disposed;
    public WindowsFeedbackSoundService(PresentationViewModel preferences) => _preferences = preferences;
    public async Task<string> PlayAsync()
    {
        if (_disposed || !_preferences.SoundEnabled) return "Sound effects are off.";
        try
        {
            string media = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Media");
            string? path = new[] { "Windows Notify System Generic.wav", "Windows Notify.wav", "Windows Ding.wav" }
                .Select(name => Path.Combine(media, name)).FirstOrDefault(File.Exists);
            if (path == null) return "No Windows notification sound is available.";
            var file = await StorageFile.GetFileFromPathAsync(path);
            if (_disposed || !_preferences.SoundEnabled) return "Sound effects are off.";
            _player ??= new MediaPlayer { AutoPlay = false };
            _player.Volume = Math.Clamp(_preferences.SoundVolume, 0, 1);
            _player.Source = MediaSource.CreateFromStorageFile(file);
            _player.Play();
            return "Windows notification sound played.";
        }
        catch { return "Windows could not play the notification sound."; }
    }
    public void Dispose() { _disposed = true; _player?.Dispose(); _player = null; }
}
