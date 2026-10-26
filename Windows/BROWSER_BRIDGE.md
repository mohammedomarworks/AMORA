# Windows browser media bridge

The Windows bridge reuses the repository's existing Chrome Manifest V3 extension without changing the Mac implementation. It adds a native Windows host and a current-user named pipe in place of macOS `DistributedNotificationCenter`.

## Explicit setup

1. Extract the complete AMORA package. It must contain `browser-host/AMORA.BrowserHost.exe` and its self-contained runtime, plus `browser-extension/manifest.json`.
2. In AMORA settings, select **Register browser host**. Registration is a separate, explicit action; it does not enable browser media or install an extension.
3. Load the bundled `browser-extension` directory as an unpacked extension in Chrome or Edge. The existing manifest key fixes its ID to `pcjbhandogggbhkjdfpcngenaaediend`.
4. Enable browser media in AMORA, and reopen/reload the browser extension. Open a supported HTTPS YouTube watch, shorts, or youtu.be page.

Registration copies the host bundle into a content-specific directory under `%LOCALAPPDATA%/AMORA/BrowserHost`. A local `com.amora.browser.json` manifest points to that stable executable. Only the current user's Chrome and Edge `NativeMessagingHosts` registry entries are set; administrator permissions are unnecessary. Moving the original AMORA folder does not break this installed host. Register again after updating AMORA to install its new host build.

Unregister removes only registry entries pointing to AMORA's own manifest. Existing binary directories are retained because a running browser may still own them. Disable browser media to disconnect an existing bridge. Extension installation, extension removal, browser playback, and cloud settings are never changed by registration.

## Implemented behavior and boundaries

- Browser media is **off by default**. The app does not open its pipe listener or accept metadata while disabled.
- The host accepts only the pinned extension origin. Both pipe endpoints use Windows `CurrentUserOnly` access control, and the pipe name is specific to the current Windows SID. There is no network listener.
- Both boundaries use four-byte little-endian framing, strict UTF-8, a 64 KiB maximum message, bounded JSON depth, and an allowlisted schema. Unknown properties, arbitrary actions, general page contents, and unsupported URLs are discarded. Payloads, URLs and track titles are not logged.
- The app keeps only the current target's media metadata in memory. It clears that state on disable, disconnect, no target, invalid state, or a stale snapshot. No browser history is persisted by the Windows app or host. The shared extension retains its existing browser-session-only recovery state.
- Play and pause use explicit tab IDs and unique request IDs. Success requires a matching action and tab acknowledgement. Timeout, failure, disconnect and stale/duplicate acknowledgements cannot create success. Unsupported next, previous and seek controls are disabled, matching the current Mac extension.
- Command delivery and acknowledgement share a five-second deadline. Closing AMORA cancels pending work. Invalid or disconnected players produce bounded status messages.
- `MediaCoordinatorService` is the single `IMediaService` consumed by the UI, assistant and automation code. Live YouTube playback takes priority. A playing Windows media player takes priority over paused YouTube. When both are paused, an enabled live YouTube target can be resumed. Otherwise the coordinator falls back to Windows system-media controls.
- The shared extension labels its browser as `Chrome` even when loaded in Edge. AMORA presents the source as YouTube; it does not infer a website from a generic GSMTC browser session.

## Source and tests

Mac behavioral references are `Sources/AMORABrowserHost/main.swift`, `Sources/AMORA/Modules/Music/ChromeMessageBridge.swift`, `Tests/AMORATests/TruthfulBrowserMediaControlTests.swift`, and `Tests/AMORATests/BrowserConnectionStatusAndRecoveryTests.swift`. Shared extension sources remain under `BrowserExtensions/Chrome`.

Windows implementation: `AMORA.BrowserHost/Program.cs`; `AMORA.Orbit/Services/BrowserBridge`; `BrowserMediaBridgeService`, `MediaCoordinatorService`; `BrowserBridgeViewModel`. The host has no third-party dependencies and must be published self-contained for the package's architecture.

`AMORA.Orbit.Tests/BrowserBridgeTests.cs` covers URL restrictions, framing limits, unknown-field removal, disabled collection, matched and mismatched acknowledgements, timeout, late acknowledgement, disconnect, disable/reconnect, stale state, explicit registration, source selection, and an actual current-user Windows named-pipe round trip. Tests use controlled metadata and never register a host, install an extension, or change user playback.

## Verification limits

The standalone host build and focused source-linked protocol/personality tests have passed on Windows. These results do not establish browser extension installation or real YouTube playback acceptance. The full WinUI build, release package checks and actual Chrome/Edge play/pause/reconnect acceptance must be recorded separately. Browser registration remains explicitly user initiated; automated testing must not install the extension or alter the user's existing playback implicitly.

The public `IMediaService` contract currently has no per-command cancellation token, so cancellation from the assistant cannot revoke a command already delivered to a browser tab. Host disconnect, disabling the bridge, application shutdown and the bounded timeout end pending acknowledgement waits. Full Mac cancellation parity remains an explicit follow-up.
