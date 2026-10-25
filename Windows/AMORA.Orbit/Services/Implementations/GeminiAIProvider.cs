using System;
using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>
/// Cloud AI completion provider using Google Gemini API via official v1beta REST endpoints.
/// Keys and settings are resolved dynamically on each request (never hardcoded or cached stale).
/// Secrets are automatically redacted from error and diagnostic messages.
/// </summary>
public class GeminiAIProvider : IAIProvider, IDisposable
{
    private const string DefaultBaseUrl = "https://generativelanguage.googleapis.com/v1beta/";
    private const string ApiKeyHeader = "x-goog-api-key";

    public const string SystemPrompt =
        "You are AMORA, a concise and helpful desktop assistant on Windows. " +
        "If the user asks you to perform an action, you can include a command tag at the start of your answer " +
        "in the exact format: [COMMAND: <command>] (e.g. [COMMAND: start 15m timer], [COMMAND: pause music], " +
        "[COMMAND: next track], [COMMAND: battery status], [COMMAND: system status]). " +
        "Otherwise, answer clearly and concisely in 1-2 friendly sentences.";

    private readonly Func<Task<string?>> _apiKeyProvider;
    private readonly Func<AISettings> _settingsProvider;
    private readonly HttpClient _httpClient;
    private readonly bool _ownsHttpClient;

    public string ProviderId => AISettings.ProviderGemini;
    public string DisplayName => "Google Gemini";

    public bool IsConfigured
    {
        get
        {
            try
            {
                var key = _apiKeyProvider().GetAwaiter().GetResult();
                return !string.IsNullOrWhiteSpace(key);
            }
            catch
            {
                return false;
            }
        }
    }

    public GeminiAIProvider(
        Func<Task<string?>> apiKeyProvider,
        Func<AISettings> settingsProvider,
        HttpClient? httpClient = null)
    {
        _apiKeyProvider = apiKeyProvider ?? throw new ArgumentNullException(nameof(apiKeyProvider));
        _settingsProvider = settingsProvider ?? throw new ArgumentNullException(nameof(settingsProvider));

        if (httpClient != null)
        {
            _httpClient = httpClient;
            _ownsHttpClient = false;
        }
        else
        {
            _httpClient = new HttpClient
            {
                Timeout = TimeSpan.FromSeconds(25)
            };
            _ownsHttpClient = true;
        }
    }

    public GeminiAIProvider(
        Func<Task<string?>> apiKeyProvider,
        AISettings? settings = null,
        HttpClient? httpClient = null)
        : this(apiKeyProvider, () => settings ?? AISettings.Default, httpClient)
    {
    }

    public void Dispose()
    {
        if (_ownsHttpClient)
        {
            _httpClient.Dispose();
        }
    }

    public async Task<string> GenerateResponseAsync(string prompt, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(prompt))
        {
            return "Please provide a question or instruction.";
        }

