# LocalFlow

Fully local, offline macOS dictation for the menu bar. Hold a key, speak, and the text is
pasted at your cursor. [WhisperKit](https://github.com/argmaxinc/WhisperKit) turns speech
into text on-device. An optional local [Ollama](https://ollama.com) model removes filler
words, fixes punctuation, and handles voice commands. Audio and text never leave your Mac.
The only network use is the one-time model downloads.

## What LocalFlow does

- **Hold Right Option**, speak, release → your speech is transcribed, cleaned up, and
  pasted at the cursor.
- **Hold Right Shift** and speak a command ("open Safari"). Or select text first and say a
  rewrite instruction ("make this more formal"), and LocalFlow replaces the selection.
- The menu-bar item shows status, recent dictations, the setup checklist, and a custom
  vocabulary for names and jargon. The vocabulary biases both transcription and cleanup.

## System requirements

| | |
|---|---|
| macOS | 14 Sonoma or later |
| Mac | Apple Silicon recommended. Intel builds but hasn't been tested, and Whisper large-v3 is very slow there. |
| Memory | 16 GB recommended when using Ollama cleanup (Whisper ≈ 3 GB + qwen2.5:7b ≈ 5 GB). 8 GB works without Ollama. |
| Disk | ~3 GB for the speech model, plus ~4.7 GB for the optional cleanup model |
| Network | Only for the first-run model downloads |

## Installation — downloaded release

1. Download `LocalFlow-<version>.zip` from
   [Releases](https://github.com/kkeef11/localflow/releases). If you want to check the
   download, also get the `.sha256` file and run
   `shasum -a 256 -c LocalFlow-<version>.zip.sha256`. Safari unzips downloads and deletes
   the zip by default; to check it, download with another browser or turn off
   Safari → Settings → General → "Open 'safe' files after downloading".
2. Double-click the zip, then drag **LocalFlow.app** into **Applications**.
3. Open LocalFlow from Applications. macOS asks to confirm an app downloaded from the
   internet; click **Open**. Release builds are notarized by Apple.
4. LocalFlow runs in the menu bar (microphone icon), not the Dock. Its **Setup** window
   opens on first launch.

You don't need Xcode, Homebrew, or Terminal.

## First-run setup

The setup window lists what's missing. You can reopen it any time from the menu (**Setup…**).
Each row has one button for its next step, and rows turn green as you finish them.

| Item | Why | How |
|---|---|---|
| **Microphone** | To hear you | Click **Allow** in the system prompt |
| **Accessibility** | To paste at the cursor and read selected text | **Open Settings** → turn on LocalFlow |
| **Input Monitoring** | To detect the Right Option / Right Shift hotkeys | **Open Settings** → turn on LocalFlow, then click **Relaunch** if macOS asks |
| **Speech model** | Whisper large-v3 speech recognition | Click **Download (~3 GB)** — one time; progress shows in the window and status line |
| **Ollama** (optional) | Cleanup and voice commands | **Get Ollama** → install the app → **Start Ollama** → **Download** the model (several GB) |

What happens if a step is skipped:

- **Microphone off:** LocalFlow won't record, and it tells you why. It doesn't record
  silence.
- **Accessibility off:** your transcript is kept in the menu's history instead of pasted.
- **Ollama missing:** dictation still works and pastes the raw transcript.
- **Dictation waits for the speech model.** Until it has finished downloading and
  preparing, the hotkeys show a status message instead of recording.
- **Nothing downloads without a click.** The first time the speech model loads, it is also
  optimized for your Mac, which can take several minutes. Later launches are quick and
  fully offline.

## Installation — build from source

Needs Xcode 26 or later (Swift 6.2, required by the pinned Swift packages). The CI and
release builds use Xcode 26.6.

```bash
git clone https://github.com/kkeef11/localflow.git
cd localflow
scripts/setup-macos.sh        # checks/installs prerequisites, configures signing, builds
open build/DerivedData/Build/Products/Debug/LocalFlow.app
```

`setup-macos.sh` is safe to re-run. It checks macOS, Xcode (including the license and
first-launch setup), and Homebrew. It installs XcodeGen and, optionally, Ollama. It checks
the cleanup model and offers to download it (`--pull-model` downloads without asking). It
sets up code signing and builds the app. It asks before installing anything, never uses
`sudo`, and prints the exact command for any step you need to do yourself. Use `--yes` to
install tools without prompts, or `--no-build` to only check.

### Code signing for development

There's nothing to edit in tracked files.

- **No Apple account (default):** builds are ad-hoc signed. They work, but macOS treats
  every rebuild as a new app, so you must grant Accessibility and Input Monitoring again
  after each rebuild.
- **Grants that survive rebuilds:** in Xcode → Settings → Accounts, add any Apple ID (free
  is fine), then **Manage Certificates → + → Apple Development**. Re-run
  `scripts/setup-macos.sh`. It writes the git-ignored file
  `Config/Signing.local.xcconfig` with your team:
  ```
  DEVELOPMENT_TEAM = ABCDE12345
  CODE_SIGN_IDENTITY = Apple Development
  ```
  For a single build, you can set `LOCALFLOW_DEVELOPMENT_TEAM=ABCDE12345` instead.

## Development commands

```bash
scripts/build.sh            # Debug build → build/DerivedData/Build/Products/Debug/LocalFlow.app
scripts/build.sh test       # unit tests
scripts/build.sh release    # Release build (ad-hoc, or your team if Signing.local.xcconfig exists)
scripts/build.sh project    # just generate LocalFlow.xcodeproj, then: open LocalFlow.xcodeproj
scripts/build.sh lock       # update pinned Swift package versions (Config/Package.resolved)
scripts/build.sh clean      # delete build/ and the generated project
```

`LocalFlow.xcodeproj` is generated from `project.yml` by XcodeGen, so edit `project.yml`,
not the project. `Config/Package.resolved` pins WhisperKit's transitive dependencies. If
it's missing, the first build creates it, and you should commit it.

Debug logs: `log stream --predicate 'subsystem == "com.kkeefer.LocalFlow"' --level debug`

CI (`.github/workflows/ci.yml`) runs the tests and a Release build on every push and pull
request. Pushes to `main` also upload an **unsigned** test zip as a workflow artifact. That
zip isn't notarized, Gatekeeper blocks it on other Macs, and it isn't a release.

## Release process

Push a version tag such as `v0.2.0` after bumping `MARKETING_VERSION` in `project.yml`.
`.github/workflows/release.yml` then does the rest:

1. Builds the app and signs it with Developer ID.
2. Notarizes it and staples the ticket.
3. Verifies the result.
4. Attaches `LocalFlow-0.2.0.zip` and its `.sha256` to a draft GitHub Release.

This needs an Apple Developer Program membership and six repository secrets. See
**[docs/RELEASING.md](docs/RELEASING.md)**.

## Upgrading

Quit LocalFlow (menu → **Quit**), drag the new `LocalFlow.app` into Applications, and choose
**Replace**. Settings, your vocabulary, and downloaded models live outside the app, so they
are kept. Permissions carry over between releases signed by the same team.

If you switch from a self-built copy to a release (or the other way), macOS sees a
different signature, so you'll need to grant permissions once more. First remove the old
LocalFlow entries with **–** in each Privacy & Security list.

## Uninstalling

1. Quit LocalFlow and delete `/Applications/LocalFlow.app`.
2. Optional — delete settings and the downloaded speech model (~3 GB):
   ```bash
   rm -rf ~/Library/Application\ Support/LocalFlow
   ```
3. Optional — remove LocalFlow's permission entries:
   `tccutil reset All com.kkeefer.LocalFlow`
4. Optional — remove the cleanup model with `ollama rm qwen2.5:7b`. To remove Ollama
   itself, follow Ollama's own instructions.

Source builds from before the setup window existed stored the speech model in
`~/Documents/huggingface/models/argmaxinc/whisperkit-coreml`. Current builds don't look
there, so they download the model once more; afterwards you can delete that folder.

Nothing is deleted automatically — not on upgrade, and not on uninstall.

## Troubleshooting

- **Hotkeys do nothing.** Open **Setup…**. If *Input Monitoring* isn't green, turn
  LocalFlow on in System Settings → Privacy & Security → Input Monitoring, then click
  **Relaunch**. macOS often needs a restart before the app sees that permission.
- **Status says "Grant Accessibility (paste blocked)".** Your text is in the menu's
  history. Turn on Accessibility for LocalFlow, and the next dictation will paste.
- **Permissions vanish after every rebuild (source builds).** The build is ad-hoc signed.
  Set up an Apple Development certificate (see [Code signing](#code-signing-for-development)),
  then grant permissions one last time.
- **"Ollama not running (cleanup off)".** Start the Ollama app, or run
  `brew services start ollama` for a Homebrew install. Dictation still works without it
  and pastes the raw transcript.
- **"Cleanup skipped (…)" under the status.** Ollama returned an error, often because the
  model is still loading or the Mac is short on memory. The raw transcript was pasted.
  Check it with `ollama run qwen2.5:7b "hi"`.
- **Speech model download failed or was interrupted.** Click **Retry** in Setup. Downloads
  resume from where they stopped, and an already-downloaded model is reloaded from disk
  (no network needed). If loading keeps failing, the files may be damaged: click
  **Re-download** to delete and fetch them again (~3 GB).
- **"Preparing speech model…" takes a long time on first launch.** macOS is compiling the
  model for your Mac's Neural Engine. This happens once.
- **Build fails with "Entitlements file was modified during the build".** Run
  `scripts/build.sh clean && scripts/build.sh`.
- **Dictionary edits don't take effect.** Vocabulary is read at launch, so restart
  LocalFlow after editing it.

## Known limitations

- **No voice-activity detection.** Silence is sent to Whisper as-is, and Whisper can
  invent a short phrase (for example "Thank you.") from it. Hold the hotkey only while
  speaking, and press Cmd+Z if a stray phrase gets pasted.
- **Holding the other same-side modifier can hide a hotkey release.** For example, holding
  Left Shift while tapping Right Shift. If recording seems stuck, release every modifier
  key and tap the hotkey once.
- **Pasting borrows the clipboard.** Text is pasted with a synthetic Cmd+V. Plain-text
  clipboard contents are restored afterwards, but non-text items (such as images) are lost.
- **The default speech model is large and accurate.** Whisper large-v3 is the most
  accurate choice and is fast on Apple Silicon, but it needs ~3 GB of disk and memory. To
  trade accuracy for speed and size, set `"sttModel"` in
  `~/Library/Application Support/LocalFlow/settings.json` to another WhisperKit variant
  (for example `"small.en"`; not tested by the maintainers), then relaunch.
- **Revoking Input Monitoring while LocalFlow runs isn't detected.** The Setup row stays
  green until the next launch.
- **No auto-update.** Download new versions from Releases (see [Upgrading](#upgrading)).
