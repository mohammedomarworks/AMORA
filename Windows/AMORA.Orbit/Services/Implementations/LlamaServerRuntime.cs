using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public sealed class LlamaServerRuntime : ILocalBrainRuntime
{
    private readonly object _gate = new();
    private Process? _process;
    private LocalBrainProcessJob? _job;
    private HttpClient? _client;
    private string? _modelId;
    private bool _disposed;
    public bool IsRunning { get { lock (_gate) return _process is { HasExited: false }; } }
    public string? LoadedModelId { get { lock (_gate) return _modelId; } }
    public event EventHandler? UnexpectedlyExited;

    public static ProcessStartInfo BuildStartInfo(string executable, string modelFile, LocalBrainModelDescriptor model, int port, string sessionKey)
    {
        if (port is < 1024 or > 65535 || sessionKey.Length < 32) throw new ArgumentException("Invalid private runtime session.");
        var start = new ProcessStartInfo(Path.GetFullPath(executable))
        {
            UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden,
            WorkingDirectory = Path.GetDirectoryName(Path.GetFullPath(executable))!,
            RedirectStandardError = true, RedirectStandardOutput = true
        };
        // Ambient llama/agent/MCP/network options must not turn on tools or change the bind address.
        foreach (var key in start.Environment.Keys.Where(k => k.StartsWith("LLAMA", StringComparison.OrdinalIgnoreCase)
            || k is "HF_TOKEN" or "HUGGING_FACE_HUB_TOKEN" or "HTTP_PROXY" or "HTTPS_PROXY" or "ALL_PROXY").ToArray())
            start.Environment.Remove(key);
        start.Environment["LLAMA_API_KEY"] = sessionKey;
        string[] args = ["--model", Path.GetFullPath(modelFile), "--host", "127.0.0.1", "--port", port.ToString(),
            "--ctx-size", model.ContextLength.ToString(), "--parallel", "1", "--n-gpu-layers", "0",
            "--threads", Math.Clamp(Environment.ProcessorCount / 2, 1, 8).ToString(), "--predict", "256",
            "--no-webui", "--no-agent", "--no-webui-mcp-proxy", "--no-slots", "--offline", "--no-context-shift",
            "--cache-ram", "0", "--no-jinja", "--log-disable", "--cors-origins", "http://127.0.0.1"];
        foreach (var argument in args) start.ArgumentList.Add(argument);
        return start;
    }

    public async Task StartAsync(string executable, string modelFile, LocalBrainModelDescriptor model, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (_process is { HasExited: false } && _modelId == model.Id) return;
        }
        Stop();
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
        string key = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
        var process = new Process { StartInfo = BuildStartInfo(executable, modelFile, model, port, key), EnableRaisingEvents = true };
        process.Exited += (_, _) =>
        {
            lock (_gate) { if (_disposed || !ReferenceEquals(_process, process)) return; }
            UnexpectedlyExited?.Invoke(this, EventArgs.Empty);
        };
        var client = new HttpClient(new SocketsHttpHandler { UseProxy = false, AllowAutoRedirect = false })
        { BaseAddress = new Uri($"http://127.0.0.1:{port}/"), Timeout = Timeout.InfiniteTimeSpan };
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", key);
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            lock (_gate)
            {
                ObjectDisposedException.ThrowIf(_disposed, this);
                if (!process.Start()) throw new LocalBrainException("The local inference process did not start.");
                _process = process;
                _client = client;
                _job = new LocalBrainProcessJob(process);
                _modelId = model.Id;
                // Discard runtime diagnostics. Prompt text and ephemeral authentication must never be logged.
                process.OutputDataReceived += (_, _) => { };
                process.ErrorDataReceived += (_, _) => { };
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
            }
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            deadline.CancelAfter(TimeSpan.FromSeconds(90));
            while (true)
            {
                deadline.Token.ThrowIfCancellationRequested();
                if (process.HasExited) throw new LocalBrainException("The local inference runtime exited while loading. Check memory availability or reinstall the verified runtime.");
                try
                {
                    using var healthTimeout = CancellationTokenSource.CreateLinkedTokenSource(deadline.Token);
                    healthTimeout.CancelAfter(TimeSpan.FromSeconds(2));
                    using var response = await client.GetAsync("health", HttpCompletionOption.ResponseHeadersRead, healthTimeout.Token);
                    if (response.IsSuccessStatusCode)
                    {
                        using var json = JsonDocument.Parse(await ReadBoundedAsync(response, 16 * 1024, healthTimeout.Token));
                        if (json.RootElement.TryGetProperty("status", out var state) && state.GetString() == "ok") return;
                    }
                }
                catch (HttpRequestException) { }
                catch (OperationCanceledException) when (!deadline.IsCancellationRequested) { }
                await Task.Delay(150, deadline.Token);
            }
        }
        catch
        {
            Stop();
            client.Dispose();
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch { }
            process.Dispose();
            throw;
        }
    }

    public async Task<string> GenerateAsync(string formattedPrompt, int contextLength, CancellationToken cancellationToken)
    {
        HttpClient client;
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (_process is not { HasExited: false } || _client == null) throw new LocalBrainException("Local Brain is not running.");
            client = _client;
        }
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(TimeSpan.FromSeconds(90));
        try
        {
            using (var tokens = await PostAsync(client, "tokenize", new { content = formattedPrompt, add_special = true }, deadline.Token))
            {
                if (!tokens.RootElement.TryGetProperty("tokens", out var array) || array.ValueKind != JsonValueKind.Array)
                    throw new LocalBrainException("The local runtime returned an invalid token count.");
                if (array.GetArrayLength() > contextLength - 272)
                    throw new LocalBrainException("This conversation exceeds the local model's context. Reset the conversation or send a shorter message.");
            }
            using var result = await PostAsync(client, "completion", new
            {
                prompt = formattedPrompt, n_predict = 256, temperature = 0.3, top_p = 0.85, stream = false,
                stop = new[] { "<|im_end|>", "<|endoftext|>" }, cache_prompt = false
            }, deadline.Token);
            if (!result.RootElement.TryGetProperty("content", out var content) || content.ValueKind != JsonValueKind.String)
                throw new LocalBrainException("The local runtime returned an invalid response.");
            string answer = content.GetString() ?? "";
            if (string.IsNullOrWhiteSpace(answer) || answer.Length > 16_000)
                throw new LocalBrainException("The local model returned no usable response. Try a shorter, clearer question.");
            cancellationToken.ThrowIfCancellationRequested();
            return answer.Trim();
        }
        catch (OperationCanceledException)
        {
            // A cancelled HTTP request alone is not proof that native inference stopped.
            Stop();
            if (!cancellationToken.IsCancellationRequested) throw new LocalBrainException("Local generation timed out. The inference process was stopped; try a shorter question.");
            throw;
        }
    }

    private static async Task<JsonDocument> PostAsync(HttpClient client, string endpoint, object body, CancellationToken token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
        { Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json") };
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        if (!response.IsSuccessStatusCode) throw new LocalBrainException("The local inference runtime rejected the request. No cloud service was used.");
        return JsonDocument.Parse(await ReadBoundedAsync(response, 256 * 1024, token));
    }
    private static async Task<byte[]> ReadBoundedAsync(HttpResponseMessage response, int maximum, CancellationToken token)
    {
        await using var input = await response.Content.ReadAsStreamAsync(token);
        using var output = new MemoryStream();
        var buffer = new byte[4096];
        int read;
        while ((read = await input.ReadAsync(buffer, token)) != 0)
        {
            if (output.Length + read > maximum) throw new LocalBrainException("The local runtime response exceeded its size limit.");
            output.Write(buffer, 0, read);
        }
        return output.ToArray();
    }
    public void Stop()
    {
        lock (_gate)
        {
            _client?.Dispose(); _client = null;
            _job?.Dispose(); _job = null;
            if (_process != null)
            {
                var process = _process;
                _process = null; // A deliberate stop is not an unexpected exit notification.
                try { if (!process.HasExited) { process.Kill(entireProcessTree: true); process.WaitForExit(2000); } } catch { }
                process.Dispose();
            }
            _modelId = null;
        }
    }
    public void Dispose() { lock (_gate) _disposed = true; Stop(); }
}
