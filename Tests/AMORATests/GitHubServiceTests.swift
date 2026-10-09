import XCTest
import CryptoKit
@testable import AMORA

// MARK: - Mocks for Testing

final class MockGitHubTokenStore: GitHubTokenStoring, @unchecked Sendable {
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func getAccessToken() async -> String? {
        return token
    }

    func saveAccessToken(_ token: String) async -> Bool {
        self.token = token
        return true
    }

    func deleteAccessToken() async -> Bool {
        self.token = nil
        return true
    }
}

final class MockGitHubNetworking: GitHubNetworking, @unchecked Sendable {
    var rawHandler: (@Sendable (URLRequest) throws -> (Data, HTTPURLResponse))?

    init(rawHandler: (@Sendable (URLRequest) throws -> (Data, HTTPURLResponse))? = nil) {
        self.rawHandler = rawHandler
    }

    func sendRaw(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let handler = rawHandler {
            return try handler(request)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(), response)
    }

    func send<T: Decodable>(_ request: URLRequest) async throws -> (T, HTTPURLResponse) {
        let (data, response) = try await sendRaw(request)

        if response.statusCode == 401 {
            throw GitHubNetworkError.unauthorized
        }

        if response.statusCode == 403 {
            if let resetHeader = response.value(forHTTPHeaderField: "x-ratelimit-reset"),
               let resetEpoch = TimeInterval(resetHeader) {
                let resetDate = Date(timeIntervalSince1970: resetEpoch)
                throw GitHubNetworkError.rateLimited(resetDate: resetDate)
            }
        }

        guard (200...299).contains(response.statusCode) else {
            if let errResp = try? JSONDecoder().decode(GitHubErrorResponse.self, from: data) {
                throw GitHubNetworkError.httpError(
                    statusCode: response.statusCode,
                    message: errResp.errorDescription ?? errResp.error
                )
            }
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(response.statusCode)"
            throw GitHubNetworkError.httpError(statusCode: response.statusCode, message: errorMsg)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(T.self, from: data)
            return (decoded, response)
        } catch {
            throw GitHubNetworkError.decodingError(error.localizedDescription)
        }
    }
}

final class MockGitHubLoopbackListener: GitHubLoopbackListening, @unchecked Sendable {
    var portToReturn: UInt16 = 54321
    var codeToReturn: String = "mock_auth_code_999"
    var errorToThrow: GitHubNetworkError? = nil
    var stateReceived: String? = nil
    var isCancelled: Bool = false

    func start() async throws -> UInt16 {
        if let error = errorToThrow {
            throw error
        }
        return portToReturn
    }

    func waitForCallback(expectedState: String, timeoutSeconds: TimeInterval) async throws -> String {
        self.stateReceived = expectedState
        if isCancelled {
            throw GitHubNetworkError.cancelled
        }
        if let error = errorToThrow {
            throw error
        }
        return codeToReturn
    }

    func cancel() {
        self.isCancelled = true
    }
}

final class MockGitHubTokenExchanger: GitHubTokenExchanging, @unchecked Sendable {
    var responseToReturn: GitHubTokenResponse = GitHubTokenResponse(accessToken: "mock_access_token_xyz", tokenType: "bearer", scope: "read:user repo")
    var errorToThrow: Error? = nil

    var lastCode: String?
    var lastCodeVerifier: String?
    var lastRedirectUri: String?
    var lastClientId: String?

    func exchangeCode(code: String, codeVerifier: String, redirectUri: String, clientId: String) async throws -> GitHubTokenResponse {
        self.lastCode = code
        self.lastCodeVerifier = codeVerifier
        self.lastRedirectUri = redirectUri
        self.lastClientId = clientId

        if let error = errorToThrow {
            throw error
        }
        return responseToReturn
    }
}

// MARK: - Unit Tests

@MainActor
final class GitHubServiceTests: XCTestCase {

    // MARK: - PKCE & Cryptographic State Tests

