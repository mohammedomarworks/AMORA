namespace AMORA.Orbit.Services.BrowserBridge;

public interface IBrowserBridgeTransport : IDisposable
{
    event EventHandler<string>? MessageReceived;
    event EventHandler<bool>? ConnectionChanged;
    void SetEnabled(bool enabled);
    Task SendAsync(string message, CancellationToken token);
}
