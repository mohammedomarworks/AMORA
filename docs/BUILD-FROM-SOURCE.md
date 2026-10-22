# AMORA — Building & Running from Source

> **Free Technical Testing Path for Apple Silicon Macs**  
> Validated on macOS 14+ (Sonoma and later) · Swift 6.0+ · Apple Silicon (M1+)

---

## Overview

AMORA is an open-source, local-first macOS companion with an interactive Dynamic Island interface, deterministic system tools (timers, notes, clipboard privacy guard, media controls), and on-device AI inference via `llama.cpp` and Metal GPU acceleration.

### Why Build from Source?

Pre-packaged `.zip` releases distributed over the internet are currently **ad-hoc signed** and **unnotarized** (an active Apple Developer ID certificate and Apple Notary service submission are required for public distribution). When downloaded through a browser, macOS Gatekeeper flags the downloaded archive with a quarantine attribute (`com.apple.quarantine`) and rejects execution.

**You do NOT need an Apple Developer account, and you must NOT disable Gatekeeper or strip quarantine attributes to evaluate AMORA.**

When you clone the repository and compile AMORA locally with Swift:
- The resulting binary is built directly on your Mac by your local developer toolchain.
- macOS does **not** attach quarantine attributes to locally compiled binaries.
- The application launches and runs natively without triggering Gatekeeper blocks or weakening system security.

> [!NOTE]
> **Scope & Environment Variance**: This build-from-source path was verified and tested end-to-end on our reference Apple Silicon development machine (compilation, bundle assembly, application launch, notch window anchoring, menu bar controls, and Chrome bridge). However, this is an experimental beta provided for technical evaluation, not a guarantee that every tester's environment will work identically without configuration. Variations in Xcode/Swift toolchain versions, macOS build versions, missing developer tools, or display layouts may require local troubleshooting.

---

## System Prerequisites

Before building, verify that your machine meets these requirements:

### 1. Hardware
- **Processor**: Apple Silicon Mac (`arm64`: M1, M2, M3, M4, or later). Intel (`x86_64`) Macs are not officially supported.
- **Memory (RAM)**:
  - Base application (deterministic utilities): ~115–180 MB idle.
  - Optional Local Brain (Qwen 2.5 1.5B Instruct): ~1.4 GB unified memory when loaded.
  - Optional Local Brain (Qwen 2.5 0.5B Instruct): ~600 MB unified memory when loaded.
- **Disk Space**:
  - ~500 MB – 1 GB for Swift Package Manager compilation artifacts (`.build/`).
  - ~30 MB for the compiled `AMORA.app` bundle.
  - Optional ~1.0 GB (0.5B model) or ~1.6 GB (1.5B model) if you choose to download offline AI weights in Settings.

### 2. Software & Developer Tools
- **Operating System**: macOS 14.0 (Sonoma) or later.
- **Swift Toolchain**: Swift 6.0 or later (included with Xcode or Command Line Tools).
  ```bash
  swift --version
  ```
  *If Swift is missing, install Apple Command Line Tools via Terminal:*
  ```bash
  xcode-select --install
  ```
- **Git**: Installed by default with Command Line Tools. Check with `git --version`.
- **Python 3**: Standard on macOS (`/usr/bin/python3`), used for Chrome native messaging host registration and diagnostics.

---

## Step-by-Step Build Instructions

### Step 1: Clone the Repository

```bash
git clone https://github.com/mohammedomarworks/AMORA.git
cd AMORA
```

### Step 2: Build the Application Bundle

Run the official build script with the `release` configuration:

```bash
./Scripts/build-app.sh release
```

*What this script does:*
1. Compiles `AMORA` and the helper `AMORA-BrowserHost` for production using `swift build -c release`.
2. Assembles the `AMORA.app` bundle structure with required metadata and resources.
3. Bundles the pre-built `llama.framework` with Apple Silicon Metal acceleration.
4. Automatically installs and registers the Chrome native messaging host (`com.amora.browser.json`) for YouTube media tracking.
5. Performs local inside-out ad-hoc code signing so macOS recognizes bundle integrity.
6. Validates the bundle structure and code signature on disk.

