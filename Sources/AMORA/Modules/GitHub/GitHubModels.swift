import Foundation

// MARK: - GitHub User Profile
public struct GitHubUser: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let login: String
    public let name: String?
    public let avatarUrl: String?
    public let htmlUrl: String
    public let bio: String?
    public let publicRepos: Int?
    public let followers: Int?
    public let following: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case name
        case avatarUrl = "avatar_url"
        case htmlUrl = "html_url"
        case bio
        case publicRepos = "public_repos"
        case followers
        case following
    }

    public init(
        id: Int,
        login: String,
        name: String? = nil,
        avatarUrl: String? = nil,
        htmlUrl: String,
        bio: String? = nil,
        publicRepos: Int? = nil,
        followers: Int? = nil,
        following: Int? = nil
    ) {
        self.id = id
        self.login = login
        self.name = name
        self.avatarUrl = avatarUrl
        self.htmlUrl = htmlUrl
        self.bio = bio
        self.publicRepos = publicRepos
        self.followers = followers
        self.following = following
    }
}

// MARK: - GitHub Repository
public struct GitHubRepository: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let fullName: String
    public let htmlUrl: String
    public let description: String?
    public let isPrivate: Bool
    public let stargazersCount: Int
    public let language: String?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case htmlUrl = "html_url"
        case description
        case isPrivate = "private"
        case stargazersCount = "stargazers_count"
        case language
        case updatedAt = "updated_at"
    }

    public init(
        id: Int,
        name: String,
        fullName: String,
        htmlUrl: String,
        description: String? = nil,
        isPrivate: Bool = false,
        stargazersCount: Int = 0,
        language: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.htmlUrl = htmlUrl
        self.description = description
        self.isPrivate = isPrivate
        self.stargazersCount = stargazersCount
        self.language = language
        self.updatedAt = updatedAt
    }
}

// MARK: - GitHub User Activity Event
public struct GitHubEvent: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let type: String
    public let repo: GitHubEventRepo
    public let createdAt: Date?
    public let payload: GitHubEventPayload?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case repo
        case createdAt = "created_at"
        case payload
    }

    public struct GitHubEventRepo: Codable, Sendable, Equatable {
        public let id: Int?
        public let name: String
        public let url: String?

        public init(id: Int? = nil, name: String, url: String? = nil) {
            self.id = id
            self.name = name
            self.url = url
        }
    }

    public struct GitHubEventPayload: Codable, Sendable, Equatable {
        public let action: String?
        public let ref: String?
        public let refType: String?
        public let size: Int?
        public let commits: [GitHubEventCommit]?

        enum CodingKeys: String, CodingKey {
            case action
            case ref
            case refType = "ref_type"
            case size
            case commits
        }

        public init(action: String? = nil, ref: String? = nil, refType: String? = nil, size: Int? = nil, commits: [GitHubEventCommit]? = nil) {
            self.action = action
            self.ref = ref
            self.refType = refType
            self.size = size
            self.commits = commits
        }
    }

    public struct GitHubEventCommit: Codable, Sendable, Equatable {
        public let sha: String
        public let message: String

        public init(sha: String, message: String) {
            self.sha = sha
            self.message = message
        }
    }

    public var summary: String {
        switch type {
        case "PushEvent":
            if let count = payload?.size, count > 0 {
                return "Pushed \(count) commit\(count == 1 ? "" : "s")"
            }
            if let msg = payload?.commits?.first?.message {
                return "Commit: \(msg.prefix(40))"
            }
            return "Pushed commits"
        case "PullRequestEvent":
            let act = payload?.action?.capitalized ?? "Updated"
            return "\(act) pull request"
        case "CreateEvent":
            let refType = payload?.refType ?? "branch"
            if let ref = payload?.ref {
                return "Created \(refType) '\(ref)'"
            }
            return "Created \(refType)"
        case "IssuesEvent":
            let act = payload?.action?.capitalized ?? "Updated"
            return "\(act) issue"
        case "WatchEvent":
            return "Starred repository"
        case "ForkEvent":
            return "Forked repository"
        default:
            return type.replacingOccurrences(of: "Event", with: "")
        }
    }

    public init(id: String, type: String, repo: GitHubEventRepo, createdAt: Date? = nil, payload: GitHubEventPayload? = nil) {
        self.id = id
        self.type = type
        self.repo = repo
        self.createdAt = createdAt
        self.payload = payload
    }
}

