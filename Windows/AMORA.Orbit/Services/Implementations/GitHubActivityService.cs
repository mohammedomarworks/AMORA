using System.Globalization;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>Read-only official GitHub APIs. No requests until an explicit connect/refresh.</summary>
public sealed class GitHubActivityService : IGitHubActivityService
{
    public const string CredentialTarget = "AMORA.GitHub.AccessToken";
    private const int MaximumResponseBytes = 2_097_152;
    private readonly ISecureCredentialStorage _credentials;
    private readonly HttpClient _http;
    private readonly bool _ownsHttp;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly CancellationTokenSource _lifetime = new();
    private string? _sessionToken;
    private bool _disposed;
    private GitHubActivitySnapshot _snapshot = GitHubActivitySnapshot.Empty;

    public GitHubActivityService(ISecureCredentialStorage credentials, HttpClient? httpClient = null)
    {
        _credentials = credentials ?? throw new ArgumentNullException(nameof(credentials));
        _ownsHttp = httpClient == null;
        _http = httpClient ?? new HttpClient(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(25) };
    }

    public GitHubActivitySnapshot Snapshot => _snapshot;
    public async Task<bool> HasSavedTokenAsync()
    {
        if (_disposed) return false;
        return await _credentials.HasCredentialAsync(CredentialTarget);
    }

    public Task<GitHubActionResult> ConnectAsync(string username, string? token = null, bool rememberToken = true, CancellationToken cancellationToken = default) =>
        RunAsync(ct => ConnectCoreAsync(username, token, rememberToken, ct), cancellationToken);

    public Task<GitHubActionResult> ConnectSavedAsync(CancellationToken cancellationToken = default) => RunAsync(async ct =>
    {
        string? token;
        try { token = await _credentials.GetCredentialAsync(CredentialTarget); }
        catch { return new(false, "The saved GitHub token could not be read. Re-enter it or disconnect to remove it."); }
        if (string.IsNullOrWhiteSpace(token)) return new(false, "No saved GitHub token is available. Enter a username or token to connect.");
        return await ConnectCoreAsync("", token, rememberToken: false, ct);
    }, cancellationToken);

    public Task<GitHubActionResult> RefreshAsync(CancellationToken cancellationToken = default) => RunAsync(async ct =>
    {
        if (_snapshot.Profile == null) return new(false, "Connect a GitHub account first.");
        return await ConnectCoreAsync(_snapshot.Profile.Login, _sessionToken, rememberToken: false, ct);
    }, cancellationToken);

    public Task<GitHubActionResult> DisconnectAsync(CancellationToken cancellationToken = default) => RunAsync(async ct =>
    {
        ct.ThrowIfCancellationRequested();
        _sessionToken = null;
        _snapshot = GitHubActivitySnapshot.Empty;
        try { await _credentials.DeleteCredentialAsync(CredentialTarget); }
        catch { return new(false, "Disconnected from GitHub, but the saved token could not be deleted. Try Disconnect again."); }
        return new(true, "Disconnected. The saved GitHub token and displayed account data were cleared.");
    }, cancellationToken);

