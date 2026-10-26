namespace AMORA.Orbit.Models;

public enum SafeApplication { Calculator, Notepad, Paint, WindowsSettings }
public enum SafeKnownFolder { Downloads, Documents, Desktop, Home }
public sealed record SafeNavigationRequest(SafeApplication? Application = null, SafeKnownFolder? Folder = null, bool Unsupported = false)
{
    public string DisplayName => Application == SafeApplication.WindowsSettings ? "Windows Settings" : Application?.ToString() ?? Folder?.ToString() ?? "that destination";
}
