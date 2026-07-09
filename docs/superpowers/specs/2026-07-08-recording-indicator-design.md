# Recording Indicator Pill — Design Spec

**Date:** 2026-07-08
**Status:** Approved
**Feature:** Wispr Flow-style floating waveform pill showing recording/processing state.

## 1. Behavior

A floating pill appears at the **bottom-center of the active screen** (`NSScreen.main`,
just above the Dock) whenever a recording session is active, and disappears when the
pipeline finishes:

| Phase | Trigger | Visual |
|---|---|---|
| Listening | hotkey pressed (`beginRecording`) | Live waveform — vertical bars driven by actual mic RMS levels |
| Processing | hotkey released (`finishRecording`) | Pulsing dots, same tint, until pipeline completes |
| Done / Error | status returns to Idle or Error | Pill hides (errors surface in the menu bar as today) |

**Mode differentiation — variant per the reference design (`audio-pills-reference.html`), no icons:**
- Dictation (Right Option): light pill — white background, black 1.5pt border, black bars/dots
- Command (Right Shift): dark pill — black background, white 1.5pt border, white bars/dots
- Pill: 120×44pt, fully rounded; 7 bars (4pt wide, 5pt gap, staggered base heights
  20/28/16/24/14/26/18) scaling 30%→100% with live level; 3 dots, 8pt, 1.2s staggered pulse.
- (v1 purple/green tint superseded by user revision on 2026-07-09.)

## 2. Components

1. **`AudioRecorder` (modified)** — gains `var onLevel: (@Sendable (Float) -> Void)?`.
   Computes RMS per tap buffer (samples already in hand), normalized to 0–1,
   invoked from the audio thread. Nil callback = zero behavior change.
2. **`WaveformModel` (new, pure)** — `Sources/LocalFlow/UI/WaveformModel.swift`.
   Ring buffer of the most recent N levels (N = bar count, 20) → per-bar heights
   with a minimum floor so silent bars stay visible as dots. Unit-tested.
3. **`RecordingIndicatorController` (new, @MainActor)** —
   `Sources/LocalFlow/UI/RecordingIndicator.swift`. Owns a borderless,
   **non-activating** `NSPanel`: `.nonactivatingPanel` style, `.statusBar` level,
   transparent background, `ignoresMouseEvents = true`,
   `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`,
   `becomesKeyOnlyIfNeeded` — the panel must NEVER become key (would steal the
   paste target's focus). Hosts `IndicatorView` via `NSHostingView`.
   API: `show(mode: IndicatorMode)`, `updateLevel(Float)`, `beginProcessing()`, `hide()`.
4. **`IndicatorView` (new, SwiftUI)** — the pill: dark capsule background, 20 bars
   (rounded rects) animating from `WaveformModel` heights, or 3 pulsing dots in
   processing phase. Tint per mode.
5. **`RecordingIndicating` (new protocol, @MainActor)** — `show/updateLevel/
   beginProcessing/hide`; `DictationController` depends on the protocol with a
   default no-op so existing `DictationControllerTests` remain valid; tests can spy.
6. **`DictationController` (modified)** — `beginRecording`: `indicator.show(mode:)` +
   set `recorder.onLevel` → MainActor hop → `indicator.updateLevel`.
   `finishRecording`: `indicator.beginProcessing()`; on terminal status
   (Idle / Error) `indicator.hide()`.
7. **`LocalFlowApp` (modified)** — constructs the controller and injects it.

## 3. Constraints

- No focus theft: non-activating panel, ignores mouse. Pipeline behavior (paste
  target = frontmost app) is unchanged.
- Audio-thread safety: `onLevel` fires on the render thread; the indicator hop is
  `Task { @MainActor in ... }`.
- Colors exactly `#9D00FF` (dictation) and `#37de43` (command).
- No new permissions. No network. Existing 28 tests must stay green.

## 4. Testing

- `WaveformModelTests` (new): ring-buffer push/wrap, normalization clamp, minimum
  bar floor, reset on new session.
- `DictationControllerTests` (extended): spy indicator asserts show → processing →
  hide sequencing for both modes, including the error path.
- Panel visuals/positioning: manual verification by the user (both modes, both
  phases, multi-space).
