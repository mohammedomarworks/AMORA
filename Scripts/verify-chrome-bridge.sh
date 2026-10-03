#!/bin/bash
set -euo pipefail

HOST_NAME="com.amora.browser"
HOST_PATH="$HOME/Library/Application Support/AMORA/AMORA-BrowserHost"
MANIFEST_PATH="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/$HOST_NAME.json"
EXPECTED_ID="${AMORA_CHROME_EXTENSION_ID:-pcjbhandogggbhkjdfpcngenaaediend}"

echo "Chrome Native Messaging Diagnostic"
echo
[ -f "$HOST_PATH" ] && echo "Host: FOUND ($HOST_PATH)" || echo "Host: MISSING ($HOST_PATH)"
[ -x "$HOST_PATH" ] && echo "Executable: OK" || echo "Executable: NOT EXECUTABLE"

manifest_ok=0
if [ -f "$MANIFEST_PATH" ] && /usr/bin/python3 - "$MANIFEST_PATH" "$HOST_PATH" "$HOST_NAME" "$EXPECTED_ID" <<'PY'
import json, os, sys
path, host, name, expected_id = sys.argv[1:]
with open(path, encoding="utf-8") as f: m = json.load(f)
assert m["name"] == name and m["type"] == "stdio"
assert os.path.abspath(m["path"]) == os.path.abspath(host)
assert m["allowed_origins"] == [f"chrome-extension://{expected_id}/"]
assert os.path.isfile(host) and os.access(host, os.X_OK)
PY
then manifest_ok=1; echo "Manifest: FOUND / VALID"; else echo "Manifest: FOUND / INVALID"; fi

if [ "$manifest_ok" -eq 1 ]; then
  echo "Host name: OK ($HOST_NAME)"
  echo "Allowed origin: MATCH"
  echo "Extension ID: $EXPECTED_ID"
  echo "Manifest path: VALID ($MANIFEST_PATH)"
else
  echo "Host name: UNKNOWN / MISMATCH"
  echo "Allowed origin: UNKNOWN / MISMATCH"
  echo "Extension ID: $EXPECTED_ID (expected stable unpacked ID)"
  echo "Manifest path: INVALID ($MANIFEST_PATH)"
fi

protocol="NOT TESTED"
if [ -x "$HOST_PATH" ]; then
  protocol=$(/usr/bin/python3 - "$HOST_PATH" <<'PY'
import json, struct, subprocess, sys
p = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
payload = json.dumps({"type":"ping"}).encode()
p.stdin.write(struct.pack("<I", len(payload)) + payload); p.stdin.flush()
header = p.stdout.read(4)
body = p.stdout.read(struct.unpack("<I", header)[0]) if len(header) == 4 else b""
p.terminate()
try: reply = json.loads(body)
except Exception: reply = {}
print("OK" if reply == {"type":"pong"} else "FAILED")
PY
  )
fi
echo "Protocol: $protocol"
echo
[ "$manifest_ok" -eq 1 ] && [ "$protocol" = "OK" ] \
  && echo "Diagnosis: host registration and stdio protocol are working." \
  || echo "Diagnosis: repair the first failing item above, then rerun this script."
