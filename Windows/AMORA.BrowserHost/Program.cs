using System.IO.Pipes;
using AMORA.Orbit.Services.BrowserBridge;

// Chrome/Edge supply the calling extension's origin. Refuse any unpinned caller.
if (args.Length == 0 || !string.Equals(args[0], BrowserWireProtocol.ExtensionOrigin, StringComparison.Ordinal)) return 2;
using var stop = new CancellationTokenSource();
using var pipe = new NamedPipeClientStream(".", BrowserWireProtocol.CurrentUserPipeName, PipeDirection.InOut,
    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
using var stdoutGate = new SemaphoreSlim(1, 1);
try
{
    await pipe.ConnectAsync(5000, stop.Token);
    var input = Console.OpenStandardInput();
    var output = Console.OpenStandardOutput();
    async Task ToBrowser(string message)
    {
        await stdoutGate.WaitAsync(stop.Token);
        try { await BrowserWireProtocol.WriteAsync(output, message, stop.Token); }
        finally { stdoutGate.Release(); }
    }
    async Task ReadBrowser()
    {
        while (await BrowserWireProtocol.ReadAsync(input, stop.Token) is { } message)
        {
            var normalized = BrowserWireProtocol.NormalizeBrowserMessage(message);
            if (normalized == null) { await ToBrowser("{\"type\":\"error\",\"error\":\"invalid_message\"}"); continue; }
            using var doc = BrowserWireProtocol.Parse(normalized);
            var type = BrowserWireProtocol.Text(doc.RootElement, "type");
            if (type == "hello") await ToBrowser("{\"type\":\"hello\",\"app\":\"AMORA\",\"version\":\"windows-1\"}");
            else if (type == "ping") await ToBrowser("{\"type\":\"pong\"}");
            await BrowserWireProtocol.WriteAsync(pipe, normalized, stop.Token);
        }
    }
    async Task ReadApp()
    {
        while (await BrowserWireProtocol.ReadAsync(pipe, stop.Token) is { } message)
        {
            var normalized = BrowserWireProtocol.NormalizeAppCommand(message);
            if (normalized != null) await ToBrowser(normalized);
        }
    }
    var browser = ReadBrowser();
    var app = ReadApp();
    var completed = await Task.WhenAny(browser, app);
    await completed;
    stop.Cancel();
    return 0;
}
catch (Exception ex) when (ex is IOException or TimeoutException or OperationCanceledException or UnauthorizedAccessException or System.Text.DecoderFallbackException)
{
    // No payloads, page URLs, track titles or private exception messages are logged.
    Console.Error.WriteLine("AMORA browser bridge disconnected or unavailable.");
    stop.Cancel();
    return 1;
}
