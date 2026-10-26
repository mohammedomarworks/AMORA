using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using AMORA.Orbit.ViewModels;
using Xunit;

namespace AMORA.Orbit.Tests;

public sealed class WorkspaceToolsTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), "AmoraWorkspaceTests", Guid.NewGuid().ToString("N"));
    private string LocalFile(string name, string text = "Original content")
    {
        Directory.CreateDirectory(_directory);
        string path = Path.Combine(_directory, name);
        File.WriteAllText(path, text);
        return path;
    }

    [Fact]
    public async Task Notes_PreserveDistinctMatchingRecords_SearchCaseInsensitivelyNewestFirst()
    {
        var now = DateTimeOffset.UtcNow;
        var storage = new TestStorage();
        var service = new WorkspaceToolsService(storage, new Launcher(), () => now);
        Assert.True((await service.SaveNoteAsync(null, "Meeting", "Meeting with Alice")).Success);
        now = now.AddMinutes(1);
        await service.SaveNoteAsync(null, "Meeting", "Meeting with Alice");
        now = now.AddMinutes(1);
        await service.SaveNoteAsync(null, "Roadmap", "Meeting with Bob");
        var notes = service.SearchNotes("  MEETING  ");
        Assert.Equal(3, notes.Count);
        Assert.Equal(3, notes.Select(n => n.Id).Distinct().Count());
        Assert.Equal("Roadmap", notes[0].Title);
        Assert.Equal(2, service.SearchNotes("alice").Count);
        Assert.Empty(service.SearchNotes("nonexistent"));
        Assert.Equal(3, service.SearchNotes("  ").Count);
    }

    [Fact]
    public async Task Notes_UpdateDeleteAndPinTargetIdentityOnly()
    {
        var service = new WorkspaceToolsService(new TestStorage(), new Launcher());
        await service.SaveNoteAsync(null, "First", "One");
        var first = Assert.Single(service.Snapshot.Notes);
        await service.SaveNoteAsync(null, "Second", "Two");
        await service.SaveNoteAsync(first.Id, "Edited", "Updated body");
        await service.ToggleNotePinAsync(first.Id);
        Assert.Equal(first.CreatedAt, service.SearchNotes("")[0].CreatedAt);
        Assert.Equal(first.Id, service.SearchNotes("")[0].Id);
        Assert.True(service.SearchNotes("")[0].IsPinned);
        Assert.Equal("Updated body", service.SearchNotes("")[0].Body);
        await service.DeleteNoteAsync(first.Id);
        Assert.Equal("Second", Assert.Single(service.Snapshot.Notes).Title);
        Assert.False((await service.SaveNoteAsync(first.Id, "Gone", "Cannot recreate accidentally")).Success);
    }

    [Theory]
    [InlineData("", "")]
    [InlineData("Title", "  ")]
    public async Task EmptyNotes_DoNotSave(string title, string body)
    {
        var storage = new TestStorage();
        var service = new WorkspaceToolsService(storage, new Launcher());
        Assert.False((await service.SaveNoteAsync(null, title, body)).Success);
        Assert.Equal(0, storage.SaveCalls);
    }

    [Fact]
    public async Task NoteLimits_RejectOversizedAndFullCollectionWithoutMutation()
    {
        var storage = new TestStorage();
        var service = new WorkspaceToolsService(storage, new Launcher());
        Assert.False((await service.SaveNoteAsync(null, new string('t', 121), "Body")).Success);
        Assert.False((await service.SaveNoteAsync(null, "Title", new string('b', 32001))).Success);
        for (int i = 0; i < WorkspaceToolsService.MaximumNotes; i++)
            Assert.True((await service.SaveNoteAsync(null, "Title", "Body")).Success);
        Assert.False((await service.SaveNoteAsync(null, "Extra", "Body")).Success);
        Assert.Equal(WorkspaceToolsService.MaximumNotes, service.Snapshot.Notes.Count);
    }

    [Fact]
    public async Task FailedWrites_RollBackCreateEditDeleteAndPin()
    {
        var storage = new TestStorage();
        var service = new WorkspaceToolsService(storage, new Launcher());
        await service.SaveNoteAsync(null, "Existing", "Preserve this");
        var original = Assert.Single(service.Snapshot.Notes);
        storage.FailSave = true;
        Assert.False((await service.SaveNoteAsync(null, "New", "Draft")).Success);
        Assert.False((await service.SaveNoteAsync(original.Id, "Changed", "Draft")).Success);
        Assert.False((await service.DeleteNoteAsync(original.Id)).Success);
        Assert.False((await service.ToggleNotePinAsync(original.Id)).Success);
        Assert.Equal(original, Assert.Single(service.Snapshot.Notes));
        Assert.Equal(original, Assert.Single(storage.Data.Notes));
    }

    [Fact]
    public async Task FailedLoad_CannotOverwriteExistingWorkspaceOrEchoPrivateErrors()
    {
        var storage = new TestStorage { FailLoad = true };
        var result = await new WorkspaceToolsService(storage, new Launcher()).SaveNoteAsync(null, "New", "Draft");
        Assert.False(result.Success);
        Assert.DoesNotContain("private-data", result.Message);
        Assert.Equal(0, storage.SaveCalls);
    }

    [Fact]
    public async Task ConcurrentNoteSaves_AreSerializedWithoutLostUpdates()
    {
        var service = new WorkspaceToolsService(new TestStorage(), new Launcher());
        var results = await Task.WhenAll(Enumerable.Range(0, 20).Select(i => service.SaveNoteAsync(null, $"Note {i}", "Body")));
        Assert.All(results, result => Assert.True(result.Success));
        Assert.Equal(20, service.Snapshot.Notes.Count);
    }

    [Fact]
    public async Task Cancellation_DoesNotMutateSavedState()
    {
        var storage = new TestStorage();
        var service = new WorkspaceToolsService(storage, new Launcher());
        using var source = new CancellationTokenSource();
        source.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => service.SaveNoteAsync(null, "Title", "Body", source.Token));
        Assert.Empty(service.Snapshot.Notes);
        Assert.Equal(0, storage.SaveCalls);
    }

    [Fact]
    public async Task Shelf_DeduplicatesReferencesPreservesPinAndNeverChangesOriginalContent()
    {
        string path = LocalFile("source.txt", "Do not copy or index me");
        var service = new WorkspaceToolsService(new TestStorage(), new Launcher());
        Assert.True((await service.AddPathsAsync(new[] { path })).Success);
        var first = Assert.Single(service.Snapshot.Shelf);
        await service.ToggleShelfPinAsync(first.Id);
        await service.AddPathsAsync(new[] { path.ToUpperInvariant(), path });
        var second = Assert.Single(service.Snapshot.Shelf);
        Assert.Equal(first.Id, second.Id);
        Assert.True(second.IsPinned);
        await service.RemoveShelfAsync(second.Id);
        Assert.Empty(service.Snapshot.Shelf);
        Assert.Equal("Do not copy or index me", File.ReadAllText(path));
    }

    [Fact]
    public async Task Shelf_InvalidBatchIsAtomic()
    {
        var storage = new TestStorage();
        var service = new WorkspaceToolsService(storage, new Launcher());
        Assert.False((await service.AddPathsAsync(new[] { LocalFile("good.txt"), "https://example.com" })).Success);
        Assert.Empty(service.Snapshot.Shelf);
        Assert.Equal(0, storage.SaveCalls);
    }

    [Fact]
    public async Task Shelf_FailedWriteDoesNotPublishReferenceOrRemoveExistingOne()
    {
        var storage = new TestStorage();
        var service = new WorkspaceToolsService(storage, new Launcher());
        await service.AddPathsAsync(new[] { LocalFile("one.txt") });
        var original = Assert.Single(service.Snapshot.Shelf);
        storage.FailSave = true;
        Assert.False((await service.AddPathsAsync(new[] { LocalFile("two.txt") })).Success);
        Assert.False((await service.RemoveShelfAsync(original.Id)).Success);
        Assert.False((await service.ToggleShelfPinAsync(original.Id)).Success);
        Assert.Equal(original, Assert.Single(service.Snapshot.Shelf));
    }

    [Fact]
    public async Task Shelf_MissingFilesAreMarkedAndNeverLaunched()
    {
        string path = LocalFile("later-missing.txt");
        var launcher = new Launcher();
        var service = new WorkspaceToolsService(new TestStorage(), launcher);
        await service.AddPathsAsync(new[] { path });
        var item = Assert.Single(service.Snapshot.Shelf);
        File.Delete(path);
        Assert.False((await service.OpenShelfAsync(item.Id)).Success);
        Assert.True(Assert.Single(service.Snapshot.Shelf).IsMissing);
        Assert.Empty(launcher.Calls);
        File.WriteAllText(path, "Restored");
        await service.RefreshAsync();
        Assert.False(Assert.Single(service.Snapshot.Shelf).IsMissing);
    }

    [Fact]
    public async Task Shelf_ExplicitDocumentFolderOpenAndRevealUseLauncherResultsTruthfully()
    {
        var launcher = new Launcher();
        var service = new WorkspaceToolsService(new TestStorage(), launcher);
        await service.AddPathsAsync(new[] { LocalFile("document.pdf"), _directory });
        var file = service.Snapshot.Shelf.Single(f => !f.IsFolder);
        var folder = service.Snapshot.Shelf.Single(f => f.IsFolder);
        Assert.Empty(launcher.Calls);
        Assert.True((await service.OpenShelfAsync(file.Id)).Success);
        Assert.True((await service.OpenShelfAsync(file.Id, reveal: true)).Success);
        Assert.True((await service.OpenShelfAsync(folder.Id)).Success);
        Assert.Equal(3, launcher.Calls.Count);
        Assert.True(launcher.Calls[1].Reveal);
        Assert.True(launcher.Calls[2].Folder);
        launcher.Success = false;
        Assert.False((await service.OpenShelfAsync(file.Id)).Success);
    }

    [Theory]
    [InlineData("danger.exe")]
    [InlineData("danger.ps1")]
    [InlineData("danger.cmd")]
    [InlineData("danger.bat")]
    [InlineData("danger.js")]
    [InlineData("danger.lnk")]
    [InlineData("danger.url")]
    [InlineData("danger.hta")]
    [InlineData("danger.docm")]
    public async Task Shelf_ExecutableScriptShortcutAndMacroOpenDeniedButRevealAvailable(string name)
    {
        var launcher = new Launcher();
        var service = new WorkspaceToolsService(new TestStorage(), launcher);
        await service.AddPathsAsync(new[] { LocalFile(name) });
        var item = Assert.Single(service.Snapshot.Shelf);
        Assert.False((await service.OpenShelfAsync(item.Id)).Success);
        Assert.Empty(launcher.Calls);
        Assert.True((await service.OpenShelfAsync(item.Id, reveal: true)).Success);
        Assert.True(Assert.Single(launcher.Calls).Reveal);
    }

    [Theory]
    [InlineData("https://example.com")]
    [InlineData("file:///C:/temp/test.txt")]
    [InlineData("shell:AppsFolder")]
    [InlineData("powershell.exe -c Get-Process")]
    [InlineData("C:relative.txt")]
    [InlineData("\\\\server\\share\\file.txt")]
    [InlineData("\\\\?\\C:\\file.txt")]
    [InlineData("C:\\safe.txt:script.ps1")]
    [InlineData("C:\\NUL.txt")]
    [InlineData("C:\\folder\\CON")]
    public void PathPolicy_DeniesCommandsUrisNetworkDeviceAndAlternateStreams(string input) =>
        Assert.False(WorkspacePathPolicy.TryNormalize(input, out _));

    [Fact]
    public async Task Persistence_RoundTripsNotesPinsAndOnlyFileReferences()
    {
        string source = LocalFile("original.txt", "File content must not enter workspace persistence");
        string state = Path.Combine(_directory, "workspace.json");
        var service = new WorkspaceToolsService(new JsonWorkspaceStorage(state), new Launcher());
        await service.SaveNoteAsync(null, "My note", "Explicit note content");
        await service.AddPathsAsync(new[] { source });
        await service.ToggleShelfPinAsync(Assert.Single(service.Snapshot.Shelf).Id);
        string json = File.ReadAllText(state);
        Assert.DoesNotContain("File content must not enter", json);
        var restored = new WorkspaceToolsService(new JsonWorkspaceStorage(state), new Launcher());
        Assert.True((await restored.RefreshAsync()).Success);
        Assert.Equal("Explicit note content", Assert.Single(restored.Snapshot.Notes).Body);
        Assert.True(Assert.Single(restored.Snapshot.Shelf).IsPinned);
    }

    [Fact]
    public async Task CorruptWorkspace_IsPreservedAndCannotBeSilentlyOverwritten()
    {
        string state = LocalFile("workspace.json", "broken original data");
        var service = new WorkspaceToolsService(new JsonWorkspaceStorage(state), new Launcher());
        Assert.False((await service.RefreshAsync()).Success);
        Assert.False((await service.SaveNoteAsync(null, "New", "Body")).Success);
        Assert.Equal("broken original data", File.ReadAllText(state));
    }

    [Fact]
    public async Task StaleWriter_IsRejectedUntilRefresh()
    {
        string state = Path.Combine(_directory, "workspace.json");
        var first = new WorkspaceToolsService(new JsonWorkspaceStorage(state), new Launcher());
        var stale = new WorkspaceToolsService(new JsonWorkspaceStorage(state), new Launcher());
        await first.RefreshAsync();
        await stale.RefreshAsync();
        await first.SaveNoteAsync(null, "Saved", "First writer");
        Assert.False((await stale.SaveNoteAsync(null, "Stale", "Second writer")).Success);
        await stale.RefreshAsync();
        Assert.True((await stale.SaveNoteAsync(null, "New", "After refresh")).Success);
        await first.RefreshAsync();
        Assert.Equal(2, first.Snapshot.Notes.Count);
    }

    [Fact]
    public async Task ViewModel_EditSearchAndSaveFailureKeepUserDraft()
    {
        var storage = new TestStorage();
        var vm = new WorkspaceToolsViewModel(new WorkspaceToolsService(storage, new Launcher()));
        await vm.InitializeAsync();
        vm.NoteTitle = "Meeting";
        vm.NoteBody = "With Alice";
        await vm.SaveNoteAsync();
        Assert.Equal("", vm.NoteBody);
        vm.SelectNote(Assert.Single(vm.Notes).Id);
        Assert.Equal("Update note", vm.NoteSaveLabel);
        vm.NoteBody = "Edited draft";
        storage.FailSave = true;
        await vm.SaveNoteAsync();
        Assert.Equal("Edited draft", vm.NoteBody);
        Assert.Equal("With Alice", Assert.Single(vm.Notes).Body);
        vm.SearchQuery = "absent";
        Assert.Empty(vm.Notes);
        Assert.True(vm.CanEdit);
    }

    [Fact]
    public async Task ViewModel_DisposeSuppressesAlreadyQueuedUiCallbacks()
    {
        var queue = new Queue<Action>();
        var service = new WorkspaceToolsService(new TestStorage(), new Launcher());
        var vm = new WorkspaceToolsViewModel(service, queue.Enqueue);
        vm.NoteTitle = "Saved";
        vm.NoteBody = "An authorized write can finish without touching a closed window.";
        await vm.SaveNoteAsync();
        Assert.NotEmpty(queue);
        vm.Dispose();
        int changes = 0;
        vm.PropertyChanged += (_, _) => changes++;
        while (queue.TryDequeue(out var callback)) callback();
        vm.SelectNote(Assert.Single(service.Snapshot.Notes).Id);
        vm.NewNote();
        vm.SearchQuery = "changed";
        await vm.RefreshAsync();
        Assert.Equal(0, changes);
        Assert.Empty(vm.Notes);
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory)) Directory.Delete(_directory, recursive: true);
    }

    private sealed class TestStorage : IWorkspaceStorage
    {
        public WorkspaceSnapshot Data { get; private set; } = WorkspaceSnapshot.Empty;
        public bool FailSave { get; set; }
        public bool FailLoad { get; set; }
        public int SaveCalls { get; private set; }
        public Task<WorkspaceSnapshot> LoadAsync(CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (FailLoad) throw new IOException("private-data failure");
            return Task.FromResult(Data);
        }
        public Task SaveAsync(WorkspaceSnapshot snapshot, CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            SaveCalls++;
            if (FailSave) throw new IOException("private-data failure");
            Data = new(snapshot.Notes.ToArray(), snapshot.Shelf.ToArray());
            return Task.CompletedTask;
        }
    }

    private sealed class Launcher : IWorkspaceLauncher
    {
        public List<(string Path, bool Folder, bool Reveal)> Calls { get; } = new();
        public bool Success { get; set; } = true;
        public Task<bool> OpenAsync(string localPath, bool isFolder, bool reveal, CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Calls.Add((localPath, isFolder, reveal));
            return Task.FromResult(Success);
        }
    }
}