    private async Task<GitHubActionResult> ConnectCoreAsync(string username, string? token, bool rememberToken, CancellationToken ct)
    {
        username = (username ?? "").Trim();
        token = string.IsNullOrWhiteSpace(token) ? null : token.Trim();
        if ((token == null && !ValidUsername(username)) || (username.Length != 0 && !ValidUsername(username)))
            return new(false, "Enter a GitHub username using letters, numbers and hyphens, up to 39 characters.");
        if (token != null && (token.Length > 4096 || token.Any(c => c > 127 || char.IsControl(c) || char.IsWhiteSpace(c))))
            return new(false, "The GitHub token contains invalid characters. Re-enter it without spaces.");

        using var profileData = await SendAsync(token == null ? $"/users/{username}" : "/user", token, null, ct);
        var profile = ParseProfile(profileData.RootElement);
        if (token != null && username.Length != 0 && !string.Equals(username, profile.Login, StringComparison.OrdinalIgnoreCase))
            return new(false, "That token belongs to a different GitHub account. Clear the username or enter the token owner's username.");

        // The four sections are independent; a failed section remains visibly unavailable.
        var repoTask = FetchSectionAsync("Repositories", async () =>
        {
            using var data = await SendAsync(token == null ? $"/users/{profile.Login}/repos?sort=updated&per_page=5&type=owner" :
                "/user/repos?sort=updated&per_page=5&type=all", token, null, ct);
            return ParseRepositories(data.RootElement);
        }, ct);
        var eventTask = FetchSectionAsync("Activity", async () =>
        {
            using var data = await SendAsync($"/users/{profile.Login}/events{(token == null ? "/public" : "")}?per_page=10", token, null, ct);
            return ParseEvents(data.RootElement);
        }, ct);
        var prTask = FetchSectionAsync("Pull requests", async () =>
        {
            string query = Uri.EscapeDataString($"author:{profile.Login} type:pr state:open");
            using var data = await SendAsync($"/search/issues?q={query}&per_page=5", token, null, ct);
            return ParsePullRequests(data.RootElement);
        }, ct);
        var calendarTask = token == null ? Task.FromResult(new Section<GitHubContributionCalendar>(null,
            "Contribution calendar requires a GitHub token. Public events are not a yearly contribution history.")) :
            FetchSectionAsync("Contribution calendar", async () =>
            {
                const string query = "query { viewer { contributionsCollection { contributionCalendar { totalContributions weeks { contributionDays { contributionCount date weekday contributionLevel } } } } } }";
                using var data = await SendAsync("/graphql", token, query, ct);
                return ParseCalendar(data.RootElement);
            }, ct);
        await Task.WhenAll(repoTask, eventTask, prTask, calendarTask);
        ct.ThrowIfCancellationRequested();
        if (_disposed) throw new OperationCanceledException(ct);
        if (token != null && rememberToken)
        {
            try { await _credentials.SetCredentialAsync(CredentialTarget, token); }
            catch { return new(false, "GitHub responded, but the token could not be saved securely. No connection change was applied. Disable Remember token to connect for this session."); }
        }
        ct.ThrowIfCancellationRequested();
        if (_disposed) throw new OperationCanceledException(ct);
        var warnings = new[] { repoTask.Result.Warning, eventTask.Result.Warning, prTask.Result.Warning, calendarTask.Result.Warning }
            .Where(w => w != null).Cast<string>().ToArray();
        _sessionToken = token;
        _snapshot = new(profile, repoTask.Result.Value ?? [], eventTask.Result.Value ?? [], prTask.Result.Value ?? [],
            calendarTask.Result.Value, token != null, DateTimeOffset.UtcNow, warnings);
        return new(true, warnings.Length == 0 ? "GitHub updated. All displayed information is read-only." :
            "GitHub connected with limited data. " + string.Join(" ", warnings));
    }

    private async Task<GitHubActionResult> RunAsync(Func<CancellationToken, Task<GitHubActionResult>> action, CancellationToken token)
    {
        if (_disposed) return new(false, "GitHub panel is closed.");
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(token, _lifetime.Token);
        await _gate.WaitAsync(linked.Token);
        try { return await action(linked.Token); }
        catch (OperationCanceledException) { throw; }
        catch (GitHubReadException ex) { return new(false, ex.Message + (_snapshot.Profile == null ? "" : " Previously displayed data has not been refreshed.")); }
        catch { return new(false, "GitHub data could not be loaded. Check the connection and try again."); }
        finally { _gate.Release(); }
    }

    private sealed record Section<T>(T? Value, string? Warning) where T : class;
    private static async Task<Section<T>> FetchSectionAsync<T>(string name, Func<Task<T>> fetch, CancellationToken ct) where T : class
    {
        try { return new(await fetch(), null); }
        catch (OperationCanceledException) { throw; }
        catch (GitHubReadException ex) { return new(null, $"{name}: {ex.Message}"); }
        catch { ct.ThrowIfCancellationRequested(); return new(null, $"{name} is unavailable. Try Refresh."); }
    }

