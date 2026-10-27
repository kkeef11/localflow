#!/usr/bin/env bash
# One-time (and safe to re-run) developer setup for building LocalFlow from source.
#
#   scripts/setup-macos.sh             # interactive: asks before installing or downloading
#   scripts/setup-macos.sh --yes       # install missing dev tools (xcodegen, ollama) without asking
#   scripts/setup-macos.sh --pull-model  # also download the Ollama cleanup model (2–5 GB) without asking
#   scripts/setup-macos.sh --no-build  # check and configure only; skip the build
#
# Never uses sudo, never changes system settings, never deletes anything. When something
# needs an admin or GUI step, it prints the exact command for you to run.
# Exit codes: 0 = ready (warnings may be printed), 1 = a required prerequisite is missing,
#             2 = bad arguments, 3 = the build failed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIN_MACOS="14.0"        # project.yml deploymentTarget
MIN_XCODE="26.0"        # Swift 6.2: the pinned swift-collections/swift-crypto need tools 6.1+
PINNED_XCODEGEN="2.46.0" # what CI uses (.github/actions/setup-tools/action.yml)
# Same model choice as the app (Sources/LocalFlow/Settings/ModelDefaults.swift): the
# "Model size" preset from settings.json, where "automatic" picks by memory.
preset="$(plutil -extract modelPreset raw -o - "$HOME/Library/Application Support/LocalFlow/settings.json" 2>/dev/null || echo automatic)"
if [[ "$preset" == "compact" ]] || { [[ "$preset" != "full" ]] && (( $(sysctl -n hw.memsize) < 12 * 1073741824 )); }; then
    DEFAULT_LLM_MODEL="qwen2.5:3b";  DEFAULT_STT_MODEL="large-v3-v20240930_626MB"; LLM_SIZE="~1.9 GB"; STT_SIZE="~0.6 GB"
else
    DEFAULT_LLM_MODEL="qwen2.5:7b";  DEFAULT_STT_MODEL="large-v3";                 LLM_SIZE="~4.7 GB"; STT_SIZE="~3 GB"
fi
SETTINGS_JSON="$HOME/Library/Application Support/LocalFlow/settings.json"
SIGNING_LOCAL="$ROOT/Config/Signing.local.xcconfig"

ASSUME_YES=0; PULL_MODEL=0; DO_BUILD=1
for arg in "$@"; do
    case "$arg" in
        --yes|-y) ASSUME_YES=1 ;;
        --pull-model) PULL_MODEL=1 ;;
        --no-build) DO_BUILD=0 ;;
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

if [[ -t 1 ]]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'; else B=; G=; Y=; R=; N=; fi
ok()   { echo "  ${G}✓${N} $*"; }
warn() { echo "  ${Y}!${N} $*"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo "  ${R}✗${N} $*"; FAILURES=$((FAILURES + 1)); }
step() { echo; echo "${B}$*${N}"; }
hint() { echo "      $*"; }
WARNINGS=0; FAILURES=0

# ask "question" default(y|n) -> 0 for yes. Non-interactive runs take the default.
ask() {
    local prompt="$1" default="$2" reply
    if [[ ! -t 0 ]]; then [[ "$default" == "y" ]]; return; fi
    read -r -p "      $prompt [$( [[ "$default" == "y" ]] && echo "Y/n" || echo "y/N" )] " reply || reply=""
    reply="${reply:-$default}"
    [[ "$reply" =~ ^[Yy] ]]
}

