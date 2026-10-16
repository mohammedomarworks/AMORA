#!/bin/bash
set -euo pipefail

# Scripts/package-beta.sh
# Packages AMORA into a release-ready beta zip archive preserving macOS bundle
# structure, framework symlinks, permissions, and code signatures.
#
# Supports optional Apple Developer ID signing and xcrun notarytool notarization.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

VERSION_FILE="$PROJECT_DIR/VERSION"
APP_VERSION="1.0.0"
if [ -f "$VERSION_FILE" ]; then
    PARSED_VERSION="$(grep '^VERSION=' "$VERSION_FILE" | cut -d '=' -f2 | tr -d '[:space:]')"
    if [ -n "$PARSED_VERSION" ]; then
        APP_VERSION="$PARSED_VERSION"
    fi
fi

# Configurable beta number with default = 1
BETA_NUMBER="${BETA_NUMBER:-1}"
NOTARIZE=false
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-${NOTARY_PROFILE:-}}"

show_usage() {
    cat <<EOF
Usage: $0 [beta_number] [options]

Arguments:
  beta_number                   Beta build number (default: 1, or set via BETA_NUMBER)

Options:
  -b, --beta <number>           Specify beta build number
  --notarize                    Submit archive to Apple notary service and staple ticket
  --keychain-profile <name>     Specify Keychain profile for xcrun notarytool
  -h, --help                    Show this help message

Environment Variables:
  DEVELOPER_ID                  Developer ID Application certificate name (e.g. "Developer ID Application: Team (XYZ)")
                                If omitted or "-", build uses ad-hoc signing.
  BETA_NUMBER                   Default beta number (default: 1)
  KEYCHAIN_PROFILE              Keychain profile name stored with xcrun notarytool store-credentials
  NOTARY_KEY_PATH               Path to App Store Connect API AuthKey_*.p8
  NOTARY_KEY_ID                 App Store Connect API Key ID
  NOTARY_ISSUER_ID              App Store Connect API Issuer UUID
  NOTARY_APPLE_ID               Apple ID email for notarytool
  NOTARY_PASSWORD               App-specific password for notarytool
  NOTARY_TEAM_ID                Apple Developer Team ID for notarytool

Examples:
  # Package ad-hoc beta 1 for local testing
  ./Scripts/package-beta.sh 1

  # Package and sign with Developer ID
  DEVELOPER_ID="Developer ID Application: Your Name (TEAM_ID)" ./Scripts/package-beta.sh 1

  # Package, sign, and notarize with stored Keychain profile
  DEVELOPER_ID="Developer ID Application: Your Name (TEAM_ID)" ./Scripts/package-beta.sh 1 --notarize --keychain-profile "AC_PASSWORD"
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--beta)
            if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
                BETA_NUMBER="$2"
                shift 2
            else
                echo "❌ Error: --beta requires a number argument" >&2
                exit 1
            fi
            ;;
        --notarize)
            NOTARIZE=true
            shift
            ;;
        --keychain-profile|--profile)
            if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
                KEYCHAIN_PROFILE="$2"
                shift 2
            else
                echo "❌ Error: --keychain-profile requires a profile name argument" >&2
                exit 1
            fi
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                BETA_NUMBER="$1"
                shift
            else
                echo "❌ Error: Unknown argument '$1'" >&2
                echo "Run '$0 --help' for usage instructions." >&2
                exit 1
            fi
            ;;
    esac
done

DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$PROJECT_DIR/AMORA.app"
ZIP_NAME="AMORA-${APP_VERSION}-beta.${BETA_NUMBER}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

echo "============================================================"
echo "📦 AMORA Beta Packaging"
echo "Version:     v$APP_VERSION"
echo "Beta Number: $BETA_NUMBER"
echo "Target:      $ZIP_PATH"
echo "============================================================"

