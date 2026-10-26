using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.ViewModels;

public sealed class WorkspaceToolsViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly IWorkspaceToolsService _service;
    private readonly Action<Action> _dispatch;
    private string _noteTitle = "", _noteBody = "", _searchQuery = "", _filePath = "";
    private string _statusMessage = "Notes stay local. Add files to keep references without copying their contents.";
    private bool _isBusy;
    private bool _disposed;
    private Guid? _selectedNoteId;

    public WorkspaceToolsViewModel(IWorkspaceToolsService service, Action<Action>? dispatch = null)
    {
        _service = service ?? throw new ArgumentNullException(nameof(service));
        _dispatch = dispatch ?? (action => action());
    }

    public ObservableCollection<WorkspaceNote> Notes { get; } = new();
    public ObservableCollection<ShelfReference> Shelf { get; } = new();
    public string NoteTitle { get => _noteTitle; set => Set(ref _noteTitle, value); }
    public string NoteBody { get => _noteBody; set => Set(ref _noteBody, value); }
    public string SearchQuery { get => _searchQuery; set { if (Set(ref _searchQuery, value)) SearchNotes(); } }
    public string FilePath { get => _filePath; set => Set(ref _filePath, value); }
    public string StatusMessage { get => _statusMessage; private set => Set(ref _statusMessage, value); }
    public bool IsBusy { get => _isBusy; private set { if (Set(ref _isBusy, value)) OnPropertyChanged(nameof(CanEdit)); } }
    public bool CanEdit => !IsBusy;
    public Guid? SelectedNoteId { get => _selectedNoteId; private set { if (Set(ref _selectedNoteId, value)) OnPropertyChanged(nameof(NoteSaveLabel)); } }
    public string NoteSaveLabel => SelectedNoteId.HasValue ? "Update note" : "Save note";
    public bool HasNotes => Notes.Count != 0;
    public bool HasShelfItems => Shelf.Count != 0;
    public event PropertyChangedEventHandler? PropertyChanged;

    public Task InitializeAsync() => RefreshAsync();
    public Task RefreshAsync() => RunAsync(() => _service.RefreshAsync());
    public Task SaveNoteAsync() => RunAsync(() => _service.SaveNoteAsync(SelectedNoteId, NoteTitle, NoteBody), NewNote);
    public Task DeleteNoteAsync(Guid id) => RunAsync(() => _service.DeleteNoteAsync(id), () => { if (SelectedNoteId == id) NewNote(); });
    public Task ToggleNotePinAsync(Guid id) => RunAsync(() => _service.ToggleNotePinAsync(id));
    public Task AddPathAsync() => AddPathsAsync(new[] { FilePath });
    public Task AddPathsAsync(IEnumerable<string> paths)
    {
        var chosen = paths.ToArray();
        return RunAsync(() => _service.AddPathsAsync(chosen), () => FilePath = "");
    }
    public Task RemoveShelfAsync(Guid id) => RunAsync(() => _service.RemoveShelfAsync(id));
    public Task ToggleShelfPinAsync(Guid id) => RunAsync(() => _service.ToggleShelfPinAsync(id));
    public Task OpenShelfAsync(Guid id) => RunAsync(() => _service.OpenShelfAsync(id));
    public Task RevealShelfAsync(Guid id) => RunAsync(() => _service.OpenShelfAsync(id, reveal: true));

    public void SelectNote(Guid id)
    {
        if (_disposed) return;
        var note = _service.Snapshot.Notes.FirstOrDefault(n => n.Id == id);
        if (note == null) { StatusMessage = "That note no longer exists. Refresh the list."; return; }
        SelectedNoteId = note.Id;
        NoteTitle = note.Title;
        NoteBody = note.Body;
    }

    public void NewNote()
    {
        if (_disposed) return;
        SelectedNoteId = null;
        NoteTitle = "";
        NoteBody = "";
    }

    public void SearchNotes()
    {
        if (_disposed) return;
        Notes.Clear();
        foreach (var note in _service.SearchNotes(SearchQuery)) Notes.Add(note);
        OnPropertyChanged(nameof(HasNotes));
    }

    private async Task RunAsync(Func<Task<WorkspaceResult>> action, Action? onSuccess = null)
    {
        if (_disposed || IsBusy) return;
        IsBusy = true;
        try
        {
            var result = await action();
            _dispatch(() =>
            {
                if (_disposed) return;
                StatusMessage = result.Message;
                if (result.Success) onSuccess?.Invoke();
                SearchNotes();
                Shelf.Clear();
                foreach (var item in _service.Snapshot.Shelf.OrderByDescending(f => f.IsPinned).ThenByDescending(f => f.AddedAt)) Shelf.Add(item);
                OnPropertyChanged(nameof(HasShelfItems));
            });
        }
        catch (OperationCanceledException) { _dispatch(() => { if (!_disposed) StatusMessage = "Workspace action canceled."; }); }
        catch { _dispatch(() => { if (!_disposed) StatusMessage = "The workspace action failed. Saved data was preserved."; }); }
        finally { _dispatch(() => { if (!_disposed) IsBusy = false; }); }
    }

    public void Dispose() => _disposed = true;

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (_disposed) return false;
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        OnPropertyChanged(name);
        return true;
    }
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
}