        string? apiKey = await _apiKeyProvider();
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            throw new InvalidOperationException("Gemini API key is not configured. Please set your key in Settings.");
        }

        var currentSettings = _settingsProvider();
        string model = SanitizeModelName(currentSettings.Model);
        string endpoint = BuildEndpointUrl(model, currentSettings.CustomEndpoint);

        var requestBody = new
        {
            contents = new[]
            {
                new
                {
                    parts = new[]
                    {
                        new { text = prompt.Trim() }
                    }
                }
            },
            systemInstruction = new
            {
                parts = new[]
                {
                    new { text = SystemPrompt }
                }
            },
            generationConfig = new
            {
                temperature = currentSettings.Temperature,
                maxOutputTokens = currentSettings.MaxOutputTokens
            }
        };

        string jsonPayload = JsonSerializer.Serialize(requestBody);

        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
        request.Headers.Add(ApiKeyHeader, apiKey.Trim());
        request.Content = new StringContent(jsonPayload, Encoding.UTF8, "application/json");

        HttpResponseMessage response;
        try
        {
            response = await _httpClient.SendAsync(request, cancellationToken);
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new TimeoutException("Gemini API request timed out after 25 seconds.");
        }
        catch (HttpRequestException ex)
        {
            string safeMsg = WindowsCredentialStorage.RedactSecret(ex.Message, apiKey);
            throw new HttpRequestException($"Network error connecting to Gemini API: {safeMsg}", ex);
        }

        string responseContent = await response.Content.ReadAsStringAsync(cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            HandleErrorResponse(response.StatusCode, responseContent, apiKey);
        }

        return ParseResponseContent(responseContent);
    }

    public async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken cancellationToken = default)
    {
        string? apiKey = await _apiKeyProvider();
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            return ConnectionTestResult.Failure("API key is missing. Please enter your Gemini API key.");
        }

        var currentSettings = _settingsProvider();
        string model = SanitizeModelName(currentSettings.Model);
        string endpoint = BuildEndpointUrl(model, currentSettings.CustomEndpoint);

        var testBody = new
        {
            contents = new[]
            {
                new
                {
                    parts = new[]
                    {
                        new { text = "Ping" }
                    }
                }
            },
            generationConfig = new
            {
                maxOutputTokens = 5
            }
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
        request.Headers.Add(ApiKeyHeader, apiKey.Trim());
        request.Content = new StringContent(JsonSerializer.Serialize(testBody), Encoding.UTF8, "application/json");

        var sw = Stopwatch.StartNew();
        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(TimeSpan.FromSeconds(10));

            var response = await _httpClient.SendAsync(request, cts.Token);
            sw.Stop();

            if (response.IsSuccessStatusCode)
            {
                return ConnectionTestResult.Success($"Connected to Gemini ({model}) in {sw.ElapsedMilliseconds}ms.", sw.Elapsed);
            }

            string errorJson = await response.Content.ReadAsStringAsync(cancellationToken);
            string safeError = ExtractSafeErrorMessage(response.StatusCode, errorJson, apiKey);
            return ConnectionTestResult.Failure(safeError);
        }
        catch (TaskCanceledException)
        {
            return ConnectionTestResult.Failure("Connection test timed out after 10 seconds.");
        }
        catch (Exception ex)
        {
            string safeMsg = WindowsCredentialStorage.RedactSecret(ex.Message, apiKey);
            return ConnectionTestResult.Failure($"Connection failed: {safeMsg}");
        }
    }

    public static string SanitizeModelName(string? rawModel)
    {
        if (string.IsNullOrWhiteSpace(rawModel))
        {
            return AISettings.DefaultGeminiModel;
        }

        string model = rawModel.Trim();
        if (model.StartsWith("models/", StringComparison.OrdinalIgnoreCase))
        {
            model = model.Substring("models/".Length);
        }

        model = Regex.Replace(model, @"[^a-zA-Z0-9_\-\.]", "");
        return string.IsNullOrWhiteSpace(model) ? AISettings.DefaultGeminiModel : model;
    }

    private static string BuildEndpointUrl(string model, string? customEndpoint)
    {
        string baseUri = !string.IsNullOrWhiteSpace(customEndpoint)
            ? customEndpoint
            : DefaultBaseUrl;

        if (!baseUri.EndsWith('/'))
        {
            baseUri += "/";
        }

        return $"{baseUri}models/{model}:generateContent";
    }

    private static string ParseResponseContent(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            if (root.TryGetProperty("candidates", out var candidates) && candidates.GetArrayLength() > 0)
            {
                var firstCandidate = candidates[0];

                if (firstCandidate.TryGetProperty("content", out var content) &&
                    content.TryGetProperty("parts", out var parts) &&
                    parts.GetArrayLength() > 0)
                {
                    var firstPart = parts[0];
                    if (firstPart.TryGetProperty("text", out var textProp))
                    {
                        string text = textProp.GetString() ?? string.Empty;
                        return text.Trim();
                    }
                }

                if (firstCandidate.TryGetProperty("finishReason", out var finishReason))
                {
                    string reason = finishReason.GetString() ?? string.Empty;
                    if (reason is "SAFETY" or "BLOCKLIST" or "PROHIBITED_CONTENT")
                    {
                        return "I cannot provide a response for that request due to content safety policies.";
                    }
                }
            }
        }
        catch (Exception ex)
        {
            throw new FormatException($"Malformed response received from Gemini API: {ex.Message}", ex);
        }

        return "Gemini returned an empty response.";
    }

    private static void HandleErrorResponse(HttpStatusCode statusCode, string responseContent, string? apiKey)
    {
        string safeMessage = ExtractSafeErrorMessage(statusCode, responseContent, apiKey);

        throw statusCode switch
        {
            HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden =>
                new HttpRequestException($"Authentication failed ({statusCode}): {safeMessage}"),

            HttpStatusCode.TooManyRequests =>
                new HttpRequestException($"Rate limit exceeded (HTTP 429): {safeMessage}"),

            HttpStatusCode.InternalServerError or HttpStatusCode.ServiceUnavailable =>
                new HttpRequestException($"Gemini service temporarily unavailable (HTTP {(int)statusCode}): {safeMessage}"),

            _ => new HttpRequestException($"Gemini API error ({statusCode}): {safeMessage}")
        };
    }

    private static string ExtractSafeErrorMessage(HttpStatusCode statusCode, string responseContent, string? apiKey)
    {
        try
        {
            if (!string.IsNullOrWhiteSpace(responseContent))
            {
                using var doc = JsonDocument.Parse(responseContent);
                if (doc.RootElement.TryGetProperty("error", out var errorObj))
                {
                    if (errorObj.TryGetProperty("message", out var msgProp))
                    {
                        string rawMessage = msgProp.GetString() ?? string.Empty;
                        return WindowsCredentialStorage.RedactSecret(rawMessage, apiKey);
                    }
                }
            }
        }
        catch
        {
        }

        return statusCode switch
        {
            HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden =>
                "Invalid API key. Please check your Gemini API key in Settings.",
            HttpStatusCode.TooManyRequests =>
                "Resource quota exhausted. Please wait a moment before trying again.",
            _ => $"HTTP {(int)statusCode} error"
        };
    }
}