    private async Task<JsonDocument> SendAsync(string path, string? token, string? query, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(query == null ? HttpMethod.Get : HttpMethod.Post, "https://api.github.com" + path);
        request.Headers.UserAgent.ParseAdd("AMORA-Windows/0.6");
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        request.Headers.Add("X-GitHub-Api-Version", "2022-11-28"); // Version used by the Mac implementation.
        if (token != null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        if (query != null) request.Content = new StringContent(JsonSerializer.Serialize(new { query }), Encoding.UTF8, "application/json");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(ct);
        deadline.CancelAfter(TimeSpan.FromSeconds(25));
        try
        {
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (!response.IsSuccessStatusCode) throw Failure(response);
            if (response.Content.Headers.ContentLength > MaximumResponseBytes) throw new GitHubReadException("GitHub returned too much data.");
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var data = new MemoryStream();
            var buffer = new byte[8192];
            int read;
            while ((read = await stream.ReadAsync(buffer, deadline.Token)) != 0)
            {
                if (data.Length + read > MaximumResponseBytes) throw new GitHubReadException("GitHub returned too much data.");
                data.Write(buffer, 0, read);
            }
            return JsonDocument.Parse(data.ToArray());
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested) { throw new GitHubReadException("GitHub request timed out. Try again."); }
        catch (OperationCanceledException) { throw; }
        catch (GitHubReadException) { throw; }
        catch (JsonException) { throw new GitHubReadException("GitHub returned an unreadable response."); }
        catch { throw new GitHubReadException("Could not reach GitHub. Check your network and try again."); }
    }

    private static GitHubReadException Failure(HttpResponseMessage response)
    {
        if (response.StatusCode == HttpStatusCode.Unauthorized) return new("GitHub rejected the token. Re-enter it or Disconnect to remove it.");
        bool limited = response.StatusCode == HttpStatusCode.TooManyRequests || response.StatusCode == HttpStatusCode.Forbidden &&
            (response.Headers.TryGetValues("X-RateLimit-Remaining", out var remaining) && remaining.FirstOrDefault() == "0" || response.Headers.RetryAfter != null);
        if (limited)
        {
            string suffix = "Wait before refreshing.";
            if (response.Headers.TryGetValues("X-RateLimit-Reset", out var reset) && long.TryParse(reset.FirstOrDefault(), out long epoch))
            {
                try { suffix = $"Resets at {DateTimeOffset.FromUnixTimeSeconds(epoch).ToLocalTime():HH:mm}."; } catch (ArgumentOutOfRangeException) { }
            }
            return new("GitHub rate limit reached. " + suffix);
        }
        return new(response.StatusCode switch
        {
            HttpStatusCode.NotFound => "The GitHub account or resource was not found.",
            HttpStatusCode.Forbidden => "GitHub denied access. Check token permissions and organization access.",
            _ => $"GitHub returned HTTP {(int)response.StatusCode}. Try again later."
        });
    }

    public static bool ValidUsername(string username) => Regex.IsMatch(username, @"\A[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?\z");
    public static bool IsSafeGitHubLink(string? value) => Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
        uri.Scheme == "https" && uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase) && uri.Port == 443 && uri.UserInfo.Length == 0;

    private static GitHubProfile ParseProfile(JsonElement value)
    {
        string login = Text(value, "login", 39);
        if (!ValidUsername(login)) throw new GitHubReadException("GitHub returned an invalid account profile.");
        string avatar = Text(value, "avatar_url", 1024);
        bool safeAvatar = Uri.TryCreate(avatar, UriKind.Absolute, out var uri) && uri.Scheme == "https" && uri.Host == "avatars.githubusercontent.com" && uri.Port == 443 && uri.UserInfo.Length == 0;
        return new(login, Text(value, "name", 200, login), Text(value, "bio", 500), "https://github.com/" + login,
            safeAvatar ? avatar : null, Count(value, "public_repos"), Count(value, "followers"), Count(value, "following"));
    }

    private static IReadOnlyList<GitHubRepositoryItem> ParseRepositories(JsonElement value) => value.EnumerateArray().Take(5).Select(item =>
        new GitHubRepositoryItem(item.GetProperty("id").GetInt64(), Text(item, "name", 200), Text(item, "full_name", 300),
            Text(item, "description", 500), Text(item, "language", 80, "Language unavailable"), Count(item, "stargazers_count"),
            item.TryGetProperty("private", out var privacy) && privacy.ValueKind == JsonValueKind.True, SafeUrl(item, "html_url"), Date(item, "updated_at"))).ToArray();

