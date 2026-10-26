using System.IO.Compression;
using System.Net.Http;
using System.Security.Cryptography;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>Only pinned official artifacts are accepted; installation never executes downloaded scripts.</summary>
public sealed class LocalBrainAssetStore : ILocalBrainAssets
{
    private readonly string _root;
    private readonly HttpClient _downloads;
    private readonly Func<long> _availableStorage;
    private static readonly HttpClient SharedDownloads = new(new SocketsHttpHandler { AllowAutoRedirect = true }) { Timeout = Timeout.InfiniteTimeSpan };
    public LocalBrainAssetStore(string? rootDirectory = null, HttpClient? downloads = null, Func<long>? availableStorage = null)
    {
        _root = Path.GetFullPath(rootDirectory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AMORA", "LocalBrain"));
        _downloads = downloads ?? SharedDownloads;
        _availableStorage = availableStorage ?? (() => new DriveInfo(Path.GetPathRoot(_root)!).AvailableFreeSpace);
    }
    private string RuntimeDirectory => Path.Combine(_root, "runtime-" + LocalBrainCatalog.RuntimeVersion);
    private string RuntimeArchive => Path.Combine(_root, "runtime.zip");
    public string RuntimeExecutable => Path.Combine(RuntimeDirectory, "llama-server.exe");
    public string ModelPath(string modelId) => Path.Combine(_root, LocalBrainCatalog.Find(modelId).FileName);
    public bool IsInstalled(string modelId)
    {
        try { return File.Exists(RuntimeExecutable) && File.Exists(RuntimeArchive) && new FileInfo(ModelPath(modelId)).Length == LocalBrainCatalog.Find(modelId).SizeBytes; }
        catch { return false; }
    }

    public async Task VerifyAsync(string modelId, Action<LocalBrainSnapshot> progress, CancellationToken cancellationToken)
    {
        var model = LocalBrainCatalog.Find(modelId);
        EnsureSafeRoot();
        progress(new(LocalBrainState.Verifying, "Verifying official runtime and model checksums…", modelId));
        if (!await VerifyArtifactAsync(RuntimeArchive, LocalBrainCatalog.RuntimeSizeBytes, LocalBrainCatalog.RuntimeSha256, cancellationToken)
            || !await RuntimeFilesMatchArchiveAsync(cancellationToken))
            throw new LocalBrainException("The Local Brain runtime is missing or changed. Use Install to repair the official runtime.");
        if (!await VerifyArtifactAsync(ModelPath(modelId), model.SizeBytes, model.Sha256, cancellationToken))
            throw new LocalBrainException("The local model is missing or failed its checksum. Use Install to download a verified copy.");
        using var modelFile = new FileStream(ModelPath(modelId), FileMode.Open, FileAccess.Read, FileShare.Read);
        var magic = new byte[4];
        if (modelFile.Read(magic) != 4 || !magic.AsSpan().SequenceEqual("GGUF"u8))
            throw new LocalBrainException("The local model is not a valid GGUF artifact.");
    }

    public async Task InstallAsync(string modelId, Action<LocalBrainSnapshot> progress, CancellationToken cancellationToken)
    {
        var model = LocalBrainCatalog.Find(modelId);
        EnsureSafeRoot();
        Directory.CreateDirectory(_root);
        bool archiveVerified = await VerifyArtifactAsync(RuntimeArchive, LocalBrainCatalog.RuntimeSizeBytes, LocalBrainCatalog.RuntimeSha256, cancellationToken);
        bool runtimeVerified = archiveVerified && await RuntimeFilesMatchArchiveAsync(cancellationToken);
        bool modelVerified = await VerifyArtifactAsync(ModelPath(modelId), model.SizeBytes, model.Sha256, cancellationToken);
        // Existing verified files need no second download. Unverified files stay in place until replacements are ready.
        long needed = RequiredSetupBytes(model.SizeBytes, modelVerified, archiveVerified, runtimeVerified);
        if (_availableStorage() < needed) throw new LocalBrainException($"Local Brain needs at least {needed / 1024 / 1024:N0} MB of additional free storage for this setup.");
        if (!archiveVerified)
            await DownloadVerifiedAsync(LocalBrainCatalog.RuntimeUrl, RuntimeArchive, LocalBrainCatalog.RuntimeSizeBytes,
                LocalBrainCatalog.RuntimeSha256, "Downloading Windows inference runtime", modelId, progress, cancellationToken);

        if (!runtimeVerified)
        {
            string staged = Path.Combine(_root, "runtime-stage-" + Guid.NewGuid().ToString("N"));
            try
            {
                await ExtractRuntimeSafelyAsync(RuntimeArchive, staged, cancellationToken);
                if (Directory.Exists(RuntimeDirectory)) Directory.Move(RuntimeDirectory, RuntimeDirectory + ".previous-" + Guid.NewGuid().ToString("N"));
                Directory.Move(staged, RuntimeDirectory);
            }
            finally { DeleteOwnedTemporaryDirectory(staged); }
        }
        if (!modelVerified)
            await DownloadVerifiedAsync(model.DownloadUrl, ModelPath(modelId), model.SizeBytes, model.Sha256,
                "Downloading " + model.DisplayName, modelId, progress, cancellationToken);
        await VerifyAsync(modelId, progress, cancellationToken);
        foreach (var name in new[] { "llama-cpp-MIT.txt", "Qwen-Apache-2.0.txt" })
        {
            using var license = typeof(LocalBrainAssetStore).Assembly.GetManifestResourceStream("AMORA.Orbit.Assets.Licenses." + name)
                ?? throw new LocalBrainException("The packaged Local Brain license notices are missing. Reinstall AMORA before setup.");
            using var reader = new StreamReader(license);
            await WriteNoticeAsync(name, await reader.ReadToEndAsync(cancellationToken), cancellationToken);
        }
        await WriteNoticeAsync("SOURCES.txt",
            "llama.cpp " + LocalBrainCatalog.RuntimeVersion + " — MIT license: https://github.com/ggml-org/llama.cpp/blob/" + LocalBrainCatalog.RuntimeVersion + "/LICENSE\n" +
            "Bundled OpenMP license: runtime-" + LocalBrainCatalog.RuntimeVersion + "/LICENSE-LLVM-OpenMP\n" +
            "Qwen2.5 models — Apache 2.0: https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF and https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF\n" +
            "AMORA verifies exact artifact sizes and SHA-256 hashes before loading. No model is downloaded automatically.\n", cancellationToken);
    }

    private async Task WriteNoticeAsync(string name, string contents, CancellationToken cancellationToken)
    {
        string temporary = Path.Combine(_root, ".notice-" + Guid.NewGuid().ToString("N"));
        try
        {
            await using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            await using (var writer = new StreamWriter(output))
            {
                await writer.WriteAsync(contents.AsMemory(), cancellationToken);
                await writer.FlushAsync(cancellationToken);
                output.Flush(flushToDisk: true);
            }
            cancellationToken.ThrowIfCancellationRequested();
            File.Move(temporary, Path.Combine(_root, name), overwrite: true);
        }
        finally { try { File.Delete(temporary); } catch { } }
    }

    public static long RequiredSetupBytes(long modelBytes, bool modelVerified, bool archiveVerified, bool runtimeVerified) =>
        1024 * 1024 // Small, bounded license/source notices and filesystem overhead.
        + (modelVerified ? 0 : modelBytes)
        + (archiveVerified ? 0 : LocalBrainCatalog.RuntimeSizeBytes)
        + (runtimeVerified ? 0 : 256L * 1024 * 1024); // Maximum permitted extracted archive size.

    private async Task DownloadVerifiedAsync(string url, string destination, long expectedSize, string sha256, string message,
        string modelId, Action<LocalBrainSnapshot> progress, CancellationToken cancellationToken)
    {
        string temporary = destination + ".download-" + Guid.NewGuid().ToString("N");
        try
        {
            using var response = await _downloads.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            if (!response.IsSuccessStatusCode) throw new LocalBrainException("The official download is unavailable. Check your network and try again.");
            if (response.Content.Headers.ContentLength is long advertised && advertised != expectedSize)
                throw new LocalBrainException("The download size differs from the pinned official artifact. Nothing was installed.");
            await using (var input = await response.Content.ReadAsStreamAsync(cancellationToken))
            await using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 128 * 1024, true))
            {
                var buffer = new byte[128 * 1024];
                long total = 0, lastReported = -4 * 1024 * 1024;
                int read;
                while ((read = await input.ReadAsync(buffer, cancellationToken)) != 0)
                {
                    total += read;
                    if (total > expectedSize) throw new LocalBrainException("The download exceeded its expected size. Nothing was installed.");
                    await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
                    if (total - lastReported >= 4 * 1024 * 1024 || total == expectedSize)
                    { progress(new(LocalBrainState.Downloading, message, modelId, total, expectedSize)); lastReported = total; }
                }
                await output.FlushAsync(cancellationToken);
                output.Flush(flushToDisk: true);
            }
            if (!await VerifyArtifactAsync(temporary, expectedSize, sha256, cancellationToken))
                throw new LocalBrainException("The download failed SHA-256 verification. Nothing was installed.");
            cancellationToken.ThrowIfCancellationRequested();
            File.Move(temporary, destination, overwrite: true);
        }
        finally { try { File.Delete(temporary); } catch { } }
    }

    public static async Task<bool> VerifyArtifactAsync(string path, long expectedSize, string expectedSha256, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!File.Exists(path) || (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0 || new FileInfo(path).Length != expectedSize) return false;
        await using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 128 * 1024, true);
        var actual = await SHA256.HashDataAsync(input, cancellationToken);
        return Convert.ToHexString(actual).Equals(expectedSha256, StringComparison.OrdinalIgnoreCase);
    }

    public static async Task ExtractRuntimeSafelyAsync(string archive, string destination, CancellationToken cancellationToken = default)
    {
        if (Directory.Exists(destination)) throw new LocalBrainException("Runtime extraction requires a new staging directory.");
        using var zip = ZipFile.OpenRead(archive);
        ValidateRuntimeEntries(zip);
        Directory.CreateDirectory(destination);
        foreach (var entry in zip.Entries)
        {
            cancellationToken.ThrowIfCancellationRequested();
            await using var source = entry.Open();
            await using var target = new FileStream(Path.Combine(destination, entry.Name), FileMode.CreateNew, FileAccess.Write, FileShare.None, 128 * 1024, true);
            await source.CopyToAsync(target, cancellationToken);
        }
    }

    private static void ValidateRuntimeEntries(ZipArchive zip)
    {
        if (zip.Entries.Count is < 1 or > 128 || zip.Entries.Sum(e => e.Length) > 256L * 1024 * 1024
            || !zip.Entries.Any(e => e.FullName == "llama-server.exe"))
            throw new LocalBrainException("The runtime archive has an unexpected structure.");
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in zip.Entries)
        {
            if (entry.FullName != entry.Name || string.IsNullOrWhiteSpace(entry.Name) || entry.Name.Contains(':')
                || entry.Name is "." or ".." || !names.Add(entry.Name) || ((entry.ExternalAttributes >> 16) & 0xF000) == 0xA000)
                throw new LocalBrainException("An unsafe runtime archive path was rejected.");
        }
    }

    private async Task<bool> RuntimeFilesMatchArchiveAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(RuntimeArchive) || !Directory.Exists(RuntimeDirectory)) return false;
        if ((File.GetAttributes(RuntimeDirectory) & FileAttributes.ReparsePoint) != 0) return false;
        using var zip = ZipFile.OpenRead(RuntimeArchive);
        ValidateRuntimeEntries(zip);
        if (Directory.GetFiles(RuntimeDirectory).Length != zip.Entries.Count || Directory.GetDirectories(RuntimeDirectory).Length != 0) return false;
        foreach (var entry in zip.Entries)
        {
            string file = Path.Combine(RuntimeDirectory, entry.Name);
            if (!File.Exists(file) || (File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0 || new FileInfo(file).Length != entry.Length) return false;
            await using var input = entry.Open();
            string expected = Convert.ToHexString(await SHA256.HashDataAsync(input, cancellationToken));
            if (!await VerifyArtifactAsync(file, entry.Length, expected, cancellationToken)) return false;
        }
        return true;
    }

    public void DeleteModel(string modelId)
    {
        EnsureSafeRoot();
        string file = ModelPath(modelId);
        if (File.Exists(file) && (File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0)
            throw new LocalBrainException("A redirected model path cannot be deleted by AMORA.");
        File.Delete(file);
    }
    private void EnsureSafeRoot()
    {
        for (var folder = new DirectoryInfo(_root); folder != null; folder = folder.Parent)
            if (folder.Exists && (folder.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new LocalBrainException("Local Brain storage cannot use a redirected directory.");
    }
    private void DeleteOwnedTemporaryDirectory(string path)
    {
        try
        {
            string full = Path.GetFullPath(path);
            if (Path.GetDirectoryName(full) != _root || !Path.GetFileName(full).StartsWith("runtime-stage-", StringComparison.Ordinal)) return;
            if (Directory.Exists(full) && (File.GetAttributes(full) & FileAttributes.ReparsePoint) == 0) Directory.Delete(full, recursive: true);
        }
        catch { }
    }
}
