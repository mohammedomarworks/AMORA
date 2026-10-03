# AMORA browser media helper

The Chrome helper is a Manifest V3 extension plus a Chrome Native Messaging
host. The extension only runs on YouTube URL patterns, forwards state only for
the active tab, and sends normalized media state through the native host. The
host forwards validated state to AMORA using local Distributed Notifications;
there is no public network listener.

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
