# LocalFlow

Fully-local, offline macOS dictation menu-bar app (a Wispr Flow clone). WhisperKit does
on-device speech-to-text; a local Ollama model cleans up the transcript, answers inline
formatting requests, and routes voice commands to app actions. No audio or text ever leaves
the machine.

## Setup (each Mac)

1. **Install dependencies**
   ```bash
   brew install xcodegen ollama
   ```
2. **Start Ollama and pull the cleanup model**
   ```bash
   brew services start ollama
   ollama pull qwen2.5:7b
   ```
3. **Clone the repo**
   ```bash
   git clone <repo> && cd localflow
   ```
4. **Configure code signing (recommended — see Troubleshooting below for why)**

   Without a signing identity, Xcode ad-hoc signs the app ("Sign to Run Locally"). This
   builds and runs fine, but macOS treats every rebuild as a new, untrusted binary, so
   Accessibility / Input Monitoring grants get silently revoked each time you rebuild.

   To fix this once per Mac:
   1. Xcode → Settings → Accounts → add your Apple ID.
   2. Manage Certificates → **+** → Apple Development.
   3. Find your 10-character Team ID: `security find-identity -v -p codesigning`.
   4. In `project.yml`, under `targets.LocalFlow.settings.base`, uncomment and fill in:
      ```yaml
      DEVELOPMENT_TEAM: YOUR_TEAM_ID
      CODE_SIGN_IDENTITY: "Apple Development"
      ```

   If you skip this step, the app still builds and runs — you'll just need to re-grant
   permissions after every rebuild (see Troubleshooting).
5. **Generate and build the Xcode project**
   ```bash
   xcodegen generate
   xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' build
   ```
6. **Launch the built app** (from `~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/LocalFlow.app`,
   or run it from Xcode) and grant **Microphone**, **Accessibility**, and **Input
   Monitoring** when prompted (System Settings → Privacy & Security).

## Use

- Hold **Right Option**, speak, release → your speech is transcribed, cleaned up, and
  pasted at the cursor.
- Hold **Right Shift**, speak a command (e.g. "open Safari") or first select some text and
  speak a rewrite instruction (e.g. "make this more formal") → LocalFlow routes it to an
  app action or replaces the selection with the rewritten text.
- Use the menu-bar item to edit your custom dictionary (proper nouns, jargon — biases both
  transcription and cleanup) and to see the current status (idle / recording /
  transcribing / error), shown as a colored dot plus text.

## Troubleshooting

- **Accessibility/Input Monitoring permission disappears after every rebuild.** Cause:
  the app is ad-hoc signed (no `DEVELOPMENT_TEAM` configured), so macOS sees each rebuild as
  a different, untrusted binary and drops the grant. Fix: complete the code-signing setup
  in step 4 above, then re-grant permissions one final time — they'll persist across
  rebuilds after that.
- **Menu bar status shows "Ollama not running (ollama serve)".** The health check couldn't
  reach `localhost:11434`. Run `brew services start ollama` (or `ollama serve` in a
  terminal) and confirm `ollama pull qwen2.5:7b` completed. Dictation still works and falls
  back to the raw, uncleaned transcript while Ollama is unreachable.
- **First run is slow / a large download happens.** WhisperKit downloads its speech model
  (~3 GB) on first launch. This is one-time and cached locally; subsequent launches are
  fast and fully offline.
- **Dictionary edits don't seem to take effect.** Custom dictionary entries are loaded when
  the transcription/cleanup pipeline is set up at launch. Restart LocalFlow after editing
  the dictionary for changes to apply.
