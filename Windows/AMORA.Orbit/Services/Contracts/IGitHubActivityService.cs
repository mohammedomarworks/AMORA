using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface IGitHubActivityService : IDisposable
{
    GitHubActivitySnapshot Snapshot { get; }
    Task<bool> HasSavedTokenAsync();
    Task<GitHubActionResult> ConnectAsync(string username, string? token = null, bool rememberToken = true, CancellationToken cancellationToken = default);
    Task<GitHubActionResult> ConnectSavedAsync(CancellationToken cancellationToken = default);
    Task<GitHubActionResult> RefreshAsync(CancellationToken cancellationToken = default);
    Task<GitHubActionResult> DisconnectAsync(CancellationToken cancellationToken = default);
}
