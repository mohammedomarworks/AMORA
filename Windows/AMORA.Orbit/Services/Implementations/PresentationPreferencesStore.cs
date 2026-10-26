using System.Text.Json;
using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Implementations;

public sealed class PresentationPreferencesStore
{
    private readonly string _path;
    private readonly SemaphoreSlim _gate = new(1, 1);
    public PresentationPreferences Current { get; private set; } = new();
    public string? LoadError { get; private set; }
    public PresentationPreferencesStore(string? path = null)
    {
        _path = path ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AMORA", "presentation.json");
        try
        {
            if (File.Exists(_path))
            {
                if (new FileInfo(_path).Length > 32_768) throw new IOException();
                Current = (JsonSerializer.Deserialize<PresentationPreferences>(File.ReadAllText(_path)) ?? throw new IOException()).Validate();
            }
        }
        catch { LoadError = "Presentation preferences could not be loaded. Defaults are active; the original file is preserved."; }
    }
    public async Task SaveAsync(PresentationPreferences value)
    {
        value.Validate();
        await _gate.WaitAsync();
        string temp = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(_path))!);
            if (LoadError != null && File.Exists(_path))
                File.Copy(_path, _path + ".recovery-" + Guid.NewGuid().ToString("N"));
            await File.WriteAllTextAsync(temp, JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temp, _path, true);
            Current = value;
            LoadError = null;
        }
        finally
        {
            try { if (File.Exists(temp)) File.Delete(temp); } catch { }
            _gate.Release();
        }
    }
}
