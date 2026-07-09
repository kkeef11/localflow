# Recording Indicator Pill — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Wispr Flow-style floating waveform pill that appears bottom-center while dictating/commanding, showing a live mic-driven waveform (purple for dictation, green for command mode), a processing phase after release, and hiding when the pipeline finishes.

**Architecture:** A pure `WaveformModel` (bar heights from mic levels, unit-tested) feeds an `IndicatorViewModel` (ObservableObject) rendered by a SwiftUI `IndicatorView` hosted in a borderless, non-activating `NSPanel` owned by `RecordingIndicatorController`. `AudioRecorder` emits per-buffer RMS via a new `onLevel` callback. `DictationController` drives the indicator lifecycle (show → level updates → processing → hide) behind a `RecordingIndicating` protocol with a no-op default, so existing tests are unaffected.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit (`NSPanel`, `NSHostingView`), XCTest.

## Global Constraints

- Platform: macOS 14.0+, Apple Silicon. Existing project conventions (XcodeGen, `xcodegen generate` after adding files).
- Colors EXACTLY: dictation `#9D00FF` = RGB(157, 0, 255); command `#37de43` = RGB(55, 222, 67).
- The panel MUST NOT become key/main or steal focus — the paste target is the frontmost app. Use `.nonactivatingPanel`, `ignoresMouseEvents = true`, `orderFrontRegardless()` (never `makeKeyAndOrderFront`).
- Audio-thread safety: `onLevel` fires on the render thread; every hop into the indicator/UI goes through `Task { @MainActor in ... }`.
- No new permissions, no network. All existing 28 tests must stay green; new tests add to that count.
- Work on a new branch off `main`: `feat/recording-indicator`.

---

## File Structure

```
Sources/LocalFlow/
  Audio/AudioRecording.swift        (modify: add onLevel to protocol)
  Audio/AudioRecorder.swift         (modify: RMS calc + onLevel emission)
  UI/WaveformModel.swift            (new: pure bar-height model)
  UI/RecordingIndicator.swift       (new: IndicatorMode, RecordingIndicating,
                                      NoopIndicator, IndicatorViewModel,
                                      RecordingIndicatorController)
  UI/IndicatorView.swift            (new: SwiftUI pill)
  Coordinator/DictationController.swift  (modify: drive the indicator)
  LocalFlowApp.swift                (modify: construct + inject the controller)
Tests/LocalFlowTests/
  WaveformModelTests.swift          (new)
  RecordingIndicatorTests.swift     (new: IndicatorMode colors)
  DictationControllerTests.swift    (modify: FakeRecorder.onLevel + spy indicator tests)
```

---

### Task 1: Branch + WaveformModel (pure, TDD)

**Files:**
- Create: `Sources/LocalFlow/UI/WaveformModel.swift`
- Test: `Tests/LocalFlowTests/WaveformModelTests.swift`

**Interfaces:**
- Produces: `struct WaveformModel { let barCount: Int; private(set) var bars: [CGFloat]; init(barCount: Int = 20); mutating func push(level: Float); mutating func reset() }`. Bar heights are in `0.0...1.0`; a silent level maps to a visible floor (`0.1`), full level to `1.0`, via gain `8.0`, all clamped. `push` scrolls: newest at the end, oldest dropped, length always `barCount`.

- [ ] **Step 1: Create the branch**

```bash
cd /Users/kevinkeefer/Documents/Personal/localflow
git checkout main && git checkout -b feat/recording-indicator
```

- [ ] **Step 2: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import LocalFlow

