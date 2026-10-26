using System.Text.RegularExpressions;
using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Implementations;

public static class NavigationCommandParser
{
    public static SafeNavigationRequest? Parse(string input)
    {
        if (string.IsNullOrWhiteSpace(input) || input.Length > 300) return null;
        string text = Regex.Replace(input.Trim().ToLowerInvariant(), @"\s+", " ");
        text = Regex.Replace(text, @"^(?:(?:hey )?amora[, ]+|please |(?:can|could) you (?:please )?)+", "");
        var match = Regex.Match(text, @"^(?:open|launch|show) (.+?)[.!?]*$");
        if (!match.Success) return null;
        string target = match.Groups[1].Value.Trim();
        // These belong to AMORA workspace routing, never to an OS launcher.
        if (target is "settings" or "notes" or "clipboard" or "files" or "file shelf" or "github" or "automations" or "home" or "dashboard") return null;
        target = Regex.Replace(target, @"^(?:my|the) ", "");
        target = Regex.Replace(target, @" folder$", "");
        return target switch
        {
            "calculator" or "calc" => new(Application: SafeApplication.Calculator),
            "notepad" => new(Application: SafeApplication.Notepad),
            "paint" or "microsoft paint" => new(Application: SafeApplication.Paint),
            "windows settings" or "system settings" => new(Application: SafeApplication.WindowsSettings),
            "downloads" or "download" => new(Folder: SafeKnownFolder.Downloads),
            "documents" or "document" or "docs" => new(Folder: SafeKnownFolder.Documents),
            "desktop" => new(Folder: SafeKnownFolder.Desktop),
            "home" or "home directory" or "user folder" => new(Folder: SafeKnownFolder.Home),
            _ => new(Unsupported: true)
        };
    }
}