    private static IReadOnlyList<GitHubActivityItem> ParseEvents(JsonElement value) => value.EnumerateArray().Take(10).Select(item =>
    {
        string repo = Text(item.GetProperty("repo"), "name", 300);
        string type = Text(item, "type", 80);
        string summary = type switch
        {
            "PushEvent" => "Pushed commits", "PullRequestEvent" => "Updated pull request", "IssuesEvent" => "Updated issue",
            "CreateEvent" => "Created branch or repository", "DeleteEvent" => "Deleted branch or tag",
            "WatchEvent" => "Starred repository", "ForkEvent" => "Forked repository", "ReleaseEvent" => "Published release",
            "IssueCommentEvent" => "Commented on issue or pull request", _ => "Repository activity"
        };
        if (item.TryGetProperty("payload", out var payload) && payload.ValueKind == JsonValueKind.Object)
        {
            int size = Count(payload, "size");
            if (type == "PushEvent" && size > 0) summary = $"Pushed {size} commit{(size == 1 ? "" : "s")}";
            string action = Text(payload, "action", 40);
            if (action is "opened" or "closed" or "reopened" && type is "PullRequestEvent" or "IssuesEvent")
                summary = char.ToUpperInvariant(action[0]) + action[1..] + (type == "PullRequestEvent" ? " pull request" : " issue");
        }
        string link = Regex.IsMatch(repo, @"\A[a-zA-Z0-9-]+/[a-zA-Z0-9_.-]+\z") ? "https://github.com/" + repo : "";
        return new GitHubActivityItem(Text(item, "id", 100), summary, repo, link, Date(item, "created_at"));
    }).ToArray();

    private static IReadOnlyList<GitHubPullRequestItem> ParsePullRequests(JsonElement value) => value.GetProperty("items").EnumerateArray().Take(5).Select(item =>
    {
        string repository = Text(item, "repository_url", 500);
        const string prefix = "https://api.github.com/repos/";
        return new GitHubPullRequestItem(item.GetProperty("id").GetInt64(), Count(item, "number"), Text(item, "title", 500),
            repository.StartsWith(prefix, StringComparison.Ordinal) ? repository[prefix.Length..] : "Repository unavailable",
            SafeUrl(item, "html_url"), Date(item, "created_at"));
    }).ToArray();

    private static GitHubContributionCalendar ParseCalendar(JsonElement response)
    {
        if (response.TryGetProperty("errors", out var errors) && errors.ValueKind == JsonValueKind.Array && errors.GetArrayLength() > 0)
            throw new GitHubReadException("Contribution calendar is unavailable for this token. Check read permissions.");
        var calendar = response.GetProperty("data").GetProperty("viewer").GetProperty("contributionsCollection").GetProperty("contributionCalendar");
        var weeks = calendar.GetProperty("weeks").EnumerateArray().Take(54).Select(week =>
        {
            var days = week.GetProperty("contributionDays").EnumerateArray().Take(7).Select(day =>
            {
                string date = Text(day, "date", 10);
                if (!DateOnly.TryParseExact(date, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out _)) throw new JsonException();
                int weekday = day.GetProperty("weekday").GetInt32(), count = day.GetProperty("contributionCount").GetInt32();
                if (weekday is < 0 or > 6 || count < 0) throw new JsonException();
                int level = Text(day, "contributionLevel", 40) switch
                {
                    "FOURTH_QUARTILE" => 4, "THIRD_QUARTILE" => 3, "SECOND_QUARTILE" => 2, "FIRST_QUARTILE" => 1,
                    "NONE" => 0, _ => count == 0 ? 0 : count <= 2 ? 1 : count <= 5 ? 2 : count <= 9 ? 3 : 4
                };
                return new GitHubContributionDay(date, count, weekday, level);
            }).ToArray();
            if (days.Select(day => day.Weekday).Distinct().Count() != days.Length) throw new JsonException();
            return new GitHubContributionWeek(Enumerable.Range(0, 7).Select(index => days.FirstOrDefault(day => day.Weekday == index) ??
                new GitHubContributionDay("", 0, index, 0, true)).ToArray());
        }).ToArray();
        return new(Count(calendar, "totalContributions"), weeks);
    }

    private static string Text(JsonElement item, string name, int limit, string fallback = "")
    {
        string? text = item.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
        if (string.IsNullOrWhiteSpace(text)) return fallback;
        return text.Length > limit ? text[..limit] : text;
    }
    private static int Count(JsonElement item, string name) => item.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out int count) ? Math.Max(0, count) : 0;
    private static DateTimeOffset? Date(JsonElement item, string name) => DateTimeOffset.TryParse(Text(item, name, 40), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var result) ? result : null;
    private static string SafeUrl(JsonElement item, string name) { string value = Text(item, name, 2048); return IsSafeGitHubLink(value) ? value : ""; }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _lifetime.Cancel();
        _sessionToken = null;
        _snapshot = GitHubActivitySnapshot.Empty;
        if (_ownsHttp) _http.Dispose();
    }

    private sealed class GitHubReadException(string message) : Exception(message);
}
