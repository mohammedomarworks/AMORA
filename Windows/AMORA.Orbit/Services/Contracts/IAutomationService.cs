using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface IAutomationService
{
    IReadOnlyList<AmoraAutomation> Automations { get; }

    event EventHandler<IReadOnlyList<AmoraAutomation>>? AutomationsChanged;
    event EventHandler<AutomationExecutionResult>? AutomationFired;

    Task<AmoraAutomation> CreateAutomationAsync(string name, AutomationTrigger trigger, AutomationAction action, bool isEnabled = true);
    Task<bool> UpdateAutomationAsync(AmoraAutomation automation);
    Task<bool> ToggleEnabledAsync(string id);
    Task<bool> DeleteAutomationAsync(string id);
    Task<AutomationExecutionResult> RunManuallyAsync(string id);
    Task LoadAutomationsAsync();
}
