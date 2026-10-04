# AMORA browser media helper

The Chrome helper is a Manifest V3 extension plus a Chrome Native Messaging
host. It tracks minimal HTML5 player metadata for supported YouTube tabs,
including background tabs, and sends only the selected media snapshot through
the native host. Minimal tab/media state is kept in `chrome.storage.session` to
survive service-worker restarts; it is reconciled against open tabs on startup
and is not browsing history. The host forwards validated state to AMORA using
local Distributed Notifications; there is no public network listener.

## Chrome setup

The host name is `com.amora.browser`, so Chrome looks for
`com.amora.browser.json`. The manifest includes a public signing key so the
unpacked development extension has the stable ID
`pcjbhandogggbhkjdfpcngenaaediend`; the registration uses the exact origin
`chrome-extension://pcjbhandogggbhkjdfpcngenaaediend/`.

Build AMORA with:

```sh
Scripts/build-app.sh
```

The build automatically runs `Scripts/install-chrome-native-host.sh`. It
copies only `AMORA-BrowserHost` to:

`~/Library/Application Support/AMORA/AMORA-BrowserHost`

and writes the Chrome manifest to:

`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.amora.browser.json`

The generated manifest contains the absolute installed host path, so it does
not depend on the repository or `AMORA.app` staying in `~/Amora`. If the
extension ID changes, rebuild the registration with
`AMORA_CHROME_EXTENSION_ID=<verified-id> Scripts/install-chrome-native-host.sh
<absolute-path-to-AMORA-BrowserHost>`.

Run `Scripts/verify-chrome-bridge.sh` to validate the installed host,
manifest, allowed origin, executable, and native messaging protocol.

Load `BrowserExtensions/Chrome` as an unpacked extension in
`chrome://extensions`, then restart Chrome after installing or refreshing the
host registration.

Safari is intentionally not reported as connected by this SwiftPM app. A
Safari Web Extension containing-app target requires an Xcode app/extension
embedding target, which this repository does not currently have; the old
AppleScript fallback remains metadata-only and controls stay disabled.

## Chrome control protocol

Read state continues to use the normalized `mediaState` message. Control uses
the same native port in the opposite direction:

```text
YouTube content script -> service worker -> normalized selected mediaState
                       -> native host -> AMORA
AMORA -> DistributedNotification -> native host -> mediaCommand -> service worker
      -> tracked YouTube tab -> content script -> verified play()/pause()
      -> mediaCommandResult + selected mediaState -> native host -> AMORA
```

Commands contain a unique `requestId` and are restricted to `play` and `pause`.
The service worker tracks state by sender tab ID; tab activation does not clear
background playback. Its target policy is deterministic: choose a playing tab
that most recently transitioned to playing; break ties by recent tab
interaction, recent AMORA control, then ascending tab ID. If all tabs are
paused, keep AMORA's last controlled tab; otherwise retain the most recently
played paused tab (so Play can resume it), then prefer the active/recent paused
tab. The content script returns only after the actual video operation has
completed or failed, and the UI changes from the acknowledged state rather than
optimistically when a command is sent. Tab-close and navigation events remove
stale records. A missing content script is reinjected and retried once.

Every command carries the same request ID and selected tab ID through AMORA,
the native host, service worker, and content script. Each acknowledgement is
checked against request ID, action, and tab ID. Failures are returned as
structured reasons before AMORA's existing five-second deadline; the worker
does not mask delivery failures by increasing that deadline. Diagnostics are
prefixed `[AMORA Control]` in AMORA logs, the Chrome service-worker console,
and YouTube's page console. The native host writes request-scoped hop logs to
stderr (visible in Chrome's native-host logs or Console.app).

The extension uses `nativeMessaging`, `scripting`, and `storage` plus YouTube
host permissions. Tab queries are constrained to supported YouTube URL
patterns; it does not request the broad `tabs` or browsing-history permission
and does not scan page contents. YouTube reports next and previous as
unsupported; AMORA disables those controls instead of simulating them.