// MARK: - GitHub Pull Request
public struct GitHubPullRequest: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let number: Int
    public let title: String
    public let htmlUrl: String
    public let state: String
    public let createdAt: Date?
    public let repoFullName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case htmlUrl = "html_url"
        case state
        case createdAt = "created_at"
        case repositoryUrl = "repository_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.number = try container.decode(Int.self, forKey: .number)
        self.title = try container.decode(String.self, forKey: .title)
        self.htmlUrl = try container.decode(String.self, forKey: .htmlUrl)
        self.state = try container.decode(String.self, forKey: .state)

        let dateString = try container.decodeIfPresent(String.self, forKey: .createdAt)
        if let dateString {
            self.createdAt = ISO8601DateFormatter().date(from: dateString)
        } else {
            self.createdAt = nil
        }

        if let repoUrl = try container.decodeIfPresent(String.self, forKey: .repositoryUrl) {
            // "https://api.github.com/repos/owner/repo" -> "owner/repo"
            let components = repoUrl.components(separatedBy: "/repos/")
            self.repoFullName = components.count > 1 ? components[1] : nil
        } else {
            self.repoFullName = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(number, forKey: .number)
        try container.encode(title, forKey: .title)
        try container.encode(htmlUrl, forKey: .htmlUrl)
        try container.encode(state, forKey: .state)
        if let createdAt {
            try container.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
        }
        if let repoFullName {
            try container.encode("https://api.github.com/repos/\(repoFullName)", forKey: .repositoryUrl)
        }
    }

    public init(
        id: Int,
        number: Int,
        title: String,
        htmlUrl: String,
        state: String,
        createdAt: Date? = nil,
        repoFullName: String? = nil
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.htmlUrl = htmlUrl
        self.state = state
        self.createdAt = createdAt
        self.repoFullName = repoFullName
    }
}

public struct GitHubSearchIssuesResponse: Codable, Sendable {
    public let totalCount: Int
    public let items: [GitHubPullRequest]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case items
    }
}

// MARK: - GitHub Device Flow Models
public struct GitHubDeviceCodeResponse: Codable, Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationUri: String
    public let expiresIn: Int
    public let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }

    public init(deviceCode: String, userCode: String, verificationUri: String, expiresIn: Int, interval: Int) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationUri = verificationUri
        self.expiresIn = expiresIn
        self.interval = interval
    }
}

public struct GitHubTokenResponse: Codable, Sendable, Equatable {
    public let accessToken: String
    public let tokenType: String
    public let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
    }

    public init(accessToken: String, tokenType: String, scope: String) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.scope = scope
    }
}

public struct GitHubErrorResponse: Codable, Sendable, Equatable {
    public let error: String
    public let errorDescription: String?
    public let errorUri: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case errorUri = "error_uri"
    }

    public init(error: String, errorDescription: String? = nil, errorUri: String? = nil) {
        self.error = error
        self.errorDescription = errorDescription
        self.errorUri = errorUri
    }
}

public struct GitHubRateLimit: Sendable, Equatable {
    public let limit: Int
    public let remaining: Int
    public let resetDate: Date

    public init(limit: Int, remaining: Int, resetDate: Date) {
        self.limit = limit
        self.remaining = remaining
        self.resetDate = resetDate
    }
}

// MARK: - GitHub Contribution Graph & Calendar Models

public struct GitHubContributionDay: Codable, Identifiable, Sendable, Equatable {
    public var id: String { date }
    public let contributionCount: Int
    public let date: String // e.g. "2026-09-01"
    public let weekday: Int // 0 (Sunday) to 6 (Saturday)
    public let color: String?
    public let contributionLevel: String? // "NONE", "FIRST_QUARTILE", "SECOND_QUARTILE", "THIRD_QUARTILE", "FOURTH_QUARTILE"

    public init(
        contributionCount: Int,
        date: String,
        weekday: Int,
        color: String? = nil,
        contributionLevel: String? = nil
    ) {
        self.contributionCount = contributionCount
        self.date = date
        self.weekday = weekday
        self.color = color
        self.contributionLevel = contributionLevel
    }