# Pre-flight notarization check if notarization was requested
if [ "$NOTARIZE" = true ]; then
    if [ -z "${DEVELOPER_ID:-}" ] || [ "${DEVELOPER_ID:-}" = "-" ]; then
        echo "" >&2
        echo "❌ Notarization Pre-flight Error:" >&2
        echo "   Apple Notary service requires apps to be signed with a valid Developer ID Application certificate." >&2
        echo "   The current signing identity is ad-hoc (-)." >&2
        echo "   Please set DEVELOPER_ID=\"Developer ID Application: <Name> (<TeamID>)\" and re-run." >&2
        exit 1
    fi

    # Verify credentials availability
    if [ -n "$KEYCHAIN_PROFILE" ]; then
        NOTARY_AUTH_ARGS=(--keychain-profile "$KEYCHAIN_PROFILE")
    elif [ -n "${NOTARY_KEY_PATH:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ]; then
        NOTARY_AUTH_ARGS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
    elif [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ]; then
        NOTARY_AUTH_ARGS=(--apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID")
    else
        echo "" >&2
        echo "❌ Notarization Pre-flight Error: Missing credentials." >&2
        echo "   To notarize, configure one of the following:" >&2
        echo "   1) Stored Keychain profile (recommended):" >&2
        echo "      xcrun notarytool store-credentials <profile-name> \\" >&2
        echo "        --apple-id <email> --team-id <team-id>" >&2
        echo "      Then pass --keychain-profile <profile-name> or set KEYCHAIN_PROFILE" >&2
        echo "   2) App Store Connect API Key:" >&2
        echo "      Set NOTARY_KEY_PATH, NOTARY_KEY_ID, and NOTARY_ISSUER_ID" >&2
        echo "   3) Apple ID with App-Specific Password:" >&2
        echo "      Set NOTARY_APPLE_ID, NOTARY_PASSWORD, and NOTARY_TEAM_ID" >&2
        exit 1
    fi
fi

# Step 1: Build the release app bundle
echo ""
echo "🔨 Step 1: Building release app bundle..."
"$SCRIPT_DIR/build-app.sh" release

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ Error: App bundle not found at $APP_BUNDLE after build." >&2
    exit 1
fi

mkdir -p "$DIST_DIR"

# Step 2: Handle optional notarization workflow
NOTARIZATION_STATUS="Not requested"
if [ "$NOTARIZE" = true ]; then
    echo ""
    echo "☁️  Step 2: Submitting to Apple Notary Service..."
    NOTARIZE_STAGING_DIR="$(mktemp -d /tmp/amora_notary_stage.XXXXXX)"
    NOTARIZE_STAGING_ZIP="$NOTARIZE_STAGING_DIR/AMORA-submission.zip"
    
    echo "  Creating submission archive with ditto..."
    ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARIZE_STAGING_ZIP"

    echo "  Submitting to xcrun notarytool (waiting for ticket)..."
    NOTARY_OUTPUT="$(xcrun notarytool submit "$NOTARIZE_STAGING_ZIP" "${NOTARY_AUTH_ARGS[@]}" --wait 2>&1)" || {
        echo "❌ xcrun notarytool submit failed:" >&2
        echo "$NOTARY_OUTPUT" >&2
        rm -rf "$NOTARIZE_STAGING_DIR"
        exit 1
    }
    rm -rf "$NOTARIZE_STAGING_DIR"

    SUBMISSION_ID="$(echo "$NOTARY_OUTPUT" | grep -E "id: " | head -1 | awk '{print $2}' || true)"
    echo "$NOTARY_OUTPUT"

    if ! echo "$NOTARY_OUTPUT" | grep -q "status: Accepted"; then
        echo "❌ Apple notarization failed (status was not 'Accepted')." >&2
        if [ -n "$SUBMISSION_ID" ]; then
            echo "Fetching notary submission log for $SUBMISSION_ID..." >&2
            xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_AUTH_ARGS[@]}" || true
        fi
        exit 1
    fi

    echo "  Attaching notarization ticket (stapling)..."
    xcrun stapler staple "$APP_BUNDLE"
    xcrun stapler validate "$APP_BUNDLE"
    NOTARIZATION_STATUS="Notarized and Stapled"
fi

# Step 3: Package AMORA.app using ditto
echo ""
echo "📦 Step 3: Packaging $ZIP_NAME..."
rm -f "$ZIP_PATH"
# Using ditto -c -k --keepParent preserves symlinks, permissions, and bundle structure
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

if [ ! -f "$ZIP_PATH" ]; then
    echo "❌ Error: Failed to create package at $ZIP_PATH" >&2
    exit 1
fi

# Step 4: Verification of the archive in a clean temporary directory
echo ""
echo "🔍 Step 4: Verifying packaged archive..."
VERIFY_DIR="$(mktemp -d /tmp/amora_verify_pkg.XXXXXX)"
trap 'rm -rf "$VERIFY_DIR"' EXIT

echo "  Extracting archive with ditto to verify..."
ditto -x -k "$ZIP_PATH" "$VERIFY_DIR"

EXTRACTED_APP="$VERIFY_DIR/AMORA.app"
if [ ! -d "$EXTRACTED_APP" ]; then
    echo "❌ Verification error: AMORA.app missing from extracted archive." >&2
    exit 1
fi

if [ ! -f "$EXTRACTED_APP/Contents/Info.plist" ]; then
    echo "❌ Verification error: Contents/Info.plist missing." >&2
    exit 1
fi

if [ ! -x "$EXTRACTED_APP/Contents/MacOS/AMORA" ]; then
    echo "❌ Verification error: Contents/MacOS/AMORA is missing or not executable." >&2
    exit 1
fi

if [ ! -x "$EXTRACTED_APP/Contents/Resources/AMORA-BrowserHost" ]; then
    echo "❌ Verification error: Contents/Resources/AMORA-BrowserHost is missing or not executable." >&2
    exit 1
fi

# Verify llama.framework symlinks
FRAMEWORK_DIR="$EXTRACTED_APP/Contents/Frameworks/llama.framework"
if [ ! -d "$FRAMEWORK_DIR" ]; then
    echo "❌ Verification error: llama.framework directory missing in Frameworks." >&2
    exit 1
fi

REQUIRED_SYMLINKS=("Headers" "Modules" "Resources" "Versions/Current" "llama")
for SYMLINK in "${REQUIRED_SYMLINKS[@]}"; do
    TARGET="$FRAMEWORK_DIR/$SYMLINK"
    if [ ! -L "$TARGET" ]; then
        echo "❌ Verification error: $SYMLINK is not a symbolic link in extracted bundle." >&2
        exit 1
    fi
    if [ ! -e "$TARGET" ]; then
        echo "❌ Verification error: $SYMLINK is a broken symlink (points to nonexistent target)." >&2
        exit 1
    fi
done
echo "  ✓ llama.framework symlinks preserved: ${REQUIRED_SYMLINKS[*]}"

# Run deep strict codesign verification
echo "  Verifying code signature of extracted bundle..."
codesign --verify --deep --strict --verbose=2 "$EXTRACTED_APP"
echo "  ✓ Code signature is valid on disk."

# Check Gatekeeper assessment (spctl)
SPCTL_OUTPUT="$(spctl -a -vv --type execute "$EXTRACTED_APP" 2>&1 || true)"

# Compute package details
ZIP_SIZE="$(ls -lh "$ZIP_PATH" | awk '{print $5}')"
ZIP_SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"

# Report final summary
CURRENT_IDENTITY="${DEVELOPER_ID:-ad-hoc (-)}"
if [ -z "$CURRENT_IDENTITY" ]; then
    CURRENT_IDENTITY="ad-hoc (-)"
fi

echo ""
echo "============================================================"
echo "🎉 AMORA Beta Package Created Successfully"
echo "============================================================"
echo "Archive:       $ZIP_PATH"
echo "Size:          $ZIP_SIZE"
echo "SHA-256:       $ZIP_SHA256"
echo "App Version:   $APP_VERSION"
echo "Beta Number:   $BETA_NUMBER"
echo "Code Signing:  $CURRENT_IDENTITY"
echo "Notarization:  $NOTARIZATION_STATUS"
echo "------------------------------------------------------------"

if [ "$NOTARIZATION_STATUS" = "Notarized and Stapled" ]; then
    echo "✅ GATEKEEPER STATUS: Ready for Distribution"
    echo "   The application is signed with a Developer ID Application identity,"
    echo "   has been notarized by Apple, and includes a stapled ticket."
    echo "   Gatekeeper will allow users to launch this app without security warnings."
elif [ "$CURRENT_IDENTITY" != "ad-hoc (-)" ]; then
    echo "⚠️  GATEKEEPER STATUS: Developer ID Signed (Not Notarized)"
    echo "   The application is signed with Developer ID, but has not been notarized."
    echo "   macOS Gatekeeper will block first launch on macOS Catalina and later."
    echo "   To notarize, re-run with --notarize and valid Apple credentials."
else
    echo "⚠️  GATEKEEPER / RELEASE STATUS: Ad-Hoc Signed (Local Testing Only)"
    echo "   Spctl result: $SPCTL_OUTPUT"
    echo "   Public distribution is BLOCKED pending Apple Developer Program prerequisites:"
    echo "     1. An active Apple Developer Program membership."
    echo "     2. A Developer ID Application certificate installed in Keychain."
    echo "     3. Submission to Apple notary service (via --notarize) and stapling."
    echo ""
    echo "   IMPORTANT SECURITY NOTE:"
    echo "   Testers should NOT be instructed to disable Gatekeeper system-wide"
    echo "   or strip quarantine attributes (xattr -d com.apple.quarantine) as a"
    echo "   standard distribution practice. Ad-hoc builds are strictly for local"
    echo "   development and internal verification on the build machine."
fi
echo "============================================================"
