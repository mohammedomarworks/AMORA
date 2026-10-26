using System;
using System.IO;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Implementations;
using AMORA.Orbit.ViewModels;
using Xunit;

namespace AMORA.Orbit.Tests;

public class AutomationsViewModelTests
{
    private (LocalAutomationService Service, AutomationsViewModel ViewModel, string FilePath) CreateTestContext()
    {
        var tempFile = Path.Combine(Path.GetTempPath(), $"amora_vm_test_{Guid.NewGuid():N}.json");
        var timer = new StandardTimerService();
        var media = new PreviewMediaService();
        var suggestion = new ProactiveSuggestionService();

        var service = new LocalAutomationService(timer, media, suggestion, tempFile);
        var vm = new AutomationsViewModel(service);

        return (service, vm, tempFile);
    }

    [Fact]
    public void AutomationsViewModel_InitialState_IsOpenFalseAndEmpty()
    {
        var (service, vm, path) = CreateTestContext();
        try
        {
            Assert.False(vm.IsOpen);
            Assert.False(vm.HasAutomations);
            Assert.Empty(vm.Items);

            vm.ToggleOpen();
            Assert.True(vm.IsOpen);
        }
        finally
        {
            vm.Dispose();
            service.Dispose();
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task AutomationsViewModel_CreateAutomation_AddsToItemsAndUpdatesStatus()
    {
        var (service, vm, path) = CreateTestContext();
        try
        {
            vm.NewName = "Drink Water";
            vm.NewTriggerTypeIndex = 1; // Every 30 mins
            vm.NewActionTypeIndex = 0;  // Reminder
            vm.NewReminderMessage = "Hydration checkpoint";

            await vm.CreateAutomationAsync();

            Assert.True(vm.HasAutomations);
            Assert.Single(vm.Items);
            Assert.Equal("Drink Water", vm.Items[0].Name);
            Assert.Contains("Every 30", vm.Items[0].TriggerText);
            Assert.Contains("Hydration checkpoint", vm.Items[0].ActionText);
            Assert.Contains("Created 'Drink Water'", vm.StatusMessage);
        }
        finally
        {
            vm.Dispose();
            service.Dispose();
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task AutomationsViewModel_CreateAutomation_ValidationFailsIfEmptyName()
    {
        var (service, vm, path) = CreateTestContext();
        try
        {
            vm.NewName = "   ";
            await vm.CreateAutomationAsync();

            Assert.False(vm.HasAutomations);
            Assert.Contains("provide an automation name", vm.StatusMessage);
        }
        finally
        {
            vm.Dispose();
            service.Dispose();
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task AutomationsViewModel_ToggleAndRunNowAndLifecycle()
    {
        var (service, vm, path) = CreateTestContext();
        try
        {
            vm.NewName = "Focus Timer";
            vm.NewTriggerTypeIndex = 0; // Daily
            vm.NewActionTypeIndex = 1;  // Start 25m Timer

            await vm.CreateAutomationAsync();
            var item = vm.Items[0];

            // Run Now
            await vm.RunNowAsync(item.Id);
            Assert.Contains("Started", vm.StatusMessage);

            // Toggle Disabled
            await vm.ToggleEnabledAsync(item.Id);
            Assert.False(vm.Items[0].IsEnabled);
            Assert.Contains("toggled", vm.StatusMessage);

            // Delete
            await vm.DeleteAsync(item.Id);
            Assert.Empty(vm.Items);
            Assert.Contains("deleted", vm.StatusMessage);
        }
        finally
        {
            vm.Dispose();
            service.Dispose();
            if (File.Exists(path)) File.Delete(path);
        }
    }
}
