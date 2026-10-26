using System.ComponentModel;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.ViewModels;

public sealed class LocalBrainViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly ILocalBrainService _service;
    private readonly IAISettingsService _settings;
    private readonly Action<Action> _dispatch;
    private readonly CancellationTokenSource _lifetime = new();
    private string _selectedModelId;
    private LocalBrainSnapshot _snapshot;
    private string? _message;
    private bool _working, _disposed;

    public LocalBrainViewModel(ILocalBrainService service, IAISettingsService settings, Action<Action>? dispatch = null)
    {
        _service = service;
        _settings = settings;
        _dispatch = dispatch ?? (action => action());
        _selectedModelId = Models.Any(m => m.Id == settings.CurrentSettings.LocalBrainModelId)
            ? settings.CurrentSettings.LocalBrainModelId : LocalBrainCatalog.DefaultModelId;
        _snapshot = service.Snapshot;
        service.StateChanged += OnStateChanged;
        settings.SettingsChanged += OnSettingsChanged;
    }
    public IReadOnlyList<LocalBrainModelDescriptor> Models => _service.Models;
    public string SelectedModelId
    {
        get => _selectedModelId;
        set
        {
            if (_disposed || IsBusy || value == _selectedModelId || !Models.Any(m => m.Id == value)) return;
            _selectedModelId = value;
            _message = _service.IsInstalled(value) ? "Selected model is installed. Start will verify its files before loading."
                : "Selected model is not installed. Install downloads the displayed model and the 23 MB runtime.";
            Notify();
        }
    }
    public string StatusMessage => _message ?? _snapshot.Message;
    public string DownloadLabel => LocalBrainCatalog.Find(SelectedModelId).DownloadLabel;
    public double ProgressPercent => _snapshot.ProgressPercent;
    public bool IsBusy => !_disposed && (_working || _snapshot.IsBusy);
    public bool CanOperate => !_disposed && !IsBusy;
    public bool IsReady => !_disposed && _snapshot.IsReady && _snapshot.ModelId == SelectedModelId;
    public bool IsInstalled => !_disposed && _service.IsInstalled(SelectedModelId);
    public bool IsSelectedProvider => _settings.CurrentSettings.SelectedProvider == AISettings.ProviderLocalBrain
        && _settings.CurrentSettings.LocalBrainModelId == SelectedModelId;
    public event PropertyChangedEventHandler? PropertyChanged;

    public Task InitializeAsync() => RunAsync((id, token) => _service.RefreshAsync(id, token));
    public Task InstallAsync() => RunAsync((id, token) => _service.InstallAsync(id, token));
    public Task StartAsync() => RunAsync((id, token) => _service.StartAsync(id, token));
    public Task DeleteAsync() => RunAsync((id, token) => _service.DeleteModelAsync(id, token));
    public Task UseSelectedAsync() => RunAsync(async (id, token) =>
    {
        token.ThrowIfCancellationRequested();
        await _settings.SaveSettingsAsync(_settings.CurrentSettings with
        { SelectedProvider = AISettings.ProviderLocalBrain, LocalBrainModelId = id });
        Update(() => _message = "Local Brain selected for conversations. No cloud fallback will be used. Install this model if needed.");
    });
    public async Task StopAsync()
    {
        if (_disposed) return;
        try { await _service.StopAsync(); }
        catch (Exception) { Update(() => _message = "Local Brain could not be stopped cleanly. Close AMORA to release its owned runtime."); }
    }
    public void Cancel() { if (!_disposed) _service.CancelOperation(); }

    private async Task RunAsync(Func<string, CancellationToken, Task> operation)
    {
        if (!CanOperate) return;
        string modelId = SelectedModelId;
        _working = true;
        _message = null;
        Notify();
        try { await operation(modelId, _lifetime.Token); }
        catch (OperationCanceledException) { Update(() => _message = "Local Brain operation cancelled."); }
        catch (LocalBrainException error) { Update(() => _message = error.Message); }
        catch (Exception) { Update(() => _message = "Local Brain could not complete this operation. Check setup and try again."); }
        finally { Update(() => _working = false); }
    }
    private void OnStateChanged(object? sender, LocalBrainSnapshot snapshot) => Update(() => { _snapshot = snapshot; _message = null; });
    private void OnSettingsChanged(object? sender, AISettings settings) => Update(() => { });
    private void Update(Action change) => _dispatch(() => { if (!_disposed) { change(); Notify(); } });
    private void Notify()
    {
        if (_disposed) return;
        foreach (var name in new[] { nameof(SelectedModelId), nameof(StatusMessage), nameof(DownloadLabel), nameof(ProgressPercent),
            nameof(IsBusy), nameof(CanOperate), nameof(IsReady), nameof(IsInstalled), nameof(IsSelectedProvider) })
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _service.StateChanged -= OnStateChanged;
        _settings.SettingsChanged -= OnSettingsChanged;
        _lifetime.Cancel();
        _lifetime.Dispose();
    }
}
