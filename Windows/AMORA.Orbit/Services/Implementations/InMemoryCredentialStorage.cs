using System.Collections.Concurrent;
using System.Threading.Tasks;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>
/// In-memory credential storage implementation for tests and transient scenarios.
/// </summary>
public class InMemoryCredentialStorage : ISecureCredentialStorage
{
    private readonly ConcurrentDictionary<string, string> _store = new();

    public Task SetCredentialAsync(string target, string secret)
    {
        if (string.IsNullOrWhiteSpace(secret))
        {
            _store.TryRemove(target, out _);
        }
        else
        {
            _store[target] = secret.Trim();
        }
        return Task.CompletedTask;
    }

    public Task<string?> GetCredentialAsync(string target)
    {
        _store.TryGetValue(target, out string? value);
        return Task.FromResult(value);
    }

    public Task DeleteCredentialAsync(string target)
    {
        _store.TryRemove(target, out _);
        return Task.CompletedTask;
    }

    public Task<bool> HasCredentialAsync(string target)
    {
        return Task.FromResult(_store.ContainsKey(target));
    }
}