    func testPKCEGenerationAndEntropy() {
        let pkce1 = GitHubPKCE.generate()
        let pkce2 = GitHubPKCE.generate()

        // Verifier length in RFC 7636 is between 43 and 128 characters
        XCTAssertGreaterThanOrEqual(pkce1.codeVerifier.count, 43)
        XCTAssertLessThanOrEqual(pkce1.codeVerifier.count, 128)
        XCTAssertEqual(pkce1.codeChallengeMethod, "S256")

        // Uniqueness / entropy
        XCTAssertNotEqual(pkce1.codeVerifier, pkce2.codeVerifier)
        XCTAssertNotEqual(pkce1.codeChallenge, pkce2.codeChallenge)

        // Verify SHA-256 calculation
        let hash = SHA256.hash(data: Data(pkce1.codeVerifier.utf8))
        let expectedChallenge = Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        XCTAssertEqual(pkce1.codeChallenge, expectedChallenge)
    }

    func testStateGenerationEntropy() {
        let state1 = GitHubPKCE.generateState()
        let state2 = GitHubPKCE.generateState()

        XCTAssertFalse(state1.isEmpty)
        XCTAssertFalse(state2.isEmpty)
        XCTAssertNotEqual(state1, state2)
        XCTAssertEqual(state1.count, 48) // 24 bytes in hex
    }

    // MARK: - Model Decoding Tests

    func testGitHubUserDecoding() throws {
        let json = """
        {
            "id": 583231,
            "login": "octocat",
            "name": "The Octocat",
            "avatar_url": "https://avatars.githubusercontent.com/u/583231",
            "html_url": "https://github.com/octocat",
            "bio": "GitHub mascot",
            "public_repos": 8
        }
        """.data(using: .utf8)!

        let user = try JSONDecoder().decode(GitHubUser.self, from: json)
        XCTAssertEqual(user.id, 583231)
        XCTAssertEqual(user.login, "octocat")
        XCTAssertEqual(user.name, "The Octocat")
        XCTAssertEqual(user.avatarUrl, "https://avatars.githubusercontent.com/u/583231")
        XCTAssertEqual(user.htmlUrl, "https://github.com/octocat")
        XCTAssertEqual(user.bio, "GitHub mascot")
        XCTAssertEqual(user.publicRepos, 8)
    }

    func testGitHubRepositoryDecoding() throws {
        let json = """
        {
            "id": 1296269,
            "name": "Hello-World",
            "full_name": "octocat/Hello-World",
            "html_url": "https://github.com/octocat/Hello-World",
            "description": "This is your first repo!",
            "language": "Swift",
            "stargazers_count": 1337,
            "private": false
        }
        """.data(using: .utf8)!

        let repo = try JSONDecoder().decode(GitHubRepository.self, from: json)
        XCTAssertEqual(repo.id, 1296269)
        XCTAssertEqual(repo.name, "Hello-World")
        XCTAssertEqual(repo.fullName, "octocat/Hello-World")
        XCTAssertEqual(repo.language, "Swift")
        XCTAssertEqual(repo.stargazersCount, 1337)
        XCTAssertFalse(repo.isPrivate)
    }

    func testGitHubEventDecodingAndSummaries() throws {
        let pushJson = """
        {
            "id": "1001",
            "type": "PushEvent",
            "repo": { "id": 1, "name": "owner/repo" },
            "payload": {
                "size": 3,
                "commits": [
                    { "sha": "abc1234", "message": "Add wide dynamic island" }
                ]
            }
        }
        """.data(using: .utf8)!

        let pushEvent = try JSONDecoder().decode(GitHubEvent.self, from: pushJson)
        XCTAssertEqual(pushEvent.type, "PushEvent")
        XCTAssertEqual(pushEvent.repo.name, "owner/repo")
        XCTAssertEqual(pushEvent.summary, "Pushed 3 commits")

        let prJson = """
        {
            "id": "1002",
            "type": "PullRequestEvent",
            "repo": { "id": 1, "name": "owner/repo" },
            "payload": { "action": "opened" }
        }
        """.data(using: .utf8)!

        let prEvent = try JSONDecoder().decode(GitHubEvent.self, from: prJson)
        XCTAssertEqual(prEvent.summary, "Opened pull request")

        let starJson = """
        {
            "id": "1003",
            "type": "WatchEvent",
            "repo": { "id": 1, "name": "owner/repo" }
        }
        """.data(using: .utf8)!

        let starEvent = try JSONDecoder().decode(GitHubEvent.self, from: starJson)
        XCTAssertEqual(starEvent.summary, "Starred repository")
    }

