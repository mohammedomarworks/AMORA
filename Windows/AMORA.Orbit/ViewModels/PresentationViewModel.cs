using System.ComponentModel;
using System.Runtime.CompilerServices;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Implementations;

namespace AMORA.Orbit.ViewModels;

public sealed class PresentationViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly PresentationPreferencesStore _store;
    private PresentationPreferences _value;
    private bool _disposed;
    private int _generation;
    private string _status;
    public PresentationViewModel(PresentationPreferencesStore store)
    { _store = store; _value = store.Current; _status = store.LoadError ?? "Ready"; }
    public PresentationPreferences Value => _value;
    public string Theme { get => _value.Theme; set => Update(_value with { Theme = value }); }
    public double MascotSize { get => _value.MascotSize; set => Update(_value with { MascotSize = value }); }
    public double SurfaceOpacity { get => _value.SurfaceOpacity; set => Update(_value with { SurfaceOpacity = value }); }
    public double MotionIntensity { get => _value.MotionIntensity; set => Update(_value with { MotionIntensity = value }); }
    public bool HoverToExpand { get => _value.HoverToExpand; set => Update(_value with { HoverToExpand = value }); }
    public double AutoCollapseSeconds { get => _value.AutoCollapseSeconds; set => Update(_value with { AutoCollapseSeconds = value }); }
    public bool SleepMode { get => _value.SleepMode; set => Update(_value with { SleepMode = value }); }
    public double IdleTimeoutSeconds { get => _value.IdleTimeoutSeconds; set => Update(_value with { IdleTimeoutSeconds = value }); }
    public bool AvoidFullscreen { get => _value.AvoidFullscreen; set => Update(_value with { AvoidFullscreen = value }); }
    public bool SoundEnabled { get => _value.SoundEnabled; set => Update(_value with { SoundEnabled = value }); }
    public double SoundVolume { get => _value.SoundVolume; set => Update(_value with { SoundVolume = value }); }
    public bool MusicEnabled { get => _value.MusicEnabled; set => Update(_value with { MusicEnabled = value }); }
    public bool TimerEnabled { get => _value.TimerEnabled; set => Update(_value with { TimerEnabled = value }); }
    public bool BatteryEnabled { get => _value.BatteryEnabled; set => Update(_value with { BatteryEnabled = value }); }
    public bool SystemMonitorEnabled { get => _value.SystemMonitorEnabled; set => Update(_value with { SystemMonitorEnabled = value }); }
    public bool BrowserBridgeEnabled { get => _value.BrowserBridgeEnabled; set => Update(_value with { BrowserBridgeEnabled = value }); }
    public string AccentHex => PresentationPreferences.AccentFor(Theme);
    public string OpacityLabel => $"{SurfaceOpacity:P0}";
    public string SizeLabel => $"{MascotSize:0} pt";
    public string MotionLabel => $"{MotionIntensity:P0}";
    public string CollapseLabel => $"{AutoCollapseSeconds:0.0}s";
    public string IdleLabel => $"{IdleTimeoutSeconds / 60:0.0} min";
    public string VolumeLabel => $"{SoundVolume:P0}";
    public string Status { get => _status; private set { _status = value; Changed(); } }
    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler? PreviewChanged;
    private void Update(PresentationPreferences value, [CallerMemberName] string? property = null)
    {
        if (_disposed || _value == value) return;
        value.Validate();
        _value = value;
        _generation++;
        Changed(property);
        foreach (var name in new[] { nameof(AccentHex), nameof(OpacityLabel), nameof(SizeLabel), nameof(MotionLabel), nameof(CollapseLabel), nameof(IdleLabel), nameof(VolumeLabel) }) Changed(name);
        Status = "Preview applied. Save preferences to keep these changes.";
        PreviewChanged?.Invoke(this, EventArgs.Empty);
    }
    public async Task SaveAsync()
    {
        if (_disposed) return;
        var version = _generation;
        try { await _store.SaveAsync(_value); if (!_disposed && version == _generation) Status = "Preferences saved on this PC."; }
        catch { if (!_disposed) Status = "Preferences could not be saved. Your previous saved configuration is preserved."; }
    }
    private void Changed([CallerMemberName] string? name = null) { if (!_disposed) PropertyChanged?.Invoke(this, new(name)); }
    public void Dispose() { _disposed = true; PreviewChanged = null; }
}
