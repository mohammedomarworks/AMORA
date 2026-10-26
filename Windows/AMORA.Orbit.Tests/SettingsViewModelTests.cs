using System;
using System.Threading;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using AMORA.Orbit.ViewModels;
using Xunit;

namespace AMORA.Orbit.Tests;

public class SettingsViewModelTests
{
    private class MockAIProvider : IAIProvider
    {
        public string ProviderId => AISettings.ProviderGemini;
        public string DisplayName => "Mock Gemini";
        public bool IsConfigured { get; set; } = true;
        public bool TestShouldSucceed { get; set; } = true;

        public Task<string> GenerateResponseAsync(string prompt, CancellationToken cancellationToken = default) =>
            Task.FromResult("Response");

        public Task<ConnectionTestResult> TestConnectionAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult(TestShouldSucceed
                ? ConnectionTestResult.Success("Connected successfully.", TimeSpan.FromMilliseconds(45))
                : ConnectionTestResult.Failure("API key invalid."));
    }

    [Fact]
    public async Task SettingsViewModel_SaveAndClearLifecycle()
    {
        var credStorage = new InMemoryCredentialStorage();
        var settingsService = new AISettingsService(credStorage);
        var mockProvider = new MockAIProvider();

        var vm = new SettingsViewModel(settingsService, mockProvider);

        Assert.False(vm.IsOpen);
        vm.ToggleOpen();
        Assert.True(vm.IsOpen);

        Assert.False(vm.HasSavedKey);

        vm.ApiKeyInput = "AIzaSy_Secret_NewKey_4567";
        vm.ModelName = "gemini-2.5-flash";

        await vm.SaveAsync();

        Assert.True(vm.HasSavedKey);
        Assert.Equal(string.Empty, vm.ApiKeyInput);
        Assert.Contains("AIzaSy", vm.MaskedApiKey);
        Assert.Contains("saved", vm.TestStatusMessage, StringComparison.OrdinalIgnoreCase);

        // Test Connection
        await vm.TestConnectionAsync();
        Assert.Contains("Connected", vm.TestStatusMessage);

        // Clear Key
        await vm.ClearKeyAsync();
        Assert.False(vm.HasSavedKey);
        Assert.Equal(string.Empty, vm.MaskedApiKey);
        Assert.Contains("cleared", vm.TestStatusMessage, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task SettingsViewModel_TestConnection_ReportsFailureAccurately()
    {
        var credStorage = new InMemoryCredentialStorage();
        var settingsService = new AISettingsService(credStorage);
        var mockProvider = new MockAIProvider { TestShouldSucceed = false };

        var vm = new SettingsViewModel(settingsService, mockProvider);

        await vm.TestConnectionAsync();

        Assert.Contains("invalid", vm.TestStatusMessage, StringComparison.OrdinalIgnoreCase);
        Assert.Equal("#FF453A", vm.TestStatusColor); // Red
    }

    [Fact]
    public async Task SettingsViewModel_SendStatusContextToAI_DefaultsFalseAndPersists()
    {
        var credStorage = new InMemoryCredentialStorage();
        var settingsService = new AISettingsService(credStorage);
        var mockProvider = new MockAIProvider();

        var vm = new SettingsViewModel(settingsService, mockProvider);

        // Privacy check: must default to false!
        Assert.False(vm.SendStatusContextToAI);

        // Toggle on and save
        vm.SendStatusContextToAI = true;
        await vm.SaveAsync();

        Assert.True(settingsService.CurrentSettings.SendStatusContextToAI);

        // Verify newly constructed ViewModel reads persisted setting
        var vm2 = new SettingsViewModel(settingsService, mockProvider);
        Assert.True(vm2.SendStatusContextToAI);
    }

    [Fact]
    public async Task SettingsViewModel_EnableProactiveSuggestions_DefaultsFalseAndPersists()
    {
        var credStorage = new InMemoryCredentialStorage();
        var settingsService = new AISettingsService(credStorage);
        var mockProvider = new MockAIProvider();

        var vm = new SettingsViewModel(settingsService, mockProvider);

        // Opt-in check: must default to false!
        Assert.False(vm.EnableProactiveSuggestions);

        // Toggle on and save
        vm.EnableProactiveSuggestions = true;
        await vm.SaveAsync();

        Assert.True(settingsService.CurrentSettings.EnableProactiveSuggestions);

        // Verify newly constructed ViewModel reads persisted setting
        var vm2 = new SettingsViewModel(settingsService, mockProvider);
        Assert.True(vm2.EnableProactiveSuggestions);
    }
}