    func testGitHubPullRequestDecodingAndEncoding() throws {
        let json = """
        {
            "id": 99901,
            "number": 42,
            "title": "Add One-Click GitHub Connection",
            "html_url": "https://github.com/owner/amora/pull/42",
            "state": "open",
            "created_at": "2026-10-09T12:00:00Z",
            "repository_url": "https://api.github.com/repos/owner/amora"
        }
        """.data(using: .utf8)!

        let pr = try JSONDecoder().decode(GitHubPullRequest.self, from: json)
        XCTAssertEqual(pr.id, 99901)
        XCTAssertEqual(pr.number, 42)
        XCTAssertEqual(pr.title, "Add One-Click GitHub Connection")
        XCTAssertEqual(pr.repoFullName, "owner/amora")
        XCTAssertEqual(pr.state, "open")
        XCTAssertNotNil(pr.createdAt)

        // Encoding roundtrip test
        let encoded = try JSONEncoder().encode(pr)
        let roundtripPR = try JSONDecoder().decode(GitHubPullRequest.self, from: encoded)
        XCTAssertEqual(roundtripPR.id, pr.id)
        XCTAssertEqual(roundtripPR.number, pr.number)
        XCTAssertEqual(roundtripPR.title, pr.title)
        XCTAssertEqual(roundtripPR.repoFullName, "owner/amora")
    }

    func testTokenResponseDecoding() throws {
        let json = """
        {
            "access_token": "ghu_16C7e42F292c6912E7710c838347Ae178B4a",
            "token_type": "bearer",
            "scope": "read:user repo"
        }
        """.data(using: .utf8)!

        let res = try JSONDecoder().decode(GitHubTokenResponse.self, from: json)
        XCTAssertEqual(res.accessToken, "ghu_16C7e42F292c6912E7710c838347Ae178B4a")
        XCTAssertEqual(res.tokenType, "bearer")
        XCTAssertEqual(res.scope, "read:user repo")
    }

    func testErrorResponseDecoding() throws {
        let json = """
        {
            "error": "bad_verification_code",
            "error_description": "The code passed is incorrect or has expired."
        }
        """.data(using: .utf8)!

        let res = try JSONDecoder().decode(GitHubErrorResponse.self, from: json)
        XCTAssertEqual(res.error, "bad_verification_code")
        XCTAssertEqual(res.errorDescription, "The code passed is incorrect or has expired.")
    }

    // MARK: - State & Token Store Tests

    func testAuthStateConnectedProperty() {
        XCTAssertFalse(GitHubAuthState.disconnected.isConnected)
        XCTAssertFalse(GitHubAuthState.connecting.isConnected)
        XCTAssertFalse(GitHubAuthState.authorizing(url: URL(string: "https://github.com")!).isConnected)
        XCTAssertFalse(GitHubAuthState.authenticating.isConnected)
        XCTAssertFalse(GitHubAuthState.cancelled.isConnected)
        XCTAssertFalse(GitHubAuthState.rateLimited(resetDate: Date()).isConnected)
        XCTAssertFalse(GitHubAuthState.error("failed").isConnected)

        let mockUser = GitHubUser(id: 1, login: "octocat", name: "The Octocat", avatarUrl: nil, htmlUrl: "https://github.com/octocat", bio: nil, publicRepos: 1)
        XCTAssertTrue(GitHubAuthState.connected(user: mockUser).isConnected)
    }

    func testMockTokenStore() async {
        let store = MockGitHubTokenStore()
        let initial = await store.getAccessToken()
        XCTAssertNil(initial)

        let saved = await store.saveAccessToken("test_token_123")
        XCTAssertTrue(saved)

        let retrieved = await store.getAccessToken()
        XCTAssertEqual(retrieved, "test_token_123")

        let deleted = await store.deleteAccessToken()
        XCTAssertTrue(deleted)

        let afterDelete = await store.getAccessToken()
        XCTAssertNil(afterDelete)
    }

    // MARK: - Loopback Socket Listener Tests

