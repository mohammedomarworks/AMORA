using System;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class GeminiAIProviderTests
{
    private const string TestApiKey = "AIzaSy_SuperSecretTestKey_12345";

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

            string responseJson = @"{
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
                Content = new StringContent(@"{""candidates"":[{""content"":{""parts"":[{""text"":""ok""}]}}}]")
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
}
