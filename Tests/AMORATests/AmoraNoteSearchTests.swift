import XCTest
@testable import AMORA

@MainActor
final class AmoraNoteSearchTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var testSuiteName: String!
    private var service: NotesService!

    override func setUp() async throws {
        try await super.setUp()
        testSuiteName = "com.amora.tests.notes.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)!
        service = NotesService(defaults: testDefaults, userDefaultsKey: "TestNotesKey")
        service.clearAll()
        NotesService.shared.clearAll()
    }

    override func tearDown() async throws {
        service.clearAll()
        NotesService.shared.clearAll()
        testDefaults.removePersistentDomain(forName: testSuiteName)
        try await super.tearDown()
    }

    // MARK: - 1. Duplicate records are preserved, not silently merged

    func testNoteSearchWithDuplicateRecordsPreservesAllRecords() {
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        let t3 = Date(timeIntervalSince1970: 3000)

        // User or system legitimately recorded three notes with the same wording at different times
        service.addNote("Weekly team sync meeting at 10 AM", date: t1)
        service.addNote("Weekly team sync meeting at 10 AM", date: t2)
        service.addNote("Weekly team sync meeting at 10 AM", date: t3)

        let matches = service.searchNotes(query: "meeting")

        // Must NOT silently merge identical texts into 1 note
        XCTAssertEqual(matches.count, 3, "All 3 distinct note records must be preserved and returned")
        XCTAssertEqual(Set(matches.map(\.id)).count, 3, "Each note must have a distinct UUID")

        // Must be ordered newest first (t3, then t2, then t1)
        XCTAssertEqual(matches[0].date, t3)
        XCTAssertEqual(matches[1].date, t2)
        XCTAssertEqual(matches[2].date, t1)
    }

    // MARK: - 2. Genuinely distinct matching notes

    func testNoteSearchWithDistinctMatchingNotes() {
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        let t3 = Date(timeIntervalSince1970: 3000)

        service.addNote("Q4 roadmap review meeting with leadership", date: t1)
        service.addNote("1:1 sync meeting with Alice regarding project goals", date: t2)
        service.addNote("Design critique meeting for new island animation", date: t3)

        let matches = service.searchNotes(query: "meeting")
        XCTAssertEqual(matches.count, 3)

        let aliceMatches = service.searchNotes(query: "alice")
        XCTAssertEqual(aliceMatches.count, 1)
        XCTAssertEqual(aliceMatches.first?.text, "1:1 sync meeting with Alice regarding project goals")

        let roadmapMatches = service.searchNotes(query: "roadmap")
        XCTAssertEqual(roadmapMatches.count, 1)
        XCTAssertEqual(roadmapMatches.first?.text, "Q4 roadmap review meeting with leadership")
    }

    // MARK: - 3. Ordering: Newest first

    func testNoteSearchOrderingNewestFirst() {
        let past = Date(timeIntervalSinceNow: -3600)
        let middle = Date(timeIntervalSinceNow: -1800)
        let recent = Date(timeIntervalSinceNow: -60)

        service.addNote("Old note about project Alpha", date: past)
        service.addNote("Recent note about project Alpha", date: recent)
        service.addNote("Middle note about project Alpha", date: middle)

        let results = service.searchNotes(query: "Alpha")
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].text, "Recent note about project Alpha")
        XCTAssertEqual(results[1].text, "Middle note about project Alpha")
        XCTAssertEqual(results[2].text, "Old note about project Alpha")
    }

    // MARK: - 4. Empty search results

    func testNoteSearchEmptyResults() {
        service.addNote("Dentist appointment tomorrow")
        service.addNote("Buy groceries: milk, eggs, bread")

        let noMatches = service.searchNotes(query: "nonexistent_query_term_12345")
        XCTAssertTrue(noMatches.isEmpty, "Search for nonexistent term must return empty array")

        let emptyQuery = service.searchNotes(query: "   ")
        XCTAssertEqual(emptyQuery.count, 2, "Whitespace or empty query must return all notes sorted")
    }

    // MARK: - 5. Non-matching notes excluded

    func testNoteSearchExcludesNonMatchingNotes() {
        service.addNote("Standup meeting notes")
        service.addNote("Grocery shopping list")
        service.addNote("Flight reservation confirmation")

        let results = service.searchNotes(query: "shopping")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.text, "Grocery shopping list")
    }

    // MARK: - 6. Storage isolation and clearAll

    func testNotesServiceClearAllWipesMemoryAndDefaults() {
        service.addNote("Persistent note to be deleted")
        XCTAssertEqual(service.notes.count, 1)

        service.clearAll()
        XCTAssertEqual(service.notes.count, 0)
        XCTAssertNil(testDefaults.data(forKey: "TestNotesKey"))

        // Create fresh service pointing to same store to verify disk wipe
        let reloaded = NotesService(defaults: testDefaults, userDefaultsKey: "TestNotesKey")
        XCTAssertEqual(reloaded.notes.count, 0)
    }
}
