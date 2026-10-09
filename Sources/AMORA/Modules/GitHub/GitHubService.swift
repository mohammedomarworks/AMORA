import Foundation
import Observation
import AppKit

@Observable @MainActor
public final class GitHubService {
    public static let shared = GitHubService()

    private let networking: any GitHubNetworking
    private let tokenStore: any GitHubTokenStoring
    private let tokenExchanger: any GitHubTokenExchanging
    private let loopbackListenerFactory: @Sendable () -> any GitHubLoopbackListening
    private var activeLoopback: (any GitHubLoopbackListening)?
    private var authTask: Task<Void, Never>?

    public private(set) var authState: GitHubAuthState = .disconnected
    public private(set) var user: GitHubUser? = nil
    public private(set) var repositories: [GitHubRepository] = []
    public private(set) var events: [GitHubEvent] = []
    public private(set) var pullRequests: [GitHubPullRequest] = []
    public private(set) var contributionCalendar: GitHubContributionCalendar? = nil
    public private(set) var isLoadingData: Bool = false
    public private(set) var dataErrorMessage: String? = nil

    public init(
        networking: any GitHubNetworking = URLSessionGitHubNetworking(),
        tokenStore: any GitHubTokenStoring = KeychainGitHubTokenStore(),
        tokenExchanger: (any GitHubTokenExchanging)? = nil,
        loopbackListenerFactory: (@Sendable () -> any GitHubLoopbackListening)? = nil
    ) {
        self.networking = networking
        self.tokenStore = tokenStore
        self.tokenExchanger = tokenExchanger ?? BackendGitHubTokenExchanger(networking: networking)
        self.loopbackListenerFactory = loopbackListenerFactory ?? { NativeSocketLoopbackListener() }
    }

    // MARK: - Initial Setup & Auth Verification

    public func checkExistingAuth() async {
        guard let token = await tokenStore.getAccessToken(), !token.isEmpty else {
            self.authState = .disconnected
            return
        }

        do {
            isLoadingData = true
            let profile = try await fetchProfile(token: token)
            self.user = profile
            self.authState = .connected(user: profile)
            await fetchAllData(token: token, username: profile.login)
            isLoadingData = false
        } catch let err as GitHubNetworkError {
            isLoadingData = false
            switch err {
            case .unauthorized:
                _ = await tokenStore.deleteAccessToken()
                self.user = nil
                self.authState = .disconnected
            case .rateLimited(let resetDate):
                self.authState = .rateLimited(resetDate: resetDate)
            default:
                self.authState = .error(err.localizedDescription)
            }
        } catch {
            isLoadingData = false
            self.authState = .error(error.localizedDescription)
        }
    }

    // MARK: - Authentication: OAuth 2.0 PKCE Flow