    /// Short formatted date for header display, e.g. "Sep 1" or "Oct 9"
    public var formattedDate: String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        guard let parsedDate = inputFormatter.date(from: date) else {
            return date
        }

        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "MMM d"
        outputFormatter.locale = Locale(identifier: "en_US")
        return outputFormatter.string(from: parsedDate)
    }

    /// Full formatted label matching reference image, e.g. "Sep 1 · 10 contributions"
    public var contributionSummary: String {
        let plural = contributionCount == 1 ? "contribution" : "contributions"
        return "\(formattedDate) · \(contributionCount) \(plural)"
    }

    /// Heatmap level from 0 to 4
    public var level: Int {
        if let levelStr = contributionLevel {
            switch levelStr.uppercased() {
            case "FOURTH_QUARTILE": return 4
            case "THIRD_QUARTILE": return 3
            case "SECOND_QUARTILE": return 2
            case "FIRST_QUARTILE": return 1
            case "NONE": return 0
            default: break
            }
        }

        // Bracket-based fallback
        if contributionCount <= 0 { return 0 }
        if contributionCount <= 2 { return 1 }
        if contributionCount <= 5 { return 2 }
        if contributionCount <= 9 { return 3 }
        return 4
    }
}

public struct GitHubContributionWeek: Codable, Identifiable, Sendable, Equatable {
    public var id: String {
        days.first?.date ?? UUID().uuidString
    }
    public let days: [GitHubContributionDay]

    enum CodingKeys: String, CodingKey {
        case days = "contributionDays"
    }

    public init(days: [GitHubContributionDay]) {
        self.days = days
    }
}

public struct GitHubContributionCalendar: Codable, Sendable, Equatable {
    public let totalContributions: Int
    public let weeks: [GitHubContributionWeek]

    public init(totalContributions: Int, weeks: [GitHubContributionWeek]) {
        self.totalContributions = totalContributions
        self.weeks = weeks
    }

    public static var empty: GitHubContributionCalendar {
        GitHubContributionCalendar(totalContributions: 0, weeks: [])
    }

    /// Generates a valid calendar from recent events when GraphQL is unavailable
    public static func generateFallback(from events: [GitHubEvent], daysCount: Int = 182) -> GitHubContributionCalendar {
        var countsByDate: [String: Int] = [:]
        let calendar = Calendar.current
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        for event in events {
            if let date = event.createdAt {
                let key = isoFormatter.string(from: date)
                var count = 1
                if event.type == "PushEvent", let size = event.payload?.size, size > 0 {
                    count = size
                }
                countsByDate[key, default: 0] += count
            }
        }

        let today = Date()
        var allDays: [GitHubContributionDay] = []

        for offset in (0..<daysCount).reversed() {
            guard let targetDate = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dateKey = isoFormatter.string(from: targetDate)
            let weekdayNumber = calendar.component(.weekday, from: targetDate) - 1 // 0 (Sun) to 6 (Sat)
            let count = countsByDate[dateKey] ?? 0
            allDays.append(
                GitHubContributionDay(
                    contributionCount: count,
                    date: dateKey,
                    weekday: weekdayNumber,
                    color: nil,
                    contributionLevel: nil
                )
            )
        }

        // Group days into weeks based on weekday
        var weeks: [GitHubContributionWeek] = []
        var currentWeekDays: [GitHubContributionDay] = []

        for day in allDays {
            if day.weekday == 0 && !currentWeekDays.isEmpty {
                weeks.append(GitHubContributionWeek(days: currentWeekDays))
                currentWeekDays = []
            }
            currentWeekDays.append(day)
        }

        if !currentWeekDays.isEmpty {
            weeks.append(GitHubContributionWeek(days: currentWeekDays))
        }

        let total = countsByDate.values.reduce(0, +)
        return GitHubContributionCalendar(totalContributions: total, weeks: weeks)
    }
}

// MARK: - GraphQL API Response Containers

public struct GitHubGraphQLDataResponse<T: Decodable & Sendable>: Decodable, Sendable {
    public let data: T?
    public let errors: [GitHubGraphQLError]?

    public init(data: T?, errors: [GitHubGraphQLError]? = nil) {
        self.data = data
        self.errors = errors
    }
}

public struct GitHubGraphQLError: Decodable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct GitHubViewerContributions: Decodable, Sendable {
    public let viewer: GitHubViewer

    public init(viewer: GitHubViewer) {
        self.viewer = viewer
    }
}

public struct GitHubViewer: Decodable, Sendable {
    public let contributionsCollection: GitHubContributionsCollection

    public init(contributionsCollection: GitHubContributionsCollection) {
        self.contributionsCollection = contributionsCollection
    }
}

public struct GitHubContributionsCollection: Decodable, Sendable {
    public let contributionCalendar: GitHubContributionCalendar

    public init(contributionCalendar: GitHubContributionCalendar) {
        self.contributionCalendar = contributionCalendar
    }
}
