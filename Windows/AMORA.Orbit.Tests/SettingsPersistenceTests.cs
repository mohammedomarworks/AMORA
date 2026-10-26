using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class SettingsPersistenceTests
{
    [Fact]
    public async Task FailedWrite_DoesNotEnableCloudContextOrReportSavedSettings()
    {
        string directory = Path.Combine(Path.GetTempPath(), "AMORA.Tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        string blocker = Path.Combine(directory, "not-a-directory");
        await File.WriteAllTextAsync(blocker, "test fixture");
        try
        {
            var settings = new AISettingsService(new InMemoryCredentialStorage(), Path.Combine(blocker, "settings.json"));
            bool changed = false;
            settings.SettingsChanged += (_, _) => changed = true;
            await Assert.ThrowsAnyAsync<IOException>(() => settings.SaveSettingsAsync(settings.CurrentSettings with { SendStatusContextToAI = true }));
            Assert.False(settings.CurrentSettings.SendStatusContextToAI);
            Assert.False(changed);
        }
        finally { Directory.Delete(directory, recursive: true); }
    }
}
