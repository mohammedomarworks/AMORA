using System.ComponentModel;
using AMORA.Orbit.Services.BrowserBridge;
using AMORA.Orbit.Services.Implementations;

namespace AMORA.Orbit.ViewModels;

public sealed class BrowserBridgeViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly BrowserMediaBridgeService _bridge;
    private readonly IBrowserHostRegistration _registration;
    private readonly Action<Action> _dispatch;
    private bool _disposed, _busy, _registered;
    private string _registrationStatus = "Host registration is optional and applies only to your Windows account.";
    public BrowserBridgeViewModel(BrowserMediaBridgeService bridge, Action<Action>? dispatch = null, IBrowserHostRegistration? registration = null)
    {
        _bridge = bridge; _dispatch = dispatch ?? (action => action());
        _registration = registration ?? new BrowserHostRegistration();
        _bridge.ConnectionChanged += OnConnection;
        Refresh();
    }
    public bool Enabled => _bridge.IsEnabled;
    public string ConnectionStatus => _bridge.StatusText.Length == 0 ? "Connected to a YouTube video." : _bridge.StatusText;
    public bool IsConnected => _bridge.IsConnected;
    public bool IsHostRegistered => _registered;
    public bool IsBusy => _busy;
    public bool CanRegister => !_busy;
    public string RegistrationStatus => _registrationStatus;
    public string ExtensionFolder => Path.Combine(AppContext.BaseDirectory, "browser-extension");
    public event PropertyChangedEventHandler? PropertyChanged;

    // The caller persists the explicit preference; this method never enables it
    // as a side effect of registration or a connection attempt.
    public void SetEnabled(bool enabled) { _bridge.SetEnabled(enabled); Notify(); }
    public void Refresh()
    {
        if (_disposed) return;
        _registered = _registration.IsRegistered;
        Notify();
    }
    public Task RegisterNativeHostAsync() => RunAsync(async () =>
    {
        await _registration.RegisterAsync();
        return "Host registered for Chrome and Edge. Load the bundled browser-extension folder, then reload the browser. Browser media stays off until you enable it.";
    });
    public Task UnregisterNativeHostAsync() => RunAsync(async () =>
    {
        await _registration.UnregisterAsync();
        return "Host registration removed. Installed host files are retained while the browser may be using them.";
    });
    private async Task RunAsync(Func<Task<string>> action)
    {
        if (_disposed || _busy) return;
        _busy = true; Notify();
        string message;
        try { message = await action(); }
        catch (InvalidOperationException) { message = "The browser host bundle is missing or invalid. Use the complete extracted AMORA release."; }
        catch { message = "Browser host registration failed. Check that your Windows account can write its local application data and registry."; }
        _dispatch(() =>
        {
            if (_disposed) return;
            _busy = false; _registrationStatus = message; _registered = _registration.IsRegistered; Notify();
        });
    }
    private void OnConnection(object? sender, EventArgs e) => _dispatch(Notify);
    private void Notify()
    {
        if (_disposed) return;
        foreach (var property in new[] { nameof(Enabled), nameof(ConnectionStatus), nameof(IsConnected), nameof(IsHostRegistered), nameof(IsBusy), nameof(CanRegister), nameof(RegistrationStatus) })
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));
    }
    public void Dispose() { if (_disposed) return; _disposed = true; _bridge.ConnectionChanged -= OnConnection; }
}
