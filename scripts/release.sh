#!/usr/bin/env bash
# Builds a Developer ID–signed, Apple-notarized DeskPet.app and zips it for
# distribution. Works with only the Xcode Command Line Tools installed.
#
#   scripts/release.sh                  # -> dist/DeskPet-<version>.zip
#
# One-time setup (see README › Releasing):
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. Notary credentials saved with:
#        xcrun notarytool store-credentials DeskPet-notary \
#          --apple-id <you@example.com> --team-id <TEAMID>
#
# Overrides:
#   DESKPET_SIGN_IDENTITY   certificate name or SHA-1 (default: the only
#                           "Developer ID Application" identity found)
#   DESKPET_NOTARY_PROFILE  notarytool keychain profile (default: DeskPet-notary)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DeskPet.app"
DIST="$ROOT/dist"
PROFILE="${DESKPET_NOTARY_PROFILE:-DeskPet-notary}"
VERSION="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$ROOT/scripts/build-app.sh")"
ZIP="$DIST/DeskPet-${VERSION%.0}.zip"

fail() { echo "error: $*" >&2; exit 1; }

# --- Preflight: check everything before spending time on a build ----------
echo "==> Checking release prerequisites"
problems=()

if [[ -n "${DESKPET_SIGN_IDENTITY:-}" ]]; then
    IDENTITY="$DESKPET_SIGN_IDENTITY"
    security find-identity -v -p codesigning | grep -qF "$IDENTITY" \
        || problems+=("Signing identity \"$IDENTITY\" is not a valid code-signing certificate in your keychain.")
else
    ids="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p' | sort -u)"
    count="$(printf '%s' "$ids" | grep -c . || true)"
    if [[ "$count" -eq 0 ]]; then
        problems+=("No \"Developer ID Application\" certificate found. Create one at
   https://developer.apple.com/account/resources/certificates and install it.")
    elif [[ "$count" -gt 1 ]]; then
        problems+=("Several Developer ID certificates found; pick one with DESKPET_SIGN_IDENTITY:
$(printf '   %s\n' "$ids")")
    else
        IDENTITY="$ids"
    fi
fi

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    problems+=("No working notary credentials for profile \"$PROFILE\". In Terminal.app run:
   xcrun notarytool store-credentials $PROFILE --apple-id <you@example.com> --team-id <TEAMID>")
fi

if [[ ${#problems[@]} -gt 0 ]]; then
    echo "Can't make a release yet:" >&2
    for p in "${problems[@]}"; do echo " • $p" >&2; done
    exit 1
fi
echo "    Signing as: $IDENTITY"
echo "    Notary profile: $PROFILE"

# --- Build ----------------------------------------------------------------
"$ROOT/scripts/build-app.sh" release

# --- Sign with Developer ID + hardened runtime ----------------------------
# Hardened runtime is required for notarization. The app isn't sandboxed, so
# the only entitlement needed is microphone access for push-to-talk.
echo "==> Signing with Developer ID (hardened runtime)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/DeskPet.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key> <true/>
</dict>
</plist>
PLIST
codesign --force --options runtime --timestamp \
    --entitlements "$WORK/DeskPet.entitlements" \
    --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# --- Notarize --------------------------------------------------------------
echo "==> Submitting to Apple for notarization (usually a few minutes)"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/upload.zip"
xcrun notarytool submit "$WORK/upload.zip" --keychain-profile "$PROFILE" | tee "$WORK/submit.txt"
SUBMISSION="$(sed -n 's/^ *id: *//p' "$WORK/submit.txt" | head -1)"
[[ -n "$SUBMISSION" ]] || fail "Upload to Apple failed (no submission ID)."

# Apple keeps processing even if this Mac drops offline, so a network error
# while waiting is retried instead of abandoning an upload that went through.
STATUS=""
for attempt in $(seq 1 20); do
    if xcrun notarytool wait "$SUBMISSION" --keychain-profile "$PROFILE" --timeout 2h > "$WORK/notary.txt" 2>&1; then :; fi
    STATUS="$(sed -n 's/^ *status: *//p' "$WORK/notary.txt" | tail -1)"
    case "$STATUS" in
        Accepted|Invalid|Rejected) break ;;
        *) echo "    Still waiting on Apple (${STATUS:-no response}); retrying in 30s…"; sleep 30 ;;
    esac
done
echo "    Apple's verdict: ${STATUS:-unknown}"
if [[ "$STATUS" != "Accepted" ]]; then
    echo "Notarization was not accepted (submission $SUBMISSION). Apple's log:" >&2
    xcrun notarytool log "$SUBMISSION" --keychain-profile "$PROFILE" >&2 || true
    echo "If it is still in progress, check later with:" >&2
    echo "  xcrun notarytool info $SUBMISSION --keychain-profile $PROFILE" >&2
    exit 1
fi

# --- Staple and package ----------------------------------------------------
echo "==> Stapling the notarization ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Done: $ZIP"
echo "    Version $VERSION, signed by $IDENTITY, notarized (submission $SUBMISSION)"
