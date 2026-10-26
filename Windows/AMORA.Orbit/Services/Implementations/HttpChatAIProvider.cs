using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>
/// Bounded text adapters for the actual Mac cloud protocols. Provider output
/// remains untrusted text for AssistantEngine's existing command allowlist.
/// </summary>
public abstract class HttpChatAIProvider : IAIProvider, IDisposable
{
    private readonly Func<Task<string?>> _apiKeyProvider;
    private readonly Func<AISettings> _settingsProvider;
    private readonly HttpClient _client;
    private readonly bool _ownsClient;
    private const int MaximumResponseBytes = 1_048_576;
    protected const string SystemInstruction = GeminiAIProvider.SystemPrompt +
        " Never claim an action succeeded before AMORA executes it. Never propose shell commands, " +
        "memory changes, or automation creation/enabling. Memory stays on the device.";

    protected HttpChatAIProvider(Func<Task<string?>> apiKeyProvider, Func<AISettings> settingsProvider, HttpClient? httpClient)
    {
        _apiKeyProvider = apiKeyProvider ?? throw new ArgumentNullException(nameof(apiKeyProvider));
        _settingsProvider = settingsProvider ?? throw new ArgumentNullException(nameof(settingsProvider));
        _ownsClient = httpClient == null;
        _client = httpClient ?? new HttpClient(new HttpClientHandler { AllowAutoRedirect = false })
        { Timeout = TimeSpan.FromSeconds(25) };
    }

    public abstract string ProviderId { get; }
    public abstract string DisplayName { get; }
    protected abstract string Endpoint { get; }
    protected abstract bool IsAnthropic { get; }

    public bool IsConfigured
    {
        get
        {
            try { return !string.IsNullOrWhiteSpace(_apiKeyProvider().GetAwaiter().GetResult()) && ValidModel(_settingsProvider().Model); }
            catch { return false; }
        }
    }

    public Task<string> GenerateResponseAsync(string prompt, CancellationToken cancellationToken = default) =>
        GenerateResponseAsync(prompt, null, cancellationToken);

    public Task<string> GenerateResponseAsync(string prompt, IReadOnlyList<ChatMessage>? history, CancellationToken cancellationToken = default) =>
        SendAsync(prompt, history, testConnection: false, cancellationToken);

