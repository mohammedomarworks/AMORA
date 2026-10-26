using System.Collections.Concurrent;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using AMORA.Orbit.ViewModels;
using Xunit;

namespace AMORA.Orbit.Tests;

public sealed class GitHubActivityTests
{
    private const string FakeToken = "unit-test-token-not-a-real-credential";
    private const string Profile = """{"login":"octocat","name":"The Octocat","bio":"Companion account","avatar_url":"https://avatars.githubusercontent.com/u/1","public_repos":8,"followers":3,"following":2}""";
    private const string Repos = """[{"id":1,"name":"Hello","full_name":"octocat/Hello","description":"Hello repo","language":"Swift","private":false,"stargazers_count":12,"html_url":"https://github.com/octocat/Hello","updated_at":"2026-10-26T10:00:00Z"}]""";
    private const string Events = """[{"id":"2","type":"PushEvent","repo":{"name":"octocat/Hello"},"payload":{"size":3},"created_at":"2026-10-26T10:00:00Z"}]""";
    private const string Prs = """{"total_count":1,"items":[{"id":3,"number":7,"title":"A real pull request","repository_url":"https://api.github.com/repos/octocat/Hello","html_url":"https://github.com/octocat/Hello/pull/7","created_at":"2026-10-25T10:00:00Z"}]}""";
    private const string Calendar = """{"data":{"viewer":{"contributionsCollection":{"contributionCalendar":{"totalContributions":42,"weeks":[{"contributionDays":[{"contributionCount":10,"date":"2026-10-26","weekday":1,"contributionLevel":"FOURTH_QUARTILE"}]}]}}}}}""";
    private static HttpResponseMessage Json(string value, HttpStatusCode status = HttpStatusCode.OK) => new(status) { Content = new StringContent(value) };
    private static HttpResponseMessage DefaultResponse(HttpRequestMessage request)
    {
        string path = request.RequestUri!.AbsolutePath;
        return Json(path switch
        {
            "/user" or "/users/octocat" => Profile,
            "/user/repos" or "/users/octocat/repos" => Repos,
            "/users/octocat/events" or "/users/octocat/events/public" => Events,
            "/search/issues" => Prs,
            "/graphql" => Calendar,
            _ => throw new InvalidOperationException("Unexpected endpoint")
        });
    }

    [Fact]
    public async Task ConstructionAndInitialization_DoNotMakeNetworkRequests()
    {
        var handler = new Handler((r, _) => Task.FromResult(DefaultResponse(r)));
        using var http = new HttpClient(handler);
        using var vm = new GitHubActivityViewModel(new GitHubActivityService(new Credentials { Token = FakeToken }, http));
        await vm.InitializeAsync();
        Assert.True(vm.HasSavedToken);
        Assert.False(vm.IsConnected);
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task PublicConnect_UsesOnlyPublicReadEndpointsAndNeverInventsContributionCalendar()
    {
        var handler = new Handler((r, _) => Task.FromResult(DefaultResponse(r)));
        using var http = new HttpClient(handler);
        var store = new Credentials();
        using var service = new GitHubActivityService(store, http);
        Assert.True((await service.ConnectAsync("octocat")).Success);
        Assert.Equal(4, handler.Requests.Count);
        Assert.All(handler.Requests, r => { Assert.Equal("GET", r.Method); Assert.Null(r.Authorization); Assert.Equal("api.github.com", r.Host); });
        Assert.Contains(handler.Requests, r => r.Path == "/users/octocat/events/public");
        Assert.DoesNotContain(handler.Requests, r => r.Path == "/graphql");
        Assert.Equal("The Octocat", service.Snapshot.Profile!.Name);
        Assert.Equal("Pushed 3 commits", Assert.Single(service.Snapshot.Activities).Summary);
        Assert.Equal("octocat/Hello", Assert.Single(service.Snapshot.PullRequests).Repository);
        Assert.Null(service.Snapshot.Calendar);
        Assert.Contains(service.Snapshot.Warnings, warning => warning.Contains("not a yearly"));
        Assert.False(service.Snapshot.IsAuthenticated);
        Assert.Null(store.Token);
    }

    [Fact]
    public async Task TokenConnect_UsesMacReadEndpointsAndFixedGraphQlQuery_StoresOnlyAfterVerification()
    {
        var handler = new Handler(async (request, ct) =>
        {
            Assert.Equal("Bearer " + FakeToken, request.Headers.Authorization!.ToString());
            Assert.Equal("2022-11-28", request.Headers.GetValues("X-GitHub-Api-Version").Single());
            if (request.RequestUri!.AbsolutePath == "/graphql")
            {
                Assert.Equal(HttpMethod.Post, request.Method);
                using var json = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(ct));
                string query = json.RootElement.GetProperty("query").GetString()!;
                Assert.StartsWith("query { viewer", query);
                Assert.DoesNotContain("mutation", query);
                Assert.DoesNotContain(FakeToken, query);
            }
            else Assert.Equal(HttpMethod.Get, request.Method);
            return DefaultResponse(request);
        });
        using var http = new HttpClient(handler);
        var credentials = new Credentials();
        using var service = new GitHubActivityService(credentials, http);
        Assert.True((await service.ConnectAsync("octocat", FakeToken)).Success);
        Assert.Equal(FakeToken, credentials.Token);
        Assert.Equal(5, handler.Requests.Count);
        var calendar = service.Snapshot.Calendar!;
        Assert.Equal(42, calendar.TotalContributions);
        var week = Assert.Single(calendar.Weeks);
        Assert.Equal(7, week.Days.Count);
        Assert.True(week.Days[0].IsPlaceholder);
        Assert.Equal(10, week.Days[1].Count);
        Assert.Equal(4, week.Days[1].Level);
        Assert.Contains("10 contributions", week.Days[1].Label);
        Assert.Contains(handler.Requests, r => r.Path == "/user/repos" && r.Query.Contains("type=all"));
    }

