using System;
using System.IO;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class PublicBetaReadinessTests : IDisposable
{
    private readonly string _testDir;

    public PublicBetaReadinessTests()
    {
        _testDir = Path.Combine(Path.GetTempPath(), "AMORA_Beta_Tests_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_testDir);
    }

    public void Dispose()
    {
        try
        {
            if (Directory.Exists(_testDir))
            {
                Directory.Delete(_testDir, true);
            }
        }
        catch
        {
        }
    }

    [Fact]
    public void CrashLogger_WritesSanitizedCrashReportToFile()
    {
        string logDir = Path.Combine(_testDir, "Logs");
        string rawSecretKey = "AIzaSy1234567890abcdef1234567890abcdef1";
        var simulatedException = new InvalidOperationException(
            $"Network connection failed while authenticating with key {rawSecretKey} and bearer token: secret_token_xyz"
        );

        CrashLogger.LogException(simulatedException, logDir, "window-activation");

        string logFile = Path.Combine(logDir, "crash.log");
        Assert.True(File.Exists(logFile));

        string content = File.ReadAllText(logFile);
        Assert.Contains("v0.6.0-beta.2", content);
        Assert.Contains("InvalidOperationException", content);
        Assert.Contains("Timestamp:", content);
        Assert.Contains("StartupStage: window-activation", content);

        // Ensure real API key is redacted
        Assert.DoesNotContain(rawSecretKey, content);
        Assert.Contains("AIzaSy*********************************", content);
        Assert.DoesNotContain("secret_token_xyz", content);
    }

    [Fact]
    public void CrashLogger_SanitizeMessage_RedactsAuthorizationHeaders()
    {
        string input = "Request Authorization: Bearer eyJhbGciOiJIUzI1NiJ9; password=SensitiveValue123";
        string sanitized = CrashLogger.SanitizeMessage(input);

        Assert.DoesNotContain("eyJhbGciOiJIUzI1NiJ9", sanitized);
        Assert.DoesNotContain("SensitiveValue123", sanitized);
        Assert.Contains("Authorization: [REDACTED]", sanitized);
    }

    [Fact]
    public void CrashLogger_SanitizeMessage_RedactsSensitiveTokenPatterns()
    {
        string input = "Request Authorization: Bearer eyJhbGciOiJIUzI1NiJ9 with password = MySecretPassword123";
        string sanitized = CrashLogger.SanitizeMessage(input);

        Assert.DoesNotContain("MySecretPassword123", sanitized);
        Assert.Contains("[REDACTED]", sanitized);
    }

    [Fact]
    public void AISettingsService_WithCorruptedJsonFile_FallsBackToDefaultCleanly()
    {
        string corruptedFilePath = Path.Combine(_testDir, "ai_settings_corrupted.json");
        File.WriteAllText(corruptedFilePath, "{ this is not valid JSON content ::: broken [");

        var storage = new InMemoryCredentialStorage();
        var service = new AISettingsService(storage, corruptedFilePath);

        Assert.NotNull(service.CurrentSettings);
        Assert.Equal(AISettings.ProviderLocalBrain, service.CurrentSettings.SelectedProvider);
        Assert.Empty(service.CurrentSettings.Model);
        Assert.False(service.CurrentSettings.SendStatusContextToAI);
        Assert.False(service.CurrentSettings.EnableProactiveSuggestions);
    }

    [Fact]
    public async Task LocalAutomationService_WithCorruptedJsonFile_PreservesRecoveryCopyAndReportsFailure()
    {
        string corruptedFilePath = Path.Combine(_testDir, "automations_corrupted.json");
        File.WriteAllText(corruptedFilePath, "<<<< corrupt XML or invalid JSON syntax >>>>");

        using var timerService = new StandardTimerService();
        var mediaService = new PreviewMediaService();
        var storage = new InMemoryCredentialStorage();
        var aiSettingsService = new AISettingsService(storage, System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AMORA.Tests", System.Guid.NewGuid().ToString("N"), "settings.json"));
        var batteryService = new PreviewBatteryService();
        using var suggestionService = new ProactiveSuggestionService(timerService, batteryService, aiSettingsService);

        using var service = new LocalAutomationService(
            timerService,
            mediaService,
            suggestionService,
            corruptedFilePath
        );

        var failure = await Assert.ThrowsAsync<AutomationPersistenceException>(() => service.LoadAutomationsAsync());

        Assert.NotNull(service.Automations);
        Assert.Empty(service.Automations);
        Assert.Contains("recovery copy", failure.Message);
        var recovery = Assert.Single(Directory.GetFiles(_testDir, "automations_corrupted.json.corrupt-*"));
        Assert.Equal(File.ReadAllText(corruptedFilePath), File.ReadAllText(recovery));
    }

    [Fact]
    public async Task WindowsCredentialStorage_SetCredential_EmptySecret_DeletesTargetCleanly()
    {
        string credDir = Path.Combine(_testDir, "Credentials");
        var storage = new WindowsCredentialStorage(credDir);

        await storage.SetCredentialAsync("test.target", "secret_value_123");
        Assert.True(await storage.HasCredentialAsync("test.target"));

        // Setting empty secret should remove it
        await storage.SetCredentialAsync("test.target", "");
        Assert.False(await storage.HasCredentialAsync("test.target"));
        Assert.Null(await storage.GetCredentialAsync("test.target"));
    }

    [Fact]
    public async Task WindowsCredentialStorage_CorruptedCipherBytes_ReturnsNullCleanly()
    {
        string credDir = Path.Combine(_testDir, "Credentials");
        var storage = new WindowsCredentialStorage(credDir);

        await storage.SetCredentialAsync("corrupt.target", "valid_secret");
        Assert.True(await storage.HasCredentialAsync("corrupt.target"));

        // Overwrite file with invalid random non-cipher bytes
        string filePath = Path.Combine(credDir, "corrupt_target.dat");
        Assert.True(File.Exists(filePath));
        File.WriteAllBytes(filePath, new byte[] { 0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x11, 0x22 });

        // GetCredentialAsync should catch failure and return null without crashing
        string? result = await storage.GetCredentialAsync("corrupt.target");
        Assert.Null(result);
    }

    [Fact]
    public void WindowsCredentialStorage_RedactSecret_HandlesEdgeCases()
    {
        Assert.Equal(string.Empty, WindowsCredentialStorage.RedactSecret("", "secret"));
        Assert.Equal("normal message", WindowsCredentialStorage.RedactSecret("normal message", null));
        Assert.Equal("short", WindowsCredentialStorage.RedactSecret("short", "ab")); // Too short to redact safely

        string message = "Error: Invalid API key: AIzaSy_Secret_Value_12345 in call.";
        string redacted = WindowsCredentialStorage.RedactSecret(message, "AIzaSy_Secret_Value_12345");
        Assert.DoesNotContain("AIzaSy_Secret_Value_12345", redacted);
        Assert.Contains("[REDACTED_API_KEY]", redacted);
    }
}
