import Foundation
import CryptoKit
import Darwin

// MARK: - Token Storage Protocol & Keychain Implementation

public protocol GitHubTokenStoring: Sendable {
    func getAccessToken() async -> String?
    func saveAccessToken(_ token: String) async -> Bool
    func deleteAccessToken() async -> Bool
}

public struct KeychainGitHubTokenStore: GitHubTokenStoring {
    private let key = "github_access_token"

    public init() {}

    public func getAccessToken() async -> String? {
        await StorageManager.shared.getSecureItem(forKey: key)
    }

    public func saveAccessToken(_ token: String) async -> Bool {
        await StorageManager.shared.setSecureItem(token, forKey: key)
    }

    public func deleteAccessToken() async -> Bool {
        await StorageManager.shared.deleteSecureItem(forKey: key)
    }
}

// MARK: - Networking Protocol & URLSession Implementation

public protocol GitHubNetworking: Sendable {
    func send<T: Decodable>(_ request: URLRequest) async throws -> (T, HTTPURLResponse)
    func sendRaw(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public enum GitHubNetworkError: LocalizedError, Sendable, Equatable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingError(String)
    case rateLimited(resetDate: Date)
    case unauthorized
    case cancelled
    case timeout
    case stateMismatch
    case accessDenied
    case loopbackFailed(String)
    case backendError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .invalidResponse:
            return "Invalid server response."
        case .httpError(let statusCode, let message):
            return "GitHub error (\(statusCode)): \(message)"
        case .decodingError(let details):
            return "Failed to parse data: \(details)"
        case .rateLimited(let resetDate):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "GitHub rate limit exceeded. Resets at \(formatter.string(from: resetDate))."
        case .unauthorized:
            return "GitHub authentication token expired or invalid."
        case .cancelled:
            return "Authentication cancelled."
        case .timeout:
            return "Authorization timed out. Please try again."
        case .stateMismatch:
            return "Security state mismatch detected (possible CSRF). Authorization rejected."
        case .accessDenied:
            return "Authorization was denied by user."
        case .loopbackFailed(let reason):
            return "Loopback callback listener failed: \(reason)"
        case .backendError(let msg):
            return "Backend exchange failed: \(msg)"
        }
    }
}

public struct URLSessionGitHubNetworking: GitHubNetworking {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func sendRaw(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubNetworkError.invalidResponse
        }
        return (data, httpResponse)
    }

    public func send<T: Decodable>(_ request: URLRequest) async throws -> (T, HTTPURLResponse) {
        let (data, httpResponse) = try await sendRaw(request)

        if httpResponse.statusCode == 401 {
            throw GitHubNetworkError.unauthorized
        }

        if httpResponse.statusCode == 403 {
            if let resetHeader = httpResponse.value(forHTTPHeaderField: "x-ratelimit-reset"),
               let resetEpoch = TimeInterval(resetHeader) {
                let resetDate = Date(timeIntervalSince1970: resetEpoch)
                throw GitHubNetworkError.rateLimited(resetDate: resetDate)
            }
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errResp = try? JSONDecoder().decode(GitHubErrorResponse.self, from: data) {
                throw GitHubNetworkError.httpError(
                    statusCode: httpResponse.statusCode,
                    message: errResp.errorDescription ?? errResp.error
                )
            }
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw GitHubNetworkError.httpError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(T.self, from: data)
            return (decoded, httpResponse)
        } catch {
            throw GitHubNetworkError.decodingError(error.localizedDescription)
        }
    }
}

// MARK: - PKCE & Cryptographic State

public struct GitHubPKCE: Sendable, Equatable {
    public let codeVerifier: String
    public let codeChallenge: String
    public let codeChallengeMethod: String = "S256"

    public init(codeVerifier: String, codeChallenge: String) {
        self.codeVerifier = codeVerifier
        self.codeChallenge = codeChallenge
    }

    public static func generate() -> GitHubPKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))

        let hash = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))

        return GitHubPKCE(codeVerifier: verifier, codeChallenge: challenge)
    }

    public static func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - GitHub Configuration

public struct GitHubConfig: Sendable {
    /// Bundled default Client ID configured by developer
    public static let defaultClientId = "Ov23ligYE0KnaqNZATwc"

