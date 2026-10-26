using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface ILocalBrainService : IDisposable
{
    IReadOnlyList<LocalBrainModelDescriptor> Models { get; }
    LocalBrainSnapshot Snapshot { get; }
    event EventHandler<LocalBrainSnapshot>? StateChanged;
    bool IsInstalled(string modelId);
    Task RefreshAsync(string modelId, CancellationToken cancellationToken = default);
    Task InstallAsync(string modelId, CancellationToken cancellationToken = default);
    Task StartAsync(string modelId, CancellationToken cancellationToken = default);
    Task StopAsync();
    Task DeleteModelAsync(string modelId, CancellationToken cancellationToken = default);
    void CancelOperation();
    Task<string> GenerateAsync(string modelId, string prompt, IReadOnlyList<ChatMessage>? history = null, CancellationToken cancellationToken = default);
}