    func testNativeSocketLoopbackListenerSuccess() async throws {
        let listener = NativeSocketLoopbackListener()
        let port = try await listener.start()
        XCTAssertGreaterThan(port, 0)

        // Make an async HTTP request simulating the browser callback
        let expectedState = "sec_state_456"
        let expectedCode = "gh_code_789"

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            let callbackURL = URL(string: "http://127.0.0.1:\(port)/callback?code=\(expectedCode)&state=\(expectedState)")!
            let task = URLSession.shared.dataTask(with: callbackURL)
            task.resume()
        }

        let receivedCode = try await listener.waitForCallback(expectedState: expectedState, timeoutSeconds: 5)
        XCTAssertEqual(receivedCode, expectedCode)
    }

    func testNativeSocketLoopbackListenerStateMismatchThrows() async throws {
        let listener = NativeSocketLoopbackListener()
        let port = try await listener.start()
        XCTAssertGreaterThan(port, 0)

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            let callbackURL = URL(string: "http://127.0.0.1:\(port)/callback?code=some_code&state=mismatched_state")!
            let task = URLSession.shared.dataTask(with: callbackURL)
            task.resume()
        }

        do {
            _ = try await listener.waitForCallback(expectedState: "correct_state", timeoutSeconds: 5)
            XCTFail("Expected stateMismatch error to be thrown")
        } catch let err as GitHubNetworkError {
            XCTAssertEqual(err, .stateMismatch)
        }
    }

    func testNativeSocketLoopbackListenerAccessDeniedThrows() async throws {
        let listener = NativeSocketLoopbackListener()
        let port = try await listener.start()
        XCTAssertGreaterThan(port, 0)

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            let callbackURL = URL(string: "http://127.0.0.1:\(port)/callback?error=access_denied&error_description=User+cancelled")!
            let task = URLSession.shared.dataTask(with: callbackURL)
            task.resume()
        }

        do {
            _ = try await listener.waitForCallback(expectedState: "any_state", timeoutSeconds: 5)
            XCTFail("Expected accessDenied error to be thrown")
        } catch let err as GitHubNetworkError {
            XCTAssertEqual(err, .accessDenied)
        }
    }

    // MARK: - Backend Token Exchanger Tests

    func testBackendGitHubTokenExchangerSuccess() async throws {
        let mockNet = MockGitHubNetworking { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try! JSONSerialization.jsonObject(with: req.httpBody!) as! [String: String]
            XCTAssertEqual(body["code"], "auth_code_123")
            XCTAssertEqual(body["code_verifier"], "verifier_456")
            XCTAssertEqual(body["redirect_uri"], "http://127.0.0.1:8080/callback")
            XCTAssertEqual(body["client_id"], "Ov23client")

            let tokenObj = GitHubTokenResponse(accessToken: "ghu_live_token", tokenType: "bearer", scope: "read:user repo")
            let data = try! JSONEncoder().encode(tokenObj)
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, resp)
        }

        let exchanger = BackendGitHubTokenExchanger(
            backendURL: URL(string: "https://amora-auth.workers.dev/api/github/token")!,
            networking: mockNet
        )

        let result = try await exchanger.exchangeCode(
            code: "auth_code_123",
            codeVerifier: "verifier_456",
            redirectUri: "http://127.0.0.1:8080/callback",
            clientId: "Ov23client"
        )

        XCTAssertEqual(result.accessToken, "ghu_live_token")
        XCTAssertEqual(result.tokenType, "bearer")
    }

    func testBackendGitHubTokenExchangerError() async throws {
        let mockNet = MockGitHubNetworking { req in
            let errorObj = GitHubErrorResponse(error: "bad_verification_code", errorDescription: "Code expired")
            let data = try! JSONEncoder().encode(errorObj)
            let resp = HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (data, resp)
        }

        let exchanger = BackendGitHubTokenExchanger(
            backendURL: URL(string: "https://amora-auth.workers.dev/api/github/token")!,
            networking: mockNet
        )

        do {
            _ = try await exchanger.exchangeCode(
                code: "expired_code",
                codeVerifier: "verifier",
                redirectUri: "http://127.0.0.1:8080/callback",
                clientId: "client"
            )
            XCTFail("Expected token exchange to fail with httpError")
        } catch let err as GitHubNetworkError {
            if case .httpError(let statusCode, let message) = err {
                XCTAssertEqual(statusCode, 400)
                XCTAssertEqual(message, "Code expired")
            } else {
                XCTFail("Expected httpError, got \(err)")
            }
        }
    }

    // MARK: - End-to-End One-Click Authentication Tests

    func testOneClickAuthenticationFlowSuccess() async {
        let tokenStore = MockGitHubTokenStore()
        let mockListener = MockGitHubLoopbackListener()
        mockListener.portToReturn = 61234
        mockListener.codeToReturn = "received_auth_code_42"

        let mockExchanger = MockGitHubTokenExchanger()
        mockExchanger.responseToReturn = GitHubTokenResponse(accessToken: "valid_new_token_123", tokenType: "bearer", scope: "read:user repo")

        let mockNet = MockGitHubNetworking { req in
            let urlStr = req.url?.absoluteString ?? ""
            if urlStr.contains("/user/repos") {
                let repos = [
                    GitHubRepository(id: 1, name: "Amora", fullName: "omar/Amora", htmlUrl: "https://github.com/omar/Amora", description: "Companion", isPrivate: false, stargazersCount: 50, language: "Swift")
                ]
                let data = try! JSONEncoder().encode(repos)
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (data, resp)
            } else if urlStr.contains("/events") {
                let events = [
                    GitHubEvent(id: "1", type: "WatchEvent", repo: GitHubEvent.GitHubEventRepo(id: 1, name: "omar/Amora"))
                ]
                let data = try! JSONEncoder().encode(events)
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (data, resp)
            } else if urlStr.contains("/search/issues") {
                let prs = GitHubSearchIssuesResponse(totalCount: 1, items: [
                    GitHubPullRequest(id: 10, number: 1, title: "Feature", htmlUrl: "https://github.com/omar/Amora/pull/1", state: "open", repoFullName: "omar/Amora")
                ])
                let data = try! JSONEncoder().encode(prs)
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (data, resp)
            } else {
                // Profile
                let user = GitHubUser(id: 1, login: "omar", name: "Omar", avatarUrl: "https://avatars.github.com/u/1", htmlUrl: "https://github.com/omar", bio: "Creator", publicRepos: 10)
                let data = try! JSONEncoder().encode(user)
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (data, resp)
            }
        }

        let service = GitHubService(
            networking: mockNet,
            tokenStore: tokenStore,
            tokenExchanger: mockExchanger,
            loopbackListenerFactory: { mockListener }
        )

        XCTAssertEqual(service.authState, .disconnected)

        await service.startAuthentication()

        // Wait a tiny bit for the task to finish
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Verify connected state
        XCTAssertTrue(service.authState.isConnected)
        XCTAssertEqual(service.user?.login, "omar")
        XCTAssertEqual(service.repositories.count, 1)
        XCTAssertEqual(service.events.count, 1)
        XCTAssertEqual(service.pullRequests.count, 1)

        // Verify token saved in tokenStore
        let savedToken = await tokenStore.getAccessToken()
        XCTAssertEqual(savedToken, "valid_new_token_123")

        // Verify exchanger received the correct parameters
        XCTAssertEqual(mockExchanger.lastCode, "received_auth_code_42")
        XCTAssertEqual(mockExchanger.lastRedirectUri, "http://127.0.0.1:61234/callback")
    }

    func testAuthCancellation() async {
        let tokenStore = MockGitHubTokenStore()
        let mockListener = MockGitHubLoopbackListener()
        let mockExchanger = MockGitHubTokenExchanger()
        let mockNet = MockGitHubNetworking()

        let service = GitHubService(
            networking: mockNet,
            tokenStore: tokenStore,
            tokenExchanger: mockExchanger,
            loopbackListenerFactory: { mockListener }
        )

        service.cancelAuthentication()
        XCTAssertEqual(service.authState, .disconnected)
        XCTAssertFalse(service.authState.isConnected)
    }

    func testDisconnectRemovesTokenAndResetsData() async {
        let tokenStore = MockGitHubTokenStore(token: "active_token")
        let service = GitHubService(tokenStore: tokenStore)

        await service.disconnect()

        let stored = await tokenStore.getAccessToken()
        XCTAssertNil(stored)
        XCTAssertNil(service.user)
        XCTAssertTrue(service.repositories.isEmpty)
        XCTAssertTrue(service.events.isEmpty)
        XCTAssertTrue(service.pullRequests.isEmpty)
        XCTAssertEqual(service.authState, .disconnected)
    }

    func testCheckExistingAuthSuccess() async {
        let tokenStore = MockGitHubTokenStore(token: "saved_token_777")
        let mockNet = MockGitHubNetworking { req in
            let user = GitHubUser(id: 42, login: "alice", name: "Alice", avatarUrl: nil, htmlUrl: "https://github.com/alice", bio: nil, publicRepos: 5)
            let data = try! JSONEncoder().encode(user)
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, resp)
        }

        let service = GitHubService(networking: mockNet, tokenStore: tokenStore)
        await service.checkExistingAuth()

        XCTAssertTrue(service.authState.isConnected)
        XCTAssertEqual(service.user?.login, "alice")
    }

    func testCheckExistingAuthExpiredTokenClearsStorage() async {
        let tokenStore = MockGitHubTokenStore(token: "expired_token_000")
        let mockNet = MockGitHubNetworking { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data("{\"message\":\"Bad credentials\"}".utf8), resp)
        }

        let service = GitHubService(networking: mockNet, tokenStore: tokenStore)
        await service.checkExistingAuth()

        let stored = await tokenStore.getAccessToken()
        XCTAssertNil(stored)
        XCTAssertEqual(service.authState, .disconnected)
    }

    func testRateLimitHandling() async {
        let tokenStore = MockGitHubTokenStore(token: "token")
        let resetEpoch = Date().addingTimeInterval(1800).timeIntervalSince1970
        let mockNet = MockGitHubNetworking { req in
            let headers = ["x-ratelimit-reset": "\(Int(resetEpoch))"]
            let resp = HTTPURLResponse(url: req.url!, statusCode: 403, httpVersion: nil, headerFields: headers)!
            return (Data("Rate limit exceeded".utf8), resp)
        }

        let service = GitHubService(networking: mockNet, tokenStore: tokenStore)
        await service.checkExistingAuth()

        if case .rateLimited = service.authState {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected rateLimited auth state, got \(service.authState)")
        }
    }

    // MARK: - Contribution Heatmap & Calendar Tests

    func testContributionDayFormattingAndLevels() {
        let day10 = GitHubContributionDay(contributionCount: 10, date: "2026-09-01", weekday: 2)
        XCTAssertEqual(day10.formattedDate, "Sep 1")
        XCTAssertEqual(day10.contributionSummary, "Sep 1 · 10 contributions")
        XCTAssertEqual(day10.level, 4)

        let day1 = GitHubContributionDay(contributionCount: 1, date: "2026-09-02", weekday: 3)
        XCTAssertEqual(day1.formattedDate, "Sep 2")
        XCTAssertEqual(day1.contributionSummary, "Sep 2 · 1 contribution")
        XCTAssertEqual(day1.level, 1)

        let day0 = GitHubContributionDay(contributionCount: 0, date: "2026-10-09", weekday: 5)
        XCTAssertEqual(day0.formattedDate, "Oct 9")
        XCTAssertEqual(day0.contributionSummary, "Oct 9 · 0 contributions")
        XCTAssertEqual(day0.level, 0)

        let dayQuartile = GitHubContributionDay(
            contributionCount: 3,
            date: "2026-08-15",
            weekday: 6,
            contributionLevel: "THIRD_QUARTILE"
        )
        XCTAssertEqual(dayQuartile.level, 3)

        let dayQuartileNone = GitHubContributionDay(
            contributionCount: 0,
            date: "2026-08-16",
            weekday: 0,
            contributionLevel: "NONE"
        )
        XCTAssertEqual(dayQuartileNone.level, 0)
    }

    func testContributionCalendarDecodingFromGraphQL() throws {
        let json = """
        {
          "data": {
            "viewer": {
              "contributionsCollection": {
                "contributionCalendar": {
                  "totalContributions": 42,
                  "weeks": [
                    {
                      "contributionDays": [
                        {
                          "contributionCount": 5,
                          "date": "2026-09-01",
                          "weekday": 2,
                          "color": "#26a641",
                          "contributionLevel": "SECOND_QUARTILE"
                        },
                        {
                          "contributionCount": 10,
                          "date": "2026-09-02",
                          "weekday": 3,
                          "color": "#39d353",
                          "contributionLevel": "FOURTH_QUARTILE"
                        }
                      ]
                    }
                  ]
                }
              }
            }
          }
        }
        """

        let decoded = try JSONDecoder().decode(GitHubGraphQLDataResponse<GitHubViewerContributions>.self, from: Data(json.utf8))
        let calendar = try XCTUnwrap(decoded.data?.viewer.contributionsCollection.contributionCalendar)

        XCTAssertEqual(calendar.totalContributions, 42)
        XCTAssertEqual(calendar.weeks.count, 1)
        XCTAssertEqual(calendar.weeks[0].days.count, 2)
        XCTAssertEqual(calendar.weeks[0].days[0].contributionCount, 5)
        XCTAssertEqual(calendar.weeks[0].days[0].contributionSummary, "Sep 1 · 5 contributions")
        XCTAssertEqual(calendar.weeks[0].days[1].contributionCount, 10)
        XCTAssertEqual(calendar.weeks[0].days[1].contributionSummary, "Sep 2 · 10 contributions")
    }

    func testContributionCalendarFallbackFromEvents() {
        let date = Date()
        let event = GitHubEvent(
            id: "evt_1",
            type: "PushEvent",
            repo: .init(name: "omar/Amora"),
            createdAt: date,
            payload: .init(size: 3)
        )

        let fallback = GitHubContributionCalendar.generateFallback(from: [event], daysCount: 14)

        XCTAssertGreaterThanOrEqual(fallback.totalContributions, 3)
        XCTAssertFalse(fallback.weeks.isEmpty)
        let allDays = fallback.weeks.flatMap { $0.days }
        XCTAssertGreaterThanOrEqual(allDays.count, 14)
    }

    func testFetchContributionCalendarServiceSuccess() async throws {
        let graphQLJson = """
        {
          "data": {
            "viewer": {
              "contributionsCollection": {
                "contributionCalendar": {
                  "totalContributions": 128,
                  "weeks": [
                    {
                      "contributionDays": [
                        {
                          "contributionCount": 4,
                          "date": "2026-09-01",
                          "weekday": 2,
                          "contributionLevel": "SECOND_QUARTILE"
                        }
                      ]
                    }
                  ]
                }
              }
            }
          }
        }
        """

        let mockNet = MockGitHubNetworking { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.url?.absoluteString, "https://api.github.com/graphql")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(graphQLJson.utf8), resp)
        }

        let service = GitHubService(networking: mockNet, tokenStore: MockGitHubTokenStore())
        let cal = try await service.fetchContributionCalendar(token: "valid_mock_token")

        XCTAssertEqual(cal.totalContributions, 128)
        XCTAssertEqual(cal.weeks.count, 1)
        XCTAssertEqual(cal.weeks[0].days[0].contributionCount, 4)
    }

    func testDisconnectResetsContributionCalendar() async {
        let user = GitHubUser(id: 1, login: "alice", htmlUrl: "https://github.com/alice")
        let tokenStore = MockGitHubTokenStore(token: "active_token")

        let graphQLJson = """
        {
          "data": {
            "viewer": {
              "contributionsCollection": {
                "contributionCalendar": {
                  "totalContributions": 50,
                  "weeks": []
                }
              }
            }
          }
        }
        """

        let mockNet = MockGitHubNetworking { req in
            let path = req.url?.absoluteString ?? ""
            if path.contains("graphql") {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(graphQLJson.utf8), resp)
            }
            if path.contains("/user") {
                let data = try! JSONEncoder().encode(user)
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (data, resp)
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("[]".utf8), resp)
        }

        let service = GitHubService(networking: mockNet, tokenStore: tokenStore)
        await service.checkExistingAuth()

        XCTAssertTrue(service.authState.isConnected)
        XCTAssertNotNil(service.contributionCalendar)

        await service.disconnect()

        XCTAssertFalse(service.authState.isConnected)
        XCTAssertNil(service.contributionCalendar)
    }
}