final class WaveformModelTests: XCTestCase {
    func test_starts_flat_at_floor() {
        let m = WaveformModel(barCount: 20)
        XCTAssertEqual(m.bars.count, 20)
        XCTAssertTrue(m.bars.allSatisfy { $0 == 0.1 })
    }
    func test_silent_push_maps_to_floor() {
        var m = WaveformModel(barCount: 4)
        m.push(level: 0)
        XCTAssertEqual(m.bars.last, 0.1)
    }
    func test_full_push_clamps_to_one() {
        var m = WaveformModel(barCount: 4)
        m.push(level: 1.0)
        XCTAssertEqual(m.bars.last, 1.0)
    }
    func test_mid_push_applies_gain() {
        var m = WaveformModel(barCount: 4)
        m.push(level: 0.05) // 0.05 * 8 = 0.4
        XCTAssertEqual(m.bars.last!, 0.4, accuracy: 0.0001)
    }
    func test_push_clamps_out_of_range() {
        var m = WaveformModel(barCount: 2)
        m.push(level: -1); XCTAssertEqual(m.bars.last, 0.1)
        m.push(level: 5);  XCTAssertEqual(m.bars.last, 1.0)
    }
    func test_push_scrolls_and_keeps_length() {
        var m = WaveformModel(barCount: 3)
        m.push(level: 1.0)          // [.1, .1, 1.0]
        m.push(level: 0)            // [.1, 1.0, .1]
        XCTAssertEqual(m.bars.count, 3)
        XCTAssertEqual(m.bars[1], 1.0)
        XCTAssertEqual(m.bars[2], 0.1)
    }
    func test_reset_returns_to_floor() {
        var m = WaveformModel(barCount: 3)
        m.push(level: 1.0)
        m.reset()
        XCTAssertTrue(m.bars.allSatisfy { $0 == 0.1 })
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test -only-testing:LocalFlowTests/WaveformModelTests 2>&1 | tail -8`
Expected: FAIL — "Cannot find 'WaveformModel' in scope".

- [ ] **Step 4: Write implementation**

```swift
import CoreGraphics

/// Fixed-length ring of recent mic levels mapped to bar heights (0...1) for the
/// waveform pill. Silent input maps to a visible floor so the pill never looks empty.
struct WaveformModel {
    static let floor: CGFloat = 0.1
    static let gain: CGFloat = 8.0

    let barCount: Int
    private(set) var bars: [CGFloat]

    init(barCount: Int = 20) {
        self.barCount = barCount
        self.bars = Array(repeating: Self.floor, count: barCount)
    }

    /// Appends a new level as the newest (rightmost) bar, dropping the oldest.
    mutating func push(level: Float) {
        let scaled = CGFloat(level) * Self.gain
        let height = min(1.0, max(Self.floor, scaled))
        bars.removeFirst()
        bars.append(height)
    }

    mutating func reset() {
        bars = Array(repeating: Self.floor, count: barCount)
    }
}
```

- [ ] **Step 5: Regenerate project, run tests to verify they pass**

Run: `xcodegen generate >/dev/null && xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test -only-testing:LocalFlowTests/WaveformModelTests 2>&1 | grep -E "Executed|TEST"`
Expected: PASS — 7 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/LocalFlow/UI/WaveformModel.swift Tests/LocalFlowTests/WaveformModelTests.swift
git commit -m "feat: add WaveformModel (pure bar-height mapping, TDD)"
```

---

### Task 2: Indicator seams — mode, protocol, no-op, level callback

**Files:**
- Create: `Sources/LocalFlow/UI/RecordingIndicator.swift` (mode + protocol + no-op only; controller added in Task 5)
- Modify: `Sources/LocalFlow/Audio/AudioRecording.swift`
- Test: `Tests/LocalFlowTests/RecordingIndicatorTests.swift`

**Interfaces:**
- Produces:
  - `enum IndicatorMode { case dictation, command; var barColor: Color }` — dictation `#9D00FF`, command `#37de43`.
  - `@MainActor protocol RecordingIndicating { func show(mode: IndicatorMode); func updateLevel(_ level: Float); func beginProcessing(); func hide() }`
  - `@MainActor final class NoopIndicator: RecordingIndicating` — all methods empty (default for tests / headless).
  - `AudioRecording` gains `var onLevel: (@Sendable (Float) -> Void)? { get set }`.

- [ ] **Step 1: Write the failing test (mode colors are the only pure-testable part)**

```swift
import XCTest
import SwiftUI
@testable import LocalFlow

final class RecordingIndicatorTests: XCTestCase {
    func test_mode_colors_are_distinct_and_correct() {
        // #9D00FF and #37de43 as resolved RGB.
        let purple = NSColor(IndicatorMode.dictation.barColor).usingColorSpace(.sRGB)!
        XCTAssertEqual(Double(purple.redComponent),   157.0/255.0, accuracy: 0.01)
        XCTAssertEqual(Double(purple.greenComponent),   0.0,        accuracy: 0.01)
        XCTAssertEqual(Double(purple.blueComponent),   255.0/255.0, accuracy: 0.01)

        let green = NSColor(IndicatorMode.command.barColor).usingColorSpace(.sRGB)!
        XCTAssertEqual(Double(green.redComponent),    55.0/255.0,  accuracy: 0.01)
        XCTAssertEqual(Double(green.greenComponent), 222.0/255.0,  accuracy: 0.01)
        XCTAssertEqual(Double(green.blueComponent),   67.0/255.0,  accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate >/dev/null; xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test -only-testing:LocalFlowTests/RecordingIndicatorTests 2>&1 | tail -8`
Expected: FAIL — "Cannot find 'IndicatorMode' in scope".

- [ ] **Step 3: Create `RecordingIndicator.swift` (mode + protocol + no-op)**

```swift
import SwiftUI

/// Which pipeline the pill is showing — drives its color.
enum IndicatorMode {
    case dictation
    case command

    /// Bar/dot tint. Dictation #9D00FF (purple), command #37de43 (green).
    var barColor: Color {
        switch self {
        case .dictation: return Color(red: 157/255, green: 0/255, blue: 255/255)
        case .command:   return Color(red: 55/255, green: 222/255, blue: 67/255)
        }
    }
}

/// Lifecycle the `DictationController` drives; implemented by the real panel
/// controller and by `NoopIndicator` (tests / when no UI is desired).
@MainActor
protocol RecordingIndicating {
    func show(mode: IndicatorMode)
    func updateLevel(_ level: Float)
    func beginProcessing()
    func hide()
}

/// Does nothing — the default so headless/test contexts need no panel.
@MainActor
final class NoopIndicator: RecordingIndicating {
    func show(mode: IndicatorMode) {}
    func updateLevel(_ level: Float) {}
    func beginProcessing() {}
    func hide() {}
}
```

- [ ] **Step 4: Add `onLevel` to the `AudioRecording` protocol**

Replace the body of `Sources/LocalFlow/Audio/AudioRecording.swift` with:
```swift
/// Minimal seam over `AudioRecorder` so `DictationController` can be exercised in tests
/// without touching real microphone hardware. `AudioRecorder` conforms to this; tests
/// substitute a fake that never starts an `AVAudioEngine`.
protocol AudioRecording: Sendable {
    func start() throws
    func stop() -> [Float]
    /// Called with a normalized RMS level (roughly 0...1) per captured buffer, from the
    /// audio thread. Set before `start()`, cleared after `stop()`. Consumers must hop to
    /// the main actor before touching UI.
    var onLevel: (@Sendable (Float) -> Void)? { get set }
}
```

- [ ] **Step 5: Run tests to verify color test passes and protocol compiles**

Run: `xcodegen generate >/dev/null && xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test -only-testing:LocalFlowTests/RecordingIndicatorTests 2>&1 | grep -E "Executed|TEST|error:"`
Expected: The color test PASSES, but the overall build will now FAIL to compile the app/other tests because `AudioRecorder` and `FakeRecorder` don't yet satisfy `onLevel`. That's expected — Tasks 3 and 4 fix the conformers. If the color test itself compiles and passes in isolation, proceed. (If the test target won't build at all due to `FakeRecorder`, temporarily proceed to Task 3+4 and run this test at the end of Task 4.)

- [ ] **Step 6: Commit**

```bash
git add Sources/LocalFlow/UI/RecordingIndicator.swift Sources/LocalFlow/Audio/AudioRecording.swift Tests/LocalFlowTests/RecordingIndicatorTests.swift
git commit -m "feat: add IndicatorMode, RecordingIndicating protocol, onLevel seam"
```

---

### Task 3: AudioRecorder RMS emission

**Files:**
- Modify: `Sources/LocalFlow/Audio/AudioRecorder.swift`

**Interfaces:**
- Consumes: `AudioRecording.onLevel`.
- Produces: `AudioRecorder` stores `onLevel` and calls it with per-buffer RMS.

- [ ] **Step 1: Add the stored property**

In `AudioRecorder` (after `targetFormat`, near line 31), add:
```swift
    /// Set on the main thread before `start()`, read on the audio thread in the tap.
    /// The class is already `@unchecked Sendable` and manages its own thread-safety
    /// contract; no recording is in flight when this is mutated.
    var onLevel: (@Sendable (Float) -> Void)?
```

- [ ] **Step 2: Emit RMS from the tap**

In the tap closure, after the existing `self.buffers.append(contentsOf: samples)` / unlock block (around line 66), add:
```swift
            if let onLevel = self.onLevel, !samples.isEmpty {
                var sumSquares: Float = 0
                for s in samples { sumSquares += s * s }
                let rms = (sumSquares / Float(samples.count)).squareRoot()
                onLevel(rms)
            }
```

- [ ] **Step 3: Build to confirm AudioRecorder conforms**

Run: `xcodegen generate >/dev/null && xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -5`
Expected: `** BUILD SUCCEEDED **` (the app target now conforms; the test target may still fail until Task 4 updates `FakeRecorder` — that's fine, this step only builds the app).

- [ ] **Step 4: Commit**

```bash
git add Sources/LocalFlow/Audio/AudioRecorder.swift
git commit -m "feat: AudioRecorder emits per-buffer RMS via onLevel"
```

---

### Task 4: DictationController drives the indicator (TDD with spy)

**Files:**
- Modify: `Sources/LocalFlow/Coordinator/DictationController.swift`
- Modify: `Tests/LocalFlowTests/DictationControllerTests.swift`

**Interfaces:**
- Consumes: `RecordingIndicating`, `IndicatorMode`, `AudioRecording.onLevel`.
- Produces: `DictationController.init` gains a trailing `indicator: RecordingIndicating = NoopIndicator()` parameter. Lifecycle: `beginRecording` → `indicator.show(mode:)` + wire `recorder.onLevel`; `finishRecording` → `indicator.beginProcessing()` after `stop()`; the async task hides the indicator on every exit path.

- [ ] **Step 1: Update the test fakes + add spy tests**

In `DictationControllerTests.swift`, first make `FakeRecorder` satisfy the new protocol member — replace the `FakeRecorder` struct with:
```swift
private final class FakeRecorder: AudioRecording, @unchecked Sendable {
    var onLevel: (@Sendable (Float) -> Void)?
    func start() throws {}
    func stop() -> [Float] { [] }
    /// Test helper: simulate the audio thread delivering a level.
    func emit(_ level: Float) { onLevel?(level) }
}
```

Add a spy indicator near the other fakes:
```swift
@MainActor
private final class SpyIndicator: RecordingIndicating {
    enum Event: Equatable { case show(IndicatorMode); case level(Float); case processing; case hide }
    private(set) var events: [Event] = []
    func show(mode: IndicatorMode) { events.append(.show(mode)) }
    func updateLevel(_ level: Float) { events.append(.level(level)) }
    func beginProcessing() { events.append(.processing) }
    func hide() { events.append(.hide) }
}
```
(For `Event` to be `Equatable`, add `extension IndicatorMode: Equatable {}` in the test file — the enum has no associated values so it is trivially equatable; declaring the conformance in-test avoids touching production code.)

Change `makeController` to accept and pass optional spy + recorder so the new tests can inspect them:
```swift
    private func makeController(
        transcript: String,
        cleanup: CleanupService?,
        state: AppState,
        injector: FakeInjector,
        indicator: RecordingIndicating = NoopIndicator(),
        recorder: FakeRecorder = FakeRecorder()
    ) -> DictationController {
        DictationController(
            recorder: recorder,
            transcriber: FakeTranscriber(transcript: transcript),
            cleanup: cleanup,
            injector: injector,
            state: state,
            contextProvider: ContextProvider(modes: [:]),
            router: CommandRouter(registry: ActionRegistry()),
            llm: FakeLLM(),
            indicator: indicator
        )
    }
```

Add two new tests:
```swift
    func test_dictation_shows_processing_then_hides() async throws {
        let state = AppState(); let injector = FakeInjector(); let spy = SpyIndicator()
        let cleanup = CleanupService(llm: FakeLLM(response: "cleaned"), dictionary: [])
        let controller = makeController(transcript: "raw", cleanup: cleanup,
                                        state: state, injector: injector, indicator: spy)
        controller.dictationHotkey(pressed: true)
        controller.dictationHotkey(pressed: false)
        try await waitForCompletion(state)
        XCTAssertEqual(spy.events.first, .show(.dictation))
        XCTAssertTrue(spy.events.contains(.processing))
        XCTAssertEqual(spy.events.last, .hide)
    }

    func test_command_shows_command_mode_and_hides() async throws {
        let state = AppState(); let injector = FakeInjector(); let spy = SpyIndicator()
        let controller = makeController(transcript: "open ZzNonexistentApp12345",
                                        cleanup: nil, state: state, injector: injector, indicator: spy)
        controller.commandHotkey(pressed: true)
        controller.commandHotkey(pressed: false)
        try await waitForCompletion(state)
        XCTAssertEqual(spy.events.first, .show(.command))
        XCTAssertEqual(spy.events.last, .hide)
    }

    func test_level_updates_forwarded_while_listening() async throws {
        let state = AppState(); let injector = FakeInjector(); let spy = SpyIndicator()
        let recorder = FakeRecorder()
        let controller = makeController(transcript: "raw", cleanup: nil,
                                        state: state, injector: injector,
                                        indicator: spy, recorder: recorder)
        controller.dictationHotkey(pressed: true)
        recorder.emit(0.5)  // simulate a mic buffer
        XCTAssertTrue(spy.events.contains(.level(0.5)))
        controller.dictationHotkey(pressed: false)
        try await waitForCompletion(state)
    }
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `xcodegen generate >/dev/null && xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test -only-testing:LocalFlowTests/DictationControllerTests 2>&1 | tail -12`
Expected: FAIL — `DictationController.init` has no `indicator:` parameter (compile error), confirming the production change is needed.

- [ ] **Step 3: Add the indicator to DictationController**

Add the stored property after `llm` (line 19):
```swift
    private let indicator: RecordingIndicating
```
Add the parameter to `init` (extend the signature, keep all existing params) — change the `init` line and add the assignment:
```swift
    init(recorder: AudioRecording, transcriber: Transcribing, cleanup: CleanupService? = nil,
         injector: TextInjecting, state: AppState,
         contextProvider: ContextProvider, router: CommandRouter, llm: LLMGenerating,
         indicator: RecordingIndicating = NoopIndicator()) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.cleanup = cleanup
        self.injector = injector
        self.state = state
        self.contextProvider = contextProvider
        self.router = router
        self.llm = llm
        self.indicator = indicator
    }
```

Update `beginRecording()` — show the pill and wire levels (note `recorder` must become mutable to set `onLevel`; change `private let recorder` to `private var recorder`):
```swift
    private func beginRecording() {
        guard !recording else { return }
        capturedTone = contextProvider.toneLabel(forBundleID: ContextProvider.frontmostBundleID())
        recording = true
        state.status = "Listening…"
        let mode: IndicatorMode = (self.mode == .command) ? .command : .dictation
        indicator.show(mode: mode)
        let indicator = self.indicator
        recorder.onLevel = { level in Task { @MainActor in indicator.updateLevel(level) } }
        try? recorder.start()
    }
```

Update `finishRecording()` — stop levels, enter processing, hide on every exit path via `defer`:
```swift
    private func finishRecording() {
        guard recording else { return }
        recording = false
        state.status = "Transcribing…"
        let samples = recorder.stop()
        recorder.onLevel = nil
        indicator.beginProcessing()
        Task { @MainActor in
            defer { indicator.hide() }
            do {
                let raw = try await transcriber.transcribe(samples: samples)
                if mode == .command {
                    state.status = "Command…"
                    await router.execute(router.decide(raw), llm: llm, injector: injector)
                    state.status = "Idle"
                    return
                }
                var text = raw
                if let cleanup {
                    state.status = "Cleaning…"
                    text = (try? await cleanup.clean(raw: text, toneLabel: capturedTone)) ?? text
                }
                guard !text.isEmpty else { state.status = "Idle"; return }
                injector.inject(text)
                state.record(text)
                state.status = "Idle"
            } catch {
                state.status = "Error: \(error.localizedDescription)"
            }
        }
    }
```

- [ ] **Step 4: Run the FULL suite to verify green**

Run: `xcodegen generate >/dev/null && xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test 2>&1 | grep -E "Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | tail -3`
Expected: PASS — 34 tests (28 prior + 7 WaveformModel + 1 color... note: prior count already includes some; accept any count ≥ previous with 0 failures and `** TEST SUCCEEDED **`). The three new DictationController tests and the color test must pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalFlow/Coordinator/DictationController.swift Tests/LocalFlowTests/DictationControllerTests.swift
git commit -m "feat: DictationController drives recording indicator (TDD)"
```

---

### Task 5: Panel controller + view (manual verification)

**Files:**
- Modify: `Sources/LocalFlow/UI/RecordingIndicator.swift` (add view-model + controller)
- Create: `Sources/LocalFlow/UI/IndicatorView.swift`

**Interfaces:**
- Consumes: `WaveformModel`, `IndicatorMode`, `RecordingIndicating`.
- Produces: `@MainActor final class IndicatorViewModel: ObservableObject`; `@MainActor final class RecordingIndicatorController: RecordingIndicating`.

- [ ] **Step 1: Add the view-model and controller to `RecordingIndicator.swift`**

Append to `RecordingIndicator.swift`:
```swift
import AppKit

/// Observable state the SwiftUI pill renders.
@MainActor
final class IndicatorViewModel: ObservableObject {
    enum Phase { case listening, processing }
    @Published var waveform = WaveformModel()
    @Published var phase: Phase = .listening
    @Published var mode: IndicatorMode = .dictation
}

/// Owns a borderless, non-activating panel that floats the waveform pill at the
/// bottom-center of the active screen. Never becomes key — must not steal the
/// paste target's focus.
@MainActor
final class RecordingIndicatorController: RecordingIndicating {
    private let viewModel = IndicatorViewModel()
    private var panel: NSPanel?

    func show(mode: IndicatorMode) {
        viewModel.mode = mode
        viewModel.phase = .listening
        viewModel.waveform.reset()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionPanel(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()   // shows WITHOUT activating the app
    }

    func updateLevel(_ level: Float) {
        guard viewModel.phase == .listening else { return }
        viewModel.waveform.push(level: level)
    }

    func beginProcessing() {
        viewModel.phase = .processing
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: IndicatorView(viewModel: viewModel))
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let frame = NSScreen.main?.visibleFrame else { return }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + 90
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
```

- [ ] **Step 2: Create `IndicatorView.swift`**

```swift
import SwiftUI

/// The floating pill: a dark capsule with animated waveform bars while listening,
/// or three pulsing dots while processing. Tinted by mode.
struct IndicatorView: View {
    @ObservedObject var viewModel: IndicatorViewModel

    var body: some View {
        ZStack {
            Capsule().fill(Color.black.opacity(0.82))
            content
                .padding(.horizontal, 20)
        }
        .frame(width: 260, height: 60)
    }

    @ViewBuilder private var content: some View {
        switch viewModel.phase {
        case .listening:
            HStack(spacing: 3) {
                ForEach(Array(viewModel.waveform.bars.enumerated()), id: \.offset) { _, h in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(viewModel.mode.barColor)
                        .frame(width: 3, height: max(4, h * 34))
                }
            }
            .animation(.easeOut(duration: 0.08), value: viewModel.waveform.bars)
        case .processing:
            ProcessingDots(color: viewModel.mode.barColor)
        }
    }
}

/// Three dots that pulse in sequence while the transcript is being processed.
private struct ProcessingDots: View {
    let color: Color
    @State private var t = 0.0
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .opacity(0.35 + 0.65 * abs(sin(t + Double(i) * 0.6)))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                t = .pi * 2
            }
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodegen generate >/dev/null && xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Sources/LocalFlow/UI/RecordingIndicator.swift Sources/LocalFlow/UI/IndicatorView.swift
git commit -m "feat: floating NSPanel waveform pill (view + controller)"
```

---

### Task 6: Wire the indicator into the app (manual verification)

**Files:**
- Modify: `Sources/LocalFlow/LocalFlowApp.swift`

**Interfaces:**
- Consumes: `RecordingIndicatorController`, `DictationController(indicator:)`.

- [ ] **Step 1: Construct and inject the controller**

In `LocalFlowApp.wire()`, after `let router = CommandRouter(registry: ActionRegistry())` (line 55), add:
```swift
        let indicator = RecordingIndicatorController()
```
Change the `DictationController(...)` construction (lines 56–58) to pass it as the trailing argument:
```swift
        let controller = DictationController(recorder: recorder, transcriber: transcriber, cleanup: cleanup,
                                             injector: injector, state: state,
                                             contextProvider: contextProvider, router: router, llm: llm,
                                             indicator: indicator)
```

- [ ] **Step 2: Build + full test suite**

Run: `xcodegen generate >/dev/null && xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test 2>&1 | grep -E "Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | tail -3`
Expected: `** TEST SUCCEEDED **`, 0 failures.

- [ ] **Step 3: Install signed build + manual verification**

```bash
pkill -x LocalFlow 2>/dev/null
APP=$(xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{d=$3}/ FULL_PRODUCT_NAME/{n=$3}END{print d"/"n}')
ditto "$APP" /Applications/LocalFlow.app && open /Applications/LocalFlow.app
```
Manual (user): hold **Right Option** → a **purple** waveform pill appears bottom-center and reacts to your voice → release → pill shows purple pulsing dots → text pastes → pill disappears. Then hold **Right Shift** → **green** pill. Confirm the pill never steals focus (the text still lands in the target app).

- [ ] **Step 4: Commit**

```bash
git add Sources/LocalFlow/LocalFlowApp.swift
git commit -m "feat: wire recording indicator into the app"
```

---

## Self-Review

**Spec coverage:**
- Bottom-center of active screen → Task 5 `positionPanel` (`NSScreen.main.visibleFrame`, midX, +90). ✓
- Live waveform from mic RMS → Task 3 (RMS) + Task 1 (mapping) + Task 5 (view). ✓
- Listening → processing → hide phases → Task 4 (`show`/`beginProcessing`/`defer hide`) + Task 5 (phase switch). ✓
- Purple #9D00FF / green #37de43, no icons → Task 2 (`IndicatorMode.barColor`) + Task 5 (bars/dots use `mode.barColor`), color-asserted test. ✓
- Non-activating, no focus theft → Task 5 (`.nonactivatingPanel`, `ignoresMouseEvents`, `orderFrontRegardless`). ✓
- Audio-thread safety → Task 4 (`Task { @MainActor in indicator.updateLevel }`). ✓
- No-op default keeps existing tests valid → Task 2/4 (`NoopIndicator`, defaulted param). ✓
- WaveformModel unit-tested; DictationController spy tests; manual panel verification → Tasks 1, 4, 6. ✓
- Existing tests stay green → Task 4 Step 4 full-suite run. ✓

**Placeholder scan:** No TBD/TODO; every code step contains complete code; commands have expected output.

**Type consistency:** `RecordingIndicating` methods (`show(mode:)`, `updateLevel(_:)`, `beginProcessing()`, `hide()`) identical across protocol (T2), NoopIndicator (T2), SpyIndicator (T4), controller (T5). `IndicatorMode` (`.dictation`/`.command`, `barColor`) consistent T2/T4/T5. `WaveformModel` (`bars`, `push(level:)`, `reset()`, `floor` 0.1, `gain` 8.0) consistent T1/T5. `AudioRecording.onLevel` signature `(@Sendable (Float) -> Void)?` identical in protocol (T2), AudioRecorder (T3), FakeRecorder (T4). `DictationController.init` trailing `indicator:` default matches call site (T6).
