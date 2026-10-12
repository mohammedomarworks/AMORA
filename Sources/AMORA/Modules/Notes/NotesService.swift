import Foundation
import Observation

struct NoteItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var date: Date

    init(id: UUID = UUID(), text: String, date: Date = Date()) {
        self.id = id
        self.text = text
        self.date = date
    }
}

@Observable @MainActor
final class NotesService {
    static let shared = NotesService()

    var notes: [NoteItem] = []
    private var defaults: UserDefaults
    private var userDefaultsKey: String

    init(defaults: UserDefaults = .standard, userDefaultsKey: String = "AMORA_Saved_Notes") {
        self.defaults = defaults
        self.userDefaultsKey = userDefaultsKey
        loadNotes()
    }

    /// Configures isolated storage for evaluation and tests so real user data is never touched.
    func useIsolatedStorage(suiteName: String = "com.amora.evaluation.notes") {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.userDefaultsKey = "Evaluation_Saved_Notes"
        self.notes = []
        loadNotes()
    }

    /// Restores standard storage for normal app runtime.
    func restoreStandardStorage() {
        self.defaults = .standard
        self.userDefaultsKey = "AMORA_Saved_Notes"
        loadNotes()
    }

    func addNote(_ text: String, date: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = NoteItem(text: trimmed, date: date)
        notes.insert(note, at: 0)
        saveNotes()
        AMORAEventCenter.shared.emit(.noteCreated)
    }

    func deleteNote(at index: Int) {
        guard index >= 0 && index < notes.count else { return }
        notes.remove(at: index)
        saveNotes()
    }

    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        saveNotes()
    }

    /// Clears all stored notes from memory and persistent store.
    func clearAll() {
        notes.removeAll()
        defaults.removeObject(forKey: userDefaultsKey)
    }

    /// Reloads notes from the persistent store.
    func reloadNotes() {
        loadNotes()
    }

    /// Searches notes containing the query string, case-insensitively,
    /// returning distinct matching notes ordered newest-first by date.
    /// Does not silently merge distinct notes that share content or title.
    func searchNotes(query: String) -> [NoteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sortedNotes = notes.sorted { $0.date > $1.date }
        guard !trimmed.isEmpty else { return sortedNotes }
        return sortedNotes.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    private func saveNotes() {
        if notes.isEmpty {
            defaults.removeObject(forKey: userDefaultsKey)
        } else if let data = try? JSONEncoder().encode(notes) {
            defaults.set(data, forKey: userDefaultsKey)
        }
    }

    private func loadNotes() {
        if let data = defaults.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode([NoteItem].self, from: data) {
            self.notes = saved
        } else {
            self.notes = []
        }
    }
}
