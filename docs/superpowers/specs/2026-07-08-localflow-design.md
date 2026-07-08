# LocalFlow — Design Spec

**Date:** 2026-07-08
**Status:** Approved, ready for implementation planning
**Author:** kkeefer

A fully-local, offline macOS clone of Wispr Flow: a native Swift/SwiftUI menu-bar
app that turns speech into clean, formatted, context-aware text and injects it at
the cursor in any app — with no network calls. Speech-to-text runs on WhisperKit
(CoreML / Apple Neural Engine); AI cleanup and command interpretation run on a
local LLM served by Ollama.

---

## 1. Goals & Non-Goals

### Goals
- A **working personal tool**, owned by the user (not a fork of another app).
- **Portable** across the user's two Apple Silicon Macs via a plain git repo.
- **Fully offline** — all inference on-device, no network dependency.
- Replicate Wispr Flow's four core capabilities: core dictation, AI cleanup,
  voice commands, context awareness.

### Non-Goals (v1)
- Cross-platform (Windows/Linux) or Intel Mac support. Both target machines are
  Apple Silicon; WhisperKit is Apple-Silicon-only and that is acceptable.
- Cloud fallback of any kind.
- App Store distribution / notarization. Local build-from-source per machine.
- Multi-language tuning beyond Whisper's built-in support.
- Open-ended shell/automation execution (see Action Registry safety note).

---

## 2. Target Environment

- **Primary machine:** Apple M4 Max, 36 GB RAM, macOS 26.0.
- **Secondary machine:** an Apple Silicon Mac (M1–M4).
- **Consequence:** hardware is not a constraint. The app can run Whisper
  **large-v3** for STT and a **7B** (or larger) cleanup model concurrently,
  near-real-time. No model-size compromises required.

### Model choices
- **STT:** WhisperKit `large-v3` (or `large-v3-turbo` if latency demands it),
  CoreML on the Neural Engine.
- **Cleanup / commands LLM:** Ollama `qwen2.5:7b` (strong instruction-following,
  tone preservation, ~5 GB). Swappable in settings.

---

## 3. Architecture

A native Swift/SwiftUI **menu-bar app** (`MenuBarExtra`, no main window)
orchestrating a two-mode pipeline.

```
        ┌─ Dictation hotkey ─┐         ┌─ Command hotkey ─┐
        ▼                    │         ▼                  │
  Audio capture ──► WhisperKit STT ──► raw text           │
  (AVAudioEngine,      (large-v3,          │              │
   16kHz mono,          CoreML/ANE)        │              │
   Silero VAD)                             ▼              ▼
                                    ┌──────────────┬──────────────┐
                                    │ Dictation:   │ Command:     │
                                    │ Ollama       │ intent →     │
                                    │ cleanup      │ rewrite sel. │
                                    │ (+ inline    │  OR app      │
                                    │  formatting) │  action      │
                                    └──────┬───────┴──────┬───────┘
                                           ▼              ▼
                                    Inject at cursor   Execute action
                                    (paste Cmd+V)      (rewrite / open app)
```

### Two hotkeys, two modes
- **Dictation mode** (default: hold Right Option): transcribe → LLM cleanup with
  inline formatting → paste at cursor.
- **Command mode** (default: hold Right Shift, or double-tap): transcribe →
  LLM intent-classify → either **rewrite the selected text** in place, or
  **run an app action** from a bounded registry.

### Tech stack
- Swift 6, SwiftUI `MenuBarExtra`
- WhisperKit (Swift Package Manager dependency)
- Ollama via local HTTP (`http://localhost:11434`)
- `CGEventTap` for global hotkeys
- Pasteboard + simulated Cmd+V (`CGEvent`) for text injection
- Accessibility API (`AXUIElement`) for reading the current selection
- Silero VAD for silence trimming

---

## 4. Components

Each component has one purpose, a defined interface, and is independently testable.

1. **HotkeyManager** — registers global hotkeys via `CGEventTap`; emits
   `.dictationStart/Stop` and `.commandStart/Stop` events. Depends on Input
   Monitoring permission.
2. **AudioRecorder** — `AVAudioEngine` tap on the input node; produces 16kHz mono
   Float32 buffers; applies Silero VAD to trim silence. Depends on Microphone
   permission.
3. **Transcriber** — wraps WhisperKit; audio buffer → raw text. Hidden behind a
   `TranscriberProtocol` so an alternative engine (e.g. whisper.cpp) could be
   substituted without touching callers.
4. **CleanupService** — Ollama HTTP client for dictation mode. Input: raw text +
   active-app context + custom dictionary. Output: cleaned, formatted text. Uses
   a few-shot system prompt (see §6).
5. **CommandRouter** — command mode only. Classifies transcribed intent as
   *rewrite* vs *action* and routes accordingly.
6. **ActionRegistry** — a bounded, explicit whitelist of app actions (open app,
   create reminder, copy, etc.). **Not** open-ended shell execution.
7. **TextInjector** — saves pasteboard → sets new text → simulates Cmd+V →
   restores pasteboard. For Command Mode rewrite, reads the current selection via
   the Accessibility API and replaces it. Depends on Accessibility permission.
8. **ContextProvider** — resolves the frontmost app's bundle ID and selects the
   prompt "Mode" (Slack / email / code / default).
9. **SettingsStore** — hotkey config, model choices, custom vocabulary, per-app
   prompt Modes, history. Persisted locally (JSON / `UserDefaults`).
10. **MenuBarUI** — status item, recording indicator, settings panel, dictation
    history.

