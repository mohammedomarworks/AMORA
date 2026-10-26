using AMORA.Orbit.Services.Contracts;
using Windows.Storage;
using Windows.System;

namespace AMORA.Orbit.Services.Implementations;

public sealed class WindowsWorkspaceLauncher : IWorkspaceLauncher
{
    public async Task<bool> OpenAsync(string localPath, bool isFolder, bool reveal, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!WorkspacePathPolicy.TryNormalize(localPath, out string path) || WorkspacePathPolicy.HasReparsePoint(path)) return false;
        if (isFolder)
        {
            var folder = await StorageFolder.GetFolderFromPathAsync(path).AsTask(cancellationToken);
            return await Launcher.LaunchFolderAsync(folder).AsTask(cancellationToken);
        }
        if (reveal)
        {
            var file = await StorageFile.GetFileFromPathAsync(path).AsTask(cancellationToken);
            var folder = await file.GetParentAsync().AsTask(cancellationToken);
            if (folder == null) return false;
            var options = new FolderLauncherOptions();
            options.ItemsToSelect.Add(file);
            return await Launcher.LaunchFolderAsync(folder, options).AsTask(cancellationToken);
        }
        if (!WorkspacePathPolicy.CanOpenFile(path)) return false;
        var document = await StorageFile.GetFileFromPathAsync(path).AsTask(cancellationToken);
        return await Launcher.LaunchFileAsync(document).AsTask(cancellationToken);
    }
}
