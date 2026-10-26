using System.Collections.ObjectModel;
using System.ComponentModel;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.ViewModels;

public sealed class ClipboardViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly IClipboardHistoryService _service;
    private readonly Action<Action> _dispatch;
    private bool _disposed;
    public ClipboardViewModel(IClipboardHistoryService service, Action<Action>? dispatch = null)
    {
        _service = service ?? throw new ArgumentNullException(nameof(service));
        _dispatch = dispatch ?? (action => action());
        _service.Changed += OnChanged;
        Apply();
    }

    public ObservableCollection<ClipboardEntry> Entries { get; } = new();
    public bool IsEnabled => _service.IsEnabled;
    public bool HasEntries => Entries.Count > 0;
    public string StatusText => _service.StatusText;
    public event PropertyChangedEventHandler? PropertyChanged;
    public Task<bool> CopyAsync(string id) => _service.CopyAsync(id);
    public void Remove(string id) => _service.Remove(id);
    public void Clear() => _service.Clear();
    private void OnChanged(object? sender, EventArgs args) => _dispatch(Apply);
    private void Apply()
    {
        if (_disposed) return;
        Entries.Clear();
        foreach (var entry in _service.Entries) Entries.Add(entry);
        foreach (var property in new[] { nameof(IsEnabled), nameof(HasEntries), nameof(StatusText) })
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));
    }
    public void Dispose() { _disposed = true; _service.Changed -= OnChanged; Entries.Clear(); }
}
