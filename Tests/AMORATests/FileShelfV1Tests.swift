import XCTest
@testable import AMORA

@MainActor
final class FileShelfV1Tests: XCTestCase {
    private var tempDirectory: URL!
    private var tempStorageURL: URL!
    private var mockOpener: ControlledAmoraFileOpener!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AMORAFileShelfTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        tempStorageURL = tempDirectory.appendingPathComponent("test_file_shelf.json")
        mockOpener = ControlledAmoraFileOpener()
    }

    override func tearDown() async throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        mockOpener = nil
        tempStorageURL = nil
        tempDirectory = nil
        try await super.tearDown()
    }

    private func createTestFile(name: String, content: String = "Test content for AMORA file shelf.") throws -> URL {
        let fileURL = tempDirectory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func createTestFolder(name: String) throws -> URL {
        let folderURL = tempDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    // MARK: - 1. Single File Intake & Metadata

    func testAddSingleFileAndMetadataInspection() throws {
        let fileURL = try createTestFile(name: "Report.pdf", content: "Important quarterly report")
        let shelf = FileShelfService(storageURL: tempStorageURL, fileOpener: mockOpener)

        let item = shelf.addFile(url: fileURL)
        XCTAssertNotNil(item)
        XCTAssertEqual(shelf.items.count, 1)

        let added = shelf.items.first!
        XCTAssertEqual(added.name, "Report.pdf")
        XCTAssertFalse(added.isMissing)
        XCTAssertFalse(added.isDirectory)
        XCTAssertNotNil(added.fileSize)
        XCTAssertGreaterThan(added.fileSize ?? 0, 0)
        XCTAssertFalse(added.contentTypeDescription.isEmpty)
        XCTAssertNotNil(added.fileSizeDescription)
        XCTAssertFalse(added.fileSizeDescription?.isEmpty ?? true)
        XCTAssertFalse(added.metadataDescription.isEmpty)
        XCTAssertEqual(added.systemIconName, "doc.text.fill")
    }

    func testAddFolderItemMetadata() throws {
        let folderURL = try createTestFolder(name: "Projects")
        let shelf = FileShelfService(storageURL: tempStorageURL, fileOpener: mockOpener)

        let item = shelf.addFile(url: folderURL)
        XCTAssertNotNil(item)
        XCTAssertEqual(shelf.items.count, 1)

        let added = shelf.items.first!
        XCTAssertEqual(added.name, "Projects")
        XCTAssertTrue(added.isDirectory)
        XCTAssertEqual(added.systemIconName, "folder.fill")
        XCTAssertEqual(added.contentTypeDescription, "Folder")
    }

    // MARK: - 2. Multi-File Intake

    func testBatchFileIntake() throws {
        let file1 = try createTestFile(name: "Document.txt")
        let file2 = try createTestFile(name: "Photo.png")
        let file3 = try createTestFile(name: "Source.swift")
        let shelf = FileShelfService(storageURL: tempStorageURL, fileOpener: mockOpener)

        let added = shelf.addFiles(urls: [file1, file2, file3])
        XCTAssertEqual(added.count, 3)
        XCTAssertEqual(shelf.items.count, 3)

        let names = Set(shelf.items.map { $0.name })
        XCTAssertTrue(names.contains("Document.txt"))
        XCTAssertTrue(names.contains("Photo.png"))
        XCTAssertTrue(names.contains("Source.swift"))
    }

    // MARK: - 3. Duplicate Handling

    func testDuplicateFilePrevention() throws {
        let file1 = try createTestFile(name: "Unique.txt")
        let shelf = FileShelfService(storageURL: tempStorageURL, fileOpener: mockOpener)

        let firstAdd = shelf.addFile(url: file1)
        XCTAssertNotNil(firstAdd)
        XCTAssertEqual(shelf.items.count, 1)

        // Adding exact same URL again should not duplicate
        let secondAdd = shelf.addFile(url: file1)
        XCTAssertNotNil(secondAdd)
        XCTAssertEqual(secondAdd?.id, firstAdd?.id)
        XCTAssertEqual(shelf.items.count, 1, "Duplicate file should not be added to shelf")

        // Batch add with already added file
        let file2 = try createTestFile(name: "Another.txt")
        let batchAdded = shelf.addFiles(urls: [file1, file2])
        XCTAssertEqual(batchAdded.count, 1, "Only the new file should be added in batch")
        XCTAssertEqual(shelf.items.count, 2)
    }

    // MARK: - 4. Removal Without File Deletion

    func testRemovingShelfItemLeavesDiskFileIntact() throws {
        let fileURL = try createTestFile(name: "KeepMeSafe.pdf")
        let shelf = FileShelfService(storageURL: tempStorageURL, fileOpener: mockOpener)

        guard let item = shelf.addFile(url: fileURL) else {
            XCTFail("Failed to add file to shelf")
            return
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(shelf.items.count, 1)

        // Remove from shelf
        shelf.removeItem(id: item.id)
        XCTAssertEqual(shelf.items.count, 0)

        // CRITICAL: File must still exist on filesystem
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fileURL.path),
            "Removing an item from the File Shelf must NEVER delete the user's file from disk."
        )
    }

    func testClearShelfLeavesAllDiskFilesIntact() throws {
        let file1 = try createTestFile(name: "Keep1.txt")
        let file2 = try createTestFile(name: "Keep2.txt")
        let shelf = FileShelfService(storageURL: tempStorageURL, fileOpener: mockOpener)

        _ = shelf.addFiles(urls: [file1, file2])
        XCTAssertEqual(shelf.items.count, 2)

        shelf.clearShelf()
        XCTAssertEqual(shelf.items.count, 0)

        // Files must still be intact
        XCTAssertTrue(FileManager.default.fileExists(atPath: file1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file2.path))
    }

    // MARK: - 5. Open & Reveal via Controlled Opener

    func testOpenFileSuccessAndFailure() throws {
        let fileURL = try createTestFile(name: "Launch.txt")
        let shelf = FileShelfService(storageURL: tempStorageURL, fileOpener: mockOpener)

        guard let item = shelf.addFile(url: fileURL) else {
            XCTFail("Could not add file")
            return
        }

        let opened = shelf.openFile(item)
        XCTAssertTrue(opened)
        XCTAssertEqual(mockOpener.openedURLs.count, 1)
        XCTAssertEqual(mockOpener.openedURLs.first?.standardizedFileURL, fileURL.standardizedFileURL)

        // Test with failure
        mockOpener.shouldSucceed = false
        let failedOpen = shelf.openFile(item)
        XCTAssertFalse(failedOpen)
        XCTAssertNotNil(shelf.lastErrorMessage)
    }

    func testRevealFileSuccessAndFailure() throws {
        let fileURL = try createTestFile(name: "Inspect.txt")
        let shelf = FileShelfService(storageURL: tempStorageURL, fileOpener: mockOpener)

        guard let item = shelf.addFile(url: fileURL) else {
            XCTFail("Could not add file")
            return
        }

        let revealed = shelf.revealFile(item)
        XCTAssertTrue(revealed)
        XCTAssertEqual(mockOpener.revealedURLs.count, 1)
        XCTAssertEqual(mockOpener.revealedURLs.first?.standardizedFileURL, fileURL.standardizedFileURL)

        // Test with failure
        mockOpener.shouldSucceed = false
        let failedReveal = shelf.revealFile(item)
        XCTAssertFalse(failedReveal)
        XCTAssertNotNil(shelf.lastErrorMessage)
    }

    // MARK: - 6. Persistence & Restoration

    func testPersistenceAcrossServiceInstances() throws {
        let file1 = try createTestFile(name: "Persist1.txt")
        let file2 = try createTestFile(name: "Persist2.pdf")

        let shelf1 = FileShelfService(storageURL: tempStorageURL, fileOpener: mockOpener)
        _ = shelf1.addFiles(urls: [file1, file2])
        XCTAssertEqual(shelf1.items.count, 2)

        // Recreate service from disk
        let shelf2 = FileShelfService(storageURL: tempStorageURL, fileOpener: mockOpener)
        XCTAssertEqual(shelf2.items.count, 2)

        let names = Set(shelf2.items.map { $0.name })
        XCTAssertTrue(names.contains("Persist1.txt"))
        XCTAssertTrue(names.contains("Persist2.pdf"))

        // Check metadata persisted
        for item in shelf2.items {
            XCTAssertFalse(item.isMissing)
            XCTAssertNotNil(item.fileSize)
        }
    }

    // MARK: - 7. Missing & Inaccessible Files

    func testMissingFileDetectionAndGracefulError() throws {
        let fileURL = try createTestFile(name: "Temporary.txt")
        let shelf = FileShelfService(storageURL: tempStorageURL, fileOpener: mockOpener)

        guard let item = shelf.addFile(url: fileURL) else {
            XCTFail("Could not add file")
            return
        }

        // Delete underlying file on disk
        try FileManager.default.removeItem(at: fileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        // Opening should fail gracefully and mark missing
        let opened = shelf.openFile(item)
        XCTAssertFalse(opened)
        XCTAssertEqual(shelf.lastErrorMessage, "File not found: Temporary.txt")

        let updatedItem = shelf.items.first { $0.id == item.id }
        XCTAssertEqual(updatedItem?.isMissing, true)

        // Reveal should also fail gracefully
        let revealed = shelf.revealFile(item)
        XCTAssertFalse(revealed)
        XCTAssertEqual(shelf.lastErrorMessage, "File not found: Temporary.txt")

        // removeMissingItems cleans it up
        shelf.removeMissingItems()
        XCTAssertEqual(shelf.items.count, 0)
    }

    // MARK: - 8. Lookup by Name

    func testFindItemByNameVariants() throws {
        let file1 = try createTestFile(name: "Budget-2026.xlsx")
        let shelf = FileShelfService(storageURL: tempStorageURL, fileOpener: mockOpener)
        _ = shelf.addFile(url: file1)

        // Exact match
        XCTAssertNotNil(shelf.findItem(named: "Budget-2026.xlsx"))
        // Case-insensitive
        XCTAssertNotNil(shelf.findItem(named: "budget-2026.xlsx"))
        // Extensionless
        XCTAssertNotNil(shelf.findItem(named: "budget-2026"))
        // Substring
        XCTAssertNotNil(shelf.findItem(named: "budget"))
        // Non-existent
        XCTAssertNil(shelf.findItem(named: "expenses"))
    }

    // MARK: - 9. Action Engine Integration

    func testActionEngineFileShelfList() async throws {
        let file1 = try createTestFile(name: "Notes.md")
        let shelf = FileShelfService(storageURL: tempStorageURL, fileOpener: mockOpener)
        _ = shelf.addFile(url: file1)

        let registry = AmoraActionRegistry()
        AmoraActionEngine.registerDefaultActions(
            into: registry,
            mediaController: ControlledAmoraMediaController(),
            appLauncher: ControlledAmoraApplicationLauncher(),
            folderOpener: ControlledAmoraFolderOpener(),
            workspaceController: ControlledAmoraWorkspaceController(),
            timerController: DefaultAmoraTimerController(),
            fileShelf: shelf
        )
        let engine = AmoraActionEngine(registry: registry)

        let result = await engine.execute(.listShelfFiles)
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(result.message.contains("Notes.md"))
        XCTAssertEqual(result.data["count"], "1")
    }

    func testActionEngineFileShelfOpenAndReveal() async throws {
        let file1 = try createTestFile(name: "QuarterlyReport.pdf")
        let shelf = FileShelfService(storageURL: tempStorageURL, fileOpener: mockOpener)
        _ = shelf.addFile(url: file1)

        let registry = AmoraActionRegistry()
        AmoraActionEngine.registerDefaultActions(
            into: registry,
            mediaController: ControlledAmoraMediaController(),
            appLauncher: ControlledAmoraApplicationLauncher(),
            folderOpener: ControlledAmoraFolderOpener(),
            workspaceController: ControlledAmoraWorkspaceController(),
            timerController: DefaultAmoraTimerController(),
            fileShelf: shelf
        )
        let engine = AmoraActionEngine(registry: registry)

        // 1. Reveal in Finder
        let revealResult = await engine.execute(.revealShelfFile(name: "QuarterlyReport"))
        XCTAssertTrue(revealResult.isSuccess)
        XCTAssertEqual(mockOpener.revealedURLs.count, 1)

        // 2. Open file
        let openResult = await engine.execute(.openShelfFile(name: "QuarterlyReport"))
        XCTAssertTrue(openResult.isSuccess)
        XCTAssertEqual(mockOpener.openedURLs.count, 1)

        // 3. Open non-existent file
        let missingResult = await engine.execute(.openShelfFile(name: "NoSuchFile.pdf"))
        XCTAssertFalse(missingResult.isSuccess)
        XCTAssertEqual(missingResult.status, .unavailable)
    }

    func testActionEngineFileShelfRemoveLeavesDiskFile() async throws {
        let file1 = try createTestFile(name: "ImportantContract.docx")
        let shelf = FileShelfService(storageURL: tempStorageURL, fileOpener: mockOpener)
        _ = shelf.addFile(url: file1)

        let registry = AmoraActionRegistry()
        AmoraActionEngine.registerDefaultActions(
            into: registry,
            mediaController: ControlledAmoraMediaController(),
            appLauncher: ControlledAmoraApplicationLauncher(),
            folderOpener: ControlledAmoraFolderOpener(),
            workspaceController: ControlledAmoraWorkspaceController(),
            timerController: DefaultAmoraTimerController(),
            fileShelf: shelf
        )
        let engine = AmoraActionEngine(registry: registry)

        let removeResult = await engine.execute(.removeShelfFile(name: "ImportantContract.docx"))
        XCTAssertTrue(removeResult.isSuccess)
        XCTAssertEqual(shelf.items.count, 0)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: file1.path),
            "Action Engine fileshelf.remove must not delete underlying disk file."
        )
    }

    func testActionEngineFileShelfClearRequiresConfirmation() async throws {
        let file1 = try createTestFile(name: "F1.txt")
        let file2 = try createTestFile(name: "F2.txt")
        let shelf = FileShelfService(storageURL: tempStorageURL, fileOpener: mockOpener)
        _ = shelf.addFiles(urls: [file1, file2])

        let registry = AmoraActionRegistry()
        AmoraActionEngine.registerDefaultActions(
            into: registry,
            mediaController: ControlledAmoraMediaController(),
            appLauncher: ControlledAmoraApplicationLauncher(),
            folderOpener: ControlledAmoraFolderOpener(),
            workspaceController: ControlledAmoraWorkspaceController(),
            timerController: DefaultAmoraTimerController(),
            fileShelf: shelf
        )
        let engine = AmoraActionEngine(registry: registry)

        // Unconfirmed execution should fail or require confirmation
        let unconfirmedResult = await engine.execute(
            .clearShelf(confirmed: false),
            context: AmoraActionContext(isConfirmed: false)
        )
        XCTAssertEqual(unconfirmedResult.status, .needsConfirmation)
        XCTAssertEqual(shelf.items.count, 2)

        // Confirmed execution should clear shelf entries
        let confirmedResult = await engine.execute(
            .clearShelf(confirmed: true),
            context: AmoraActionContext(isConfirmed: true)
        )
        XCTAssertTrue(confirmedResult.isSuccess)
        XCTAssertEqual(shelf.items.count, 0)

        // Underlying files remain safe
        XCTAssertTrue(FileManager.default.fileExists(atPath: file1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file2.path))
    }

    // MARK: - 10. Natural Language Routing

    func testDeterministicRouterFileShelfCommands() {
        let listDecision = AmoraDeterministicRouter.decision(for: "what files are on my shelf?")
        XCTAssertEqual(listDecision, .toolCall(name: "fileshelf.list", arguments: [:]))

        let openDecision = AmoraDeterministicRouter.decision(for: "open report.pdf from file shelf")
        XCTAssertEqual(openDecision, .toolCall(name: "fileshelf.open", arguments: ["name": "report.pdf"]))

        let revealDecision = AmoraDeterministicRouter.decision(for: "reveal report.pdf in finder")
        XCTAssertEqual(revealDecision, .toolCall(name: "fileshelf.reveal", arguments: ["name": "report.pdf"]))

        let removeDecision = AmoraDeterministicRouter.decision(for: "unpin report.pdf from shelf")
        XCTAssertEqual(removeDecision, .toolCall(name: "fileshelf.remove", arguments: ["name": "report.pdf"]))

        let clearDecision = AmoraDeterministicRouter.decision(for: "clear file shelf")
        XCTAssertEqual(clearDecision, .toolCall(name: "fileshelf.clear", arguments: [:]))
    }
}
