# AMORA — Local-First macOS App with Native Windows Companion (Beta)

AMORA is a local-first macOS application featuring an interactive Dynamic Island interface, deterministic system automation, and optional AI capabilities bounded by a strict tool allowlist. AMORA Orbit is its native Windows companion and is currently in controlled beta.

The macOS app's core utilities—including timers, media playback, system monitoring, notes, clipboard history, and desktop navigation—run on-device without a cloud subscription. Optional AI integrations connect to their selected providers; see the privacy details below.

---

## Windows Orbit Beta

AMORA Orbit brings a native floating companion to Windows. **Version `0.6.0-beta.2` is available for Windows x64 (`win-x64`) only.** The package targets Windows 10 version 1809 (build 17763) or later and Windows 11 on a 64-bit Intel or AMD processor. It bundles the .NET 8 and Windows App SDK runtimes; the Microsoft Visual C++ 2015–2022 x64 Redistributable may need to be installed if it is missing.

**[Download `AMORA.Orbit-v0.6.0-beta.2-win-x64.zip` from GitHub Releases](https://github.com/mohammedomarworks/AMORA/releases)**. This is an unsigned beta executable; Windows SmartScreen may show an “Unknown Publisher” warning. See the [Windows installation guide](Windows/README.md#controlled-public-beta-guide) and [release manifest](Windows/RELEASE_MANIFEST.md) for requirements and setup details.

Orbit includes focus timers, media playback controls, battery and CPU/RAM status, local scheduled automations, and an optional Gemini assistant. Local features work without an AI account. To enable Gemini, expand Orbit with **Ctrl + Alt + O**, open **Settings**, enter a Gemini API key, choose **Test Connection**, then **Save**. The key is encrypted with Windows DPAPI. When Gemini is enabled, submitted prompts are sent to Google; sharing system status is opt-in. Read the [Windows privacy boundaries](Windows/README.md#3-data-privacy-boundaries).

---

## Key Capabilities

- **Interactive Dynamic Island**: A floating notch interface anchored near the top of the screen that expands into a quick-control panel or a full workspace dashboard.
- **Local-First Architecture**: Core utilities—including timers, battery diagnostics, system metrics, notes, file pinning, and local media controls—execute deterministically on-device with zero network latency.
- **AMORA Local Brain**: Built-in offline language model inference powered by `llama.cpp` and Metal GPU acceleration, running quantized models (Qwen 2.5) locally inside the application process.
- **Bounded Tool Registry**: Model-generated actions are restricted to a typed schema with a maximum of 4 calls per request. Destructive filesystem operations and arbitrary shell execution are strictly excluded, and folder navigation requires explicit user confirmation.
- **Clipboard Privacy Guard**: Clipboard history monitors local copies while automatically filtering out sensitive credentials, transient data, and password-manager entries.
- **Privacy-Preserving Long-Term Memory**: Allows users to save explicit preferences with automated rejection of credentials, financial secrets, health records, and private communications.
- **Multi-Source Media Integration**: Real-time track display and playback control for Spotify, Apple Music, YouTube in Google Chrome (via native messaging bridge), and frontmost Safari tabs.

---

## System Requirements

### Hardware
- **Architecture**: Apple Silicon Mac (arm64; M1 or later). AMORA is compiled and validated exclusively for Apple Silicon using Metal GPU acceleration. While the bundled `llama.xcframework` includes an x86_64 slice, Intel (x86_64) builds are currently unverified and not officially supported.
- **Memory (RAM)**:
  - Base application (deterministic tools): Varies with system activity (unverified rough estimate: ~100–180 MB idle; not formally profiled).
  - With Default Local Brain (Qwen 2.5 1.5B Instruct Q4_K_M): Model descriptor runtime estimate is ~1.4 GB RAM (`estimatedRAMBytes`), but actual memory consumption varies with active context length and Metal unified memory allocation.
  - With Compact Local Brain (Qwen 2.5 0.5B Instruct Q4_K_M): Model descriptor runtime estimate is ~600 MB RAM (`estimatedRAMBytes`), varying with context length.
- **Disk Space**:
  - Base application: ~30 MB installed.
  - Default Local Brain (1.5B): Final model file is ~1.04 GB (1,117,320,736 bytes). Requires at least **~1.6 GB** free disk space during setup (model file plus a 500 MB temporary download headroom).
  - Compact Local Brain (0.5B): Final model file is ~469 MB (491,400,032 bytes). Requires at least **~1.0 GB** free disk space during setup.

### Software & Operating System
- **macOS**: macOS 14.0 (Sonoma) or later.
- **Permissions**:
  - *Core Utilities & Local AI*: Require **no special macOS permissions**.
  - *Automation (Apple Events)*: Required only when controlling external playback in Apple Music, Spotify, or Safari.
  - *Accessibility*: Optional; used only for global keyboard shortcut monitoring and auxiliary window alignment.
- **Integrations & Third-Party Applications (Optional)**:
  - *Google Chrome*: Required only if using the bidirectional YouTube media bridge extension.
  - *Cloud AI Providers*: An Anthropic or OpenAI API key is required only when selecting cloud model providers.

---

## Installation & Distribution Status

### Distribution Status & Gatekeeper Notice

> [!IMPORTANT]
> **Public Distribution Status: Blocked**
> AMORA beta releases built from source or packaged locally are **ad-hoc signed**. macOS Gatekeeper will reject ad-hoc signed archives when opened on other Macs (`spctl` assessment returns `rejected`).
>
> Public beta distribution is blocked pending the following Apple Developer prerequisites:
> 1. An active Apple Developer Program membership.
> 2. A valid `Developer ID Application` certificate installed in the macOS Keychain.
> 3. Archive notarization via Apple's notary service (`xcrun notarytool`) and ticket stapling (`xcrun stapler`).
>
> **Security Policy**: Testers must **never** be instructed to disable Gatekeeper system-wide or strip quarantine attributes (`xattr -d com.apple.quarantine`) as standard practice. Ad-hoc builds are strictly for local development and verification on the build machine.

### Building and Running Locally

> 📖 **Step-by-Step Guide**: For detailed prerequisites, verification steps, and Chrome extension setup, see the [Building from Source Guide](docs/BUILD-FROM-SOURCE.md).

To build and run AMORA on your local machine:

1. **Clone the repository**:
   ```bash
   git clone https://github.com/mohammedomarworks/AMORA.git
   cd AMORA
   ```

2. **Build the release binary and bundle**:
   ```bash
   ./Scripts/build-app.sh release
   ```
   This compiles `AMORA` and `AMORA-BrowserHost`, bundles `llama.framework`, registers the Chrome native messaging manifest, and performs inside-out ad-hoc code signing.

3. **Launch the application**:
   ```bash
   open AMORA.app
   ```

### Packaging Beta Releases (Maintainers)

The repository includes a packaging script that preserves framework symlinks, permissions, and bundle structure using Apple's `ditto`:

```bash
# Package beta build (default: beta 1)
./Scripts/package-beta.sh 1
```

The output archive is created at:
```text
dist/AMORA-1.0.0-beta.1.zip
```

When an Apple Developer ID Application identity and credentials are configured:
```bash
# Sign with Developer ID, submit to Apple Notary Service, and staple
DEVELOPER_ID="Developer ID Application: Your Name (TEAM_ID)" \
  ./Scripts/package-beta.sh 1 --notarize --keychain-profile "AC_PASSWORD"
```

---

## First Launch & AI Setup

Upon launch, AMORA appears in the macOS menu bar and presents a floating Dynamic Island near the top of the main display.

### 1. AMORA Local Brain (On-Device LLM)

AMORA includes an embedded inference engine powered by `llama.cpp` and Metal GPU acceleration. No external network requests are made during inference.

- **Storage Location**: Models are stored locally in:
  ```text
  ~/Library/Application Support/AMORA/models/
  ```
- **Supported Models**:
  - **Qwen 2.5 1.5B Instruct (Default)**:
    - Quantization: `Q4_K_M` (Apache 2.0 License).
    - Download Size: ~1.04 GB (1,117,320,736 bytes; requires ~1.6 GB free disk space during setup).
    - Estimated RAM: ~1.4 GB runtime estimate (`estimatedRAMBytes`), varying with active context.
    - Expected SHA-256: `6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e`.
    - Recommended for superior reasoning and zero-shot structured JSON formatting.
  - **Qwen 2.5 0.5B Instruct (Compact)**:
    - Quantization: `Q4_K_M` (Apache 2.0 License).
    - Download Size: ~469 MB (491,400,032 bytes; requires ~1.0 GB free disk space during setup).
    - Estimated RAM: ~600 MB runtime estimate (`estimatedRAMBytes`), varying with active context.
    - Expected SHA-256: `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`.
    - Retained for resource-constrained environments.

- **Downloading a Model**:
  1. Open AMORA **Settings** (gear icon) > **AI**.
  2. Select **Local Brain** as your provider.
  3. Click **Download Model**. The UI displays real-time download progress, downloaded bytes, and transfer speed.
  4. After the download completes, AMORA automatically performs a SHA-256 checksum integrity verification before marking the model ready.
- **Failures and Retries**:
  - If a download is interrupted by network disconnects or if the file fails integrity validation, AMORA marks the model as failed or corrupt.
  - Click **Retry Download** in Settings to clear the partial `.download` file and re-download.

### 2. Available AI Providers

AMORA supports four provider modes in **Settings > AI**:

1. **Local Brain (Default & Recommended)**: Fully offline on-device inference via Metal. No API keys or accounts required.
2. **Apple On-Device (Foundation Models)**: Uses Apple Intelligence on supported macOS versions and compatible Apple hardware. No network calls or API keys required.
3. **Cloud Providers (Anthropic / OpenAI)**:
   - Requires your own API key.
   - Enter your key in **Settings > AI**.
   - Keys are stored securely in macOS Keychain (`kSecClassGenericPassword` under service `com.amora.app`) via `StorageManager`, never written to disk in plain text, and transmitted solely over HTTPS to the designated provider's API endpoint (`api.anthropic.com` or `api.openai.com`).
4. **None (Deterministic Only)**:
   - Disables all LLM inference.
   - All built-in tools (timers, notes, music controls, battery metrics, app launcher, view switching) continue to function deterministically with zero AI latency.

---

## Browser Integration

AMORA connects to Google Chrome for real-time YouTube media status and playback controls across active and background tabs.

### Chrome Extension Installation

The extension is located in the repository at `BrowserExtensions/chrome/`. It uses Manifest V3 and Native Messaging to communicate with AMORA via macOS `DistributedNotificationCenter`.

1. **Install the Native Messaging Host**:
   When building AMORA with `./Scripts/build-app.sh`, the host is installed automatically. To install or update it independently:
   ```bash
   ./Scripts/install-chrome-native-host.sh
   ```
   This script:
   - Copies `AMORA-BrowserHost` to `~/Library/Application Support/AMORA/AMORA-BrowserHost`.
   - Registers `com.amora.browser.json` in `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`.
   - Binds the native host to the stable extension ID: `pcjbhandogggbhkjdfpcngenaaediend`.

2. **Load the Extension in Chrome**:
   - In Google Chrome, navigate to `chrome://extensions`.
   - Turn on the **Developer mode** toggle in the top-right corner.
   - Click **Load unpacked** in the top-left corner.
   - Select the `BrowserExtensions/chrome/` folder inside the AMORA repository.
   - Fully restart Google Chrome.

3. **Verify the Bridge**:
   Run the diagnostic script:
   ```bash
   ./Scripts/verify-chrome-bridge.sh
   ```
   The script checks:
   - Host binary existence and executable permissions.
   - Manifest path and JSON format.
   - Extension ID and allowed origin match.
   - Standard input/output ping/pong communication protocol.

### Safari Support & Known Limitations

- **Safari Web Extension**: Safari does not support loading unpacked extensions directly without an Xcode containing-app project.
- **AppleScript Fallback**: AMORA includes an AppleScript fallback for Safari that inspects the active tab of the frontmost Safari window.
- **Requirements**: Requires enabling **Safari > Settings > Advanced > Show features for web developers**, followed by **Develop > Allow JavaScript from Apple Events**.
- **Limitations**: Safari support is limited to detecting media and toggling play/pause in the frontmost active tab. Background tab tracking and bidirectional event synchronization are only available in Chrome.

---

## Privacy, Permissions & Security Invariants

### 1. Clipboard Privacy Guard

AMORA monitors the system pasteboard to display recent copies in the Dashboard's Clipboard section.

- **Sensitive Marker Filtering**: Before reading or storing copied text, `ClipboardService` inspects the pasteboard item's declared types. It immediately skips recording any item carrying:
  - `org.nspasteboard.ConcealedType` (used by password managers such as 1Password, Bitwarden, KeePassXC)
  - `org.nspasteboard.TransientType`
  - `org.nspasteboard.AutoGeneratedType`
- **Context Isolation**: Clipboard history is an isolated local dashboard utility. AMORA never automatically inspects, reads, or injects clipboard history entries into AI prompts, conversation context, memory records, logs, or automation triggers. (Only text that you explicitly type or paste directly into the chat prompt input is sent to the active AI provider).

### 2. Privacy-Safe Long-Term Memory

AMORA allows saving explicit user preferences (e.g., "remember my lunch break is 30 minutes").

- **Heuristic Privacy Validation**: Every memory candidate is checked against `AmoraMemoryPrivacyValidator`. The validator uses regex patterns and keyword matching designed to reject:
  - Common passwords, API keys, access tokens, and SSH keys.
  - Payment card numbers, bank account numbers, IBANs, and Social Security Numbers.
  - Medical diagnoses, prescription dosages, and health terminology.
  - Private messages, chat logs, and email text.
  - Clipboard history dumps, file contents, screen contents, and keystrokes.
- **Scope & Limitations**: Heuristic filtering blocks known common patterns, but cannot guarantee detecting every possible form of obfuscated, unstructured, or novel sensitive data. Users should never request AMORA to remember confidential secrets or personal credentials.
- **Management**: Stored memories are saved locally in `Application Support` and can be inspected, updated, or permanently deleted at any time in **Settings > Memory**.

### 3. Tool Sandboxing & Safety

Model actions execute strictly through `AMORAToolRegistry`:
- **Execution Limit**: Maximum of 4 tool invocations per request.
- **No Arbitrary Execution**: There is no shell execution, terminal command invocation, or arbitrary Swift reflection.
- **Folder Allowlist**: The folder tool is restricted to opening `Desktop`, `Documents`, and `Downloads`. It cannot access arbitrary paths and **always requires user confirmation** before opening.
- **Deterministic Multi-Tool Order**: Requests with multiple actions execute sequentially. Partial failures are preserved and reported accurately rather than masked as success.

---

## Troubleshooting & FAQ

### App Shows "Damaged" or Gatekeeper Warning
- **Cause**: The application was packaged with an ad-hoc signature and marked with quarantine attributes upon download.
- **Solution**: Ad-hoc builds are intended for local development. Build the application locally using `./Scripts/build-app.sh release` and run `open AMORA.app`.

### Local Brain Download Fails
- **Cause**: Insufficient disk space or connection interruption.
- **Solution**: Ensure your drive has sufficient free space for the model file plus a 500 MB buffer (~1.6 GB free for the 1.5B model, ~1.0 GB free for the 0.5B model). Open **Settings > AI** and click **Retry Download**.

### Chrome Media Status Not Showing
- **Cause**: Chrome was not restarted after registering the native host, or the extension is disabled.
- **Solution**:
  1. Run `./Scripts/verify-chrome-bridge.sh` and ensure all diagnostic tests pass.
  2. Open `chrome://extensions` and verify that the AMORA extension is enabled.
  3. Completely quit and relaunch Google Chrome (`Cmd + Q`).

### Apple Music or Spotify Controls Not Responding
- **Cause**: Missing macOS Automation permission.
- **Solution**: Open macOS **System Settings > Privacy & Security > Automation**. Locate **AMORA** and ensure checkboxes for **Music** and **Spotify** are enabled.

### Providing Feedback
Encountered an issue or have a feature request? Please submit a report on the official GitHub Issues page:
[AMORA GitHub Issues](https://github.com/mohammedomarworks/AMORA/issues)

---

## Beta Changelog (Release Readiness)

- **Step 1: UI & Layout Stability**:
  - Fixed island layout clipping and normalized dynamic height transitions across notch and non-notch displays.
  - Unified theme styling and typography across all panels.
- **Step 2: Local Brain Architecture**:
  - Integrated `LlamaSwift` (llama.cpp) with Apple Silicon Metal acceleration.
  - Promoted Qwen 2.5 1.5B Instruct as the default model (83.6% evaluation benchmark completion).
  - Added live download progress, SHA-256 integrity verification, and dynamic UI size labels.
- **Step 3: Clipboard Privacy Hardening**:
  - Hardened `ClipboardService` with pre-read type inspection.
  - Automatically filters `ConcealedType`, `TransientType`, and `AutoGeneratedType` to protect password-manager copies.
- **Step 4: Centralized Versioning & Asset Consistency**:
  - Centralized application version (`1.0.0`) and build number (`1`) in authoritative `VERSION` file.
  - Injected versioning dynamically into `Info.plist` and exposed via `AppVersion` helper in About and Settings.
  - Synchronized model-size formatters across Dynamic Island and Settings.
- **Step 5: Beta Packaging & Gatekeeper Workflow**:
  - Implemented inside-out code signing supporting optional `DEVELOPER_ID` and hardened runtime.
  - Created `Scripts/package-beta.sh` using Apple `ditto` to preserve framework symlinks and permissions.
  - Added pre-flight notarization workflow for `xcrun notarytool` and `xcrun stapler`.
  - Documented Gatekeeper blockers and release status honestly.
- **Step 6: Public Beta Documentation**:
  - Published comprehensive documentation, system requirements, setup guides, and privacy invariants.