    [Fact]
    public async Task SessionOnlyToken_IsNotPersistedAndRefreshUsesTheSameAccount()
    {
        var handler = new Handler((r, _) => Task.FromResult(DefaultResponse(r)));
        using var http = new HttpClient(handler);
        var credentials = new Credentials();
        using var service = new GitHubActivityService(credentials, http);
        Assert.True((await service.ConnectAsync("", FakeToken, rememberToken: false)).Success);
        Assert.Null(credentials.Token);
        Assert.True((await service.RefreshAsync()).Success);
        Assert.Equal(10, handler.Requests.Count);
        Assert.All(handler.Requests, r => Assert.Equal("Bearer " + FakeToken, r.Authorization));
    }

    [Theory]
    [InlineData("https://github.com/octocat")]
    [InlineData("octocat/../../user")]
    [InlineData("name?token=secret")]
    [InlineData("invalid account")]
    [InlineData("-bad")]
    public async Task InvalidUsernameNeverReachesNetwork(string username)
    {
        var handler = new Handler((r, _) => Task.FromResult(DefaultResponse(r)));
        using var http = new HttpClient(handler);
        using var service = new GitHubActivityService(new Credentials(), http);
        Assert.False((await service.ConnectAsync(username)).Success);
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task AccountMismatch_DoesNotSaveTokenOrFetchAnyPrivateSections()
    {
        var handler = new Handler((r, _) => Task.FromResult(DefaultResponse(r)));
        using var http = new HttpClient(handler);
        var credentials = new Credentials();
        using var service = new GitHubActivityService(credentials, http);
        var result = await service.ConnectAsync("another-user", FakeToken);
        Assert.False(result.Success);
        Assert.Single(handler.Requests);
        Assert.Null(credentials.Token);
        Assert.Null(service.Snapshot.Profile);
    }

    [Fact]
    public async Task CredentialSaveFailure_DoesNotClaimConnectedOrEchoSecret()
    {
        using var http = new HttpClient(new Handler((r, _) => Task.FromResult(DefaultResponse(r))));
        using var service = new GitHubActivityService(new Credentials { FailSave = true }, http);
        var result = await service.ConnectAsync("", FakeToken);
        Assert.False(result.Success);
        Assert.Contains("securely", result.Message);
        Assert.DoesNotContain(FakeToken, result.Message);
        Assert.Null(service.Snapshot.Profile);
    }

    [Theory]
    [InlineData(401, "rejected the token")]
    [InlineData(403, "denied access")]
    [InlineData(404, "not found")]
    [InlineData(500, "HTTP 500")]
    public async Task ErrorBodiesAndHeadersNeverLeakIntoUi(int code, string expected)
    {
        using var http = new HttpClient(new Handler((_, _) => Task.FromResult(Json(FakeToken, (HttpStatusCode)code))));
        using var service = new GitHubActivityService(new Credentials(), http);
        var result = await service.ConnectAsync("octocat", FakeToken);
        Assert.False(result.Success);
        Assert.Contains(expected, result.Message);
        Assert.DoesNotContain(FakeToken, result.Message);
    }

    [Fact]
    public async Task RateLimitIsDistinctFromPermissionDenied()
    {
        using var http = new HttpClient(new Handler((_, _) =>
        {
            var response = Json(FakeToken, HttpStatusCode.Forbidden);
            response.Headers.Add("X-RateLimit-Remaining", "0");
            response.Headers.Add("X-RateLimit-Reset", "1800000000");
            return Task.FromResult(response);
        }));
        using var service = new GitHubActivityService(new Credentials(), http);
        var result = await service.ConnectAsync("octocat");
        Assert.False(result.Success);
        Assert.Contains("rate limit", result.Message);
        Assert.Contains("Resets at", result.Message);
    }

    [Fact]
    public async Task OneSectionFailureIsVisibleWithoutHidingOtherRealSections()
    {
        using var http = new HttpClient(new Handler((request, _) => Task.FromResult(request.RequestUri!.AbsolutePath == "/user/repos" ?
            Json("private error " + FakeToken, HttpStatusCode.Forbidden) : request.RequestUri.AbsolutePath == "/graphql" ?
            Json("""{"errors":[{"message":"private remote content"}]}""") : DefaultResponse(request))));
        using var service = new GitHubActivityService(new Credentials(), http);
        var result = await service.ConnectAsync("", FakeToken);
        Assert.True(result.Success);
        Assert.Empty(service.Snapshot.Repositories);
        Assert.Single(service.Snapshot.Activities);
        Assert.Single(service.Snapshot.PullRequests);
        Assert.Null(service.Snapshot.Calendar);
        Assert.Contains("Repositories", result.Message);
        Assert.DoesNotContain("private remote content", result.Message);
        Assert.DoesNotContain(FakeToken, result.Message);
    }

    [Fact]
    public async Task FailedRefreshPreservesPreviousSnapshotAndLabelsItStale()
    {
        bool fail = false;
        using var http = new HttpClient(new Handler((r, _) => Task.FromResult(fail ? Json("unavailable", HttpStatusCode.ServiceUnavailable) : DefaultResponse(r))));
        using var service = new GitHubActivityService(new Credentials(), http);
        await service.ConnectAsync("octocat");
        var previous = service.Snapshot;
        fail = true;
        var result = await service.RefreshAsync();
        Assert.False(result.Success);
        Assert.Contains("not been refreshed", result.Message);
        Assert.Same(previous, service.Snapshot);
    }

    [Fact]
    public async Task DisconnectClearsAllDataAndSavedToken_FailedDeletionIsReported()
    {
        using var http = new HttpClient(new Handler((r, _) => Task.FromResult(DefaultResponse(r))));
        var credentials = new Credentials();
        using var service = new GitHubActivityService(credentials, http);
        await service.ConnectAsync("", FakeToken);
        credentials.FailDelete = true;
        Assert.False((await service.DisconnectAsync()).Success);
        Assert.Null(service.Snapshot.Profile);
        Assert.Empty(service.Snapshot.Repositories);
        Assert.Null(service.Snapshot.Calendar);
        Assert.NotNull(credentials.Token);
        credentials.FailDelete = false;
        Assert.True((await service.DisconnectAsync()).Success);
        Assert.Null(credentials.Token);
    }

    [Fact]
    public async Task ExplicitSavedConnectionUsesToken_NoAutomaticRequest()
    {
        var handler = new Handler((r, _) => Task.FromResult(DefaultResponse(r)));
        using var http = new HttpClient(handler);
        using var service = new GitHubActivityService(new Credentials { Token = FakeToken }, http);
        Assert.True(await service.HasSavedTokenAsync());
        Assert.Empty(handler.Requests);
        Assert.True((await service.ConnectSavedAsync()).Success);
        Assert.Equal(5, handler.Requests.Count);
    }

    [Fact]
    public async Task CancellationDoesNotSaveTokenOrPublishProfile()
    {
        using var http = new HttpClient(new Handler(async (_, ct) => { await Task.Delay(Timeout.Infinite, ct); return Json(Profile); }));
        var credentials = new Credentials();
        using var service = new GitHubActivityService(credentials, http);
        using var cts = new CancellationTokenSource();
        var request = service.ConnectAsync("", FakeToken, cancellationToken: cts.Token);
        cts.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => request);
        Assert.Null(service.Snapshot.Profile);
        Assert.Null(credentials.Token);
    }

