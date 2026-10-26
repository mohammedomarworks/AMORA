namespace AMORA.Orbit.Services.Implementations;

/// <summary>Local references only. No URI, network share, device namespace or shell command.</summary>
public static class WorkspacePathPolicy
{
    private static readonly HashSet<string> OpenableExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".txt", ".md", ".pdf", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tif", ".tiff",
        ".mp3", ".wav", ".flac", ".m4a", ".ogg", ".mp4", ".mov", ".mkv", ".webm",
        ".docx", ".xlsx", ".pptx", ".odt", ".ods", ".odp", ".csv", ".rtf"
    };

    public static bool TryNormalize(string? input, out string path)
    {
        path = string.Empty;
        if (string.IsNullOrWhiteSpace(input) || input.Length > 32760) return false;
        string value = input.Trim();
        // Requiring a drive-qualified path also excludes UNC, file:, http:, shell: and relative names.
        if (value.Length < 3 || !char.IsAsciiLetter(value[0]) || value[1] != ':' ||
            (value[2] != '\\' && value[2] != '/') || value[2..].Contains(':') || value.Any(char.IsControl)) return false;
        try
        {
            path = Path.GetFullPath(value);
            if (path.Split(Path.DirectorySeparatorChar).Skip(1).Any(part =>
                part.EndsWith(' ') || part.EndsWith('.') || IsDeviceName(part))) return false;
            return true;
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException) { return false; }
    }

    public static bool CanOpenFile(string path) => OpenableExtensions.Contains(Path.GetExtension(path));

    public static bool HasReparsePoint(string path)
    {
        try
        {
            for (string? cursor = path; !string.IsNullOrEmpty(cursor); cursor = Directory.GetParent(cursor)?.FullName)
                if ((File.GetAttributes(cursor) & FileAttributes.ReparsePoint) != 0) return true;
            return false;
        }
        catch { return true; }
    }

    private static bool IsDeviceName(string part)
    {
        var name = part.Split('.')[0].ToUpperInvariant();
        return name is "CON" or "PRN" or "AUX" or "NUL" ||
            name.Length == 4 && (name.StartsWith("COM") || name.StartsWith("LPT")) && name[3] is >= '1' and <= '9';
    }
}
