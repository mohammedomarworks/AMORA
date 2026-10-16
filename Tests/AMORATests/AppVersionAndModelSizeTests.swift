import Foundation
import XCTest
@testable import AMORA

final class AppVersionAndModelSizeTests: XCTestCase {

    // MARK: - 1. AppVersion Fallbacks & Formatting

    func testAppVersionDefaultFallbackValues() {
        XCTAssertEqual(AppVersion.defaultVersion, "1.0.0")
        XCTAssertEqual(AppVersion.defaultBuild, "1")

        // When running in unit tests outside an app bundle, Bundle.main falls back safely
        XCTAssertFalse(AppVersion.current.isEmpty)
        XCTAssertFalse(AppVersion.build.isEmpty)
        XCTAssertTrue(AppVersion.fullDisplay.contains("Version"))
        XCTAssertTrue(AppVersion.fullDisplay.contains("Build"))
        XCTAssertTrue(AppVersion.shortDisplay.hasPrefix("Version "))
    }

    func testAppVersionReadsFromBundleMetadata() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AMORAVersionTest_\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plistData: [String: Any] = [
            "CFBundleShortVersionString": "2.5.1",
            "CFBundleVersion": "42"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plistData, format: .xml, options: 0)
        try data.write(to: tempDir.appendingPathComponent("Info.plist"))

        guard let testBundle = Bundle(url: tempDir) else {
            XCTFail("Failed to instantiate Bundle from test directory")
            return
        }

        XCTAssertEqual(AppVersion.marketingVersion(in: testBundle), "2.5.1")
        XCTAssertEqual(AppVersion.buildNumber(in: testBundle), "42")
        XCTAssertEqual(AppVersion.fullDisplayString(in: testBundle), "Version 2.5.1 (Build 42)")
        XCTAssertEqual(AppVersion.shortDisplayString(in: testBundle), "Version 2.5.1")
    }

    func testAppVersionWhitespaceAndEmptyFallbacks() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AMORAVersionEmptyTest_\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plistData: [String: Any] = [
            "CFBundleShortVersionString": "   \n  ",
            "CFBundleVersion": ""
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plistData, format: .xml, options: 0)
        try data.write(to: tempDir.appendingPathComponent("Info.plist"))

        guard let testBundle = Bundle(url: tempDir) else {
            XCTFail("Failed to instantiate Bundle from test directory")
            return
        }

        XCTAssertEqual(AppVersion.marketingVersion(in: testBundle), AppVersion.defaultVersion)
        XCTAssertEqual(AppVersion.buildNumber(in: testBundle), AppVersion.defaultBuild)
        XCTAssertEqual(AppVersion.fullDisplayString(in: testBundle), "Version \(AppVersion.defaultVersion) (Build \(AppVersion.defaultBuild))")
    }

    func testAppVersionFallsBackToVersionFileWhenBundleMetadataMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AMORANoPlist_\(UUID().uuidString).bundle")
        let resourcesDir = tempDir.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let versionFileContent = "VERSION=3.1.4\nBUILD=99\n"
        try versionFileContent.write(to: resourcesDir.appendingPathComponent("VERSION"), atomically: true, encoding: .utf8)

        guard let testBundle = Bundle(url: tempDir) else {
            XCTFail("Failed to instantiate Bundle from test directory")
            return
        }

        XCTAssertEqual(AppVersion.marketingVersion(in: testBundle), "3.1.4")
        XCTAssertEqual(AppVersion.buildNumber(in: testBundle), "99")
        XCTAssertEqual(AppVersion.fullDisplayString(in: testBundle), "Version 3.1.4 (Build 99)")
    }

    func testAuthoritativeVersionFileMatchesCodeConstants() throws {
        // Resolve path to the root VERSION file
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AMORATests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Repo root
        let versionFileURL = repoRoot.appendingPathComponent("VERSION")

        XCTAssertTrue(FileManager.default.fileExists(atPath: versionFileURL.path), "VERSION file must exist at repo root")

        let content = try String(contentsOf: versionFileURL, encoding: .utf8)
        var parsedVersion: String?
        var parsedBuild: String?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("VERSION=") {
                parsedVersion = String(trimmed.dropFirst("VERSION=".count))
            } else if trimmed.hasPrefix("BUILD=") {
                parsedBuild = String(trimmed.dropFirst("BUILD=".count))
            }
        }

        XCTAssertEqual(parsedVersion, AppVersion.defaultVersion, "Repo VERSION must match AppVersion.defaultVersion")
        XCTAssertEqual(parsedBuild, AppVersion.defaultBuild, "Repo BUILD must match AppVersion.defaultBuild")
    }

    // MARK: - 2. Model Size Formatting & Consistency

    func testDefaultModelSizeFormattingIsDynamicAndAccurate() {
        let defaultModel = AmoraModelDescriptor.defaultModel
        XCTAssertEqual(defaultModel.id, "qwen2.5-1.5b-instruct-q4_k_m")
        XCTAssertEqual(defaultModel.expectedSizeBytes, 1_117_320_736)

        // 1.5B model must format as gigabytes, not 491 MB
        XCTAssertEqual(defaultModel.formattedExpectedSize, "1.0 GB")
        XCTAssertNotEqual(defaultModel.formattedExpectedSize, "491 MB")
    }

    func testCompactModelSizeFormatting() {
        let compactModel = AmoraModelDescriptor.qwen2_5_0_5b
        XCTAssertEqual(compactModel.expectedSizeBytes, 491_400_032)

        // 0.5B model must format as megabytes (~469 MB)
        XCTAssertEqual(compactModel.formattedExpectedSize, "469 MB")
    }

    func testSmolLM3ModelSizeFormatting() {
        let smollm = AmoraModelDescriptor.smollm3_3b
        XCTAssertEqual(smollm.expectedSizeBytes, 1_915_305_312)

        // 3B model must format as gigabytes (~1.8 GB)
        XCTAssertEqual(smollm.formattedExpectedSize, "1.8 GB")
    }

    func testModelSizeFormattingThresholdBoundaries() {
        // Below 1 GB: 500 MB
        let model500MB = AmoraModelDescriptor(
            id: "test-500mb",
            displayName: "500MB",
            version: "1.0",
            quantization: "Q4_0",
            license: "MIT",
            author: "Tester",
            sourceURL: URL(string: "https://example.com/model.gguf")!,
            expectedSizeBytes: 500 * 1024 * 1024,
            estimatedRAMBytes: 600 * 1024 * 1024,
            expectedSHA256: "",
            filename: "model.gguf",
            systemPrompt: ""
        )
        XCTAssertEqual(model500MB.formattedExpectedSize, "500 MB")

        // Exact 1 GB boundary
        let model1GB = AmoraModelDescriptor(
            id: "test-1gb",
            displayName: "1GB",
            version: "1.0",
            quantization: "Q4_0",
            license: "MIT",
            author: "Tester",
            sourceURL: URL(string: "https://example.com/model.gguf")!,
            expectedSizeBytes: 1024 * 1024 * 1024,
            estimatedRAMBytes: 1200 * 1024 * 1024,
            expectedSHA256: "",
            filename: "model.gguf",
            systemPrompt: ""
        )
        XCTAssertEqual(model1GB.formattedExpectedSize, "1.0 GB")
    }

    @MainActor
    func testModelManagerSharedUsesDefaultModelDynamicSize() {
        let manager = AmoraModelManager.shared
        XCTAssertEqual(manager.descriptor.id, AmoraModelDescriptor.defaultModel.id)
        XCTAssertEqual(manager.descriptor.formattedExpectedSize, "1.0 GB")
    }
}