    [Fact]
    public async Task OversizedAndMalformedResponsesFailWithoutPartialProfile()
    {
        foreach (bool oversized in new[] { true, false })
        {
            using var http = new HttpClient(new Handler((_, _) =>
            {
                var response = Json("malformed");
                if (oversized) response.Content.Headers.ContentLength = 2_097_153;
                return Task.FromResult(response);
            }));
            using var service = new GitHubActivityService(new Credentials(), http);
            Assert.False((await service.ConnectAsync("octocat")).Success);
            Assert.Null(service.Snapshot.Profile);
        }
    }

    [Theory]
    [InlineData("https://github.com/octocat", true)]
    [InlineData("https://github.com/octocat/Hello/pull/7", true)]
    [InlineData("https://github.com.evil.test/octocat", false)]
    [InlineData("http://github.com/octocat", false)]
    [InlineData("https://token@github.com/octocat", false)]
    [InlineData("https://github.com:444/octocat", false)]
    [InlineData("shell:AppsFolder", false)]
    public void LinkPolicy_OnlyAllowsOfficialHttpsGitHub(string url, bool expected) => Assert.Equal(expected, GitHubActivityService.IsSafeGitHubLink(url));

    [Fact]
    public async Task ViewModelDisposeDropsQueuedCallbacksAndTokenInput()
    {
        var queue = new Queue<Action>();
        using var http = new HttpClient(new Handler((r, _) => Task.FromResult(DefaultResponse(r))));
        var vm = new GitHubActivityViewModel(new GitHubActivityService(new Credentials(), http), queue.Enqueue);
        vm.Username = "octocat";
        vm.TokenInput = FakeToken;
        await vm.ConnectAsync();
        vm.Dispose();
        int changes = 0;
        vm.PropertyChanged += (_, _) => changes++;
        while (queue.TryDequeue(out var action)) action();
        Assert.Equal(0, changes);
        Assert.Empty(vm.Repositories);
        Assert.Equal("", vm.TokenInput);
        Assert.False(vm.IsConnected);
    }

    private sealed record RequestInfo(string Method, string Host, string Path, string Query, string? Authorization);
    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> handle) : HttpMessageHandler
    {
        public ConcurrentBag<RequestInfo> Requests { get; } = new();
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Requests.Add(new(request.Method.Method, request.RequestUri!.Host, request.RequestUri.AbsolutePath, request.RequestUri.Query, request.Headers.Authorization?.ToString()));
            return handle(request, cancellationToken);
        }
    }
    private sealed class Credentials : ISecureCredentialStorage
    {
        public string? Token { get; set; }
        public bool FailSave { get; set; }
        public bool FailDelete { get; set; }
        public Task SetCredentialAsync(string target, string secret)
        {
            Assert.Equal(GitHubActivityService.CredentialTarget, target);
            if (FailSave) throw new IOException(FakeToken);
            Token = secret; return Task.CompletedTask;
        }
        public Task<string?> GetCredentialAsync(string target) => Task.FromResult(Token);
        public Task DeleteCredentialAsync(string target)
        {
            if (FailDelete) throw new IOException(FakeToken);
            Token = null; return Task.CompletedTask;
        }
        public Task<bool> HasCredentialAsync(string target) => Task.FromResult(Token != null);
    }
}
