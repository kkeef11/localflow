# LocalFlow

Fully local, offline macOS dictation for the menu bar. Hold a key, speak, and the text is
pasted at your cursor. [WhisperKit](https://github.com/argmaxinc/WhisperKit) turns speech
into text on-device. A local [Ollama](https://ollama.com) model removes filler words, fixes
punctuation, and handles voice commands. Audio and text never leave your Mac.
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
| Mac | Apple Silicon recommended. Intel builds but hasn't been tested, and Whisper is very slow there. |
| Memory | 8 GB works (LocalFlow picks compact models); 16 GB or more gets the full-size models. See [Models](#models). |
| Disk | ~2.5 GB for the models on an 8 GB Mac, ~7.7 GB on 16 GB or more |
| Other software | [Ollama](https://ollama.com/download) (free). The Setup window links to it. |
| Network | Only for the first-run model downloads |

## Installation — downloaded release

1. Download `LocalFlow-<version>.zip` from
   [Releases](https://github.com/kkeef11/localflow/releases). If you want to check the
   download, also get the `.sha256` file and run
   `shasum -a 256 -c LocalFlow-<version>.zip.sha256`. Safari unzips downloads and deletes
   the zip by default; to check it, download with another browser or turn off
   Safari → Settings → General → "Open 'safe' files after downloading".
2. Double-click the zip, then drag **LocalFlow.app** into **Applications**.
3. Open LocalFlow from Applications. Releases are signed but **not notarized by Apple**,
   so the first launch is blocked:
   1. macOS says it can't verify LocalFlow. Click **Done**, not "Move to Trash".
   2. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**
      next to LocalFlow. Confirm with your password.

   You do this once per version. Every release is signed with the same certificate, so
   your permissions carry over when you upgrade. If a release notes that it's notarized,
   it opens normally instead.
4. LocalFlow runs in the menu bar (microphone icon), not the Dock. Its **Setup** window
   opens on first launch.

You don't need Xcode, Homebrew, or Terminal. If you prefer Terminal to the Settings
steps, `xattr -dr com.apple.quarantine /Applications/LocalFlow.app` does the same. Only do
this for a download you trust.

## First-run setup

The setup window lists what's missing. You can reopen it any time from the menu (**Setup & Models…**).
Each row has one button for its next step, and rows turn green as you finish them.

| Item | Why | How |
|---|---|---|
| **Microphone** | To hear you | Click **Allow** in the system prompt |
| **Accessibility** | To paste at the cursor and read selected text | **Open Settings** → turn on LocalFlow |
| **Input Monitoring** | To detect the Right Option / Right Shift hotkeys | **Open Settings** → turn on LocalFlow, then click **Relaunch** if macOS asks |
| **Speech model** | On-device speech recognition | Click **Download** (size shown on the button) — one time; progress shows in the window and status line |
| **Ollama** | Cleanup and voice commands | **Get Ollama** → install the app → **Start Ollama** → **Download** the model (several GB) |

What happens if a step is skipped:

- **Microphone off:** LocalFlow won't record, and it tells you why. It doesn't record
  silence.
- **Accessibility off:** your transcript is kept in the menu's history instead of pasted.
- **Ollama stops responding later:** your dictation is still pasted, as the raw transcript,
  with a note under the status line.
- **Dictation waits for the speech model.** Until it has finished downloading and
  preparing, the hotkeys show a status message instead of recording.
- **Nothing downloads without a click.** The first time the speech model loads, it is also
  optimized for your Mac, which can take several minutes. Later launches are quick and
  fully offline.

## Models

LocalFlow needs two models in memory at once while you dictate, so it picks them by how much
memory your Mac has:

| | Mac with less than 12 GB (e.g. 8 GB) | Mac with 12 GB or more |
|---|---|---|
| Speech (Whisper) | `large-v3-v20240930_626MB`: large-v3 turbo, compressed. ~0.6 GB | `large-v3`. ~3 GB |
| Cleanup (Ollama) | `qwen2.5:3b`. ~1.9 GB | `qwen2.5:7b`. ~4.7 GB |
| Total in memory | ~2.6 GB | ~8 GB |

On an 8 GB M3, the full-size pair pushed the Mac into heavy swap: dictations took over a
minute and everything lagged. The compact pair takes a few seconds.

**Whisper large-v3 vs. large-v3 turbo (compressed)**
- large-v3 is the most accurate, especially for uncommon words, names, accents and noisy
  audio. But it's ~3 GB and slower, because it uses 32 decoder layers to produce each word.
- Turbo cuts the decoder to 4 layers, which makes it much faster, and the compressed
  version shrinks it to ~0.6 GB. Accuracy is close to large-v3 for everyday English
  dictation, but a little lower on rare words and difficult audio. Your custom vocabulary
  helps with names.

**qwen2.5:7b vs. qwen2.5:3b**
- 7b follows the cleanup rules more reliably: dropping "scratch that", formatting bullets,
  not answering questions you dictate. It's also better at rewrites and voice commands.
  The cost is ~4.7 GB of memory and slower responses.
- 3b handles punctuation, capitalization and filler-word removal well, at ~1.9 GB and
  roughly twice the speed. It's more likely to occasionally rephrase something or slip on
  a complex rewrite.

**Choosing a size.** Open the menu → **Setup & Models…**. Under **Model size**, pick:
- **Automatic** (the default): Compact or Full quality, based on your Mac's memory.
- **Compact** or **Full quality**: always that pair. Full quality shows a warning on Macs
  with less than 12 GB.

Then click **Relaunch**, and **Download** anything new in the same window. Models you
switch away from stay on disk until you delete them (see [Uninstalling](#uninstalling)).

**Advanced: other models.** Quit LocalFlow and set `sttModel` and/or `llmModel` in
`~/Library/Application Support/LocalFlow/settings.json`. For example:

```json
{"sttModel": "small.en", "llmModel": "llama3.2:3b"}
```

Any [WhisperKit model name](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main)
without the `openai_whisper-` prefix works, as does any Ollama model, but only the presets
are tested. Setup shows them as "custom models", and choosing a size there replaces them.

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
first-launch setup), and Homebrew. It installs XcodeGen and, if you agree, Ollama. It checks
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

1. Builds the app and signs it, with the free self-signed certificate or, if those
   secrets are set, with Developer ID plus notarization.
2. Verifies the result.
3. Attaches `LocalFlow-0.2.0.zip` and its `.sha256` to a draft GitHub Release.

The free route needs only two repository secrets, created by
`scripts/create-signing-cert.sh`. See **[docs/RELEASING.md](docs/RELEASING.md)**.

## Upgrading

Quit LocalFlow (menu → **Quit**), drag the new `LocalFlow.app` into Applications, and choose
**Replace**. Settings, your vocabulary, and downloaded models live outside the app, so they
are kept. Permissions carry over between releases signed with the same certificate.

If you switch from a self-built copy to a release (or the other way), macOS sees a
different signature, so you'll need to grant permissions once more. First remove the old
LocalFlow entries with **–** in each Privacy & Security list.

## Uninstalling

1. Quit LocalFlow and delete `/Applications/LocalFlow.app`.
2. Optional — delete settings and the downloaded speech models (0.6–3 GB each):
   ```bash
   rm -rf ~/Library/Application\ Support/LocalFlow
   ```
3. Optional — remove LocalFlow's permission entries:
   `tccutil reset All com.kkeefer.LocalFlow`
4. Optional — remove the cleanup model with `ollama rm qwen2.5:3b` (or `qwen2.5:7b`; `ollama list`
   shows which you have). To remove Ollama
   itself, follow Ollama's own instructions.

Source builds from before the setup window existed stored the speech model in
`~/Documents/huggingface/models/argmaxinc/whisperkit-coreml`. Current builds don't look
there, so they download the model once more; afterwards you can delete that folder.

Nothing is deleted automatically — not on upgrade, and not on uninstall.

## Troubleshooting

- **Hotkeys do nothing.** Open **Setup & Models…**. If *Input Monitoring* isn't green, turn
  LocalFlow on in System Settings → Privacy & Security → Input Monitoring, then click
  **Relaunch**. macOS often needs a restart before the app sees that permission.
- **Status says "Grant Accessibility (paste blocked)".** Your text is in the menu's
  history. Turn on Accessibility for LocalFlow, and the next dictation will paste.
- **Permissions vanish after every rebuild (source builds).** The build is ad-hoc signed.
  Set up an Apple Development certificate (see [Code signing](#code-signing-for-development)),
  then grant permissions one last time.
- **"Ollama not running".** Start the Ollama app (or click **Start Ollama** in Setup), or
  run `brew services start ollama` for a Homebrew install. Until it's running, dictations
  are pasted as the raw transcript.
- **"Cleanup skipped (…)" under the status.** Ollama returned an error, often because the
  model is still loading or the Mac is short on memory. The raw transcript was pasted.
  Check it with `ollama run qwen2.5:3b "hi"` (use your model's name from `ollama list`).
- **Speech model download failed or was interrupted.** Click **Retry** in Setup. Downloads
  resume from where they stopped, and an already-downloaded model is reloaded from disk
  (no network needed). If loading keeps failing, the files may be damaged: click
  **Re-download** to delete and fetch them again.
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
- **Revoking Input Monitoring while LocalFlow runs isn't detected.** The Setup row stays
  green until the next launch.
- **No auto-update.** Download new versions from Releases (see [Upgrading](#upgrading)).
