#!/bin/bash
# Builds DataTracker and installs it on every iPhone connected to this Mac.
#
#   ./scripts/install-on-iphones.sh                 # asks for your Team ID the first time
#   ./scripts/install-on-iphones.sh ABCDE12345      # Team ID as an argument
#
# Before running:
#   - Xcode is installed and signed in to your paid Apple Developer account
#     (Xcode > Settings > Accounts).
#   - Each iPhone is plugged in (or paired over Wi-Fi), unlocked, and trusts this Mac.
#   - Developer Mode is on (Settings > Privacy & Security > Developer Mode). iOS only shows
#     that switch after the phone has been connected to Xcode once; this script does that.
set -euo pipefail

cd "$(dirname "$0")/.."
LOCAL_CONFIG=Config/Local.xcconfig
BUILD_DIR=build/DeviceBuild

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[31mError: %s\033[0m\n' "$*" >&2; exit 1; }

# 1. Tools
command -v xcodebuild >/dev/null || fail "Xcode is not installed. Install it from the App Store, open it once, then run this again."
if ! command -v xcodegen >/dev/null; then
    command -v brew >/dev/null || fail "Homebrew is needed to install XcodeGen: https://brew.sh"
    say "Installing XcodeGen"
    brew install xcodegen
fi

# 2. Signing settings (kept in Config/Local.xcconfig, which git ignores)
TEAM_ID="${1:-}"
if [[ -z "$TEAM_ID" && -f "$LOCAL_CONFIG" ]]; then
    TEAM_ID=$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$LOCAL_CONFIG" | tr -d ' ')
fi
if [[ -z "$TEAM_ID" ]]; then
    echo "Your Team ID is the 10-character code at developer.apple.com > Account > Membership details."
    read -r -p "Team ID: " TEAM_ID
fi
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail "\"$TEAM_ID\" doesn't look like a Team ID (10 letters/digits)."

PREFIX=""
CONTACT=""
if [[ -f "$LOCAL_CONFIG" ]]; then
    PREFIX=$(sed -n 's/^BUNDLE_ID_PREFIX *= *//p' "$LOCAL_CONFIG" | tr -d ' ')
    CONTACT=$(sed -n 's/^DEVELOPER_CONTACT_EMAIL *= *//p' "$LOCAL_CONFIG" | tr -d ' ')
fi
if [[ -z "$CONTACT" ]]; then
    read -r -p "Email where users' messages from Settings should go (Enter to skip): " CONTACT
fi
# Bundle IDs must be unique across all Apple developers, so derive one from the team.
[[ -n "$PREFIX" ]] || PREFIX="com.t$(echo "$TEAM_ID" | tr '[:upper:]' '[:lower:]')"
printf 'DEVELOPMENT_TEAM = %s\nBUNDLE_ID_PREFIX = %s\nDEVELOPER_CONTACT_EMAIL = %s\n' \
    "$TEAM_ID" "$PREFIX" "$CONTACT" > "$LOCAL_CONFIG"
echo "Team $TEAM_ID, bundle ID $PREFIX.datatracker (saved in $LOCAL_CONFIG)"

# 3. Project
say "Generating the Xcode project"
xcodegen generate --quiet

# 4. Connected iPhones
say "Looking for connected iPhones"
DEVICES_JSON=$(mktemp)
trap 'rm -f "$DEVICES_JSON"' EXIT
xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null

UDIDS=()
NAMES=()
i=0
while plutil -extract "result.devices.$i" json -o /dev/null "$DEVICES_JSON" 2>/dev/null; do
    get() { plutil -extract "result.devices.$i.$1" raw -o - "$DEVICES_JSON" 2>/dev/null || true; }
    platform=$(get hardwareProperties.platform)
    pairing=$(get connectionProperties.pairingState)
    udid=$(get hardwareProperties.udid)
    name=$(get deviceProperties.name)
    if [[ "$platform" == "iOS" && "$pairing" == "paired" && -n "$udid" ]]; then
        UDIDS+=("$udid")
        NAMES+=("$name")
        echo "  found: $name"
    fi
    i=$((i + 1))
done
[[ ${#UDIDS[@]} -gt 0 ]] || fail "No paired iPhone found. Plug the phone in, unlock it, tap Trust, and run again."

# 5. Build for each phone (registers it with your developer account) and install.
#    The second build is incremental and quick.
build_for() {
    xcodebuild build \
        -project DataTracker.xcodeproj \
        -scheme DataTracker \
        -configuration Release \
        -destination "id=$1" \
        -derivedDataPath "$BUILD_DIR" \
        -allowProvisioningUpdates \
        -allowProvisioningDeviceRegistration \
        -skipPackagePluginValidation \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        > build.log 2>&1
}

# Build number goes up with every commit, so each install shows a new version in Settings.
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || date +%Y%m%d%H%M)

APP="$BUILD_DIR/Build/Products/Release-iphoneos/DataTracker.app"
INSTALLED=0
for index in "${!UDIDS[@]}"; do
    name="${NAMES[$index]}"
    udid="${UDIDS[$index]}"
    say "Building for $name (the first build downloads packages and takes a few minutes)"
    if ! build_for "$udid"; then
        grep -E "error:" build.log | sort -u | head -40 >&2 || true
        cat >&2 <<'EOT'

Build failed. Full log: build.log
Common fixes:
  - "No Account for Team" / "No profiles": open Xcode > Settings > Accounts and sign in.
  - "Developer Mode disabled": turn it on on the phone, restart it, run again.
  - Capability errors: open DataTracker.xcodeproj, select each target > Signing & Capabilities,
    and click "Try Again".
EOT
        continue
    fi
    [[ -d "$APP" ]] || fail "Build succeeded but $APP is missing."

    say "Installing on $name"
    if xcrun devicectl device install app --device "$udid" "$APP"; then
        echo "Installed on $name."
        INSTALLED=$((INSTALLED + 1))
    else
        echo "Install on $name failed. Check that the phone is unlocked and Developer Mode is on." >&2
    fi
done
[[ $INSTALLED -gt 0 ]] || fail "Nothing was installed."

cat <<'EOF'

Done. On each iPhone:
  1. If iOS says "Untrusted Developer": Settings > General > VPN & Device Management > your account > Trust.
  2. Open DataTracker > Settings > turn on "Per-app tracking" > Continue > Allow.
EOF
