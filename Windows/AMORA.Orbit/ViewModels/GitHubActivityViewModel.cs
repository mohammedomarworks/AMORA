using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using Windows.System;

namespace AMORA.Orbit.ViewModels;

public sealed class GitHubActivityViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly IGitHubActivityService _service;
    private readonly Action<Action> _dispatch;
    private readonly Func<string, Task<bool>> _openLink;
    private CancellationTokenSource? _request;
    private int _generation;
    private bool _disposed, _isBusy, _hasSavedToken, _rememberToken = true;
    private string _username = "", _tokenInput = "";
    private string _statusMessage = "Enter a public username, or your GitHub token for account and contribution data. Nothing loads until you connect.";
    private string _contributionSummary = "Connect GitHub to view activity.";

    public GitHubActivityViewModel(IGitHubActivityService service, Action<Action>? dispatch = null, Func<string, Task<bool>>? openLink = null)
    {
        _service = service ?? throw new ArgumentNullException(nameof(service));
        _dispatch = dispatch ?? (action => action());
        _openLink = openLink ?? (async url => await Launcher.LaunchUriAsync(new Uri(url)));
    }

    public ObservableCollection<GitHubRepositoryItem> Repositories { get; } = new();
    public ObservableCollection<GitHubActivityItem> Activities { get; } = new();
    public ObservableCollection<GitHubPullRequestItem> PullRequests { get; } = new();
    public ObservableCollection<GitHubContributionWeek> Weeks { get; } = new();
    public string Username { get => _username; set => Set(ref _username, value); }
    public string TokenInput { get => _tokenInput; set => Set(ref _tokenInput, value); }
    public bool RememberToken { get => _rememberToken; set => Set(ref _rememberToken, value); }
    public bool HasSavedToken { get => _hasSavedToken; private set => Set(ref _hasSavedToken, value); }
    public bool IsBusy { get => _isBusy; private set { if (Set(ref _isBusy, value)) OnPropertyChanged(nameof(CanConnect)); } }
    public bool CanConnect => !IsBusy;
    public bool IsConnected => _service.Snapshot.Profile != null;
    public bool HasCalendar => _service.Snapshot.Calendar != null;
    public string ProfileName => _service.Snapshot.Profile?.Name ?? "GitHub";
    public string Login => _service.Snapshot.Profile is { } profile ? "@" + profile.Login : "Not connected";
    public string ProfileUrl => _service.Snapshot.Profile?.ProfileUrl ?? "";
    public string? AvatarUrl => _service.Snapshot.Profile?.AvatarUrl;
    public string Bio => _service.Snapshot.Profile?.Bio ?? "";
    public string ConnectionText => !IsConnected ? "Disconnected" : _service.Snapshot.IsAuthenticated ? "Token connected · read-only" : "Public account · read-only";
    public string StatusMessage { get => _statusMessage; private set => Set(ref _statusMessage, value); }
    public string ContributionSummary { get => _contributionSummary; private set => Set(ref _contributionSummary, value); }
    public string RepositoryHeading => $"Repositories ({Repositories.Count})";
    public string PullRequestHeading => $"PRs ({PullRequests.Count})";
    public string ActivityHeading => $"Recent activity ({Activities.Count})";
    public string LastUpdatedText => _service.Snapshot.UpdatedAt is { } time ? $"Updated {time.ToLocalTime():HH:mm}" : "Not loaded";
    public event PropertyChangedEventHandler? PropertyChanged;

    public async Task InitializeAsync()
    {
        if (_disposed) return;
        try
        {
            bool available = await _service.HasSavedTokenAsync();
            _dispatch(() => { if (!_disposed) HasSavedToken = available; });
        }
        catch { _dispatch(() => { if (!_disposed) StatusMessage = "Saved GitHub credential availability could not be checked."; }); }
    }

    public Task ConnectAsync()
    {
        string username = Username, token = TokenInput;
        bool remember = RememberToken;
        TokenInput = "";
        return RunAsync(ct => _service.ConnectAsync(username, token, remember, ct));
    }
    public Task ConnectSavedAsync() => RunAsync(_service.ConnectSavedAsync);
    public Task RefreshAsync() => RunAsync(_service.RefreshAsync);
    public Task DisconnectAsync() => RunAsync(_service.DisconnectAsync, replaceActive: true);

    public void Cancel() { if (!_disposed) _request?.Cancel(); }
    public void SelectDay(GitHubContributionDay day)
    {
        if (!_disposed && !day.IsPlaceholder) ContributionSummary = day.Label;
    }

    public async Task OpenLinkAsync(string url)
    {
        if (_disposed) return;
        if (!GitHubActivityService.IsSafeGitHubLink(url)) { StatusMessage = "Only official HTTPS GitHub links can be opened here."; return; }
        bool opened;
        try { opened = await _openLink(url); } catch { opened = false; }
        _dispatch(() => { if (!_disposed) StatusMessage = opened ? "Opened GitHub in your browser." : "Windows could not open the GitHub link."; });
    }

    private async Task RunAsync(Func<CancellationToken, Task<GitHubActionResult>> operation, bool replaceActive = false)
    {
        if (_disposed || IsBusy && !replaceActive) return;
        _request?.Cancel();
        _request?.Dispose();
        var request = _request = new CancellationTokenSource();
        int generation = ++_generation;
        IsBusy = true;
        StatusMessage = "Loading GitHub…";
        try
        {
            var result = await operation(request.Token);
            bool saved = await _service.HasSavedTokenAsync();
            _dispatch(() =>
            {
                if (_disposed || generation != _generation) return;
                StatusMessage = result.Message;
                HasSavedToken = saved;
                Reload();
            });
        }
        catch (OperationCanceledException)
        { _dispatch(() => { if (!_disposed && generation == _generation) StatusMessage = "GitHub request canceled."; }); }
        catch
        { _dispatch(() => { if (!_disposed && generation == _generation) StatusMessage = "GitHub request failed. Try again."; }); }
        finally
        { _dispatch(() => { if (!_disposed && generation == _generation) IsBusy = false; }); }
    }

    private void Reload()
    {
        var data = _service.Snapshot;
        Repositories.Clear(); foreach (var item in data.Repositories) Repositories.Add(item);
        Activities.Clear(); foreach (var item in data.Activities) Activities.Add(item);
        PullRequests.Clear(); foreach (var item in data.PullRequests) PullRequests.Add(item);
        Weeks.Clear(); foreach (var week in data.Calendar?.Weeks.TakeLast(28) ?? []) Weeks.Add(week);
        ContributionSummary = data.Calendar is { } calendar ? $"{calendar.TotalContributions} contributions in the past year" :
            data.Profile == null ? "Connect GitHub to view activity." : data.IsAuthenticated ?
                "Contribution calendar unavailable — check token permissions and refresh." : "Contribution calendar unavailable — a GitHub token is required.";
        foreach (string name in new[] { nameof(IsConnected), nameof(HasCalendar), nameof(ProfileName), nameof(Login), nameof(ProfileUrl),
            nameof(AvatarUrl), nameof(Bio), nameof(ConnectionText), nameof(RepositoryHeading), nameof(PullRequestHeading), nameof(ActivityHeading), nameof(LastUpdatedText) }) OnPropertyChanged(name);
    }

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (_disposed || EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value; OnPropertyChanged(name); return true;
    }
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true; ++_generation;
        _request?.Cancel(); _request?.Dispose(); _request = null;
        _tokenInput = "";
        _service.Dispose();
    }
}
