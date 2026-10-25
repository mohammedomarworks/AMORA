using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class GeminiAIProviderTests
{
    private const string TestApiKey = "AIzaSy_SuperSecretTestKey_12345";
    private const string SuccessfulResponseJson = @"
        {
            ""candidates"": [
                {
                    ""content"": {
                        ""parts"": [
                            { ""text"": ""Hello! AMORA is standing by to help you on Windows."" }
                        ],
                        ""role"": ""model""
                    },
                    ""finishReason"": ""STOP""
                }
            ]
        }";

    private class MockHttpMessageHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> _handler;

        public MockHttpMessageHandler(Func<HttpRequestMessage, HttpResponseMessage> handler)
        {
            _handler = (req, ct) => Task.FromResult(handler(req));
        }

        public MockHttpMessageHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> handler)
        {
            _handler = handler;
        }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            return _handler(request, cancellationToken);
        }
    }

    [Fact]
    public async Task GenerateResponseAsync_SuccessfulContent_ReturnsCleanText()
    {
        string? capturedKeyHeader = null;

        var handler = new MockHttpMessageHandler(req =>
        {
            if (req.Headers.TryGetValues("x-goog-api-key", out var values))
            {
                capturedKeyHeader = string.Join(",", values);
            }

            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(SuccessfulResponseJson)
            };
        });

        using var client = new HttpClient(handler);
        var provider = new GeminiAIProvider(
            () => Task.FromResult<string?>(TestApiKey),
            AISettings.Default,
            client
        );

        var result = await provider.GenerateResponseAsync("Hello");

        Assert.Equal("Hello! AMORA is standing by to help you on Windows.", result);
        Assert.Equal(TestApiKey, capturedKeyHeader);
    }

    [Fact]
    public async Task GenerateResponseAsync_UnconfiguredKey_ThrowsInvalidOperationException()
    {
        var provider = new GeminiAIProvider(
            () => Task.FromResult<string?>(null),
            AISettings.Default
        );

        Assert.False(provider.IsConfigured);

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(() =>
            provider.GenerateResponseAsync("Test prompt")
        );

        Assert.Contains("Gemini API key is not configured", ex.Message);
    }

    [Fact]
    public async Task GenerateResponseAsync_AuthFailure_RedactsKeyAndThrows()
    {
        var handler = new MockHttpMessageHandler(req =>
        {
            string errorJson = $@"{{
                ""error"": {{
                    ""code"": 401,
                    ""message"": ""API_KEY_INVALID: key '{TestApiKey}' is not valid"",
                    ""status"": ""UNAUTHENTICATED""
                }}
            }}";

            return new HttpResponseMessage(HttpStatusCode.Unauthorized)
            {
                Content = new StringContent(errorJson)
            };
        });

        using var client = new HttpClient(handler);
        var provider = new GeminiAIProvider(
            () => Task.FromResult<string?>(TestApiKey),
            AISettings.Default,
            client
        );

        var ex = await Assert.ThrowsAsync<HttpRequestException>(() =>
            provider.GenerateResponseAsync("Test")
        );

        // Security check: API key MUST NEVER be leaked in exception messages!
        Assert.DoesNotContain(TestApiKey, ex.Message);
        Assert.Contains("Authentication failed", ex.Message);
        Assert.Contains("[REDACTED_API_KEY]", ex.Message);
    }

    [Fact]
    public async Task GenerateResponseAsync_RateLimit_ThrowsHelpfulMessage()
    {
        var handler = new MockHttpMessageHandler(req =>
        {
            string errorJson = @"{
                ""error"": {
                    ""code"": 429,
                    ""message"": ""Quota exceeded for quota metric 'GenerateContentRequests'"",
                    ""status"": ""RESOURCE_EXHAUSTED""
                }
            }";

            return new HttpResponseMessage(HttpStatusCode.TooManyRequests)
            {
                Content = new StringContent(errorJson)
            };
        });

        using var client = new HttpClient(handler);
        var provider = new GeminiAIProvider(
            () => Task.FromResult<string?>(TestApiKey),
            AISettings.Default,
            client
        );

        var ex = await Assert.ThrowsAsync<HttpRequestException>(() =>
            provider.GenerateResponseAsync("Test")
        );

        Assert.Contains("Rate limit exceeded (HTTP 429)", ex.Message);
    }

    [Fact]
    public async Task GenerateResponseAsync_ServiceUnavailable_Throws()
    {
        var handler = new MockHttpMessageHandler(req =>
            new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)
            {
                Content = new StringContent(@"{ ""error"": { ""message"": ""Overloaded"" } }")
            }
        );

        using var client = new HttpClient(handler);
        var provider = new GeminiAIProvider(
            () => Task.FromResult<string?>(TestApiKey),
            AISettings.Default,
            client
        );

        var ex = await Assert.ThrowsAsync<HttpRequestException>(() =>
            provider.GenerateResponseAsync("Test")
        );

        Assert.Contains("temporarily unavailable", ex.Message);
    }

    [Fact]
    public async Task GenerateResponseAsync_MalformedJson_ThrowsFormatException()
    {
        var handler = new MockHttpMessageHandler(req =>
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("<!DOCTYPE html><html><body>Error</body></html>")
            }
        );

        using var client = new HttpClient(handler);
        var provider = new GeminiAIProvider(
            () => Task.FromResult<string?>(TestApiKey),
            AISettings.Default,
            client
        );

        var ex = await Assert.ThrowsAsync<FormatException>(() =>
            provider.GenerateResponseAsync("Test")
        );

        Assert.Contains("Malformed response received", ex.Message);
    }

    [Fact]
    public async Task GenerateResponseAsync_SafetyBlocked_ReturnsExplainingMessage()
    {
        var handler = new MockHttpMessageHandler(req =>
        {
            string responseJson = @"{
                ""candidates"": [
                    {
                        ""finishReason"": ""SAFETY""
                    }
                ]
            }";

            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(responseJson)
            };
        });

        using var client = new HttpClient(handler);
        var provider = new GeminiAIProvider(
            () => Task.FromResult<string?>(TestApiKey),
            AISettings.Default,
            client
        );

        var result = await provider.GenerateResponseAsync("Harmful prompt");

        Assert.Contains("content safety policies", result);
    }

    [Fact]
    public async Task GenerateResponseAsync_CanceledToken_ThrowsTaskCanceledException()
    {
        var handler = new MockHttpMessageHandler(async (req, ct) =>
        {
            await Task.Delay(500, ct);
            return new HttpResponseMessage(HttpStatusCode.OK);
        });

        using var client = new HttpClient(handler);
        var provider = new GeminiAIProvider(
            () => Task.FromResult<string?>(TestApiKey),
            AISettings.Default,
            client
        );

        using var cts = new CancellationTokenSource();
        cts.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            provider.GenerateResponseAsync("Test", cts.Token)
        );
    }

    [Fact]
    public async Task TestConnectionAsync_Success_ReturnsSuccessResult()
    {
        var handler = new MockHttpMessageHandler(req =>
        {
            string responseJson = @"{
                ""candidates"": [
                    {
                        ""content"": {
                            ""parts"": [ { ""text"": ""Pong"" } ]
                        }
                    }
                ]
            }";

            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(responseJson)
            };
        });

        using var client = new HttpClient(handler);
        var provider = new GeminiAIProvider(
            () => Task.FromResult<string?>(TestApiKey),
            AISettings.Default,
            client
        );

        var result = await provider.TestConnectionAsync();

        Assert.True(result.IsSuccessful);
        Assert.Contains("Connected to Gemini", result.Message);
    }

    [Fact]
    public async Task TestConnectionAsync_MissingKey_ReturnsFailure()
    {
        var provider = new GeminiAIProvider(
            () => Task.FromResult<string?>(null),
            AISettings.Default
        );

        var result = await provider.TestConnectionAsync();

        Assert.False(result.IsSuccessful);
        Assert.Contains("API key is missing", result.Message);
    }

    [Theory]
    [InlineData(null, AISettings.DefaultGeminiModel)]
    [InlineData("", AISettings.DefaultGeminiModel)]
    [InlineData("   ", AISettings.DefaultGeminiModel)]
    [InlineData("models/gemini-2.5-flash", "gemini-2.5-flash")]
    [InlineData("MODELS/gemini-1.5-pro", "gemini-1.5-pro")]
    [InlineData("../../etc/passwd", "etcpasswd")]
    [InlineData("models/../gemini-2.5-flash", "gemini-2.5-flash")]
    [InlineData("foo\\..\\gemini-custom_model.v1", "foogemini-custom_model.v1")]
    [InlineData("gemini-custom_model.v1", "gemini-custom_model.v1")]
    public void SanitizeModelName_StripsPrefixAndPathTraversal(string? input, string expected)
    {
        string sanitized = GeminiAIProvider.SanitizeModelName(input);
        Assert.Equal(expected, sanitized);
    }

    [Fact]
    public async Task DynamicSettings_UpdatesEndpointWithoutRestart()
    {
        string? capturedUri = null;
        var currentSettings = new AISettings(Model: "gemini-2.5-flash");

        var handler = new MockHttpMessageHandler(req =>
        {
            capturedUri = req.RequestUri?.ToString();
            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(SuccessfulResponseJson)
            };
        });

        using var client = new HttpClient(handler);
        var provider = new GeminiAIProvider(
            () => Task.FromResult<string?>(TestApiKey),
            () => currentSettings,
            client
        );

        await provider.GenerateResponseAsync("Test 1");
        Assert.Contains("gemini-2.5-flash", capturedUri);

        // Update settings dynamically
        currentSettings = currentSettings with { Model = "gemini-1.5-pro" };

        await provider.GenerateResponseAsync("Test 2");
        Assert.Contains("gemini-1.5-pro", capturedUri);
    }

    [Fact]
    public async Task GenerateResponseAsync_WithHistory_SendsAlternatingUserAndModelContents()
    {
        string? capturedJson = null;

        var handler = new MockHttpMessageHandler(async (req, ct) =>
        {
            if (req.Content != null)
            {
                capturedJson = await req.Content.ReadAsStringAsync(ct);
            }

            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(SuccessfulResponseJson)
            };
        });

        using var client = new HttpClient(handler);
        var provider = new GeminiAIProvider(
            () => Task.FromResult<string?>(TestApiKey),
            AISettings.Default,
            client
        );

        var history = new List<ChatMessage>
        {
            ChatMessage.User("What is the capital of France?"),
            ChatMessage.Model("Paris is the capital of France.")
        };

        var result = await provider.GenerateResponseAsync("What is its population?", history);

        Assert.NotNull(capturedJson);
        using var doc = JsonDocument.Parse(capturedJson!);
        var contents = doc.RootElement.GetProperty("contents");
        Assert.Equal(3, contents.GetArrayLength());

        // Turn 1 User
        Assert.Equal("user", contents[0].GetProperty("role").GetString());
        Assert.Equal("What is the capital of France?", contents[0].GetProperty("parts")[0].GetProperty("text").GetString());

        // Turn 1 Model
        Assert.Equal("model", contents[1].GetProperty("role").GetString());
        Assert.Equal("Paris is the capital of France.", contents[1].GetProperty("parts")[0].GetProperty("text").GetString());

        // Current Turn User
        Assert.Equal("user", contents[2].GetProperty("role").GetString());
        Assert.Equal("What is its population?", contents[2].GetProperty("parts")[0].GetProperty("text").GetString());
    }

    [Fact]
    public async Task GenerateResponseAsync_WithMisalignedHistory_TrimsLeadingModelMessage()
    {
        string? capturedJson = null;

        var handler = new MockHttpMessageHandler(async (req, ct) =>
        {
            if (req.Content != null)
            {
                capturedJson = await req.Content.ReadAsStringAsync(ct);
            }

            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(SuccessfulResponseJson)
            };
        });

        using var client = new HttpClient(handler);
        var provider = new GeminiAIProvider(
            () => Task.FromResult<string?>(TestApiKey),
            AISettings.Default,
            client
        );

        // Misaligned: starts with a Model message
        var history = new List<ChatMessage>
        {
            ChatMessage.Model("An orphaned model response."),
            ChatMessage.User("Hello again"),
            ChatMessage.Model("Welcome back!")
        };

        await provider.GenerateResponseAsync("How are you?", history);

        Assert.NotNull(capturedJson);
        using var doc = JsonDocument.Parse(capturedJson!);
        var contents = doc.RootElement.GetProperty("contents");

        // The orphaned leading model message must be skipped; first message must be user!
        Assert.Equal(3, contents.GetArrayLength());
        Assert.Equal("user", contents[0].GetProperty("role").GetString());
        Assert.Equal("Hello again", contents[0].GetProperty("parts")[0].GetProperty("text").GetString());
        Assert.Equal("model", contents[1].GetProperty("role").GetString());
        Assert.Equal("user", contents[2].GetProperty("role").GetString());
    }

    [Fact]
    public async Task GenerateResponseAsync_WithNullHistory_SendsSingleUserContent()
    {
        string? capturedJson = null;

        var handler = new MockHttpMessageHandler(async (req, ct) =>
        {
            if (req.Content != null)
            {
                capturedJson = await req.Content.ReadAsStringAsync(ct);
            }

            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(SuccessfulResponseJson)
            };
        });

        using var client = new HttpClient(handler);
        var provider = new GeminiAIProvider(
            () => Task.FromResult<string?>(TestApiKey),
            AISettings.Default,
            client
        );

        await provider.GenerateResponseAsync("Single turn test", history: null);

        Assert.NotNull(capturedJson);
        using var doc = JsonDocument.Parse(capturedJson!);
        var contents = doc.RootElement.GetProperty("contents");
        Assert.Equal(1, contents.GetArrayLength());
        Assert.Equal("user", contents[0].GetProperty("role").GetString());
        Assert.Equal("Single turn test", contents[0].GetProperty("parts")[0].GetProperty("text").GetString());
    }
}
