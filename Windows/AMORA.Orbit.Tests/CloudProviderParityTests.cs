using System.Net;
using System.Net.Http;
using System.Text.Json;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public sealed class CloudProviderParityTests
{
    private const string FakeKey = "unit-test-key-not-a-real-credential";
    private const string OpenAiSuccess = """{"choices":[{"message":{"role":"assistant","content":"Hello from AMORA"}}]}""";
    private const string AnthropicSuccess = """{"content":[{"type":"text","text":"Hello from AMORA"}]}""";

    private static HttpChatAIProvider Create(bool anthropic, HttpClient client, AISettings? settings = null, Func<Task<string?>>? key = null) =>
        anthropic ? new AnthropicMessagesProvider(key ?? (() => Task.FromResult<string?>(FakeKey)), () => settings ?? new AISettings(Model: "test-claude-model"), client) :
            new OpenAIChatProvider(key ?? (() => Task.FromResult<string?>(FakeKey)), () => settings ?? new AISettings(Model: "test-openai-model"), client);

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Requests_UseOfficialEndpointCorrectHeadersAndBoundedHistory(bool anthropic)
    {
        var handler = new Handler(async (request, ct) =>
        {
            Assert.Equal(anthropic ? "https://api.anthropic.com/v1/messages" : "https://api.openai.com/v1/chat/completions", request.RequestUri!.AbsoluteUri);
            if (anthropic)
            {
                Assert.Equal(FakeKey, request.Headers.GetValues("x-api-key").Single());
                Assert.Equal("2023-06-01", request.Headers.GetValues("anthropic-version").Single());
                Assert.Null(request.Headers.Authorization);
            }
            else Assert.Equal("Bearer " + FakeKey, request.Headers.Authorization!.ToString());
            string body = await request.Content!.ReadAsStringAsync(ct);
            Assert.DoesNotContain(FakeKey, body);
            using var json = JsonDocument.Parse(body);
            var root = json.RootElement;
            Assert.Equal(1024, root.GetProperty(anthropic ? "max_tokens" : "max_completion_tokens").GetInt32());
            Assert.False(root.TryGetProperty("temperature", out _));
            if (!anthropic) Assert.False(root.GetProperty("store").GetBoolean());
            var messages = root.GetProperty("messages").EnumerateArray().ToArray();
            var conversation = messages.Where(m => m.GetProperty("role").GetString() != "system").ToArray();
            Assert.Equal(new[] { "user", "assistant", "user" }, conversation.Select(m => m.GetProperty("role").GetString()));
            Assert.Equal("Earlier question", conversation[0].GetProperty("content").GetString());
            Assert.Equal("Follow up", conversation[2].GetProperty("content").GetString());
            return Response(anthropic);
        });
        using var client = new HttpClient(handler);
        using var provider = Create(anthropic, client, new AISettings(Model: "test-model", MaxHistoryTurns: 1));
        var history = new[] { ChatMessage.User("Dropped question"), ChatMessage.Model("Dropped answer"), ChatMessage.User("Earlier question"), ChatMessage.Model("Earlier answer") };
        Assert.Equal("Hello from AMORA", await provider.GenerateResponseAsync("Follow up", history));
        Assert.Equal(1, handler.Calls);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task MemoryProvenanceAndLegacyMemoryTurns_NeverEnterCloudPayload(bool anthropic)
    {
        var handler = new Handler(async (request, ct) =>
        {
            string json = await request.Content!.ReadAsStringAsync(ct);
            Assert.DoesNotContain("LocalPrivateFact", json);
            Assert.DoesNotContain("remember editor", json);
            Assert.DoesNotContain("[Relevant user memories]", json);
            Assert.Contains("Ordinary question", json);
            return Response(anthropic);
        });
        using var client = new HttpClient(handler);
        using var provider = Create(anthropic, client);
        var history = new[]
        {
            new ChatMessage(ChatRole.User, "LocalPrivateFact", IsMemoryDerived: true),
            ChatMessage.Model("LocalPrivateFact acknowledged"),
            ChatMessage.User("remember editor: LocalPrivateFact"),
            ChatMessage.Model("Remembered LocalPrivateFact"),
            ChatMessage.User("[Relevant user memories] LocalPrivateFact"),
            ChatMessage.Model("LocalPrivateFact contextual reply"),
            ChatMessage.User("Ordinary question"), ChatMessage.Model("Ordinary answer")
        };
        await provider.GenerateResponseAsync("Hello", history);
        Assert.Equal(1, handler.Calls);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task DirectMemoryRequest_AndCustomEndpoint_DoNotSendAnything(bool anthropic)
    {
        var handler = new Handler((_, _) => Task.FromResult(Response(anthropic)));
        using var client = new HttpClient(handler);
        using var provider = Create(anthropic, client);
        await Assert.ThrowsAsync<InvalidOperationException>(() => provider.GenerateResponseAsync("remember editor: Vim"));
        using var custom = Create(anthropic, client, new AISettings(Model: "test-model", CustomEndpoint: "https://unapproved.example/api"));
        await Assert.ThrowsAsync<InvalidOperationException>(() => custom.GenerateResponseAsync("Hello"));
        Assert.Equal(0, handler.Calls);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task MissingKeyAndModel_AreUnavailable_WithoutRequests(bool anthropic)
    {
        var handler = new Handler((_, _) => Task.FromResult(Response(anthropic)));
        using var client = new HttpClient(handler);
        using var noKey = Create(anthropic, client, key: () => Task.FromResult<string?>(null));
        Assert.False(noKey.IsConfigured);
        Assert.False((await noKey.TestConnectionAsync()).IsSuccessful);
        using var noModel = Create(anthropic, client, new AISettings(Model: ""));
        Assert.False(noModel.IsConfigured);
        Assert.False((await noModel.TestConnectionAsync()).IsSuccessful);
        Assert.Equal(0, handler.Calls);
    }

    [Theory]
    [InlineData(false, 401)]
    [InlineData(true, 403)]
    [InlineData(false, 429)]
    [InlineData(true, 500)]
    public async Task ErrorResponses_NeverEchoKeysOrPrivateProviderBody(bool anthropic, int status)
    {
        using var client = new HttpClient(new Handler((_, _) => Task.FromResult(new HttpResponseMessage((HttpStatusCode)status)
        { Content = new StringContent($"Error includes {FakeKey} and private-user-prompt") })));
        using var provider = Create(anthropic, client);
        var error = await Assert.ThrowsAsync<HttpRequestException>(() => provider.GenerateResponseAsync("Hello"));
        Assert.DoesNotContain(FakeKey, error.ToString());
        Assert.DoesNotContain("private-user-prompt", error.ToString());
        Assert.Contains(status.ToString(), error.Message);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task NetworkFailures_AreContentFree(bool anthropic)
    {
        using var client = new HttpClient(new Handler((_, _) => throw new HttpRequestException("Bearer " + FakeKey)));
        using var provider = Create(anthropic, client);
        var error = await Assert.ThrowsAsync<HttpRequestException>(() => provider.GenerateResponseAsync("Hello"));
        Assert.DoesNotContain(FakeKey, error.ToString());
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Cancellation_Propagates_AndDoesNotBecomeConnectivitySuccess(bool anthropic)
    {
        using var client = new HttpClient(new Handler(async (_, ct) => { await Task.Delay(30_000, ct); return Response(anthropic); }));
        using var provider = Create(anthropic, client);
        using var cts = new CancellationTokenSource();
        var request = provider.TestConnectionAsync(cts.Token);
        cts.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => request);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task MalformedOrEmptySuccessBody_IsFailure(bool anthropic)
    {
        using var client = new HttpClient(new Handler((_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{}") })));
        using var provider = Create(anthropic, client);
        Assert.False((await provider.TestConnectionAsync()).IsSuccessful);
    }

    [Fact]
    public async Task Routing_UsesSelectedProviderCredential_WithoutFallback()
    {
        var settings = new AISettings(SelectedProvider: AISettings.ProviderOpenAI, Model: "test-model");
        var requestedKeys = new List<string>();
        var hosts = new List<string>();
        using var client = new HttpClient(new Handler((request, _) =>
        {
            hosts.Add(request.RequestUri!.Host);
            return Task.FromResult(Response(request.RequestUri.Host == "api.anthropic.com"));
        }));
        using var provider = new RoutingAIProvider(id => { requestedKeys.Add(id); return Task.FromResult<string?>(FakeKey); }, () => settings, client);
        await provider.GenerateResponseAsync("Hello");
        settings = settings with { SelectedProvider = AISettings.ProviderAnthropic };
        await provider.GenerateResponseAsync("Hello again");
        Assert.Equal(new[] { "openai", "anthropic" }, requestedKeys);
        Assert.Equal(new[] { "api.openai.com", "api.anthropic.com" }, hosts);
        settings = settings with { SelectedProvider = "unsupported-provider" };
        Assert.False(provider.IsConfigured);
        await provider.GenerateResponseAsync("Hello without cloud");
        Assert.Equal(2, hosts.Count);
    }

    private static HttpResponseMessage Response(bool anthropic) => new(HttpStatusCode.OK)
    { Content = new StringContent(anthropic ? AnthropicSuccess : OpenAiSuccess) };

    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        public int Calls { get; private set; }
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        { Calls++; return send(request, cancellationToken); }
    }
}