    public static var clientId: String {
        if let env = ProcessInfo.processInfo.environment["AMORA_GITHUB_CLIENT_ID"], !env.isEmpty {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let plistVal = Bundle.main.object(forInfoDictionaryKey: "AMORA_GITHUB_CLIENT_ID") as? String, !plistVal.isEmpty {
            return plistVal.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return defaultClientId
    }

    /// Bundled token-exchange backend endpoint
    public static let defaultBackendURL = URL(string: "https://amora-github-auth.omar-amora.workers.dev/api/github/token")!

    public static var backendExchangeURL: URL {
        if let env = ProcessInfo.processInfo.environment["AMORA_GITHUB_BACKEND_URL"], let url = URL(string: env) {
            return url
        }
        if let plistVal = Bundle.main.object(forInfoDictionaryKey: "AMORA_GITHUB_BACKEND_URL") as? String, let url = URL(string: plistVal) {
            return url
        }
        return defaultBackendURL
    }

    /// Requested OAuth scopes (minimum read-only profile, user events, repos, PRs)
    public static let scope = "read:user repo"
}

// MARK: - Native Loopback Listener Protocol & Implementation

public protocol GitHubLoopbackListening: Sendable {
    func start() async throws -> UInt16
    func waitForCallback(expectedState: String, timeoutSeconds: TimeInterval) async throws -> String
    func cancel()
}

final class LoopbackSocketState: @unchecked Sendable {
    private let lock = NSLock()
    private var serverFd: Int32 = -1
    private var assignedPort: UInt16 = 0
    private var isCancelled: Bool = false

    func openAndBind() throws -> UInt16 {
        try lock.withLock {
            isCancelled = false
            let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else {
                throw GitHubNetworkError.loopbackFailed("Failed to create socket.")
            }

            var opt: Int32 = 1
            Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = 0
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            var bindAddr = addr
            let bindRes = withUnsafePointer(to: &bindAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindRes == 0 else {
                Darwin.close(fd)
                throw GitHubNetworkError.loopbackFailed("Failed to bind socket to 127.0.0.1.")
            }

            guard Darwin.listen(fd, 1) == 0 else {
                Darwin.close(fd)
                throw GitHubNetworkError.loopbackFailed("Failed to listen on socket.")
            }

            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let nameRes = withUnsafeMutablePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    Darwin.getsockname(fd, sa, &len)
                }
            }
            guard nameRes == 0 else {
                Darwin.close(fd)
                throw GitHubNetworkError.loopbackFailed("Failed to get ephemeral port.")
            }

            let port = UInt16(bigEndian: addr.sin_port)
            self.serverFd = fd
            self.assignedPort = port
            return port
        }
    }

    func getSocketAndPort() -> (Int32, UInt16)? {
        lock.withLock {
            guard serverFd >= 0, !isCancelled else { return nil }
            return (serverFd, assignedPort)
        }
    }

    func cancel() {
        lock.withLock {
            isCancelled = true
            if serverFd >= 0 {
                Darwin.close(serverFd)
                serverFd = -1
            }
        }
    }

    func isCurrentlyCancelled() -> Bool {
        lock.withLock { isCancelled }
    }
}

public final class NativeSocketLoopbackListener: GitHubLoopbackListening, Sendable {
    private let state = LoopbackSocketState()

    public init() {}

    public func start() async throws -> UInt16 {
        try state.openAndBind()
    }

