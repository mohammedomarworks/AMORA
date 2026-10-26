using System.Runtime.InteropServices;
using AMORA.Orbit.Services.Contracts;
using Windows.ApplicationModel.DataTransfer;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>UI-thread native adapter. Its constructor never subscribes or reads clipboard data.</summary>
public sealed class WindowsClipboardSource : IClipboardSource
{
    private readonly Action<Action> _dispatch;
    private EventHandler? _changed;
    private bool _subscribed;
    private bool _disposed;

    public WindowsClipboardSource(Action<Action> dispatch) => _dispatch = dispatch ?? throw new ArgumentNullException(nameof(dispatch));

    public event EventHandler? ContentChanged
    {
        add
        {
            _changed += value;
            _dispatch(() =>
            {
                if (_disposed || _subscribed || _changed == null) return;
                Clipboard.ContentChanged += OnNativeChanged;
                _subscribed = true;
            });
        }
        remove
        {
            _changed -= value;
            _dispatch(() =>
            {
                if (!_subscribed || _changed != null) return;
                Clipboard.ContentChanged -= OnNativeChanged;
                _subscribed = false;
            });
        }
    }

    private void OnNativeChanged(object? sender, object args) { if (!_disposed) _changed?.Invoke(this, EventArgs.Empty); }

    public Task<IClipboardContentSnapshot?> GetSnapshotAsync(CancellationToken cancellationToken) => OnUiAsync<IClipboardContentSnapshot?>(() =>
    {
        uint sequence = GetClipboardSequenceNumber();
        if (sequence == 0) return null;
        var nativeMarkers = ClipboardPrivacyFilter.ExcludedFormats.Where(format =>
        {
            uint registered = RegisterClipboardFormat(format);
            return registered != 0 && IsClipboardFormatAvailable(registered);
        }).ToArray();
        // Do not even request the WinRT data package when native privacy markers are present.
        if (nativeMarkers.Length > 0) return new RejectedSnapshot(nativeMarkers);
        var content = Clipboard.GetContent();
        var formats = content.AvailableFormats.ToArray();
        if (GetClipboardSequenceNumber() != sequence) return null;
        return new NativeSnapshot(content, formats, sequence, this);
    }, cancellationToken);

    public Task<bool> WriteTextAsync(string text, CancellationToken cancellationToken) => OnUiAsync(() =>
    {
        var package = new DataPackage { RequestedOperation = DataPackageOperation.Copy };
        package.SetText(text);
        package.SetData("AMORA.PrivateClipboardRestore", "1");
        bool copied = Clipboard.SetContentWithOptions(package, new ClipboardContentOptions { IsAllowedInHistory = false, IsRoamable = false });
        if (copied) Clipboard.Flush();
        return copied;
    }, cancellationToken);

    private Task<T> OnUiAsync<T>(Func<T> action, CancellationToken cancellationToken)
    {
        var completion = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        if (cancellationToken.IsCancellationRequested) return Task.FromCanceled<T>(cancellationToken);
        _dispatch(() =>
        {
            if (_disposed || cancellationToken.IsCancellationRequested) { completion.TrySetCanceled(cancellationToken); return; }
            try { completion.TrySetResult(action()); }
            catch (Exception error) { completion.TrySetException(error); }
        });
        return completion.Task.WaitAsync(cancellationToken);
    }

    private sealed record RejectedSnapshot(IReadOnlyList<string> Formats) : IClipboardContentSnapshot
    {
        public bool HasText => false;
        public Task<string?> ReadTextAsync(CancellationToken cancellationToken) => throw new InvalidOperationException("Protected clipboard content must not be read.");
    }

    private sealed class NativeSnapshot(DataPackageView content, IReadOnlyList<string> formats, uint sequence, WindowsClipboardSource owner) : IClipboardContentSnapshot
    {
        public IReadOnlyList<string> Formats => formats;
        public bool HasText => formats.Contains(StandardDataFormats.Text, StringComparer.OrdinalIgnoreCase);
        public async Task<string?> ReadTextAsync(CancellationToken cancellationToken)
        {
            if (ClipboardPrivacyFilter.HasExcludedFormat(formats) || GetClipboardSequenceNumber() != sequence) return null;
            var operation = await owner.OnUiAsync(() => content.GetTextAsync(), cancellationToken);
            string text = await operation.AsTask(cancellationToken);
            return GetClipboardSequenceNumber() == sequence ? text : null;
        }
    }

    public void Dispose()
    {
        _disposed = true;
        _changed = null;
        _dispatch(() =>
        {
            if (_subscribed) Clipboard.ContentChanged -= OnNativeChanged;
            _subscribed = false;
        });
    }

    [DllImport("user32.dll")] private static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "RegisterClipboardFormatW")] private static extern uint RegisterClipboardFormat(string format);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool IsClipboardFormatAvailable(uint format);
}
