namespace AMORA.Orbit.Models;

public sealed record GitHubProfile(string Login, string Name, string Bio, string ProfileUrl, string? AvatarUrl,
    int PublicRepositories, int Followers, int Following);

public sealed record GitHubRepositoryItem(long Id, string Name, string FullName, string Description, string Language,
    int Stars, bool IsPrivate, string Url, DateTimeOffset? UpdatedAt)
{
    public string Details => $"{(IsPrivate ? "Private" : "Public")} · {Language} · ★ {Stars}";
}

public sealed record GitHubActivityItem(string Id, string Summary, string Repository, string Url, DateTimeOffset? CreatedAt)
{
    public string DateText => CreatedAt?.ToLocalTime().ToString("MMM d, HH:mm") ?? "Date unavailable";
}

public sealed record GitHubPullRequestItem(long Id, int Number, string Title, string Repository, string Url, DateTimeOffset? CreatedAt)
{
    public string Details => $"{Repository} · #{Number}";
}

public sealed record GitHubContributionDay(string Date, int Count, int Weekday, int Level, bool IsPlaceholder = false)
{
    public string Label => IsPlaceholder ? "" : $"{Date} · {Count} contribution{(Count == 1 ? "" : "s")}";
    // Fixed palette from the Mac renderer; remote data never supplies markup or color strings.
    public string Color => IsPlaceholder ? "#00000000" : Level switch
    {
        1 => "#0D4729", 2 => "#006E38", 3 => "#26A642", 4 => "#39D353", _ => "#1F242B"
    };
}

public sealed record GitHubContributionWeek(IReadOnlyList<GitHubContributionDay> Days);
public sealed record GitHubContributionCalendar(int TotalContributions, IReadOnlyList<GitHubContributionWeek> Weeks);
public sealed record GitHubActivitySnapshot(GitHubProfile? Profile, IReadOnlyList<GitHubRepositoryItem> Repositories,
    IReadOnlyList<GitHubActivityItem> Activities, IReadOnlyList<GitHubPullRequestItem> PullRequests,
    GitHubContributionCalendar? Calendar, bool IsAuthenticated, DateTimeOffset? UpdatedAt, IReadOnlyList<string> Warnings)
{
    public static GitHubActivitySnapshot Empty => new(null, Array.Empty<GitHubRepositoryItem>(), Array.Empty<GitHubActivityItem>(),
        Array.Empty<GitHubPullRequestItem>(), null, false, null, Array.Empty<string>());
}

public sealed record GitHubActionResult(bool Success, string Message);
