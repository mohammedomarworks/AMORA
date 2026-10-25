import Foundation
#if os(macOS)
import Security
#endif
import CryptoKit

/// Abstract protocol for storing secure credentials (API keys, auth tokens).
public protocol SecureCredentialStoring: Sendable {
    func setSecureItem(_ value: String, forKey key: String) -> Bool
    func getSecureItem(forKey key: String) -> String?
    func deleteSecureItem(forKey key: String) -> Bool
}

#if os(macOS)
/// macOS Keychain implementation of secure credential storage.
public struct MacOSKeychainCredentialStorage: SecureCredentialStoring {
    public init() {}

    public func setSecureItem(_ value: String, forKey key: String) -> Bool {
        _ = deleteSecureItem(forKey: key)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return true
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.amora.app",
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    public func getSecureItem(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.amora.app",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    public func deleteSecureItem(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.amora.app"
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
#endif

actor StorageManager {
    static let shared = StorageManager()

    private let fileManager = FileManager.default
    private let appSupportURL: URL
    private let secureStorage: any SecureCredentialStoring

    private init(secureStorage: (any SecureCredentialStoring)? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directoryURL = appSupport.appendingPathComponent("AMORA", isDirectory: true)
        self.appSupportURL = directoryURL
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        #if os(macOS)
        self.secureStorage = secureStorage ?? MacOSKeychainCredentialStorage()
        #else
        guard let storage = secureStorage else {
            fatalError("No SecureCredentialStoring implementation configured for this platform")
        }
        self.secureStorage = storage
        #endif
    }

    func load<T: Decodable>(from filename: String) async -> T? {
        let url = appSupportURL.appendingPathComponent(filename).appendingPathExtension("json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    func save<T: Encodable>(_ value: T, to filename: String) async {
        let url = appSupportURL.appendingPathComponent(filename).appendingPathExtension("json")
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(value)
            try data.write(to: url)
        } catch {
            // Silent fail for settings data
        }
    }

    nonisolated func save() {
        // Called during app termination — persist any pending state
    }

    nonisolated func load() {
        // Load any cached data
    }

    // MARK: - Secure Credential Storage

    @discardableResult
    nonisolated func setSecureItem(_ value: String, forKey key: String) -> Bool {
        secureStorage.setSecureItem(value, forKey: key)
    }

    nonisolated func getSecureItem(forKey key: String) -> String? {
        secureStorage.getSecureItem(forKey: key)
    }

    @discardableResult
    nonisolated func deleteSecureItem(forKey key: String) -> Bool {
        secureStorage.deleteSecureItem(forKey: key)
    }

    func storeFileReference(url: URL) async -> String? {
        return url.path
    }
}