# version_ge A B -> true if A >= B (numeric, dot-separated; bash 3.2 compatible).
version_ge() {
    local IFS=.
    local -a a=($1) b=($2)
    local i
    for ((i = 0; i < 3; i++)); do
        local x="${a[i]:-0}" y="${b[i]:-0}"
        x="${x//[^0-9]/}"; y="${y//[^0-9]/}"
        ((10#${x:-0} > 10#${y:-0})) && return 0
        ((10#${x:-0} < 10#${y:-0})) && return 1
    done
    return 0
}

# Reads a string key from the app's settings.json (if the app has run), else the default.
setting() {
    local key="$1" default="$2" value
    if [[ -f "$SETTINGS_JSON" ]] && value="$(plutil -extract "$key" raw -o - "$SETTINGS_JSON" 2>/dev/null)" && [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# ---------------------------------------------------------------------------------------
step "1. macOS"
[[ "$(uname -s)" == "Darwin" ]] || { echo "LocalFlow only builds on macOS."; exit 1; }
macos="$(sw_vers -productVersion)"
if version_ge "$macos" "$MIN_MACOS"; then ok "macOS $macos (minimum $MIN_MACOS)"; else fail "macOS $macos is older than the required $MIN_MACOS"; fi
arch="$(uname -m)"
if [[ "$arch" == "arm64" ]]; then
    ok "Apple Silicon ($arch)"
else
    warn "Intel Mac ($arch): builds, but on-device Whisper is very slow without the Neural Engine."
    hint "Consider a smaller speech model (see README → Known limitations)."
fi

# ---------------------------------------------------------------------------------------
step "2. Xcode"
XCODE_OK=0
dev_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "$dev_dir" ]]; then
    fail "No developer tools selected."
    hint "Install Xcode from the App Store, then: sudo xcode-select -s /Applications/Xcode.app"
elif [[ "$dev_dir" == *CommandLineTools* ]]; then
    fail "Only the Command Line Tools are selected ($dev_dir); building a macOS app needs full Xcode."
    hint "Install Xcode from the App Store, then: sudo xcode-select -s /Applications/Xcode.app"
elif ! xcode_version="$(xcodebuild -version 2>/dev/null | awk 'NR==1{print $2}')" || [[ -z "$xcode_version" ]]; then
    fail "xcodebuild did not run. The Xcode license may need accepting."
    hint "Run: sudo xcodebuild -license accept"
elif ! version_ge "$xcode_version" "$MIN_XCODE"; then
    fail "Xcode $xcode_version is older than the required $MIN_XCODE (Swift 6.2, needed by the pinned packages)."
else
    ok "Xcode $xcode_version ($dev_dir)"
    XCODE_OK=1
    if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
        fail "Xcode's first-launch setup hasn't run (or its license isn't accepted)."
        hint "Open Xcode once, or run: sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch"
        XCODE_OK=0
    fi
fi

# ---------------------------------------------------------------------------------------
step "3. Homebrew"
BREW=""
if command -v brew >/dev/null 2>&1; then BREW="$(command -v brew)"
elif [[ -x /opt/homebrew/bin/brew ]]; then BREW=/opt/homebrew/bin/brew
elif [[ -x /usr/local/bin/brew ]]; then BREW=/usr/local/bin/brew
fi
if [[ -n "$BREW" ]]; then
    ok "Homebrew ($BREW)"
    # Homebrew may be installed but not on PATH yet (shell profile not set up); make the
    # tools it installs visible to the rest of this script and to scripts/build.sh.
    PATH="$(dirname "$BREW"):$PATH"; export PATH
else
    warn "Homebrew not found — needed only to install xcodegen (and, if you like, ollama) below."
    hint "Install from https://brew.sh, or install xcodegen manually: https://github.com/yonaskolb/XcodeGen/releases"
fi

brew_install() { # brew_install formula description
    local formula="$1" what="$2"
    if [[ -z "$BREW" ]]; then fail "$what is missing and Homebrew isn't available to install it."; return 1; fi
    if [[ "$ASSUME_YES" -eq 1 ]] || ask "Install $what with 'brew install $formula'?" n; then
        "$BREW" install "$formula" && return 0
        fail "brew install $formula failed (see output above)."
        return 1
    fi
    fail "$what is required. Install it with: brew install $formula"
    return 1
}

# ---------------------------------------------------------------------------------------
step "4. XcodeGen"
if ! command -v xcodegen >/dev/null 2>&1; then brew_install xcodegen XcodeGen || true; fi
if command -v xcodegen >/dev/null 2>&1; then
    xg_version="$(xcodegen --version 2>/dev/null | awk '{print $NF}')"
    ok "XcodeGen $xg_version"
    [[ "$xg_version" == "$PINNED_XCODEGEN" ]] || hint "(CI uses $PINNED_XCODEGEN; other versions usually work but aren't what releases are built with.)"
elif [[ "$FAILURES" -eq 0 ]]; then
    fail "XcodeGen is still not on PATH. Add Homebrew to your shell: eval \"\$($BREW shellenv)\""
fi

# ---------------------------------------------------------------------------------------
step "5. Ollama (required by LocalFlow at runtime for cleanup; not needed to build)"
LLM_MODEL="$(setting llmModel "$DEFAULT_LLM_MODEL")"
OLLAMA_CLI=""
if command -v ollama >/dev/null 2>&1; then OLLAMA_CLI="$(command -v ollama)"
elif [[ -x /Applications/Ollama.app/Contents/Resources/ollama ]]; then OLLAMA_CLI=/Applications/Ollama.app/Contents/Resources/ollama
fi
if [[ -z "$OLLAMA_CLI" ]]; then
    warn "Ollama is not installed."
    if [[ -n "$BREW" ]] && { [[ "$ASSUME_YES" -eq 1 ]] || ask "Install it with 'brew install ollama'?" n; }; then
        "$BREW" install ollama && OLLAMA_CLI="$(command -v ollama || true)"
    else
        hint "Install the app from https://ollama.com/download (or: brew install ollama)."
    fi
fi
if [[ -n "$OLLAMA_CLI" ]]; then
    ok "Ollama CLI ($OLLAMA_CLI)"
    if curl -fsS --max-time 2 http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
        ok "Ollama server is running"
        # `ollama list` prints NAME as the first column; untagged names default to :latest.
        want="$LLM_MODEL"; [[ "$want" == *:* ]] || want="$want:latest"
        if "$OLLAMA_CLI" list 2>/dev/null | awk 'NR>1{print $1}' | grep -Fxq "$want"; then
            ok "Cleanup model $LLM_MODEL is installed"
        else
            warn "Cleanup model $LLM_MODEL is not downloaded."
            if [[ "$PULL_MODEL" -eq 1 ]] || ask "Download $LLM_MODEL now ($LLM_SIZE)?" n; then
                "$OLLAMA_CLI" pull "$LLM_MODEL" && ok "Downloaded $LLM_MODEL" || fail "ollama pull $LLM_MODEL failed."
            else
                hint "Later: ollama pull $LLM_MODEL   (or use the Download button in LocalFlow's menu)"
            fi
        fi
    else
        warn "Ollama is installed but its server isn't running, so the model can't be checked."
        hint "Start it with: open -a Ollama   (app install)  or  brew services start ollama  (Homebrew)"
        hint "Then re-run this script, or: ollama pull $LLM_MODEL"
    fi
fi

# ---------------------------------------------------------------------------------------
step "6. Speech model (Whisper)"
STT_MODEL="$(setting sttModel "$DEFAULT_STT_MODEL")"
if ls -d "$HOME/Library/Application Support/LocalFlow/Models/models/argmaxinc/whisperkit-coreml/"*"$STT_MODEL" >/dev/null 2>&1; then
    ok "Whisper $STT_MODEL is cached for LocalFlow"
else
    ok "Whisper $STT_MODEL is not downloaded yet: click Download in LocalFlow's Setup window ($STT_SIZE, one time)."
fi

# ---------------------------------------------------------------------------------------
step "7. Code signing"
if [[ -f "$SIGNING_LOCAL" ]]; then
    ok "Using $(basename "$SIGNING_LOCAL"): $(grep -E '^DEVELOPMENT_TEAM' "$SIGNING_LOCAL" | tr -s ' ' || echo 'custom settings')"
else
    identity="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/{print $2; exit}')"
    team=""
    if [[ -n "$identity" ]]; then
        # The Team ID is the certificate's OU, not the ID shown in parentheses.
        team="$(security find-certificate -c "$identity" -p 2>/dev/null \
            | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
            | awk -F'= ' '/organizationalUnitName/{print $2; exit}')"
    fi
    if [[ -n "$team" ]]; then
        printf '%s\n' "// Generated by scripts/setup-macos.sh from \"$identity\". Git-ignored; edit freely." \
            "DEVELOPMENT_TEAM = $team" "CODE_SIGN_IDENTITY = Apple Development" > "$SIGNING_LOCAL"
        ok "Signing with \"$identity\" (team $team) — wrote Config/Signing.local.xcconfig"
        hint "Permission grants will now survive rebuilds."
    else
        warn "No Apple Development certificate found — builds will be ad-hoc signed."
        hint "Works fine, but macOS forgets Accessibility/Input Monitoring grants after every rebuild."
        hint "Fix (free Apple ID is enough): Xcode → Settings → Accounts → add Apple ID →"
        hint "Manage Certificates → + → Apple Development. Then re-run this script."
    fi
fi

# ---------------------------------------------------------------------------------------
if [[ "$FAILURES" -gt 0 ]]; then
    step "Setup incomplete: $FAILURES required item(s) missing (see ✗ above). Fix them and re-run."
    exit 1
fi

if [[ "$DO_BUILD" -eq 1 ]]; then
    step "8. Build"
    if [[ "$XCODE_OK" -eq 1 ]] && "$ROOT/scripts/build.sh" debug; then
        ok "Build succeeded"
    else
        fail "Build failed — see the xcodebuild output above. Try: scripts/build.sh clean && scripts/build.sh"
        exit 3
    fi
fi

if [[ "$WARNINGS" -gt 0 ]]; then step "Done ($WARNINGS warning(s) above)"; else step "Done"; fi
echo "  Run:   open build/DerivedData/Build/Products/Debug/LocalFlow.app"
echo "  Test:  scripts/build.sh test"
echo "  On first launch, grant Microphone, Accessibility and Input Monitoring from LocalFlow's setup window."
