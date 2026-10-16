import Foundation

/// Centralized authority for application version and build information.
/// Reads from the bundle's `infoDictionary` (`CFBundleShortVersionString` and `CFBundleVersion`)
/// and provides deterministic, safe fallback values for development/test environments.
public enum AppVersion {
    public static let defaultVersion = "1.0.0"
    public static let defaultBuild = "1"

    /// Reads the short marketing version (e.g., "1.0.0").
    public static func marketingVersion(in bundle: Bundle = .main) -> String {
        if let raw = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let fileVersion = fallbackFromVersionFile(in: bundle).version, !fileVersion.isEmpty {
            return fileVersion
        }
        return defaultVersion
    }

    /// Reads the build number (e.g., "1").
    public static func buildNumber(in bundle: Bundle = .main) -> String {
        if let raw = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let fileBuild = fallbackFromVersionFile(in: bundle).build, !fileBuild.isEmpty {
            return fileBuild
        }
        return defaultBuild
    }

    private static func fallbackFromVersionFile(in bundle: Bundle) -> (version: String?, build: String?) {
        var candidates: [URL] = []
        if let url = bundle.url(forResource: "VERSION", withExtension: nil) {
            candidates.append(url)
        }
        if let resourceURL = bundle.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("VERSION"))
        }
        if bundle == .main {
            candidates.append(URL(fileURLWithPath: "VERSION"))
        }
        for url in candidates {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                var v: String?
                var b: String?
                for line in content.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("VERSION=") {
                        v = String(trimmed.dropFirst("VERSION=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if trimmed.hasPrefix("BUILD=") {
                        b = String(trimmed.dropFirst("BUILD=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                if v != nil || b != nil {
                    return (v, b)
                }
            }
        }
        return (nil, nil)
    }

    /// Full version display string with build number, e.g. "Version 1.0.0 (Build 1)".
    public static func fullDisplayString(in bundle: Bundle = .main) -> String {
        "Version \(marketingVersion(in: bundle)) (Build \(buildNumber(in: bundle)))"
    }

    /// Short version display string, e.g. "Version 1.0.0".
    public static func shortDisplayString(in bundle: Bundle = .main) -> String {
        "Version \(marketingVersion(in: bundle))"
    }

    // MARK: - Convenient Static Accessors

    /// Current marketing version string (e.g. "1.0.0").
    public static var current: String {
        marketingVersion()
    }

    /// Current build number string (e.g. "1").
    public static var build: String {
        buildNumber()
    }

    /// Formatted display string for settings/about, e.g. "Version 1.0.0 (Build 1)".
    public static var fullDisplay: String {
        fullDisplayString()
    }

    /// Formatted display string for dialogs/menu, e.g. "Version 1.0.0".
    public static var shortDisplay: String {
        shortDisplayString()
    }
}