### Step 3: Launch AMORA

Start the application using the launcher script:

```bash
./Scripts/run-app.sh release
```

*(Alternatively, you can launch the app bundle directly using `open AMORA.app`.)*

---

## Verifying That AMORA Is Running

Once launched, verify that AMORA is operating properly:

1. **Menu Bar Status Item**: Look for the AMORA icon in the macOS menu bar at the top right of your screen. Clicking it opens the primary controls:
   - *Show AMORA* / *Quick Controls* / *Open Dashboard*
   - *Settings…* (`Cmd+,`)
   - *About AMORA*
   - *Quit AMORA* (`Cmd+Q`)
2. **Dynamic Island Interface**: The floating island appears anchored near the top of your display around the camera notch. Hovering or clicking expands the quick panel and dashboard.
3. **Process Verification (Terminal)**:
   ```bash
   pgrep -l AMORA
   ```
   You should see `AMORA` running as an active process.

---

## Optional: Google Chrome YouTube Media Integration

AMORA includes bidirectional media tracking for YouTube in Google Chrome via a native messaging bridge.

The `build-app.sh` script automatically installs the host binary and registers Chrome's Native Messaging manifest. To enable tracking in Google Chrome:

### 1. Load the Chrome Extension
1. Open **Google Chrome** and navigate to `chrome://extensions`.
2. Toggle on **Developer mode** in the top-right corner.
3. Click **Load unpacked** in the top-left corner.
4. Select the `BrowserExtensions/Chrome` directory from your cloned `AMORA` repository.
5. Fully restart Google Chrome (`Cmd+Q`, then open Chrome again).

### 2. Verify the Bridge
Run the diagnostic script to confirm the host binary, manifest, and stdio communication are operational:

```bash
./Scripts/verify-chrome-bridge.sh
```

Expected output:
```text
Chrome Native Messaging Diagnostic

Host: FOUND (/Users/.../Library/Application Support/AMORA/AMORA-BrowserHost)
Executable: OK
Manifest: FOUND / VALID
Host name: OK (com.amora.browser)
Allowed origin: MATCH
Extension ID: pcjbhandogggbhkjdfpcngenaaediend
Manifest path: VALID
Protocol: OK

Diagnosis: host registration and stdio protocol are working.
```

---

## Stopping & Teardown

### To Stop AMORA
Click the AMORA menu bar icon and select **Quit AMORA**, or run:
```bash
killall AMORA
```

### To Remove Build Artifacts
To reclaim disk space occupied by the build cache:
```bash
rm -rf .build AMORA.app
```

### To Remove the Chrome Native Messaging Registration
If you want to unregister the Chrome native messaging host:
```bash
rm -f "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.amora.browser.json"
rm -rf "$HOME/Library/Application Support/AMORA/AMORA-BrowserHost"
```

---

## Security & Gatekeeper FAQ

### Q: Why does the pre-packaged `.zip` fail to open?
Downloaded `.zip` files from GitHub Releases are given the `com.apple.quarantine` extended attribute by macOS. Because AMORA is an independent project without an Apple Developer ID membership, the binary is not notarized by Apple, causing Gatekeeper to reject it.

### Q: Does building from source bypass Gatekeeper?
No. Building from source does not disable or bypass Gatekeeper. macOS security architecture intentionally differentiates between files downloaded from untrusted internet sources (quarantined) and code compiled locally by the user. Locally built binaries do not receive quarantine flags and are safe to run.

### Q: Should I run `xattr -d com.apple.quarantine` on the downloaded ZIP?
**No.** Stripping quarantine attributes from downloaded binaries bypasses macOS security protections and is strongly discouraged. Technical testers should clone the repository and run `./Scripts/build-app.sh release` instead.

### Q: Is building from source guaranteed to work on every Mac?
**No.** While the workflow has been verified end-to-end on our reference development Mac, individual machines may have different Swift/Xcode versions, command line tools setups, display configurations, or macOS permissions. If you run into build or runtime issues, please file a report on [GitHub Issues](https://github.com/mohammedomarworks/AMORA/issues) with your terminal output and system version.
