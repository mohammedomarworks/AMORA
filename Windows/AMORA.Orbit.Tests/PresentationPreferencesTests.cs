using System.Text.Json;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Implementations;
using AMORA.Orbit.ViewModels;
using Xunit;

namespace AMORA.Orbit.Tests;

public sealed class PresentationPreferencesTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), "AmoraPresentationTests", Guid.NewGuid().ToString("N"));
    private string FilePath => Path.Combine(_directory, "presentation.json");

    [Fact]
    public async Task ValidPreferencesRoundTripEveryCategoryWithoutChangingOnLoad()
    {
        var value = new PresentationPreferences(Theme: "Ocean", MascotSize: 40, SurfaceOpacity: .6,
            MotionIntensity: .3, HoverToExpand: false, AutoCollapseSeconds: 8, SleepMode: false,
            IdleTimeoutSeconds: 120, AvoidFullscreen: false, SoundEnabled: false, SoundVolume: .2,
            MusicEnabled: false, TimerEnabled: false, BatteryEnabled: false, SystemMonitorEnabled: false,
            BrowserBridgeEnabled: true);
        var store = new PresentationPreferencesStore(FilePath);
        await store.SaveAsync(value);
        Assert.Equal(value, store.Current);
        var restored = new PresentationPreferencesStore(FilePath);
        Assert.Equal(value, restored.Current);
        Assert.Null(restored.LoadError);
        Assert.Empty(Directory.GetFiles(_directory, "*.tmp"));
    }

    public static IEnumerable<object[]> InvalidPreferences()
    {
        yield return [new PresentationPreferences(Theme: "Unknown")];
        yield return [new PresentationPreferences(MascotSize: 23)];
        yield return [new PresentationPreferences(MascotSize: 49)];
        yield return [new PresentationPreferences(MascotSize: double.NaN)];
        yield return [new PresentationPreferences(SurfaceOpacity: .49)];
        yield return [new PresentationPreferences(SurfaceOpacity: double.PositiveInfinity)];
        yield return [new PresentationPreferences(MotionIntensity: -1)];
        yield return [new PresentationPreferences(MotionIntensity: 1.1)];
        yield return [new PresentationPreferences(AutoCollapseSeconds: .1)];
        yield return [new PresentationPreferences(AutoCollapseSeconds: 16)];
        yield return [new PresentationPreferences(IdleTimeoutSeconds: 29)];
        yield return [new PresentationPreferences(IdleTimeoutSeconds: 1801)];
        yield return [new PresentationPreferences(SoundVolume: -.1)];
        yield return [new PresentationPreferences(SoundVolume: 1.1)];
    }

    [Theory]
    [MemberData(nameof(InvalidPreferences))]
    public async Task InvalidRangesNeverChangePersistedOrActivePreferences(PresentationPreferences invalid)
    {
        var store = new PresentationPreferencesStore(FilePath);
        var original = new PresentationPreferences(Theme: "Matrix");
        await store.SaveAsync(original);
        string previousFile = await File.ReadAllTextAsync(FilePath);
        await Assert.ThrowsAsync<ArgumentException>(() => store.SaveAsync(invalid));
        Assert.Equal(original, store.Current);
        Assert.Equal(previousFile, await File.ReadAllTextAsync(FilePath));
        Assert.Empty(Directory.GetFiles(_directory, "*.tmp"));
    }

    [Fact]
    public async Task FailedAtomicReplacementLeavesPreviousFileAndActiveStateIntact()
    {
        var store = new PresentationPreferencesStore(FilePath);
        var original = new PresentationPreferences(Theme: "Ocean");
        await store.SaveAsync(original);
        byte[] previous = await File.ReadAllBytesAsync(FilePath);
        using (var held = new FileStream(FilePath, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            var failure = await Record.ExceptionAsync(() => store.SaveAsync(original with { Theme = "Bubblegum" }));
            Assert.True(failure is IOException or UnauthorizedAccessException,
                $"Expected an operating-system file replacement failure, got {failure?.GetType().Name ?? "success"}.");
        }
        Assert.Equal(original, store.Current);
        Assert.Equal(previous, await File.ReadAllBytesAsync(FilePath));
        Assert.Empty(Directory.GetFiles(_directory, "*.tmp"));
    }

    [Fact]
    public async Task CorruptPreferencesArePreservedBeforeReplacementAndValidSaveRecovers()
    {
        Directory.CreateDirectory(_directory);
        const string corrupt = "{ malformed previous preferences";
        await File.WriteAllTextAsync(FilePath, corrupt);
        var store = new PresentationPreferencesStore(FilePath);
        Assert.NotNull(store.LoadError);
        Assert.Equal(new PresentationPreferences(), store.Current);
        Assert.Equal(corrupt, await File.ReadAllTextAsync(FilePath));
        var replacement = new PresentationPreferences(Theme: "Minimal");
        await store.SaveAsync(replacement);
        string recovery = Assert.Single(Directory.GetFiles(_directory, "presentation.json.recovery-*"));
        Assert.Equal(corrupt, await File.ReadAllTextAsync(recovery));
        Assert.Equal(replacement, new PresentationPreferencesStore(FilePath).Current);
        Assert.Null(store.LoadError);
    }

    [Fact]
    public async Task FailedCorruptBackupDoesNotOverwriteOriginalOrClearError()
    {
        Directory.CreateDirectory(_directory);
        const string corrupt = "damaged original";
        await File.WriteAllTextAsync(FilePath, corrupt);
        var store = new PresentationPreferencesStore(FilePath);
        using (var held = new FileStream(FilePath, FileMode.Open, FileAccess.Read, FileShare.None))
            await Assert.ThrowsAnyAsync<IOException>(() => store.SaveAsync(new PresentationPreferences(Theme: "Ocean")));
        Assert.Equal(corrupt, await File.ReadAllTextAsync(FilePath));
        Assert.NotNull(store.LoadError);
        Assert.Equal("Midnight", store.Current.Theme);
    }

    [Fact]
    public async Task OutOfRangePersistedDocumentIsNotSilentlyTrusted()
    {
        Directory.CreateDirectory(_directory);
        string invalid = JsonSerializer.Serialize(new PresentationPreferences(SurfaceOpacity: 2));
        await File.WriteAllTextAsync(FilePath, invalid);
        var store = new PresentationPreferencesStore(FilePath);
        Assert.NotNull(store.LoadError);
        Assert.Equal(.85, store.Current.SurfaceOpacity);
        Assert.Equal(invalid, await File.ReadAllTextAsync(FilePath));
    }

    [Fact]
    public async Task ConcurrentSavesLeaveCompleteJsonMatchingPublishedSnapshot()
    {
        var store = new PresentationPreferencesStore(FilePath);
        var values = PresentationPreferences.Themes.Select(theme => new PresentationPreferences(Theme: theme)).ToArray();
        await Task.WhenAll(values.Select(store.SaveAsync));
        Assert.Contains(store.Current, values);
        Assert.Equal(store.Current, new PresentationPreferencesStore(FilePath).Current);
        Assert.Empty(Directory.GetFiles(_directory, "*.tmp"));
    }

    [Fact]
    public async Task PreviewIsImmediateButDoesNotPersistUntilExplicitSave()
    {
        var store = new PresentationPreferencesStore(FilePath);
        using var vm = new PresentationViewModel(store);
        int previews = 0;
        vm.PreviewChanged += (_, _) => previews++;
        vm.Theme = "Matrix";
        vm.MascotSize = 42;
        Assert.Equal(2, previews);
        Assert.Equal("#35EF78", vm.AccentHex);
        Assert.Equal("42 pt", vm.SizeLabel);
        Assert.Contains("Preview", vm.Status);
        Assert.False(File.Exists(FilePath));
        Assert.Equal("Midnight", store.Current.Theme);
        await vm.SaveAsync();
        Assert.Equal(vm.Value, new PresentationPreferencesStore(FilePath).Current);
        Assert.Contains("saved", vm.Status);
    }

    [Fact]
    public async Task SaveCapturesSubmittedSnapshotWithoutSavingLaterPreview()
    {
        var store = new PresentationPreferencesStore(FilePath);
        using var vm = new PresentationViewModel(store);
        vm.Theme = "Ocean";
        var submitted = vm.Value;
        var saving = vm.SaveAsync();
        vm.Theme = "Bubblegum";
        await saving;
        Assert.Equal(submitted, new PresentationPreferencesStore(FilePath).Current);
        Assert.Equal("Bubblegum", vm.Theme);
        Assert.Contains("Preview", vm.Status);
    }

    [Fact]
    public async Task FailedSaveKeepsPreviewAndTruthfulStatusWithoutChangingSavedState()
    {
        var store = new PresentationPreferencesStore(FilePath);
        await store.SaveAsync(new PresentationPreferences());
        using var vm = new PresentationViewModel(store);
        vm.Theme = "Ocean";
        using (var held = new FileStream(FilePath, FileMode.Open, FileAccess.Read, FileShare.Read)) await vm.SaveAsync();
        Assert.Equal("Ocean", vm.Theme);
        Assert.Equal("Midnight", store.Current.Theme);
        Assert.Contains("could not be saved", vm.Status);
        Assert.Equal("Midnight", new PresentationPreferencesStore(FilePath).Current.Theme);
    }

    [Fact]
    public async Task DisposedViewModelCannotPreviewNotifyOrStartNewSave()
    {
        var vm = new PresentationViewModel(new PresentationPreferencesStore(FilePath));
        vm.Dispose();
        int changes = 0, previews = 0;
        vm.PropertyChanged += (_, _) => changes++;
        vm.PreviewChanged += (_, _) => previews++;
        vm.Theme = "Ocean";
        vm.MotionIntensity = 0;
        await vm.SaveAsync();
        Assert.Equal("Midnight", vm.Theme);
        Assert.Equal(0, changes);
        Assert.Equal(0, previews);
        Assert.False(File.Exists(FilePath));
    }

    [Fact]
    public async Task FreshAISettingsDefaultToLocalBrainWithoutCloudConsentOrCredentialAccess()
    {
        var service = new AISettingsService(new InMemoryCredentialStorage(), Path.Combine(_directory, "new-ai.json"));
        var settings = await service.LoadSettingsAsync();
        Assert.Equal(AISettings.ProviderLocalBrain, settings.SelectedProvider);
        Assert.Empty(settings.Model);
        Assert.Equal(LocalBrainCatalog.DefaultModelId, settings.LocalBrainModelId);
        Assert.False(settings.SendStatusContextToAI);
        Assert.False(settings.EnableProactiveSuggestions);
        Assert.False(settings.EnableClipboardHistory);
        Assert.False(new PresentationPreferencesStore(Path.Combine(_directory, "new-presentation.json")).Current.BrowserBridgeEnabled);
        Assert.False(File.Exists(Path.Combine(_directory, "new-ai.json")));
    }

    [Theory]
    [InlineData(AISettings.ProviderGemini)]
    [InlineData(AISettings.ProviderOpenAI)]
    [InlineData(AISettings.ProviderAnthropic)]
    [InlineData(AISettings.ProviderLocalStub)]
    public async Task ExistingSavedProviderChoiceIsPreserved(string provider)
    {
        Directory.CreateDirectory(_directory);
        string path = Path.Combine(_directory, "existing-ai.json");
        var saved = new AISettings(SelectedProvider: provider, Model: "previous-user-model");
        await File.WriteAllTextAsync(path, JsonSerializer.Serialize(saved));
        var service = new AISettingsService(new InMemoryCredentialStorage(), path);
        Assert.Equal(saved, service.CurrentSettings);
        Assert.Equal(saved, await service.LoadSettingsAsync());
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory)) Directory.Delete(_directory, recursive: true);
    }
}
