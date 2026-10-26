using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface IClipboardHistoryService : IDisposable
{
    bool IsEnabled { get; }
    IReadOnlyList<ClipboardEntry> Entries { get; }
    string StatusText { get; }
    event EventHandler? Changed;
    void SetEnabled(bool enabled);
    void Clear();
    bool Remove(string id);
    Task<bool> CopyAsync(string id);
}

/// <summary>Metadata must be inspected before ReadTextAsync is called.</summary>
public interface IClipboardContentSnapshot
{
    IReadOnlyList<string> Formats { get; }
    bool HasText { get; }
    Task<string?> ReadTextAsync(CancellationToken cancellationToken);
}

/// <summary>Injectable OS boundary; tests never access the user's clipboard.</summary>
public interface IClipboardSource : IDisposable
{
    event EventHandler? ContentChanged;
    Task<IClipboardContentSnapshot?> GetSnapshotAsync(CancellationToken cancellationToken);
    Task<bool> WriteTextAsync(string text, CancellationToken cancellationToken);
}
