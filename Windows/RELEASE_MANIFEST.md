# AMORA Orbit — Windows Public Beta Release Manifest

**Package:** `AMORA.Orbit-v0.6.0-beta-win-x64.zip`
**Version:** `0.6.0-beta`
**Release Channel:** Controlled Public Beta
**Target Architecture:** Windows x64 (`win-x64`)
**Target Framework:** .NET 8 (`net8.0-windows10.0.19041.0`)
**Deployment Model:** Self-Contained Unpackaged WinUI 3 Desktop Application

---

## 1. System Requirements & Prerequisites

| Requirement | Specification | Notes |
| :--- | :--- | :--- |
| **Operating System** | Windows 10 version 1809 (build 17763) or later, or Windows 11 | Required for WinUI 3 and XAML island support |
| **Architecture** | 64-bit Intel / AMD processor (`x64`) | This beta ZIP is built for `win-x64` only |
| **.NET Runtime** | .NET 8.0 Runtime | **Bundled self-contained**; no separate download required |
| **Windows App SDK** | Windows App Runtime 1.5 | **Bundled self-contained**; no separate MSIX required |
| **C++ Runtime** | Microsoft Visual C++ 2015–2022 Redistributable (x64) | Install it if it is missing |
| **Display** | Primary monitor with 100%–300% DPI scaling | PerMonitorV2 high-DPI awareness enabled |

---

## 2. Package Contents

The distributed release archive contains the complete standalone application directory:

```
AMORA.Orbit/
├── AMORA.Orbit.exe                  # Primary application entry point & launcher
├── AMORA.Orbit.dll                  # Managed application logic
├── resources.pri                    # Compiled WinUI 3 XAML resources & styles
├── Microsoft.WindowsAppRuntime*.dll # Windows App SDK self-contained runtime components
├── Microsoft.ui.xaml.dll            # WinUI 3 desktop visual engine
├── coreclr.dll, System.*.dll         # Self-contained .NET 8 runtime and framework libraries
├── AMORA.Orbit.exe                  # Embeds DPI awareness and OS compatibility manifest
└── RELEASE_MANIFEST.md              # This release manifest and deployment guide
```

---

## 3. Code Signing & Windows SmartScreen Notice

> [!IMPORTANT]
> **This public beta release is unsigned.** No commercial code-signing certificate is bundled into this open-source repository.

When launching `AMORA.Orbit.exe` for the first time on a fresh Windows system:
1. Microsoft Defender SmartScreen will display an *"Unknown Publisher"* notification:
   *"Windows protected your PC — Microsoft Defender SmartScreen prevented an unrecognized app from starting."*
2. To proceed:
   - Click **More info**.
   - Click **Run anyway**.
3. Verify the downloaded ZIP against the SHA-256 value published in the GitHub pre-release notes.

The Actions artifact uploaded for CI debugging expires after 30 days. It is not the permanent download; use the [GitHub Releases page](https://github.com/mohammedomarworks/AMORA/releases).

---

## 4. Installation & First Launch

### Installation
1. Open the [AMORA GitHub Releases page](https://github.com/mohammedomarworks/AMORA/releases), select the `AMORA Orbit v0.6.0-beta` pre-release, and download `AMORA.Orbit-v0.6.0-beta-win-x64.zip`.
2. Extract the archive into a dedicated folder (recommended: `%LocalAppData%\Programs\AMORA.Orbit` or any portable folder).
3. Run `AMORA.Orbit.exe`.
4. *(Optional)* Right-click `AMORA.Orbit.exe` -> **Pin to Start** or **Show more options -> Create shortcut** on Desktop.

### First-Run Experience
- Orbit launches directly into its **collapsed pill** mode at the top-center of your primary display.
- Press `Ctrl + Alt + O` or click the pill to expand the workspace downward.
- Upon expansion, the command input box automatically receives keyboard focus.
- **Offline & Local Features**: All local features (focus timers, media transport controls, battery/power metrics, hardware gauges, and local scheduled automations) operate immediately with **zero configuration**.

If startup fails after Windows allows the executable to run, AMORA displays a startup error when its managed startup handler is available and attempts to write a sanitized report to `%LOCALAPPDATA%\AMORA\Logs\crash.log`. Failures before managed logging starts may only appear in Windows Event Viewer. Include the matching Event Viewer entry (Application log, AMORA.Orbit.exe or a related Windows App Runtime module, with timestamp and exception/faulting-module details) when reporting a failure. Selecting **Run anyway** only bypasses the unsigned-app warning; it does not guarantee successful startup.

### Google Gemini Setup (Optional Cloud AI)
1. Open the expanded Orbit workspace and click the **Settings** (Gear) button in the header toolbar.
2. Enter your Google Gemini API key.
3. Click **Test Connection** to verify API communication.
4. Click **Save**.
5. Credentials are encrypted locally using Windows Data Protection API (`DPAPI`) tied to your Windows user account (`DataProtectionScope.CurrentUser`). Keys are never written to disk in plaintext.

---

## 5. Privacy & Data Flow Boundaries

| Data Type | Destination | Storage / Transmission Rules |
| :--- | :--- | :--- |
| **Focus Timers & Presets** | Local Only | Stored in memory; never transmitted. |
| **Media Playback State** | Local Only | Read via WinRT GSMTC; never transmitted. |
| **Battery & Telemetry** | Local Only | Read via Win32 APIs; never transmitted unless user opts in. |
| **Scheduled Automations** | Local Disk Only | Saved at `%LocalAppData%\AMORA\automations.json`. Never sent to cloud. |
| **Conversation History** | Local Memory Only | Ephemeral in-memory FIFO buffer (max 6 turns). Discarded upon exit or reset. |
| **Gemini API Prompts** | Google Gemini API | Sent over HTTPS to `generativelanguage.googleapis.com` only when user submits a query. |
| **Status Context Sharing** | Google Gemini API | **Opt-in only** (default: OFF). Only sent if explicitly toggled in Settings. |
| **Proactive Suggestions** | Local Only | **Opt-in only** (default: OFF). Evaluated deterministically on-device; never calls cloud AI. |

---

## 6. Updating, Uninstalling & Recovery

### Updating to a Newer Beta
1. Exit AMORA Orbit (right-click the taskbar notification area icon -> **Exit Orbit**, or close the capsule).
2. Extract the updated `.zip` package over your existing installation folder.
3. User configuration files (`%LocalAppData%\AMORA\ai_settings.json`, `%LocalAppData%\AMORA\Credentials`, `%LocalAppData%\AMORA\automations.json`) remain outside the application folder and persist across upgrades.

### Uninstalling
1. Exit AMORA Orbit.
2. Delete the application installation folder.
3. *(Optional)* Delete `%LocalAppData%\AMORA` to remove user settings, encrypted credentials, automations, and logs.
4. Orbit does not install system drivers, background services, or global registry run-keys.

### Recovery from Corrupted State
- If `ai_settings.json` or `automations.json` become corrupted, Orbit automatically recovers to safe default settings without crashing.
- To perform a complete factory reset:
  1. Exit Orbit.
  2. Delete `%LocalAppData%\AMORA`.
  3. Relaunch `AMORA.Orbit.exe`.
- For managed startup failures, sanitized diagnostic details are written when possible to `%LocalAppData%\AMORA\Logs\crash.log`. Very early native or runtime failures can occur before this file can be created; use the matching Windows Event Viewer Application log entry in that case.
