# AMORA

AMORA is a local-first macOS companion with a Dynamic Island interface, deterministic commands, optional AI, and a bounded allowlist of local tools.

## Routing

`AMORACommandGateway` parses simple known commands first. Timer, battery, notes, media, application, folder, and view commands continue to work without AI. Unknown or conversational requests are sent to the configured provider.

The AI boundary is provider-neutral. A provider may return ordinary prose or the strict JSON shape below:

```json
{"calls":[{"tool":"timer","action":"start","seconds":1500,"text":null,"name":null}]}
```

Only allowlisted tools and typed operations are decoded. `AMORAToolRegistry` validates every request, enforces a four-call limit, applies confirmation requirements, executes existing services, and returns structured results. The registry has no shell or arbitrary filesystem operation.

## Supported tools

- `battery`: read percentage, charging state, and explicitly estimated remaining time.
- `timer`: start, pause, resume, stop, and add time using `TimerService`.
- `music` / `browserMedia`: read or control supported Apple Music and browser media capabilities.
- `notes`: create or list notes using `NotesService`.
- `system`: read the metrics exposed by `SystemMonitorService`.
- `application`: open known applications through `NSWorkspace`.
- `folder`: open only Desktop, Documents, or Downloads, with confirmation.
- `view`: navigate supported AMORA views locally.

Clipboard history and File Shelf contents are not included in AI context. File contents, browser history, notifications, and other private data are not uploaded automatically.

## Safety and failures

Read-only and low-risk actions execute directly. Folder opening requires confirmation. Destructive filesystem actions, arbitrary shell commands, unknown tools, malformed arguments, and unsupported provider actions are rejected. Multi-tool requests are executed in deterministic order and each result is preserved, so a partial failure is reported as partial rather than as overall success.

Apple Foundation Models remains the on-device path when available; Anthropic and OpenAI are optional providers. The existing Event Center remains the lifecycle path for personality and UI reactions.

## Verification

Run `swift build` and `swift test`. On restricted environments, set `CLANG_MODULE_CACHE_PATH` and `SWIFT_MODULECACHE_PATH` to writable workspace directories. Manual Chrome tests additionally require the native messaging bridge and the AMORA browser extension.
