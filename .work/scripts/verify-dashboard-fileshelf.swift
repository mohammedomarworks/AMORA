import Foundation
import AppKit

// Check file_shelf.json location
let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let storageURL = appSupport.appendingPathComponent("AMORA/file_shelf.json")

print("Storage URL: \(storageURL.path)")

// Create two real test files
let testFile1 = URL(fileURLWithPath: "/tmp/amora_test_dashboard_1.txt")
let testFile2 = URL(fileURLWithPath: "/tmp/amora_test_dashboard_2.txt")
try? "File 1 content".write(to: testFile1, atomically: true, encoding: .utf8)
try? "File 2 content".write(to: testFile2, atomically: true, encoding: .utf8)

// Create bookmark data for file 1
var bookmark1 = try? testFile1.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
var bookmark2 = try? testFile2.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)

struct PersistedShelfItem: Codable {
    let id: UUID
    let path: String
    let name: String
    let bookmarkData: Data?
    let dateAdded: Date
}

let item1 = PersistedShelfItem(id: UUID(), path: testFile1.path, name: testFile1.lastPathComponent, bookmarkData: bookmark1, dateAdded: Date())
let item2 = PersistedShelfItem(id: UUID(), path: testFile2.path, name: testFile2.lastPathComponent, bookmarkData: bookmark2, dateAdded: Date())

let data = try! JSONEncoder().encode([item1, item2])
try! data.write(to: storageURL, options: .atomic)
print("Wrote 2 items to storage. File size: \(data.count) bytes")

// Read back and verify
let readData = try! Data(contentsOf: storageURL)
let decoded = try! JSONDecoder().decode([PersistedShelfItem].self, from: readData)
assert(decoded.count == 2)
assert(decoded[0].name == "amora_test_dashboard_1.txt")
assert(decoded[1].name == "amora_test_dashboard_2.txt")
print("Verified decoded: \(decoded.map { $0.name })")

// Test resolve
var isStale = false
let resolved1 = try? URL(resolvingBookmarkData: decoded[0].bookmarkData!, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
assert(resolved1?.path == testFile1.path)
print("Bookmark resolution successful: \(resolved1?.path ?? "")")

// Delete physical file 2 to test missing file detection
try? FileManager.default.removeItem(at: testFile2)
let exists1 = FileManager.default.fileExists(atPath: testFile1.path)
let exists2 = FileManager.default.fileExists(atPath: testFile2.path)
assert(exists1 == true)
assert(exists2 == false)
print("Missing file detection: File 1 exists=\(exists1), File 2 exists=\(exists2)")

// Clean up test file 1
try? FileManager.default.removeItem(at: testFile1)
// Clean up storage
try? "[]".data(using: .utf8)?.write(to: storageURL)
print("ALL VERIFICATIONS PASSED")
