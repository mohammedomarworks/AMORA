namespace AMORA.Orbit.Models;

public sealed record LocalBrainModelDescriptor(string Id, string DisplayName, string FileName, string DownloadUrl,
    string Sha256, long SizeBytes, long EstimatedRamBytes, int ContextLength = 2048)
{
    public string DownloadLabel => $"{DisplayName} · {SizeBytes / 1024 / 1024:N0} MB · Apache 2.0";
}

public static class LocalBrainCatalog
{
    public const string CompactModelId = "qwen2.5-0.5b-instruct-q4_k_m";
    public const string DefaultModelId = "qwen2.5-1.5b-instruct-q4_k_m";
    public const string RuntimeVersion = "b11901";
    public const string RuntimeUrl = "https://github.com/ggml-org/llama.cpp/releases/download/b11901/llama-b11901-bin-win-cpu-x64.zip";
    public const string RuntimeSha256 = "039951745399d7c1228b1e882d6e41b24d393f1795e3a6e176162bfb8193500a";
    public const long RuntimeSizeBytes = 24_228_082;
    public static IReadOnlyList<LocalBrainModelDescriptor> Models { get; } = Array.AsReadOnly(new[]
    {
        new LocalBrainModelDescriptor(DefaultModelId, "Qwen 2.5 1.5B · Mac default", DefaultModelId + ".gguf",
            "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
            "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e", 1_117_320_736, 1_800L * 1024 * 1024),
        new LocalBrainModelDescriptor(CompactModelId, "Qwen 2.5 0.5B · Compact", CompactModelId + ".gguf",
            "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf",
            "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db", 491_400_032, 900L * 1024 * 1024)
    });
    public static LocalBrainModelDescriptor Find(string id) => Models.FirstOrDefault(model => model.Id == id)
        ?? throw new ArgumentException("Choose a supported Local Brain model.");
}

public enum LocalBrainState { NotInstalled, Installed, Downloading, Verifying, Starting, Ready, Generating, Stopped, Cancelled, Failed, UnsupportedDevice }
public sealed record LocalBrainSnapshot(LocalBrainState State, string Message, string? ModelId = null,
    long CompletedBytes = 0, long TotalBytes = 0)
{
    public bool IsBusy => State is LocalBrainState.Downloading or LocalBrainState.Verifying or LocalBrainState.Starting or LocalBrainState.Generating;
    public bool IsReady => State is LocalBrainState.Ready;
    public double ProgressPercent => TotalBytes > 0 ? Math.Clamp(100.0 * CompletedBytes / TotalBytes, 0, 100) : 0;
}

public sealed class LocalBrainException(string message) : Exception(message);
