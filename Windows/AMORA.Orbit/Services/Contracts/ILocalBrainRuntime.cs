using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface ILocalBrainRuntime : IDisposable
{
    bool IsRunning { get; }
    string? LoadedModelId { get; }
    event EventHandler? UnexpectedlyExited;
    Task StartAsync(string executable, string modelFile, LocalBrainModelDescriptor model, CancellationToken cancellationToken);
    Task<string> GenerateAsync(string formattedPrompt, int contextLength, CancellationToken cancellationToken);
    void Stop();
}

public interface ILocalBrainAssets
{
    string RuntimeExecutable { get; }
    string ModelPath(string modelId);
    bool IsInstalled(string modelId);
    Task VerifyAsync(string modelId, Action<LocalBrainSnapshot> progress, CancellationToken cancellationToken);
    Task InstallAsync(string modelId, Action<LocalBrainSnapshot> progress, CancellationToken cancellationToken);
    void DeleteModel(string modelId);
}