    private async Task<string> SendAsync(string prompt, IReadOnlyList<ChatMessage>? history, bool testConnection, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (string.IsNullOrWhiteSpace(prompt)) throw new InvalidOperationException("Enter a question first.");
        if (prompt.Length > 32_000) throw new InvalidOperationException("That question is too long. Shorten it and try again.");
        EnsureCloudPrompt(prompt);
        AISettings settings = _settingsProvider();
        if (!ValidModel(settings.Model)) throw new InvalidOperationException($"Enter a model ID available to your {DisplayName} account in Settings.");
        if (!string.IsNullOrWhiteSpace(settings.CustomEndpoint))
            throw new InvalidOperationException($"Custom endpoints are not supported for {DisplayName}; credentials stay on its official API endpoint.");
        string? key;
        try { key = await _apiKeyProvider().WaitAsync(token); }
        catch (OperationCanceledException) { throw; }
        catch { throw new InvalidOperationException($"The {DisplayName} credential could not be read. Re-enter it in Settings."); }
        if (string.IsNullOrWhiteSpace(key)) throw new InvalidOperationException($"{DisplayName} API key is not configured. Set it in Settings.");
        key = key.Trim();
        if (key.Length > 4096 || key.Any(c => c > 127 || char.IsControl(c) || char.IsWhiteSpace(c)))
            throw new InvalidOperationException("The API key contains invalid characters. Re-enter it in Settings.");
        var messages = BuildMessages(prompt, testConnection ? null : history, settings.MaxHistoryTurns);
        int tokenLimit = testConnection ? 64 : Math.Clamp(settings.MaxOutputTokens, 64, 8192);
        object payload;
        if (IsAnthropic)
        {
            payload = new { model = settings.Model.Trim(), max_tokens = tokenLimit, system = SystemInstruction, messages };
        }
        else
        {
            messages.Insert(0, new OutboundMessage("system", SystemInstruction));
            payload = new { model = settings.Model.Trim(), max_completion_tokens = tokenLimit, store = false, messages };
        }
        using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint);
        if (IsAnthropic)
        {
            request.Headers.Add("x-api-key", key);
            request.Headers.Add("anthropic-version", "2023-06-01"); // Same protocol version as the Mac source.
        }
        else request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
        request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(testConnection ? 10 : 25));
        try
        {
            using var response = await _client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (!response.IsSuccessStatusCode) throw SafeHttpFailure(response.StatusCode);
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var content = new MemoryStream();
            byte[] buffer = new byte[8192];
            int read;
            while ((read = await stream.ReadAsync(buffer, deadline.Token)) != 0)
            {
                if (content.Length + read > MaximumResponseBytes) throw new FormatException($"{DisplayName} returned an oversized response.");
                content.Write(buffer, 0, read);
            }
            return ParseResponse(content.ToArray());
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested)
        { throw new TimeoutException($"{DisplayName} request timed out. Try again."); }
        catch (OperationCanceledException) { throw; }
        catch (HttpRequestException ex)
        {
            // Never echo an exception or provider response body: either can
            // contain credentials or submitted user content.
            if (ex.StatusCode is { } status) throw SafeHttpFailure(status);
            throw new HttpRequestException($"Could not connect to {DisplayName}. Check the network and try again.");
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException or KeyNotFoundException)
        { throw new FormatException($"{DisplayName} returned an invalid response."); }
        catch (FormatException) { throw; }
        catch { throw new HttpRequestException($"The {DisplayName} request failed. Try again."); }
    }

    private sealed record OutboundMessage(string role, string content);

    private static List<OutboundMessage> BuildMessages(string prompt, IReadOnlyList<ChatMessage>? history, int maxTurns)
    {
        var messages = FilterHistory(history, maxTurns)
            .Select(message => new OutboundMessage(message.Role == ChatRole.User ? "user" : "assistant", message.Content.Trim())).ToList();
        messages.Add(new OutboundMessage("user", prompt.Trim()));
        return messages;
    }

    internal static void EnsureCloudPrompt(string prompt)
    {
        if (prompt.Contains("[Relevant user memories]", StringComparison.OrdinalIgnoreCase) || MemoryCommandParser.Parse(prompt) != null)
            throw new InvalidOperationException("Memory requests are handled locally and are never sent to cloud providers.");
    }

    internal static IReadOnlyList<ChatMessage> FilterHistory(IReadOnlyList<ChatMessage>? history, int maxTurns)
    {
        var messages = new List<ChatMessage>();
        bool omitReply = false;
        foreach (var message in (history ?? Array.Empty<ChatMessage>()).TakeLast(Math.Clamp(maxTurns, 0, 20) * 2))
        {
            if (message.Role == ChatRole.User)
                omitReply = message.IsMemoryDerived || message.Content.Contains("[Relevant user memories]", StringComparison.OrdinalIgnoreCase) ||
                    MemoryCommandParser.Parse(message.Content) != null;
            if (omitReply || message.IsMemoryDerived || string.IsNullOrWhiteSpace(message.Content) ||
                message.Content.Contains("[Relevant user memories]", StringComparison.OrdinalIgnoreCase) || message.Content.Length > 32_000) continue;
            if (messages.Count == 0 && message.Role != ChatRole.User) continue;
            messages.Add(message);
        }
        return messages;
    }

    private string ParseResponse(byte[] json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        string text;
        if (IsAnthropic)
        {
            text = string.Join(Environment.NewLine, root.GetProperty("content").EnumerateArray()
                .Where(block => block.TryGetProperty("type", out var type) && type.GetString() == "text")
                .Select(block => block.GetProperty("text").GetString()));
        }
        else
        {
            var choices = root.GetProperty("choices");
            if (choices.GetArrayLength() == 0) throw new FormatException("OpenAI returned no completion.");
            var message = choices[0].GetProperty("message");
            text = message.TryGetProperty("content", out var responseText) && responseText.ValueKind == JsonValueKind.String ? responseText.GetString()! : "";
            if (string.IsNullOrWhiteSpace(text) && message.TryGetProperty("refusal", out var refusal) && refusal.ValueKind == JsonValueKind.String)
                text = refusal.GetString()!;
        }
        if (string.IsNullOrWhiteSpace(text)) throw new FormatException($"{DisplayName} returned no text response.");
        return text.Trim();
    }

    private static bool ValidModel(string? model) => !string.IsNullOrWhiteSpace(model) && model != "default" &&
        model.Length <= 128 && !model.Any(char.IsWhiteSpace) && !model.Any(char.IsControl);

    private HttpRequestException SafeHttpFailure(HttpStatusCode status)
    {
        string reason = status switch
        {
            HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden => "Authentication failed. Check the saved API key and account access.",
            HttpStatusCode.TooManyRequests => "Rate limit or quota reached. Wait before trying again.",
            HttpStatusCode.NotFound => "The configured model is unavailable to this account. Check its model ID.",
            HttpStatusCode.BadRequest => "The configured model rejected the request. Check the model ID and supported settings.",
            _ => "The provider is unavailable or rejected the request. Try again later."
        };
        return new HttpRequestException($"{DisplayName} HTTP {(int)status}: {reason}", null, status);
    }

    public async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken cancellationToken = default)
    {
        var stopwatch = Stopwatch.StartNew();
        try
        {
            _ = await SendAsync("Reply with OK.", null, testConnection: true, cancellationToken);
            return ConnectionTestResult.Success($"Connected to {DisplayName} in {stopwatch.ElapsedMilliseconds}ms.", stopwatch.Elapsed);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException or TimeoutException or FormatException)
        { return ConnectionTestResult.Failure(ex.Message); }
        catch { return ConnectionTestResult.Failure($"Connection to {DisplayName} failed."); }
    }

    public void Dispose() { if (_ownsClient) _client.Dispose(); }
}

public sealed class OpenAIChatProvider(Func<Task<string?>> apiKeyProvider, Func<AISettings> settingsProvider, HttpClient? httpClient = null)
    : HttpChatAIProvider(apiKeyProvider, settingsProvider, httpClient)
{
    public override string ProviderId => AISettings.ProviderOpenAI;
    public override string DisplayName => "OpenAI";
    protected override string Endpoint => "https://api.openai.com/v1/chat/completions";
    protected override bool IsAnthropic => false;
}

public sealed class AnthropicMessagesProvider(Func<Task<string?>> apiKeyProvider, Func<AISettings> settingsProvider, HttpClient? httpClient = null)
    : HttpChatAIProvider(apiKeyProvider, settingsProvider, httpClient)
{
    public override string ProviderId => AISettings.ProviderAnthropic;
    public override string DisplayName => "Anthropic Claude";
    protected override string Endpoint => "https://api.anthropic.com/v1/messages";
    protected override bool IsAnthropic => true;
}
