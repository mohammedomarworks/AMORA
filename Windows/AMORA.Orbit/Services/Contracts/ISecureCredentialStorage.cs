using System.Threading.Tasks;

namespace AMORA.Orbit.Services.Contracts;

/// <summary>
/// Contract for securely storing sensitive credentials (e.g. API keys)
/// using Windows DPAPI CurrentUser user-encrypted storage.
/// </summary>
public interface ISecureCredentialStorage
{
    Task SetCredentialAsync(string target, string secret);
    Task<string?> GetCredentialAsync(string target);
    Task DeleteCredentialAsync(string target);
    Task<bool> HasCredentialAsync(string target);
}
