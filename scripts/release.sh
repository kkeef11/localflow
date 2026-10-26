#!/usr/bin/env bash
# Build, sign, notarize, staple, verify and zip a LocalFlow release. Used by
# .github/workflows/release.yml and runnable locally. See docs/RELEASING.md.
#
#   scripts/release.sh 0.2.0              # Developer ID signed + notarized (needs credentials below)
#   scripts/release.sh 0.2.0 --no-notarize  # Developer ID signed only — NOT for distribution
#   scripts/release.sh 0.2.0 --unsigned   # ad-hoc signed test build — NOT for distribution
#
# Output: dist/LocalFlow-<version>[-suffix].zip and a matching .sha256 file.
#
# Signed builds need:
#   DEVELOPER_ID_TEAM        10-character Apple Team ID owning the Developer ID certificate
#   SIGNING_KEYCHAIN         (optional) keychain holding the "Developer ID Application" identity
# Notarization needs EITHER an App Store Connect API key (CI):
#   NOTARY_API_KEY_PATH, NOTARY_API_KEY_ID, NOTARY_API_ISSUER_ID
# OR a notarytool keychain profile (local; create with `xcrun notarytool store-credentials`):
#   NOTARY_KEYCHAIN_PROFILE
#
#   BUILD_NUMBER             (optional) CFBundleVersion; defaults to the git commit count
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/release"
DIST="$ROOT/dist"
BUNDLE_ID="com.kkeefer.LocalFlow"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

VERSION=""; MODE="notarized"
for arg in "$@"; do
    case "$arg" in
        --unsigned) MODE="unsigned" ;;
        --no-notarize) MODE="signed" ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "unknown option $arg" ;;
        *) VERSION="${arg#v}" ;;
    esac
done
[[ -n "$VERSION" ]] || die "usage: scripts/release.sh <version> [--unsigned|--no-notarize]"
# Tags may carry a pre-release suffix (0.2.0-beta.1); CFBundleShortVersionString may not.
[[ "$VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(-[0-9A-Za-z.]+)?$ ]] || die "version '$VERSION' must look like 1.2.3 or 1.2.3-beta.1"
MARKETING_VERSION="${BASH_REMATCH[1]}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD)}"

case "$MODE" in
    unsigned) ZIP_NAME="LocalFlow-$VERSION-unsigned.zip" ;;
    signed)   ZIP_NAME="LocalFlow-$VERSION-not-notarized.zip" ;;
    *)        ZIP_NAME="LocalFlow-$VERSION.zip" ;;
esac

if [[ "$MODE" != "unsigned" ]]; then
    [[ "${DEVELOPER_ID_TEAM:-}" =~ ^[A-Z0-9]{10}$ ]] || die "DEVELOPER_ID_TEAM must be your 10-character Apple Team ID"
    keychain_args=()
    [[ -n "${SIGNING_KEYCHAIN:-}" ]] && keychain_args=("$SIGNING_KEYCHAIN")
    identities="$(security find-identity -v -p codesigning ${keychain_args[@]+"${keychain_args[@]}"})"
    grep -q "Developer ID Application: .*($DEVELOPER_ID_TEAM)" <<<"$identities" \
        || die "no valid \"Developer ID Application\" identity for team $DEVELOPER_ID_TEAM in the keychain"
fi
if [[ "$MODE" == "notarized" ]]; then
    if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
        notary_auth=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
    elif [[ -n "${NOTARY_API_KEY_PATH:-}" && -n "${NOTARY_API_KEY_ID:-}" && -n "${NOTARY_API_ISSUER_ID:-}" ]]; then
        [[ -f "$NOTARY_API_KEY_PATH" ]] || die "NOTARY_API_KEY_PATH does not exist"
        notary_auth=(--key "$NOTARY_API_KEY_PATH" --key-id "$NOTARY_API_KEY_ID" --issuer "$NOTARY_API_ISSUER_ID")
    else
        die "notarization credentials missing: set NOTARY_KEYCHAIN_PROFILE, or NOTARY_API_KEY_PATH + NOTARY_API_KEY_ID + NOTARY_API_ISSUER_ID (or pass --no-notarize)"
    fi
fi

rm -rf "$BUILD"; mkdir -p "$BUILD" "$DIST"
"$ROOT/scripts/build.sh" project

# --- Archive ---------------------------------------------------------------------------
sign_settings=()
if [[ "$MODE" == "unsigned" ]]; then
    sign_settings=(CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Automatic)
