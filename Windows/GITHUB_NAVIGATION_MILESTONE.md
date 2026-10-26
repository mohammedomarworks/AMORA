# GitHub activity and safe Windows navigation

This increment adds real read-only GitHub transport and a bounded native navigation service. It remains **Partial parity** until the integrated UI/runtime evidence below is completed. The prior [milestone report](MILESTONE_REPORT.md) records a different verified working tree; its 477-test result must not be presented as verification of these new files.

## Mac behavior inspected

- `Sources/AMORA/Modules/GitHub/GitHubService.swift`: explicit OAuth connect/disconnect, secure token reuse, profile, five recently updated repositories, ten recent events, five authored open PRs and GraphQL viewer contribution calendar.
- `Sources/AMORA/Modules/GitHub/GitHubModels.swift`: profile/repository/PR/event models, contribution day levels and summaries, week grouping; its fallback derives an approximate calendar from recent events.
- `Sources/AMORA/Modules/GitHub/GitHubAuth.swift`: Keychain token store, PKCE/state validation, localhost callback and developer-operated HTTPS token exchange backend. The Windows service does not reuse a configured OAuth identity/backend without a Windows authorization flow.
- `Sources/AMORA/UI/IslandPages.swift` (`IslandGitHubPage`, `GitHubContributionGraphView`): profile header, Activity/Repos/PR tabs, refresh/disconnect/profile link, seven-row calendar and last 28 visible weeks with day selection.
- `Tests/AMORATests/GitHubServiceTests.swift`: decoding, token persistence/deletion, expired/ratelimited auth, OAuth cancellation/state, calendar decoding/levels/fallback and disconnect clearing calendar.
- `Sources/AMORA/ActionEngine/AmoraActionProtocols.swift`: dynamic native app discovery and Downloads/Documents/Desktop/Home folder resolution; `AmoraActionEngine.swift` bounded app/folder actions; `Core/AITools.swift` explicitly requires confirmation for known folders. Existing Windows `DeterministicCommandRouter.cs` did not have real app/folder launch support.

## Windows GitHub implementation

No constructor or initialize method performs HTTP. `InitializeAsync` checks only whether a saved credential exists. The user explicitly selects Connect, Connect saved token or Refresh.

| Mode/data | Endpoint and behavior |
|---|---|
| Public profile | `GET https://api.github.com/users/{validatedUsername}`; no Authorization header. |
| Token profile | `GET https://api.github.com/user`; if the entered username differs from the authenticated owner, stop before any other account data or token persistence. |
| Repositories | Public `/users/{login}/repos?sort=updated&per_page=5&type=owner`; token `/user/repos?sort=updated&per_page=5&type=all` matching Mac. Metadata only, up to five records. |
| Recent events | Public `/users/{login}/events/public?per_page=10`; token `/users/{login}/events?per_page=10` matching Mac. No repository contents fetched. |
| Authored open PRs | `/search/issues?q=author:{login} type:pr state:open&per_page=5`, URL-encoded. Titles/metadata only; no comments or diffs fetched. |
| Contributions | Token-only `POST /graphql` with a fixed `query { viewer { contributionsCollection { contributionCalendar { ... } } } }`; never a mutation. Actual counts/levels/dates; last 28 weeks presented with seven cells per week. |
| Missing/partial sections | Explicit section warnings; failed sections remain unavailable while successful sections show actual data. Public events are never extrapolated into a fabricated yearly contribution grid. |

Requests use fixed `api.github.com` endpoints, the Mac `2022-11-28` REST API version, an AMORA User-Agent, 25-second bounded requests, cancellation and a 2 MiB maximum response. Owned HTTP clients disable redirects. Usernames cannot supply paths/query strings. Remote error bodies and exception details are never displayed, so credentials/private response text cannot leak through failure messages. Rate-limit errors are distinct from forbidden access and display a validated reset time when supplied. Failed refresh retains the previous snapshot with an explicit stale-data message.

Optional Remember token stores the verified token through existing Windows DPAPI `ISecureCredentialStorage` under `AMORA.GitHub.AccessToken`; session-only mode does not persist it. No connection/profile state is persisted separately. Disconnect clears displayed/session data and explicitly deletes the stored token; deletion failures are reported rather than claiming success. A rejected token is retained until the user replaces or disconnects it, rather than silently deleting credentials. The panel never requests screenshots, clipboard, file contents or AI context.

Profile/repository/PR links can only open `https://github.com` on port 443 without embedded credentials. Avatar URLs, if displayed, are restricted to the official HTTPS avatar host. Remote color or markup strings are not used; contribution colors are a fixed Mac-derived palette.

The Mac one-click OAuth flow is **not ported** in this increment. Windows offers explicit public username or user-supplied token connection, with saved-token reuse. The service makes only read requests, regardless of any broader permissions a supplied token happens to possess. Users should supply only the read permissions needed for the account data they want to display. No real token is provisioned, read or used by automated tests.