    public func waitForCallback(expectedState: String, timeoutSeconds: TimeInterval = 180) async throws -> String {
        let state = self.state
        return try await Task.detached {
            guard let (fd, port) = state.getSocketAndPort() else {
                throw GitHubNetworkError.cancelled
            }

            let start = Date()
            while Date().timeIntervalSince(start) < timeoutSeconds {
                if state.isCurrentlyCancelled() {
                    throw GitHubNetworkError.cancelled
                }

                var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let pollRes = Darwin.poll(&pfd, 1, 500)
                if pollRes > 0 {
                    if (pfd.revents & Int16(POLLIN)) != 0 {
                        var clientAddr = sockaddr_in()
                        var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                        let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                                Darwin.accept(fd, sa, &clientLen)
                            }
                        }
                        guard clientFd >= 0 else {
                            throw GitHubNetworkError.loopbackFailed("Failed to accept connection.")
                        }

                        defer {
                            Darwin.close(clientFd)
                            state.cancel()
                        }

                        var buffer = [UInt8](repeating: 0, count: 4096)
                        let bytesRead = Darwin.read(clientFd, &buffer, buffer.count)
                        guard bytesRead > 0, let reqString = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) else {
                            throw GitHubNetworkError.invalidResponse
                        }

                        guard let firstLine = reqString.components(separatedBy: "\r\n").first,
                              let pathAndQuery = firstLine.split(separator: " ").dropFirst().first else {
                            throw GitHubNetworkError.invalidResponse
                        }

                        guard let url = URL(string: "http://127.0.0.1:\(port)\(pathAndQuery)"),
                              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                            throw GitHubNetworkError.invalidResponse
                        }

                        let queryItems = components.queryItems ?? []
                        let code = queryItems.first(where: { $0.name == "code" })?.value
                        let stateParam = queryItems.first(where: { $0.name == "state" })?.value
                        let error = queryItems.first(where: { $0.name == "error" })?.value
                        let errorDesc = queryItems.first(where: { $0.name == "error_description" })?.value

                        if let error {
                            let respHtml = Self.htmlPage(
                                title: "Authentication Failed",
                                message: errorDesc ?? "GitHub authorization was not completed (\(error)).",
                                isError: true
                            )
                            Self.sendHTTPResponse(clientFd: clientFd, statusCode: 400, html: respHtml)
                            if error == "access_denied" {
                                throw GitHubNetworkError.accessDenied
                            } else {
                                throw GitHubNetworkError.httpError(statusCode: 400, message: errorDesc ?? error)
                            }
                        }

                        guard let receivedCode = code, !receivedCode.isEmpty else {
                            let respHtml = Self.htmlPage(title: "Error", message: "Missing authorization code.", isError: true)
                            Self.sendHTTPResponse(clientFd: clientFd, statusCode: 400, html: respHtml)
                            throw GitHubNetworkError.invalidResponse
                        }

                        guard let receivedState = stateParam, receivedState == expectedState else {
                            let respHtml = Self.htmlPage(title: "Security Verification Failed", message: "State token mismatch. Possible CSRF.", isError: true)
                            Self.sendHTTPResponse(clientFd: clientFd, statusCode: 400, html: respHtml)
                            throw GitHubNetworkError.stateMismatch
                        }

                        let successHtml = Self.htmlPage(
                            title: "Authorized!",
                            message: "You can close this tab and return to AMORA.",
                            isError: false
                        )
                        Self.sendHTTPResponse(clientFd: clientFd, statusCode: 200, html: successHtml)
                        return receivedCode
                    }
                } else if pollRes < 0 {
                    let err = errno
                    if err == EINTR { continue }
                    throw GitHubNetworkError.loopbackFailed("Socket poll failed (\(err)).")
                }
            }

            state.cancel()
            throw GitHubNetworkError.timeout
        }.value
    }

    public func cancel() {
        state.cancel()
    }

    private static func sendHTTPResponse(clientFd: Int32, statusCode: Int, html: String) {
        let statusText = statusCode == 200 ? "OK" : "Bad Request"
        let data = Data(html.utf8)
        let header = "HTTP/1.1 \(statusCode) \(statusText)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        let full = Data(header.utf8) + data
        _ = full.withUnsafeBytes { ptr in
            Darwin.write(clientFd, ptr.baseAddress, ptr.count)
        }
    }

    private static func htmlPage(title: String, message: String, isError: Bool) -> String {
        let accentColor = isError ? "#ff453a" : "#30d158"
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>AMORA - \(title)</title>
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
              background-color: #0d0e12;
              color: #ffffff;
              display: flex;
              align-items: center;
              justify-content: center;
              min-height: 100vh;
              margin: 0;
            }
            .card {
              background: rgba(255, 255, 255, 0.05);
              border: 1px solid rgba(255, 255, 255, 0.1);
              border-radius: 16px;
              padding: 36px 40px;
              text-align: center;
              max-width: 400px;
              box-shadow: 0 16px 40px rgba(0, 0, 0, 0.5);
            }
            h1 {
              color: \(accentColor);
              font-size: 22px;
              margin: 0 0 12px;
              font-weight: 600;
            }
            p {
              color: #8e8e93;
              font-size: 14px;
              line-height: 1.5;
              margin: 0;
            }
          </style>
        </head>
        <body>
          <div class="card">
            <h1>\(title)</h1>
            <p>\(message)</p>
          </div>
        </body>
        </html>
        """
    }
}

// MARK: - Token Exchanger Protocol & Implementation

public protocol GitHubTokenExchanging: Sendable {
    func exchangeCode(
        code: String,
        codeVerifier: String,
        redirectUri: String,
        clientId: String
    ) async throws -> GitHubTokenResponse
}

public struct BackendGitHubTokenExchanger: GitHubTokenExchanging {
    private let backendURL: URL
    private let networking: any GitHubNetworking

    public init(
        backendURL: URL = GitHubConfig.backendExchangeURL,
        networking: any GitHubNetworking = URLSessionGitHubNetworking()
    ) {
        self.backendURL = backendURL
        self.networking = networking
    }

    public func exchangeCode(
        code: String,
        codeVerifier: String,
        redirectUri: String,
        clientId: String
    ) async throws -> GitHubTokenResponse {
        var request = URLRequest(url: backendURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AMORA-macOS", forHTTPHeaderField: "User-Agent")

        let payload: [String: String] = [
            "code": code,
            "code_verifier": codeVerifier,
            "redirect_uri": redirectUri,
            "client_id": clientId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (tokenResponse, _): (GitHubTokenResponse, _) = try await networking.send(request)
        return tokenResponse
    }
}

// MARK: - GitHub Authentication State

public enum GitHubAuthState: Sendable, Equatable {
    case disconnected
    case connecting
    case authorizing(url: URL)
    case authenticating
    case connected(user: GitHubUser)
    case cancelled
    case rateLimited(resetDate: Date)
    case error(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
