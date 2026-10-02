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
    private let userDefaultsKey = "AMORA_Saved_Notes"

    private init() {
        loadNotes()
    }

    func addNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = NoteItem(text: trimmed)
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

    private func saveNotes() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func loadNotes() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode([NoteItem].self, from: data) {
            self.notes = saved
        }
    }
}