Official references checked: [GitHub users](https://docs.github.com/en/rest/users/users), [repositories](https://docs.github.com/en/rest/repos/repos), [REST API versions](https://docs.github.com/en/rest/about-the-rest-api/api-versions) (the Mac version remains supported), and [GraphQL authentication and query transport](https://docs.github.com/en/graphql/guides/forming-calls-with-graphql).

## Safe Windows navigation

`SafeNavigationService.TryExecuteAsync(rawInput)` accepts explicit open/launch/show intents. It returns null for non-navigation and AMORA-owned views so the parent engine keeps its existing workspace routing. Unsupported navigation returns a local unsupported result rather than a shell fallback.

- Applications: Calculator and Windows Settings use only fixed `calculator:` and `ms-settings:` URIs after `QueryUriSupportAsync` confirms Available. There is no executable or Store fallback for absent Calculator. Notepad/Paint use fixed OS-system-directory names with `UseShellExecute=false`, no arguments/PATH lookup, and immediate stub exit is rejected. A successful request reports Windows accepted the launch, not proof of a visible window. Arbitrary app paths, executable names, terminal commands, URI arguments and chaining are rejected. Installed third-party app discovery remains missing; this is narrower than Mac dynamic app discovery.
- Folders: Downloads, Documents, Desktop and Home resolve via `SHGetKnownFolderPath` for the current Windows user and open via `StorageFolder`/`Launcher.LaunchFolderAsync`. Folder resolution supports normal OS redirection without guessing paths. No directory contents are read.
- Folder commands create a service-owned confirmation valid for two minutes; confirming consumes it once. Cancellation, unrelated new input or expiry invalidates it. The outer assistant must call `ConfirmAsync` only through its existing confirmation gate. A bare confirmation/action identifier cannot create a folder request.
- `open home` remains reserved for the AMORA home view; `open my home folder` targets the Windows user folder. `open settings` remains AMORA settings; `open Windows Settings` targets the OS.

Official Windows references checked: [SHGetKnownFolderPath](https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shgetknownfolderpath), [known-folder GUIDs](https://learn.microsoft.com/en-us/windows/win32/shell/knownfolderid). Returned native memory is released even on failure.

## New files and ownership

| File under `Windows/` | Purpose |
|---|---|
| `AMORA.Orbit/Models/GitHubActivity.cs` | Immutable GitHub profile/repository/activity/PR/calendar/result models and fixed day palette. |
| `AMORA.Orbit/Services/Contracts/IGitHubActivityService.cs` | Explicit connect/saved-connect/refresh/disconnect contract. |
| `AMORA.Orbit/Services/Implementations/GitHubActivityService.cs` | Real bounded read-only API transport, safe partial errors and DPAPI credential integration. |
| `AMORA.Orbit/ViewModels/GitHubActivityViewModel.cs` | Panel inputs/state/collections, cancellation, day selection, official link opening and disposal guards. |
| `AMORA.Orbit.Tests/GitHubActivityTests.cs` | Mock-HTTP endpoint/schema/credentials/privacy/cancellation/partial failure/link/lifecycle regressions; no live credentials. |
| `AMORA.Orbit/Models/SafeNavigation.cs` | Typed allowlisted application/folder targets. |
| `AMORA.Orbit/Services/Contracts/ISafeNavigationService.cs` | Explicit navigation/confirmation plus mockable native boundary. |
| `AMORA.Orbit/Services/Implementations/NavigationCommandParser.cs` | Bounded explicit grammar and AMORA-view deferral. |
| `AMORA.Orbit/Services/Implementations/SafeNavigationService.cs` | Own confirmation token, expiration/cancel and truthful native results. |
| `AMORA.Orbit/Services/Implementations/WindowsSafeNavigationPlatform.cs` | Fixed OS application and known-folder Windows launch implementation. |
| `AMORA.Orbit.Tests/SafeNavigationTests.cs` | Known target mapping, shell/path rejection, confirmation lifecycle and failed native outcomes. |
| `GITHUB_NAVIGATION_MILESTONE.md` | This source/implementation/validation record. |

The integration owner modifies App/Orbit/navigation UI and assistant wiring separately; those changed files belong in the final integrated ledger. No Mac source, version, tag or public release was changed by this subtask.

## Verification status

- Source inspection and JSON test-fixture syntax checks completed; `git diff --check` clean at handoff.
- The GitHub service/models/contracts compiled in an isolated .NET 8 harness without touching the WinUI solution build outputs. The coordinated Release build and all GitHub tests subsequently passed in the 643-test run; see CONTINUATION_REPORT.md for the final audit and package evidence.
- Actual public-account loading for `mohammedomarworks` **passed** at 18:08:01–18:08:05 UTC on 2026-10-26 (00:08 local on 2026-10-27): four unauthenticated HTTPS GETs returned 200, yielding the real profile, five repositories, ten recent events and one authored open PR. Credential-store access count was zero, no Authorization headers were allowed, and contribution calendar stayed explicitly unavailable. `evidence/public-github-service.json` (Live service evidence).
- The native panel subsequently rendered real Activity/Repos/PRs tabs for the public account; Windows Settings opened a real OS window. Calculator acceptance exposed a successful stub exit despite its missing app, motivating the protocol-preflight correction above. Final navigation regression/package acceptance is tracked in [CONTINUATION_REPORT.md](CONTINUATION_REPORT.md). No live token/private-account test is claimed.
- Real GraphQL contribution data, saved-token authentication, OAuth parity, all physical display/accessibility states and full Mac parity remain unverified or incomplete as described above.

Executed from the task workspace:

```powershell
& ./work/dotnet/dotnet.exe run --project work/github-public-check/GitHubPublicCheck.csproj --configuration Release -- outputs/evidence/public-github-service.json
```

Exit code 0. The harness links the actual checked-out GitHub source and wraps HttpClient with a guard that permits only unauthenticated `GET https://api.github.com/...`; it rejects any credential-store access. Its files remain in task `work/`, outside repository source and packaging.