else
    flags="--timestamp"; [[ -n "${SIGNING_KEYCHAIN:-}" ]] && flags="$flags --keychain $SIGNING_KEYCHAIN"
    sign_settings=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Developer ID Application"
                   "DEVELOPMENT_TEAM=$DEVELOPER_ID_TEAM" "OTHER_CODE_SIGN_FLAGS=$flags")
fi
lock_args=()
[[ -f "$ROOT/Config/Package.resolved" ]] && lock_args=(-onlyUsePackageVersionsFromResolvedFile)

log "Archiving LocalFlow $MARKETING_VERSION ($BUILD_NUMBER) [$MODE]"
xcodebuild archive -project "$ROOT/LocalFlow.xcodeproj" -scheme LocalFlow -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$BUILD/LocalFlow.xcarchive" \
    -derivedDataPath "$ROOT/build/DerivedData" -skipPackagePluginValidation -skipMacroValidation \
    ${lock_args[@]+"${lock_args[@]}"} \
    "MARKETING_VERSION=$MARKETING_VERSION" "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
    "${sign_settings[@]}"

# --- Export ----------------------------------------------------------------------------
APP="$BUILD/export/LocalFlow.app"
if [[ "$MODE" == "unsigned" ]]; then
    mkdir -p "$BUILD/export"
    ditto "$BUILD/LocalFlow.xcarchive/Products/Applications/LocalFlow.app" "$APP"
else
    cat > "$BUILD/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
    <key>teamID</key><string>$DEVELOPER_ID_TEAM</string>
</dict>
</plist>
EOF
    log "Exporting with Developer ID"
    xcodebuild -exportArchive -archivePath "$BUILD/LocalFlow.xcarchive" \
        -exportOptionsPlist "$BUILD/ExportOptions.plist" -exportPath "$BUILD/export"
fi
[[ -d "$APP" ]] || die "export did not produce $APP"

# --- Verify the bundle before spending time on notarization ----------------------------
log "Verifying bundle"
plist="$APP/Contents/Info.plist"
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$plist")" == "$BUNDLE_ID" ]] || die "bundle identifier is not $BUNDLE_ID"
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$plist")" == "$MARKETING_VERSION" ]] || die "CFBundleShortVersionString is not $MARKETING_VERSION"
codesign --verify --deep --strict --verbose=2 "$APP"
entitlements="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)"
grep -q "com.apple.security.device.audio-input" <<<"$entitlements" || die "audio-input entitlement missing (microphone would be blocked under the hardened runtime)"
if [[ "$MODE" != "unsigned" ]]; then
    details="$(codesign -dv "$APP" 2>&1)"
    grep -q "flags=.*runtime" <<<"$details" || die "hardened runtime not enabled (required for notarization)"
    grep -q "TeamIdentifier=$DEVELOPER_ID_TEAM" <<<"$details" || die "not signed by team $DEVELOPER_ID_TEAM"
    ! grep -q "com.apple.security.get-task-allow" <<<"$entitlements" || die "get-task-allow entitlement present (debug signing) — notarization would reject it"
fi

# --- Notarize + staple -----------------------------------------------------------------
if [[ "$MODE" == "notarized" ]]; then
    upload="$BUILD/LocalFlow-notarize.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$upload"
    log "Submitting to Apple notary service (usually a few minutes)"
    result="$BUILD/notary-result.json"
    xcrun notarytool submit "$upload" "${notary_auth[@]}" --wait --timeout 30m --output-format json > "$result" || true
    status="$(plutil -extract status raw -o - "$result" 2>/dev/null || echo unknown)"
    submission="$(plutil -extract id raw -o - "$result" 2>/dev/null || echo "")"
    if [[ "$status" != "Accepted" ]]; then
        cat "$result" >&2 || true
        if [[ -n "$submission" ]]; then
            xcrun notarytool log "$submission" "${notary_auth[@]}" >&2 || true
        fi
        die "notarization status: $status"
    fi
    log "Notarization accepted ($submission); stapling"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=4 "$APP"
fi

# --- Package ---------------------------------------------------------------------------
rm -f "$DIST/$ZIP_NAME" "$DIST/$ZIP_NAME.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$ZIP_NAME"
(cd "$DIST" && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")
log "Created dist/$ZIP_NAME"
cat "$DIST/$ZIP_NAME.sha256"
[[ "$MODE" == "notarized" ]] || log "NOTE: this $MODE build is for testing only; Gatekeeper will block it on other Macs."