    public func startAuthentication() async {
        cancelAuthentication()

        authState = .connecting
        dataErrorMessage = nil

        let listener = loopbackListenerFactory()
        self.activeLoopback = listener

        authTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let pkce = GitHubPKCE.generate()
            let state = GitHubPKCE.generateState()

            do {
                let port = try await listener.start()
                guard !Task.isCancelled else {
                    listener.cancel()
                    self.authState = .cancelled
                    return
                }

                let redirectUri = "http://127.0.0.1:\(port)/callback"
                guard var components = URLComponents(string: "https://github.com/login/oauth/authorize") else {
                    self.authState = .error("Invalid authorization endpoint.")
                    return
                }

                components.queryItems = [
                    URLQueryItem(name: "client_id", value: GitHubConfig.clientId),
                    URLQueryItem(name: "redirect_uri", value: redirectUri),
                    URLQueryItem(name: "scope", value: GitHubConfig.scope),
                    URLQueryItem(name: "state", value: state),
                    URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
                    URLQueryItem(name: "code_challenge_method", value: pkce.codeChallengeMethod)
                ]

                guard let authURL = components.url else {
                    self.authState = .error("Failed to construct authorization URL.")
                    return
                }

                self.authState = .authorizing(url: authURL)
                NSWorkspace.shared.open(authURL)

                // Wait for the browser redirect callback on loopback port
                let code = try await listener.waitForCallback(expectedState: state, timeoutSeconds: 180)
                guard !Task.isCancelled else {
                    self.authState = .cancelled
                    return
                }

                self.authState = .authenticating

                // Exchange authorization code + PKCE verifier via HTTPS backend
                let tokenResponse = try await self.tokenExchanger.exchangeCode(
                    code: code,
                    codeVerifier: pkce.codeVerifier,
                    redirectUri: redirectUri,
                    clientId: GitHubConfig.clientId
                )

                // Save token securely in macOS Keychain
                _ = await self.tokenStore.saveAccessToken(tokenResponse.accessToken)

                // Fetch user profile and associated account data
                let profile = try await self.fetchProfile(token: tokenResponse.accessToken)
                self.user = profile
                self.authState = .connected(user: profile)

                await self.fetchAllData(token: tokenResponse.accessToken, username: profile.login)
            } catch let err as GitHubNetworkError {
                if case .cancelled = err {
                    self.authState = .cancelled
                } else if case .accessDenied = err {
                    self.authState = .error("GitHub authorization was denied.")
                } else if case .stateMismatch = err {
                    self.authState = .error("Security state mismatch. Please try connecting again.")
                } else if case .timeout = err {
                    self.authState = .error("Authorization timed out. Please try connecting again.")
                } else {
                    self.authState = .error(err.localizedDescription)
                }
            } catch {
                if Task.isCancelled {
                    self.authState = .cancelled
                } else {
                    self.authState = .error(error.localizedDescription)
                }
            }
        }
    }

    public func cancelAuthentication() {
        authTask?.cancel()
        authTask = nil
        activeLoopback?.cancel()
        activeLoopback = nil
        if !authState.isConnected {
            authState = .disconnected
        }
    }

    public func disconnect() async {
        cancelAuthentication()
        _ = await tokenStore.deleteAccessToken()
        self.user = nil
        self.repositories = []
        self.events = []
        self.pullRequests = []
        self.contributionCalendar = nil
        self.dataErrorMessage = nil
        self.authState = .disconnected
    }

    // MARK: - Data Fetching & Sync

    public func refreshData() async {
        guard let token = await tokenStore.getAccessToken(), !token.isEmpty else {
            await disconnect()
            return
        }

        isLoadingData = true
        dataErrorMessage = nil

        do {
            let profile = try await fetchProfile(token: token)
            self.user = profile
            self.authState = .connected(user: profile)
            await fetchAllData(token: token, username: profile.login)
            isLoadingData = false
        } catch let err as GitHubNetworkError {
            isLoadingData = false
            switch err {
            case .unauthorized:
                await disconnect()
                self.authState = .error("Session expired. Please reconnect.")
            case .rateLimited(let resetDate):
                self.authState = .rateLimited(resetDate: resetDate)
            default:
                self.dataErrorMessage = err.localizedDescription
            }
        } catch {
            isLoadingData = false
            self.dataErrorMessage = error.localizedDescription
        }
    }

    private func fetchAllData(token: String, username: String) async {
        async let reposTask: [GitHubRepository] = (try? fetchRepositories(token: token)) ?? []
        async let eventsTask: [GitHubEvent] = (try? fetchEvents(token: token, username: username)) ?? []
        async let prsTask: [GitHubPullRequest] = (try? fetchPullRequests(token: token, username: username)) ?? []
        async let calendarTask: GitHubContributionCalendar? = try? fetchContributionCalendar(token: token)

        let (repos, evts, prs, cal) = await (reposTask, eventsTask, prsTask, calendarTask)
        self.repositories = repos
        self.events = evts
        self.pullRequests = prs
        self.contributionCalendar = cal ?? GitHubContributionCalendar.generateFallback(from: evts)
    }

    public func fetchContributionCalendar(token: String) async throws -> GitHubContributionCalendar {
        guard let url = URL(string: "https://api.github.com/graphql") else {
            throw GitHubNetworkError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AMORA-macOS", forHTTPHeaderField: "User-Agent")

        let query = """
        query {
          viewer {
            contributionsCollection {
              contributionCalendar {
                totalContributions
                weeks {
                  contributionDays {
                    contributionCount
                    date
                    weekday
                    color
                    contributionLevel
                  }
                }
              }
            }
          }
        }
        """

        let payload = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (resp, _): (GitHubGraphQLDataResponse<GitHubViewerContributions>, _) = try await networking.send(request)
        guard let calendar = resp.data?.viewer.contributionsCollection.contributionCalendar else {
            if let firstErr = resp.errors?.first {
                throw GitHubNetworkError.backendError(firstErr.message)
            }
            throw GitHubNetworkError.decodingError("Missing contribution calendar in GraphQL response.")
        }
        return calendar
    }

    private func makeAuthenticatedRequest(urlString: String, token: String) throws -> URLRequest {
        guard let url = URL(string: urlString) else {
            throw GitHubNetworkError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AMORA-macOS", forHTTPHeaderField: "User-Agent")
        return request
    }

    public func fetchProfile(token: String) async throws -> GitHubUser {
        let req = try makeAuthenticatedRequest(urlString: "https://api.github.com/user", token: token)
        let (user, _): (GitHubUser, _) = try await networking.send(req)
        return user
    }

    public func fetchRepositories(token: String) async throws -> [GitHubRepository] {
        let req = try makeAuthenticatedRequest(
            urlString: "https://api.github.com/user/repos?sort=updated&per_page=5&type=all",
            token: token
        )
        let (repos, _): ([GitHubRepository], _) = try await networking.send(req)
        return repos
    }

    public func fetchEvents(token: String, username: String) async throws -> [GitHubEvent] {
        let req = try makeAuthenticatedRequest(
            urlString: "https://api.github.com/users/\(username)/events?per_page=10",
            token: token
        )
        let (evts, _): ([GitHubEvent], _) = try await networking.send(req)
        return evts
    }

    public func fetchPullRequests(token: String, username: String) async throws -> [GitHubPullRequest] {
        guard let encodedUser = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }
        let req = try makeAuthenticatedRequest(
            urlString: "https://api.github.com/search/issues?q=author:\(encodedUser)+type:pr+state:open&per_page=5",
            token: token
        )
        let (resp, _): (GitHubSearchIssuesResponse, _) = try await networking.send(req)
        return resp.items
    }
}