---

## 5. Feature → Mechanism Map

| Feature | Mechanism |
|---|---|
| Core dictation | HotkeyManager → AudioRecorder → Transcriber → TextInjector |
| AI cleanup | CleanupService (Ollama `qwen2.5:7b`), few-shot prompt, strip fillers, punctuate, format |
| Inline formatting | Inside the cleanup prompt: "new paragraph", "new line", "bullet point", "scratch that" |
| Command Mode (rewrite) | CommandRouter → read selection (Accessibility) → Ollama rewrite → TextInjector replaces selection |
| App actions | CommandRouter → ActionRegistry (whitelisted actions only) |
| Context awareness | ContextProvider → active app bundle ID → swaps system prompt Mode |
| Custom vocabulary | Dictionary injected into both the WhisperKit decoding prompt and the cleanup prompt |

---

## 6. LLM Prompt Design (cleanup)

Critical rules drawn from the research:
- Tell the model the input **is dictation, not a command or question**, so it
  formats rather than answers.
- "Output only the cleaned transcript, with no preamble or explanation."
- On a spoken self-correction, keep only the corrected version.
- Remove filler words (um, uh, like), add punctuation, capitalize proper nouns,
  apply the custom dictionary, and honor inline formatting cues.
- Provide **~6 few-shot examples** to stop a 7B model from adding or
  hallucinating words during refinement.

The context Mode (from ContextProvider) is injected as an additional system-prompt
segment ("Target app: Slack — use a casual tone" / "Target app: Mail — use a
professional tone" / "Target app: code editor — terse, filler-free comments").

---

## 7. Data Flow — worked examples

**Dictation:** hold Right Option → speak "um so send the email to john new paragraph
tell him it's ready" → WhisperKit raw text → CleanupService (Mail context) →
`Send the email to John.\n\nTell him it's ready.` → paste at cursor.

**Command / rewrite:** select a paragraph → hold Right Shift → speak "make this more
formal" → CommandRouter classifies *rewrite* → read selection → Ollama rewrite →
TextInjector replaces selection.

**Command / action:** hold Right Shift → speak "open Safari" → CommandRouter
classifies *action* → ActionRegistry matches `open app` → launches Safari.

---

## 8. Permissions

The app requires three macOS permissions, requested with clear rationale on first
run:
- **Microphone** — audio capture.
- **Accessibility** — text injection (Cmd+V) and reading the current selection.
- **Input Monitoring** — system-wide hotkey detection via `CGEventTap`.

**Stability note:** unsigned ad-hoc builds lose Accessibility / Input Monitoring
permission on every rebuild. Mitigation: enable automatic code-signing with a free
personal Apple ID in Xcode so permissions persist across rebuilds and across both
Macs.

---

## 9. Error Handling

- **Ollama not running / model missing** — detect on startup and on first
  dictation; show a menu-bar warning with a one-line fix ("run `ollama serve` /
  `ollama pull qwen2.5:7b`"). Dictation degrades gracefully to raw STT output
  (paste uncleaned text) rather than failing silently.
- **WhisperKit model not downloaded** — download on first run with a progress
  indicator; block dictation until ready.
- **Permission denied** — menu-bar UI surfaces exactly which permission is missing
  and deep-links to the correct System Settings pane.
- **Empty / silence-only capture** — VAD yields no speech → no-op, brief indicator.
- **Pasteboard restore** — always restore prior pasteboard contents after
  injection, even on error paths.

---

## 10. Testing Strategy

- **Unit-testable in isolation:** CleanupService (prompt → expected transform,
  using recorded raw/clean pairs), CommandRouter (transcript → intent
  classification), ActionRegistry (phrase → action match), ContextProvider (bundle
  ID → Mode), TextInjector pasteboard save/restore logic.
- **Transcriber:** golden-audio → expected-text fixtures for a small set of clips.
- **Manual / integration:** end-to-end hotkey → cursor injection across a few real
  apps (Mail, Slack, a code editor), verified by observing actual pasted output.
- Follow test-driven development per phase where the unit has deterministic I/O
  (CleanupService, CommandRouter, ActionRegistry, ContextProvider).

---

## 11. Phased Build Plan

Each phase is independently usable; the user can stop at Phase 2 and have a genuine
Wispr Flow substitute.

| Phase | Ships | Verifiable outcome |
|---|---|---|
| **0 — Scaffold** | Xcode project, menu-bar app shell, WhisperKit SPM dep, Ollama installed, permission requests | App launches in menu bar; mic + accessibility granted |
| **1 — MVP dictation** | Dictation hotkey → STT → paste (no cleanup) | Hold key, speak, raw text appears at cursor |
| **2 — Flow** | Ollama cleanup + inline formatting | Filler removed; "new paragraph" works |
| **3 — Context** | ContextProvider + per-app Modes | Slack casual vs Mail formal |
| **4 — Commands** | Command hotkey; rewrite selection; ActionRegistry | Select → "make formal"; "open Safari" |
| **5 — Polish** | Custom dictionary, history, recording indicator, code-signing | Portable + stable permissions on both Macs |

---

## 12. Open Questions / Deferred

- Streaming (live partial transcription) vs. transcribe-on-release. v1 assumes
  transcribe-on-release for simplicity; streaming is a later enhancement.
- Exact default hotkeys are configurable; Right Option (dictation) and Right Shift
  (command) are defaults, not commitments.
- ActionRegistry's initial action set (open app, create reminder, copy, paste,
  press keystroke) to be finalized during Phase 4.
