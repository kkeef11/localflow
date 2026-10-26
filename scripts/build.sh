#!/usr/bin/env bash
# Generate the Xcode project and build / test LocalFlow. Used by developers, CI, and
# scripts/release.sh, so every build goes through the same steps.
#
#   scripts/build.sh            # Debug build  -> build/DerivedData/Build/Products/Debug/LocalFlow.app
#   scripts/build.sh release    # Release build (signed per Config/LocalFlow.xcconfig)
#   scripts/build.sh test       # Run the unit tests
#   scripts/build.sh project    # Only generate LocalFlow.xcodeproj (e.g. to open it in Xcode)
#   scripts/build.sh lock       # Re-resolve Swift packages and refresh Config/Package.resolved
#   scripts/build.sh clean      # Remove build/ and the generated project
#
# Environment:
#   LOCALFLOW_DEVELOPMENT_TEAM  Sign with this team's "Apple Development" identity for this
#                               run (overrides Config/Signing.local.xcconfig).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/LocalFlow.xcodeproj"
DERIVED="$ROOT/build/DerivedData"
LOCKFILE="$ROOT/Config/Package.resolved"
# Where Xcode looks for the resolved-package lockfile inside the (generated, git-ignored) project.
PROJECT_LOCK="$PROJECT/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

generate() {
    command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found. Install Xcode from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"
    command -v xcodegen >/dev/null 2>&1 || die "xcodegen not found. Run scripts/setup-macos.sh, or: brew install xcodegen"
    log "Generating LocalFlow.xcodeproj (xcodegen $(xcodegen --version 2>/dev/null | awk '{print $NF}'))"
    (cd "$ROOT" && xcodegen generate --quiet)
    # Pin every transitive Swift package (WhisperKit's dependencies use version ranges).
    if [[ -f "$LOCKFILE" ]]; then
        mkdir -p "$(dirname "$PROJECT_LOCK")"
        cp "$LOCKFILE" "$PROJECT_LOCK"
    fi
}

# Shared xcodebuild arguments. Plugin/macro validation prompts can't be answered headlessly.
xcb() {
    local extra=()
    if [[ -f "$LOCKFILE" ]]; then
        extra+=(-onlyUsePackageVersionsFromResolvedFile)
    fi
    if [[ -n "${LOCALFLOW_DEVELOPMENT_TEAM:-}" ]]; then
        extra+=(DEVELOPMENT_TEAM="$LOCALFLOW_DEVELOPMENT_TEAM" CODE_SIGN_IDENTITY="Apple Development")
    fi
    xcodebuild -project "$PROJECT" -scheme LocalFlow -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED" -skipPackagePluginValidation -skipMacroValidation \
        ${extra[@]+"${extra[@]}"} "$@"
}

save_lock_if_missing() {
    if [[ ! -f "$LOCKFILE" && -f "$PROJECT_LOCK" ]]; then
        cp "$PROJECT_LOCK" "$LOCKFILE"
        log "Created Config/Package.resolved — commit it so every build uses the same package versions."
    fi
}

action="${1:-debug}"
case "$action" in
    debug|release)
        config="Debug"; [[ "$action" == "release" ]] && config="Release"
        generate
        log "Building $config"
        xcb -configuration "$config" build
        save_lock_if_missing
        app="$DERIVED/Build/Products/$config/LocalFlow.app"
        [[ -d "$app" ]] || die "build reported success but $app is missing"
        log "Built: $app"
        log "Run it: open \"$app\""
        ;;
    test)
        generate
        log "Running tests"
        xcb -configuration Debug test
        save_lock_if_missing
        ;;
    project)
        generate
        log "Generated $PROJECT"
        ;;
    lock)
        generate
        rm -f "$PROJECT_LOCK"
        log "Resolving Swift packages"
        xcodebuild -project "$PROJECT" -scheme LocalFlow -derivedDataPath "$DERIVED" \
            -skipPackagePluginValidation -skipMacroValidation -resolvePackageDependencies
        cp "$PROJECT_LOCK" "$LOCKFILE"
        log "Updated Config/Package.resolved — review and commit the diff."
        ;;
    clean)
        log "Removing build/ and LocalFlow.xcodeproj"
        rm -rf "$ROOT/build" "$PROJECT"
        ;;
    -h|--help|help)
        sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        die "unknown action '$action' (expected: debug, release, test, project, lock, clean)"
        ;;
esac
