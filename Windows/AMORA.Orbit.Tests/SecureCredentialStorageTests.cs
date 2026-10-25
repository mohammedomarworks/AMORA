using System.Threading.Tasks;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class SecureCredentialStorageTests
{
    [Fact]
    public async Task InMemoryCredentialStorage_EndToEndLifecycle()
    {
        var storage = new InMemoryCredentialStorage();
        string target = "amora.ai.gemini.apikey";
        string secret = "test-secret-key-12345";

        Assert.False(await storage.HasCredentialAsync(target));
        Assert.Null(await storage.GetCredentialAsync(target));

        await storage.SetCredentialAsync(target, secret);

        Assert.True(await storage.HasCredentialAsync(target));
        Assert.Equal(secret, await storage.GetCredentialAsync(target));

        await storage.DeleteCredentialAsync(target);

        Assert.False(await storage.HasCredentialAsync(target));
        Assert.Null(await storage.GetCredentialAsync(target));
    }

    [Theory]
    [InlineData(null, "")]
    [InlineData("", "")]
    [InlineData("   ", "")]
    [InlineData("short", "••••••••")]
    [InlineData("12345678", "••••••••")]
    [InlineData("AIzaSyB_1234567890abcdefg", "AIzaSy...defg")]
    public void MaskSecret_MasksAppropriately(string? input, string expected)
    {
        string masked = WindowsCredentialStorage.MaskSecret(input);
        Assert.Equal(expected, masked);
    }

    [Fact]
    public void RedactSecret_ScrubsExactSecretFromLogsAndExceptions()
    {
        string key = "AIzaSy_TopSecret_Key_999";
        string logMessage = $"Error 401 occurred while calling API with key {key}. Request failed.";

        string safeLog = WindowsCredentialStorage.RedactSecret(logMessage, key);

        Assert.DoesNotContain(key, safeLog);
        Assert.Contains("[REDACTED_API_KEY]", safeLog);
    }
}
