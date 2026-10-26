using System.IO.Pipes;

namespace AMORA.Orbit.Services.BrowserBridge;

/// <summary>Local-only IPC, restricted by the OS to the current Windows user.</summary>
public sealed class NamedPipeBrowserTransport : IBrowserBridgeTransport
{
    private readonly object _sync = new();
    private readonly SemaphoreSlim _writeGate = new(1, 1);
    private readonly string _pipeName;
    private CancellationTokenSource? _run;
    private NamedPipeServerStream? _pipe;
    private bool _disposed;
    public event EventHandler<string>? MessageReceived;
    public event EventHandler<bool>? ConnectionChanged;
    public NamedPipeBrowserTransport(string? pipeName = null) => _pipeName = pipeName ?? BrowserWireProtocol.CurrentUserPipeName;

    public void SetEnabled(bool enabled)
    {
        lock (_sync)
        {
            if (_disposed || enabled == (_run != null)) return;
            if (!enabled)
            {
                _run?.Cancel(); _run = null;
                _pipe?.Dispose(); _pipe = null;
                return;
            }
            var run = new CancellationTokenSource();
            _run = run;
            _ = Task.Run(() => ListenAsync(run));
        }
    }

    private async Task ListenAsync(CancellationTokenSource run)
    {
        var token = run.Token;
        try
        {
            while (!token.IsCancellationRequested)
            {
                NamedPipeServerStream? server = null;
                try
                {
                    server = new NamedPipeServerStream(_pipeName, PipeDirection.InOut, 1,
                        PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly, 8192, 8192);
                    lock (_sync)
                    {
                        if (_run != run || token.IsCancellationRequested) { server.Dispose(); return; }
                        _pipe = server;
                    }
                    await server.WaitForConnectionAsync(token).ConfigureAwait(false);
                    ConnectionChanged?.Invoke(this, true);
                    while (await BrowserWireProtocol.ReadAsync(server, token).ConfigureAwait(false) is { } message)
                        MessageReceived?.Invoke(this, message);
                }
                catch (Exception ex) when (ex is IOException or OperationCanceledException or ObjectDisposedException or UnauthorizedAccessException or System.Text.DecoderFallbackException) { }
                finally
                {
                    server?.Dispose();
                    bool current;
                    lock (_sync) { current = _run == run; if (ReferenceEquals(_pipe, server)) _pipe = null; }
                    if (current) ConnectionChanged?.Invoke(this, false);
                }
                if (!token.IsCancellationRequested) await Task.Delay(500, token).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        finally { run.Dispose(); }
    }

    public async Task SendAsync(string message, CancellationToken token)
    {
        var normalized = BrowserWireProtocol.NormalizeAppCommand(message) ?? throw new InvalidOperationException("Unsupported browser command.");
        await _writeGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            NamedPipeServerStream? pipe;
            lock (_sync) pipe = _pipe;
            if (pipe?.IsConnected != true) throw new IOException("Browser bridge disconnected.");
            await BrowserWireProtocol.WriteAsync(pipe, normalized, token).ConfigureAwait(false);
        }
        finally { _writeGate.Release(); }
    }

    public void Dispose()
    {
        lock (_sync)
        {
            if (_disposed) return;
            _disposed = true; _run?.Cancel(); _run = null; _pipe?.Dispose(); _pipe = null;
        }
    }
}
