using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public sealed class ClipboardHistoryService : IClipboardHistoryService
{
    public const int Capacity = 15;
    private readonly IClipboardSource _source;
    private readonly object _gate = new();
    private readonly List<ClipboardEntry> _entries = new();
    private readonly CancellationTokenSource _lifetime = new();
    private readonly CancellationToken _lifetimeToken;
    private CancellationTokenSource _captureSession = new();
    private bool _enabled;
    private bool _disposed;
    private long _generation;
    private long _capture;
    private string _status = "Clipboard history is off. Enable it in Settings to capture future copied text.";

    public ClipboardHistoryService(IClipboardSource source)
    {
        _source = source ?? throw new ArgumentNullException(nameof(source));
        _lifetimeToken = _lifetime.Token;
    }

    public bool IsEnabled { get { lock (_gate) return _enabled; } }
    public IReadOnlyList<ClipboardEntry> Entries { get { lock (_gate) return _entries.ToArray(); } }
    public string StatusText { get { lock (_gate) return _status; } }
    public event EventHandler? Changed;

    public void SetEnabled(bool enabled)
    {
        lock (_gate)
        {
            if (_disposed || _enabled == enabled) return;
            _enabled = enabled;
            _generation++;
            _captureSession.Cancel();
            _captureSession.Dispose();
            _captureSession = new CancellationTokenSource();
            if (enabled) _source.ContentChanged += OnContentChanged;
            else
            {
                _source.ContentChanged -= OnContentChanged;
                _entries.Clear();
            }
            _status = enabled ? "Capturing future copied text locally. Protected content is skipped; history clears when disabled or closed."
                : "Clipboard history is off. Enable it in Settings to capture future copied text.";
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }

    private async void OnContentChanged(object? sender, EventArgs args) => await CaptureLatestAsync();

    public async Task CaptureLatestAsync()
    {
        long generation, capture;
        CancellationToken cancellationToken;
        lock (_gate)
        {
            if (!_enabled || _disposed) return;
            generation = _generation;
            capture = ++_capture;
            cancellationToken = _captureSession.Token;
        }
        try
        {
            var snapshot = await _source.GetSnapshotAsync(cancellationToken);
            if (snapshot == null || !snapshot.HasText || ClipboardPrivacyFilter.HasExcludedFormat(snapshot.Formats)) return;
            lock (_gate) if (!CanCapture(generation, capture)) return;
            var text = await snapshot.ReadTextAsync(cancellationToken);
            if (!ClipboardPrivacyFilter.IsSafeText(text)) return;
            lock (_gate)
            {
                if (!CanCapture(generation, capture)) return;
                if (_entries.FirstOrDefault()?.Text == text) return;
                _entries.Insert(0, new ClipboardEntry(Guid.NewGuid().ToString("N"), text!, DateTimeOffset.UtcNow));
                if (_entries.Count > Capacity) _entries.RemoveRange(Capacity, _entries.Count - Capacity);
                _status = $"{_entries.Count} local clipboard item{(_entries.Count == 1 ? "" : "s")}. Nothing is saved to disk or shared with AI.";
            }
            Changed?.Invoke(this, EventArgs.Empty);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
        catch
        {
            lock (_gate)
            {
                if (!CanCapture(generation, capture)) return;
                _status = "Clipboard is temporarily unavailable. AMORA will try again on the next copy.";
            }
            Changed?.Invoke(this, EventArgs.Empty);
        }
    }

    private bool CanCapture(long generation, long capture) => !_disposed && _enabled && _generation == generation && _capture == capture;

    public void Clear()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _generation++;
            _captureSession.Cancel();
            _captureSession.Dispose();
            _captureSession = new CancellationTokenSource();
            _entries.Clear();
            _status = _enabled ? "History cleared. Future copied text will appear here." : "Clipboard history is off.";
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public bool Remove(string id)
    {
        bool removed;
        lock (_gate)
        {
            if (_disposed) return false;
            removed = _entries.RemoveAll(entry => entry.Id == id) > 0;
            if (removed) _generation++;
        }
        if (removed) Changed?.Invoke(this, EventArgs.Empty);
        return removed;
    }

    public async Task<bool> CopyAsync(string id)
    {
        ClipboardEntry? entry;
        lock (_gate)
        {
            if (_disposed || !_enabled) return false;
            entry = _entries.FirstOrDefault(item => item.Id == id);
        }
        if (entry == null) return false;
        bool copied;
        try { copied = await _source.WriteTextAsync(entry.Text, _lifetimeToken); }
        catch { copied = false; }
        lock (_gate)
        {
            if (_disposed || !_enabled) return copied;
            _status = copied ? "Copied to the clipboard. This restore is excluded from clipboard history and cloud sync."
                : "The clipboard could not be updated. Try again.";
        }
        Changed?.Invoke(this, EventArgs.Empty);
        return copied;
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true;
            if (_enabled) _source.ContentChanged -= OnContentChanged;
            _enabled = false;
            _entries.Clear();
            _generation++;
            _captureSession.Cancel();
            _lifetime.Cancel();
        }
        _source.Dispose();
        _captureSession.Dispose();
        _lifetime.Dispose();
    }
}
