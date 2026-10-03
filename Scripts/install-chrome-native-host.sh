#!/bin/bash
set -euo pipefail

# Install only the executable Chrome needs and register it in Chrome's
# user-level NativeMessagingHosts directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOST_SOURCE="${1:-$PROJECT_DIR/AMORA.app/Contents/Resources/AMORA-BrowserHost}"
# The key in manifest.json gives unpacked development builds a stable ID.
EXTENSION_ID="${AMORA_CHROME_EXTENSION_ID:-pcjbhandogggbhkjdfpcngenaaediend}"
HOST_NAME="com.amora.browser"

if [ ! -f "$HOST_SOURCE" ]; then
    echo "❌ Native messaging host executable not found: $HOST_SOURCE" >&2
    echo "   Build AMORA first, or pass the executable path as the first argument." >&2
    exit 1
fi

if [ "${HOST_SOURCE#/}" = "$HOST_SOURCE" ]; then
    echo "❌ Native messaging host path must be absolute: $HOST_SOURCE" >&2
    exit 1
fi

if [[ ! "$EXTENSION_ID" =~ ^[a-p]{32}$ ]]; then
    echo "❌ Invalid Chrome extension ID: $EXTENSION_ID" >&2
    exit 1
fi

CHROME_HOST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
AMORA_SUPPORT_DIR="$HOME/Library/Application Support/AMORA"
INSTALLED_HOST="$AMORA_SUPPORT_DIR/AMORA-BrowserHost"
MANIFEST_PATH="$CHROME_HOST_DIR/$HOST_NAME.json"

mkdir -p "$AMORA_SUPPORT_DIR" "$CHROME_HOST_DIR"
if [ "$HOST_SOURCE" != "$INSTALLED_HOST" ]; then
    install -m 755 "$HOST_SOURCE" "$INSTALLED_HOST"
else
    chmod 755 "$INSTALLED_HOST"
fi

/usr/bin/python3 - "$MANIFEST_PATH" "$INSTALLED_HOST" "$EXTENSION_ID" <<'PY'
import json
import os
import sys

manifest_path, host_path, extension_id = sys.argv[1:]
manifest = {
    "name": "com.amora.browser",
    "description": "AMORA browser media bridge",
    "path": os.path.abspath(host_path),
    "type": "stdio",
    "allowed_origins": [f"chrome-extension://{extension_id}/"],
}

temporary_path = manifest_path + ".tmp"
with open(temporary_path, "w", encoding="utf-8") as manifest_file:
    json.dump(manifest, manifest_file, indent=2)
    manifest_file.write("\n")
os.replace(temporary_path, manifest_path)
PY

test -x "$INSTALLED_HOST" || { echo "❌ Installed host is not executable" >&2; exit 1; }
/usr/bin/python3 - "$MANIFEST_PATH" <<'PY'
import json, os, sys
with open(sys.argv[1], encoding="utf-8") as f: data = json.load(f)
assert data["name"] == "com.amora.browser"
assert os.path.isabs(data["path"]) and os.access(data["path"], os.X_OK)
assert data["type"] == "stdio"
assert len(data["allowed_origins"]) == 1
PY

echo "✅ Chrome native messaging host installed"
echo "   host:     $INSTALLED_HOST"
echo "   manifest: $MANIFEST_PATH"
echo "   origin:   chrome-extension://$EXTENSION_ID/"
echo "   restart Chrome completely, then reload the unpacked extension"
