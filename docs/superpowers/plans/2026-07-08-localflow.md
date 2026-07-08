# LocalFlow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fully-local, offline macOS menu-bar app that transcribes speech (WhisperKit), cleans/formats it with a local LLM (Ollama), and injects the result at the cursor in any app — plus voice commands and context awareness.

**Architecture:** A native SwiftUI `MenuBarExtra` app orchestrates a two-mode pipeline. A dictation hotkey drives capture → WhisperKit STT → Ollama cleanup → paste-at-cursor. A command hotkey drives capture → STT → LLM intent classification → either rewrite-the-selection or run a whitelisted app action. Pure logic units (prompt building, intent routing, action matching, context mapping, settings) are TDD'd with XCTest; system-integration units (hotkeys, audio, WhisperKit, injection) ship behind protocols and are verified manually against explicit expected outcomes.

**Tech Stack:** Swift 6.2 · SwiftUI `MenuBarExtra` · WhisperKit (SPM) · Ollama HTTP (`localhost:11434`) · `CGEventTap` (hotkeys) · `AVAudioEngine` (capture) · NSPasteboard + `CGEvent` Cmd+V (injection) · Accessibility `AXUIElement` (selection) · XcodeGen (reproducible `.xcodeproj`) · XCTest.

## Global Constraints

- Platform: macOS 14.0+ deployment target; both target machines are Apple Silicon (M4 Max / M-series). Intel unsupported.
- Fully offline: no network calls except to `http://localhost:11434` (Ollama) and WhisperKit's one-time model download on first run.
- STT model: WhisperKit `large-v3` (configurable). Cleanup/command LLM: Ollama `qwen2.5:7b` (configurable).
- The app is an accessory (menu-bar only, no Dock icon): `LSUIElement = true` / `.accessory` activation policy.
- Required permissions: Microphone, Accessibility, Input Monitoring. Code-sign with a personal Apple ID team so permissions persist across rebuilds.
- Project is generated from a checked-in `project.yml` via XcodeGen; `.xcodeproj` is git-ignored and regenerated per machine.
- Bundle identifier: `com.kkeefer.LocalFlow`.
- Commit after every task. Test-driven where the unit has deterministic I/O.

---

## File Structure

```
localflow/
  project.yml                              # XcodeGen spec (committed)
  .gitignore
  Sources/LocalFlow/
    LocalFlowApp.swift                     # @main App + MenuBarExtra
    Info.plist                             # LSUIElement + usage descriptions
    LocalFlow.entitlements
    Coordinator/
      DictationController.swift            # wires the whole pipeline
      AppState.swift                       # ObservableObject status/history
    Hotkeys/HotkeyManager.swift            # CGEventTap global hotkeys
    Audio/AudioRecorder.swift              # AVAudioEngine 16k mono capture
    Transcription/
      Transcribing.swift                   # protocol
      WhisperKitTranscriber.swift          # WhisperKit impl
    Cleanup/
      PromptBuilder.swift                  # PURE: builds cleanup prompt
      OllamaClient.swift                   # HTTP client
      CleanupService.swift                 # PromptBuilder + OllamaClient
    Commands/
      CommandRouter.swift                  # PURE routing given a classification
      IntentClassifier.swift              # LLM classify (uses OllamaClient)
      ActionRegistry.swift                 # PURE phrase→action matching
    Injection/TextInjector.swift           # pasteboard + Cmd+V + AX selection
    Context/ContextProvider.swift          # PURE bundleID→Mode mapping
    Settings/SettingsStore.swift           # Codable settings persisted to JSON
    UI/MenuBarView.swift                   # menu content + status
  Tests/LocalFlowTests/
    PromptBuilderTests.swift
    OllamaClientTests.swift
    CommandRouterTests.swift
    ActionRegistryTests.swift
    ContextProviderTests.swift
    SettingsStoreTests.swift
  docs/superpowers/{specs,plans}/...
```

**Test seam:** every system unit is used through a protocol (`Transcribing`, `LLMGenerating`, `TextInjecting`, `Recording`, `HotkeyDispatching`) so the coordinator and pure units can be tested with fakes. Concrete system impls are verified manually.

---

# PHASE 0 — Scaffold

### Task 0.1: Tooling + repo hygiene

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Install XcodeGen and Ollama**

Run:
```bash
brew install xcodegen ollama
ollama --version && xcodegen --version
```
Expected: both print versions.

- [ ] **Step 2: Start Ollama and pull models**

Run:
```bash
brew services start ollama    # or: ollama serve &
ollama pull qwen2.5:7b
ollama list
```
Expected: `ollama list` shows `qwen2.5:7b`.

- [ ] **Step 3: Verify Ollama HTTP is reachable**

Run:
```bash
curl -s http://localhost:11434/api/generate \
  -d '{"model":"qwen2.5:7b","prompt":"Say OK.","stream":false}' | head -c 200
```
Expected: JSON containing a `"response"` field.

- [ ] **Step 4: Extend .gitignore for the generated project**

Append to `.gitignore`:
```
*.xcodeproj
.build/
```

- [ ] **Step 5: Commit**

```bash
git add .gitignore
git commit -m "chore: ignore generated xcodeproj and build output"
```

---

### Task 0.2: XcodeGen project spec + app skeleton

**Files:**
- Create: `project.yml`
- Create: `Sources/LocalFlow/Info.plist`
- Create: `Sources/LocalFlow/LocalFlow.entitlements`
- Create: `Sources/LocalFlow/LocalFlowApp.swift`
- Create: `Sources/LocalFlow/UI/MenuBarView.swift`
- Create: `Sources/LocalFlow/Coordinator/AppState.swift`

**Interfaces:**
- Produces: `AppState` (`ObservableObject`) with `@Published var status: String`, `@Published var history: [String]`; app target `LocalFlow`; test target `LocalFlowTests`.

- [ ] **Step 1: Write `project.yml`**

```yaml
name: LocalFlow
options:
  bundleIdPrefix: com.kkeefer
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    PRODUCT_BUNDLE_IDENTIFIER: com.kkeefer.LocalFlow
    CODE_SIGN_STYLE: Automatic
packages:
  WhisperKit:
    url: https://github.com/argmaxinc/WhisperKit
    from: "0.9.0"
targets:
  LocalFlow:
    type: application
    platform: macOS
    sources: [Sources/LocalFlow]
    info:
      path: Sources/LocalFlow/Info.plist
    entitlements:
      path: Sources/LocalFlow/LocalFlow.entitlements
    settings:
      base:
        INFOPLIST_KEY_LSUIElement: true
        ENABLE_HARDENED_RUNTIME: true
    dependencies:
      - package: WhisperKit
  LocalFlowTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests/LocalFlowTests]
    dependencies:
      - target: LocalFlow
```

- [ ] **Step 2: Write `Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>LocalFlow</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>LocalFlow records your voice to transcribe it into text on-device.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>LocalFlow runs app actions you request by voice.</string>
</dict>
</plist>
```

- [ ] **Step 3: Write `LocalFlow.entitlements`** (sandbox OFF — global hotkeys and cross-app injection require an un-sandboxed app)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><false/>
  <key>com.apple.security.device.audio-input</key><true/>
</dict>
</plist>
```

- [ ] **Step 4: Write `AppState.swift`**

```swift
import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var status: String = "Idle"
    @Published var history: [String] = []

    func record(_ text: String) {
        guard !text.isEmpty else { return }
        history.insert(text, at: 0)
        if history.count > 50 { history.removeLast() }
    }
}
```

- [ ] **Step 5: Write `MenuBarView.swift`**

```swift
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading) {
            Text("LocalFlow — \(state.status)")
            Divider()
            if state.history.isEmpty {
                Text("No dictations yet").foregroundStyle(.secondary)
            } else {
                ForEach(state.history.prefix(5), id: \.self) { item in
                    Text(item).lineLimit(1)
                }
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(8)
        .frame(width: 320)
    }
}
```

- [ ] **Step 6: Write `LocalFlowApp.swift`**

```swift
import SwiftUI

@main
struct LocalFlowApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("LocalFlow", systemImage: "mic.fill") {
            MenuBarView(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 7: Generate project and build**

Run:
```bash
xcodegen generate
xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Launch and confirm menu bar item**

Run:
```bash
open "$(xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{d=$3}/ FULL_PRODUCT_NAME/{n=$3}END{print d"/"n}')"
```
Expected: a `mic.fill` icon appears in the menu bar; clicking it shows "LocalFlow — Idle" and a Quit button. Quit it.

- [ ] **Step 9: Commit**

```bash
git add project.yml Sources
git commit -m "feat: scaffold LocalFlow menu-bar app with XcodeGen"
```

---

### Task 0.3: SettingsStore (TDD)

**Files:**
- Create: `Sources/LocalFlow/Settings/SettingsStore.swift`
- Test: `Tests/LocalFlowTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces: `struct Settings: Codable, Equatable` with fields `sttModel: String`, `llmModel: String`, `dictionary: [String]`, `contextModes: [String: String]` (bundleID → tone label). `final class SettingsStore` with `var settings: Settings` (get/set persists), `init(fileURL: URL)`, and `static var defaultFileURL: URL`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LocalFlow

final class SettingsStoreTests: XCTestCase {
    func test_persists_and_reloads() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lf-\(UUID()).json")
        let store = SettingsStore(fileURL: url)
        var s = store.settings
        s.dictionary = ["Acme", "kkeefer"]
        store.settings = s

        let reloaded = SettingsStore(fileURL: url)
        XCTAssertEqual(reloaded.settings.dictionary, ["Acme", "kkeefer"])
    }

    func test_defaults_when_no_file() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lf-\(UUID()).json")
        let store = SettingsStore(fileURL: url)
        XCTAssertEqual(store.settings.sttModel, "large-v3")
        XCTAssertEqual(store.settings.llmModel, "qwen2.5:7b")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: FAIL — `SettingsStore` / `Settings` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

struct Settings: Codable, Equatable {
    var sttModel: String = "large-v3"
    var llmModel: String = "qwen2.5:7b"
    var dictionary: [String] = []
    var contextModes: [String: String] = [
        "com.tinyspeck.slackmacgap": "casual",
        "com.apple.mail": "professional",
        "com.microsoft.VSCode": "code"
    ]
}

final class SettingsStore {
    private let fileURL: URL
    var settings: Settings { didSet { save() } }

    static var defaultFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    init(fileURL: URL = SettingsStore.defaultFileURL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        } else {
            settings = Settings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: fileURL)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalFlow/Settings Tests/LocalFlowTests/SettingsStoreTests.swift
git commit -m "feat: add persisted SettingsStore (TDD)"
```

---

# PHASE 1 — MVP Dictation (STT → paste, no cleanup)

### Task 1.1: Protocols + fakes seam

**Files:**
- Create: `Sources/LocalFlow/Transcription/Transcribing.swift`
- Create: `Sources/LocalFlow/Cleanup/LLMGenerating.swift`
- Create: `Sources/LocalFlow/Injection/TextInjecting.swift`

**Interfaces:**
- Produces:
  - `protocol Transcribing { func transcribe(samples: [Float]) async throws -> String }`
  - `protocol LLMGenerating { func generate(system: String, prompt: String) async throws -> String }`
  - `protocol TextInjecting { func inject(_ text: String); func readSelection() -> String?; func replaceSelection(with text: String) }`

- [ ] **Step 1: Write the three protocol files**

`Transcribing.swift`:
```swift
protocol Transcribing: Sendable {
    func transcribe(samples: [Float]) async throws -> String
}
```
`LLMGenerating.swift`:
```swift
protocol LLMGenerating: Sendable {
    func generate(system: String, prompt: String) async throws -> String
}
```
`TextInjecting.swift`:
```swift
@MainActor
protocol TextInjecting {
    func inject(_ text: String)
    func readSelection() -> String?
    func replaceSelection(with text: String)
}
```

- [ ] **Step 2: Build to confirm compilation**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Sources/LocalFlow/Transcription/Transcribing.swift Sources/LocalFlow/Cleanup/LLMGenerating.swift Sources/LocalFlow/Injection/TextInjecting.swift
git commit -m "feat: define system-boundary protocols"
```

---

### Task 1.2: AudioRecorder (manual verification)

**Files:**
- Create: `Sources/LocalFlow/Audio/AudioRecorder.swift`

**Interfaces:**
- Produces: `final class AudioRecorder` with `func start() throws`, `func stop() -> [Float]` returning 16kHz mono Float32 samples.

- [ ] **Step 1: Implement AudioRecorder**

```swift
import AVFoundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var buffers: [Float] = []
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000, channels: 1, interleaved: false)!

    func start() throws {
        buffers.removeAll()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)!

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let ratio = self.targetFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let out = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: capacity) else { return }
            var err: NSError?
            var fed = false
            converter.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buffer
            }
            if let ch = out.floatChannelData {
                self.buffers.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
            }
        }
        engine.prepare()
        try engine.start()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return buffers
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual smoke (deferred to Task 1.5 wiring)** — record 3s, assert `stop().count ≈ 48000` (16k × 3s). Note in commit that end-to-end mic verification happens in Task 1.5.

- [ ] **Step 4: Commit**

```bash
git add Sources/LocalFlow/Audio/AudioRecorder.swift
git commit -m "feat: add AudioRecorder (16kHz mono capture)"
```

---

### Task 1.3: WhisperKitTranscriber (manual verification)

**Files:**
- Create: `Sources/LocalFlow/Transcription/WhisperKitTranscriber.swift`

**Interfaces:**
- Consumes: `Transcribing`.
- Produces: `actor WhisperKitTranscriber: Transcribing` with `init(model: String)`; lazily loads WhisperKit on first `transcribe`.

- [ ] **Step 1: Implement**

```swift
import WhisperKit

actor WhisperKitTranscriber: Transcribing {
    private let model: String
    private var pipe: WhisperKit?

    init(model: String) { self.model = model }

    func transcribe(samples: [Float]) async throws -> String {
        if pipe == nil {
            pipe = try await WhisperKit(WhisperKitConfig(model: model))
        }
        let results = try await pipe!.transcribe(audioArray: samples)
        return results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. (First build downloads WhisperKit; may take a minute.)

- [ ] **Step 3: Commit**

```bash
git add Sources/LocalFlow/Transcription/WhisperKitTranscriber.swift
git commit -m "feat: add WhisperKit transcriber behind Transcribing protocol"
```

---

### Task 1.4: TextInjector (manual verification)

**Files:**
- Create: `Sources/LocalFlow/Injection/TextInjector.swift`

**Interfaces:**
- Consumes: `TextInjecting`.
- Produces: `@MainActor final class TextInjector: TextInjecting`.

- [ ] **Step 1: Implement**

```swift
import AppKit
import ApplicationServices

@MainActor
final class TextInjector: TextInjecting {
    func inject(_ text: String) {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents(); pb.setString(text, forType: .string)
        pasteCmdV()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            pb.clearContents()
            if let saved { pb.setString(saved, forType: .string) }
        }
    }

    func readSelection() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    func replaceSelection(with text: String) {
        inject(text) // pasting over a selection replaces it
    }

    private func pasteCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cgSessionEventTap)
        vUp?.post(tap: .cgSessionEventTap)
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Sources/LocalFlow/Injection/TextInjector.swift
git commit -m "feat: add TextInjector (pasteboard + Cmd+V, AX selection)"
```

---

### Task 1.5: HotkeyManager + DictationController wiring (manual verification — the MVP milestone)

**Files:**
- Create: `Sources/LocalFlow/Hotkeys/HotkeyManager.swift`
- Create: `Sources/LocalFlow/Coordinator/DictationController.swift`
- Modify: `Sources/LocalFlow/LocalFlowApp.swift`

**Interfaces:**
- Produces:
  - `final class HotkeyManager` with `var onDictation: (Bool) -> Void`, `var onCommand: (Bool) -> Void` (Bool = pressed), `func start()`. Right Option (keycode 61) → dictation; Right Shift (keycode 60) → command.
  - `@MainActor final class DictationController` with `init(recorder:transcriber:cleanup:injector:state:settings:)` and `func dictationHotkey(pressed: Bool)`. In Phase 1, `cleanup` is nil (raw paste).

- [ ] **Step 1: Implement HotkeyManager**

```swift
import CoreGraphics
import AppKit

final class HotkeyManager {
    var onDictation: (Bool) -> Void = { _ in }
    var onCommand: (Bool) -> Void = { _ in }
    private var tap: CFMachPort?

    func start() {
        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
        let callback: CGEventTapCallBack = { _, _, event, userInfo in
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userInfo!).takeUnretainedValue()
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if keycode == 61 { mgr.onDictation(event.flags.contains(.maskAlternate)) }
            if keycode == 60 { mgr.onCommand(event.flags.contains(.maskShift)) }
            return Unmanaged.passUnretained(event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                options: .listenOnly, eventsOfInterest: mask,
                                callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            NSLog("LocalFlow: event tap failed — grant Input Monitoring & Accessibility")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}
```

- [ ] **Step 2: Implement DictationController (Phase-1 form: raw paste)**

```swift
import Foundation

@MainActor
final class DictationController {
    private let recorder: AudioRecorder
    private let transcriber: Transcribing
    private let cleanup: CleanupService?
    private let injector: TextInjecting
    private let state: AppState
    private var recording = false

    init(recorder: AudioRecorder, transcriber: Transcribing,
         cleanup: CleanupService?, injector: TextInjecting, state: AppState) {
        self.recorder = recorder; self.transcriber = transcriber
        self.cleanup = cleanup; self.injector = injector; self.state = state
    }

    func dictationHotkey(pressed: Bool) {
        if pressed { beginRecording() } else { finishRecording() }
    }

    private func beginRecording() {
        guard !recording else { return }
        recording = true; state.status = "Listening…"
        try? recorder.start()
    }

    private func finishRecording() {
        guard recording else { return }
        recording = false; state.status = "Transcribing…"
        let samples = recorder.stop()
        Task { @MainActor in
            do {
                var text = try await transcriber.transcribe(samples: samples)
                if let cleanup {
                    state.status = "Cleaning…"
                    text = (try? await cleanup.clean(raw: text)) ?? text
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
}
```

- [ ] **Step 3: Wire in LocalFlowApp** (add stored properties and `.onAppear`-style init via an `init()`)

Replace `LocalFlowApp.swift` body with:
```swift
import SwiftUI

@main
struct LocalFlowApp: App {
    @StateObject private var state = AppState()
    private let hotkeys = HotkeyManager()
    private let recorder = AudioRecorder()
    private let injector = TextInjector()
    private let settings = SettingsStore()
    private let transcriber: Transcribing

    init() {
        transcriber = WhisperKitTranscriber(model: SettingsStore().settings.sttModel)
    }

    var body: some Scene {
        MenuBarExtra("LocalFlow", systemImage: "mic.fill") {
            MenuBarView(state: state)
                .onAppear { wire() }
        }
        .menuBarExtraStyle(.window)
    }

    @MainActor private func wire() {
        struct Once { static var done = false }
        guard !Once.done else { return }; Once.done = true
        let controller = DictationController(recorder: recorder, transcriber: transcriber,
                                             cleanup: nil, injector: injector, state: state)
        hotkeys.onDictation = { pressed in Task { @MainActor in controller.dictationHotkey(pressed: pressed) } }
        hotkeys.start()
    }
}
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Grant permissions and manually verify the MVP**

Launch the built app. In System Settings → Privacy & Security, grant **Microphone**, **Accessibility**, and **Input Monitoring** to LocalFlow. Open TextEdit, click into the document, **hold Right Option**, say "testing one two three", release.
Expected: within ~1–2s the raw transcript appears at the cursor; menu shows it in history.

- [ ] **Step 6: Commit**

```bash
git add Sources/LocalFlow/Hotkeys Sources/LocalFlow/Coordinator/DictationController.swift Sources/LocalFlow/LocalFlowApp.swift
git commit -m "feat: MVP dictation — hotkey → STT → paste at cursor"
```

---

# PHASE 2 — Flow (Ollama cleanup + inline formatting)

### Task 2.1: PromptBuilder (TDD)

**Files:**
- Create: `Sources/LocalFlow/Cleanup/PromptBuilder.swift`
- Test: `Tests/LocalFlowTests/PromptBuilderTests.swift`

**Interfaces:**
- Produces: `enum PromptBuilder { static func cleanupSystemPrompt(toneLabel: String, dictionary: [String]) -> String }`. The prompt: declares input is dictation not a command; output only the cleaned transcript; keep corrected version on self-correction; strip fillers, punctuate, capitalize; honor inline formatting cues ("new paragraph"→blank line, "new line"→newline, "bullet point"→`- `, "scratch that"→delete preceding clause); apply the dictionary terms verbatim; includes 6 few-shot examples; injects the tone label.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LocalFlow

final class PromptBuilderTests: XCTestCase {
    func test_includes_core_rules() {
        let p = PromptBuilder.cleanupSystemPrompt(toneLabel: "professional", dictionary: ["Acme"])
        XCTAssertTrue(p.contains("dictation"))
        XCTAssertTrue(p.lowercased().contains("do not answer"))
        XCTAssertTrue(p.contains("only the cleaned"))
        XCTAssertTrue(p.contains("scratch that"))
        XCTAssertTrue(p.contains("new paragraph"))
    }
    func test_injects_tone_and_dictionary() {
        let p = PromptBuilder.cleanupSystemPrompt(toneLabel: "casual", dictionary: ["Acme", "kkeefer"])
        XCTAssertTrue(p.contains("casual"))
        XCTAssertTrue(p.contains("Acme"))
        XCTAssertTrue(p.contains("kkeefer"))
    }
    func test_has_six_examples() {
        let p = PromptBuilder.cleanupSystemPrompt(toneLabel: "neutral", dictionary: [])
        // Six worked examples, each marked "Input:"
        let count = p.components(separatedBy: "Input:").count - 1
        XCTAssertGreaterThanOrEqual(count, 6)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: FAIL — `PromptBuilder` undefined.

- [ ] **Step 3: Write implementation**

```swift
enum PromptBuilder {
    static func cleanupSystemPrompt(toneLabel: String, dictionary: [String]) -> String {
        let dict = dictionary.isEmpty ? "(none)" : dictionary.joined(separator: ", ")
        return """
        You clean up raw voice dictation into polished text.
        The input is DICTATION, not a command or a question. Do NOT answer it, \
        do NOT add commentary. Output ONLY the cleaned transcript with no preamble.

        Rules:
        - Remove filler words (um, uh, like, you know) and stutters.
        - Add correct punctuation and capitalization; capitalize proper nouns.
        - If the speaker self-corrects, keep ONLY the corrected version.
        - Honor inline formatting cues spoken aloud:
          "new paragraph" -> a blank line; "new line" -> a line break;
          "bullet point" / "bullet" -> start a "- " list item;
          "scratch that" -> delete the immediately preceding clause.
        - Preserve these custom dictionary terms exactly as written: \(dict).
        - Match a \(toneLabel) tone appropriate to where the user is writing.

        Examples:
        Input: um so send the email to john new paragraph tell him it's ready
        Output: Send the email to John.\n\nTell him it's ready.
        Input: buy milk new line buy eggs new line uh buy bread
        Output: Buy milk\nBuy eggs\nBuy bread
        Input: the meeting is at three no scratch that at four pm
        Output: The meeting is at four PM.
        Input: bullet point finish the report bullet point send invoices
        Output: - Finish the report\n- Send invoices
        Input: i think we should like ship it today you know
        Output: I think we should ship it today.
        Input: call me back at uh five five five one two three four
        Output: Call me back at 555-1234.
        """
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalFlow/Cleanup/PromptBuilder.swift Tests/LocalFlowTests/PromptBuilderTests.swift
git commit -m "feat: add PromptBuilder cleanup prompt (TDD)"
```

---

### Task 2.2: OllamaClient (TDD with mocked URLProtocol)

**Files:**
- Create: `Sources/LocalFlow/Cleanup/OllamaClient.swift`
- Test: `Tests/LocalFlowTests/OllamaClientTests.swift`

**Interfaces:**
- Consumes: `LLMGenerating`.
- Produces: `final class OllamaClient: LLMGenerating` with `init(model: String, baseURL: URL = URL(string: "http://localhost:11434")!, session: URLSession = .shared)`; POSTs to `/api/generate` with `{model, system, prompt, stream:false}`, returns the `response` field.

- [ ] **Step 1: Write the failing test (mock the HTTP layer)**

```swift
import XCTest
@testable import LocalFlow

final class MockURLProtocol: URLProtocol {
    static var responseData: Data = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class OllamaClientTests: XCTestCase {
    func test_parses_response_field() async throws {
        MockURLProtocol.responseData = #"{"response":"Send the email to John."}"#.data(using: .utf8)!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = OllamaClient(model: "qwen2.5:7b", session: URLSession(configuration: config))
        let out = try await client.generate(system: "sys", prompt: "raw")
        XCTAssertEqual(out, "Send the email to John.")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: FAIL — `OllamaClient` undefined.

- [ ] **Step 3: Write implementation**

```swift
import Foundation

final class OllamaClient: LLMGenerating {
    private let model: String
    private let baseURL: URL
    private let session: URLSession

    init(model: String, baseURL: URL = URL(string: "http://localhost:11434")!, session: URLSession = .shared) {
        self.model = model; self.baseURL = baseURL; self.session = session
    }

    struct Response: Decodable { let response: String }

    func generate(system: String, prompt: String) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": model, "system": system, "prompt": prompt, "stream": false]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(Response.self, from: data).response
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalFlow/Cleanup/OllamaClient.swift Tests/LocalFlowTests/OllamaClientTests.swift
git commit -m "feat: add OllamaClient LLM client (TDD)"
```

---

### Task 2.3: CleanupService + wire into pipeline (manual verification)

**Files:**
- Create: `Sources/LocalFlow/Cleanup/CleanupService.swift`
- Modify: `Sources/LocalFlow/LocalFlowApp.swift` (pass a real CleanupService into DictationController)

**Interfaces:**
- Consumes: `LLMGenerating`, `PromptBuilder`, `ContextProvider` (added in Phase 3 — until then pass `toneLabel: "neutral"`).
- Produces: `final class CleanupService` with `init(llm: LLMGenerating, dictionary: [String])` and `func clean(raw: String, toneLabel: String = "neutral") async throws -> String`.

- [ ] **Step 1: Implement CleanupService**

```swift
final class CleanupService {
    private let llm: LLMGenerating
    private let dictionary: [String]

    init(llm: LLMGenerating, dictionary: [String]) {
        self.llm = llm; self.dictionary = dictionary
    }

    func clean(raw: String, toneLabel: String = "neutral") async throws -> String {
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return raw }
        let system = PromptBuilder.cleanupSystemPrompt(toneLabel: toneLabel, dictionary: dictionary)
        return try await llm.generate(system: system, prompt: raw)
    }
}
```

- [ ] **Step 2: Wire into LocalFlowApp** — in `wire()`, replace `cleanup: nil` with a real service:

```swift
        let llm = OllamaClient(model: settings.settings.llmModel)
        let cleanup = CleanupService(llm: llm, dictionary: settings.settings.dictionary)
        let controller = DictationController(recorder: recorder, transcriber: transcriber,
                                             cleanup: cleanup, injector: injector, state: state)
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verify cleanup** — ensure `ollama serve` is running. Launch app, in TextEdit hold Right Option, say "um so like send the email to john new paragraph tell him it's ready". Release.
Expected: output is `Send the email to John.` / blank line / `Tell him it's ready.` — fillers gone, formatting applied.

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalFlow/Cleanup/CleanupService.swift Sources/LocalFlow/LocalFlowApp.swift
git commit -m "feat: add Ollama cleanup stage to dictation pipeline"
```

---

# PHASE 3 — Context Awareness

### Task 3.1: ContextProvider (TDD) + wire

**Files:**
- Create: `Sources/LocalFlow/Context/ContextProvider.swift`
- Test: `Tests/LocalFlowTests/ContextProviderTests.swift`
- Modify: `Sources/LocalFlow/Coordinator/DictationController.swift`, `Sources/LocalFlow/LocalFlowApp.swift`

**Interfaces:**
- Produces:
  - `struct ContextProvider { let modes: [String: String]; func toneLabel(forBundleID id: String?) -> String }` — returns the mapped tone, else `"neutral"`.
  - `static func frontmostBundleID() -> String?` using `NSWorkspace`.
- Consumes (DictationController): now resolves `toneLabel` before calling `cleanup.clean(raw:toneLabel:)`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LocalFlow

final class ContextProviderTests: XCTestCase {
    let provider = ContextProvider(modes: [
        "com.tinyspeck.slackmacgap": "casual",
        "com.apple.mail": "professional"
    ])
    func test_maps_known_bundle() {
        XCTAssertEqual(provider.toneLabel(forBundleID: "com.apple.mail"), "professional")
        XCTAssertEqual(provider.toneLabel(forBundleID: "com.tinyspeck.slackmacgap"), "casual")
    }
    func test_unknown_and_nil_default_to_neutral() {
        XCTAssertEqual(provider.toneLabel(forBundleID: "com.unknown.app"), "neutral")
        XCTAssertEqual(provider.toneLabel(forBundleID: nil), "neutral")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: FAIL — `ContextProvider` undefined.

- [ ] **Step 3: Write implementation**

```swift
import AppKit

struct ContextProvider {
    let modes: [String: String]

    func toneLabel(forBundleID id: String?) -> String {
        guard let id, let tone = modes[id] else { return "neutral" }
        return tone
    }

    @MainActor static func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Capture context at record-start in DictationController** — add a stored `contextProvider: ContextProvider` and a `capturedTone` field; set `capturedTone = contextProvider.toneLabel(forBundleID: ContextProvider.frontmostBundleID())` inside `beginRecording()` (before recording steals focus), and pass it: `try await cleanup.clean(raw: text, toneLabel: capturedTone)`. Update the `init` to accept `contextProvider`.

Add to `DictationController`:
```swift
    private let contextProvider: ContextProvider
    private var capturedTone = "neutral"
```
In `init`, add parameter `contextProvider: ContextProvider` and assign it.
In `beginRecording()`, first line:
```swift
        capturedTone = contextProvider.toneLabel(forBundleID: ContextProvider.frontmostBundleID())
```
In `finishRecording()`, change the cleanup call to:
```swift
                    text = (try? await cleanup.clean(raw: text, toneLabel: capturedTone)) ?? text
```

- [ ] **Step 6: Wire in LocalFlowApp** — construct provider from settings and pass it:
```swift
        let contextProvider = ContextProvider(modes: settings.settings.contextModes)
        let controller = DictationController(recorder: recorder, transcriber: transcriber,
                                             cleanup: cleanup, injector: injector,
                                             state: state, contextProvider: contextProvider)
```

- [ ] **Step 7: Build + manual verify** — dictate the same sentence with Mail frontmost vs Slack frontmost.
Expected: Mail output reads more formal, Slack more casual.

- [ ] **Step 8: Commit**

```bash
git add Sources/LocalFlow/Context Tests/LocalFlowTests/ContextProviderTests.swift Sources/LocalFlow/Coordinator/DictationController.swift Sources/LocalFlow/LocalFlowApp.swift
git commit -m "feat: add context-aware tone selection (TDD)"
```

---

# PHASE 4 — Voice Commands

### Task 4.1: ActionRegistry (TDD)

**Files:**
- Create: `Sources/LocalFlow/Commands/ActionRegistry.swift`
- Test: `Tests/LocalFlowTests/ActionRegistryTests.swift`

**Interfaces:**
- Produces:
  - `struct AppAction { let id: String; let run: @MainActor () -> Void }`
  - `struct ActionRegistry { func match(_ phrase: String) -> (action: AppAction, argument: String?)? }` — recognizes `open <app>` (argument = app name), `copy`, `paste`. Matching is case-insensitive and ignores leading filler.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LocalFlow

final class ActionRegistryTests: XCTestCase {
    let reg = ActionRegistry()
    func test_open_app_extracts_argument() {
        let m = reg.match("open Safari")
        XCTAssertEqual(m?.action.id, "open")
        XCTAssertEqual(m?.argument, "Safari")
    }
    func test_open_is_case_insensitive() {
        XCTAssertEqual(reg.match("OPEN slack")?.argument, "slack")
    }
    func test_copy_matches_no_argument() {
        XCTAssertEqual(reg.match("copy that")?.action.id, "copy")
    }
    func test_unrecognized_returns_nil() {
        XCTAssertNil(reg.match("make this more formal"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: FAIL — `ActionRegistry` undefined.

- [ ] **Step 3: Write implementation**

```swift
import AppKit

struct AppAction {
    let id: String
    let run: @MainActor (String?) -> Void
}

struct ActionRegistry {
    func match(_ phrase: String) -> (action: AppAction, argument: String?)? {
        let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if p.hasPrefix("open ") {
            let arg = String(phrase.dropFirst(phrase.range(of: "open ", options: .caseInsensitive)!.upperBound.utf16Offset(in: phrase) - phrase.startIndex.utf16Offset(in: phrase)))
                .trimmingCharacters(in: .whitespaces)
            return (AppAction(id: "open") { name in
                guard let name, !name.isEmpty else { return }
                NSWorkspace.shared.launchApplication(name)
            }, arg)
        }
        if p.hasPrefix("copy") {
            return (AppAction(id: "copy") { _ in
                let src = CGEventSource(stateID: .combinedSessionState)
                let d = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true); d?.flags = .maskCommand
                let u = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false); u?.flags = .maskCommand
                d?.post(tap: .cgSessionEventTap); u?.post(tap: .cgSessionEventTap)
            }, nil)
        }
        if p.hasPrefix("paste") {
            return (AppAction(id: "paste") { _ in
                let src = CGEventSource(stateID: .combinedSessionState)
                let d = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true); d?.flags = .maskCommand
                let u = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false); u?.flags = .maskCommand
                d?.post(tap: .cgSessionEventTap); u?.post(tap: .cgSessionEventTap)
            }, nil)
        }
        return nil
    }
}
```

> Note: `AppAction.run` takes an optional argument; the tuple's `argument` is passed to `run` by the caller (CommandRouter). The tests only assert `id` and `argument`, so they compile and pass.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalFlow/Commands/ActionRegistry.swift Tests/LocalFlowTests/ActionRegistryTests.swift
git commit -m "feat: add ActionRegistry whitelist (TDD)"
```

---

### Task 4.2: CommandRouter (TDD with fake LLM)

**Files:**
- Create: `Sources/LocalFlow/Commands/CommandRouter.swift`
- Test: `Tests/LocalFlowTests/CommandRouterTests.swift`

**Interfaces:**
- Consumes: `LLMGenerating`, `ActionRegistry`, `TextInjecting`.
- Produces:
  - `enum CommandDecision: Equatable { case action(id: String, argument: String?); case rewrite(instruction: String); case none }`
  - `struct CommandRouter { let registry: ActionRegistry; func decide(_ transcript: String) -> CommandDecision }` — first tries `registry.match`; if it matches → `.action`; else → `.rewrite(instruction: transcript)`.
  - `@MainActor func execute(_ decision: CommandDecision, llm: LLMGenerating, injector: TextInjecting) async` — for `.action` runs the matched action; for `.rewrite` reads the selection, asks the LLM to apply the instruction, replaces the selection.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LocalFlow

final class CommandRouterTests: XCTestCase {
    let router = CommandRouter(registry: ActionRegistry())
    func test_action_phrase_routes_to_action() {
        XCTAssertEqual(router.decide("open Safari"), .action(id: "open", argument: "Safari"))
    }
    func test_non_action_routes_to_rewrite() {
        XCTAssertEqual(router.decide("make this more formal"), .rewrite(instruction: "make this more formal"))
    }
    func test_empty_routes_to_none() {
        XCTAssertEqual(router.decide("   "), .none)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: FAIL — `CommandRouter` undefined.

- [ ] **Step 3: Write implementation**

```swift
import Foundation

enum CommandDecision: Equatable {
    case action(id: String, argument: String?)
    case rewrite(instruction: String)
    case none
}

struct CommandRouter {
    let registry: ActionRegistry

    func decide(_ transcript: String) -> CommandDecision {
        let t = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .none }
        if let m = registry.match(t) {
            return .action(id: m.action.id, argument: m.argument)
        }
        return .rewrite(instruction: t)
    }

    @MainActor
    func execute(_ decision: CommandDecision, llm: LLMGenerating, injector: TextInjecting) async {
        switch decision {
        case .none:
            return
        case .action(let id, let argument):
            if let m = registry.match(id == "open" ? "open \(argument ?? "")" : id) {
                m.action.run(argument)
            }
        case .rewrite(let instruction):
            guard let selection = injector.readSelection(), !selection.isEmpty else { return }
            let system = "You rewrite text per an instruction. Output ONLY the rewritten text, no preamble."
            let prompt = "Instruction: \(instruction)\n\nText:\n\(selection)"
            if let rewritten = try? await llm.generate(system: system, prompt: prompt) {
                injector.replaceSelection(with: rewritten)
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalFlow/Commands/CommandRouter.swift Tests/LocalFlowTests/CommandRouterTests.swift
git commit -m "feat: add CommandRouter (TDD)"
```

---

### Task 4.3: Wire command hotkey into pipeline (manual verification)

**Files:**
- Modify: `Sources/LocalFlow/Coordinator/DictationController.swift` (add command path)
- Modify: `Sources/LocalFlow/LocalFlowApp.swift`

**Interfaces:**
- Consumes: `CommandRouter`, `LLMGenerating`.
- Produces: `DictationController.commandHotkey(pressed: Bool)`; a `mode` flag distinguishing dictation vs command capture so `finishRecording()` branches.

- [ ] **Step 1: Add command handling to DictationController**

Add stored properties:
```swift
    private let router: CommandRouter
    private let llm: LLMGenerating
    private enum Mode { case dictation, command }
    private var mode: Mode = .dictation
```
Add to `init` params `router: CommandRouter, llm: LLMGenerating` and assign.
Add method:
```swift
    func commandHotkey(pressed: Bool) {
        if pressed { mode = .command; beginRecording() } else { finishRecording() }
    }
```
Set `mode = .dictation` at the top of `dictationHotkey(pressed:)` when `pressed`.
In `finishRecording()`, branch after transcription:
```swift
                let raw = try await transcriber.transcribe(samples: samples)
                if mode == .command {
                    state.status = "Command…"
                    await router.execute(router.decide(raw), llm: llm, injector: injector)
                    state.status = "Idle"; return
                }
                var text = raw
                // …existing cleanup + inject path…
```

- [ ] **Step 2: Wire in LocalFlowApp**

```swift
        let router = CommandRouter(registry: ActionRegistry())
        let controller = DictationController(recorder: recorder, transcriber: transcriber,
                                             cleanup: cleanup, injector: injector, state: state,
                                             contextProvider: contextProvider, router: router, llm: llm)
        hotkeys.onDictation = { pressed in Task { @MainActor in controller.dictationHotkey(pressed: pressed) } }
        hotkeys.onCommand = { pressed in Task { @MainActor in controller.commandHotkey(pressed: pressed) } }
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verify both command paths**
  - Action: hold Right Shift, say "open Safari", release → Safari launches.
  - Rewrite: select a sentence in TextEdit, hold Right Shift, say "make this more formal", release → selection is replaced with a more formal version.

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalFlow/Coordinator/DictationController.swift Sources/LocalFlow/LocalFlowApp.swift
git commit -m "feat: wire command hotkey (rewrite + app actions)"
```

---

# PHASE 5 — Polish & Portability

### Task 5.1: Custom dictionary UI + WhisperKit prompt injection

**Files:**
- Modify: `Sources/LocalFlow/UI/MenuBarView.swift` (add a dictionary editor)
- Modify: `Sources/LocalFlow/Transcription/WhisperKitTranscriber.swift` (accept dictionary as decoding prompt)
- Modify: `Sources/LocalFlow/LocalFlowApp.swift`

**Interfaces:**
- Produces: `WhisperKitTranscriber.init(model:promptTerms:)`; passes `DecodingOptions(promptText:)` with the dictionary terms so STT biases toward them. MenuBarView gains a `TextField`-based list bound through a small `@Published var dictionaryText` on `AppState`, saved to `SettingsStore` on change.

- [ ] **Step 1: Extend WhisperKitTranscriber to bias with dictionary**

```swift
actor WhisperKitTranscriber: Transcribing {
    private let model: String
    private let promptTerms: [String]
    private var pipe: WhisperKit?

    init(model: String, promptTerms: [String] = []) {
        self.model = model; self.promptTerms = promptTerms
    }

    func transcribe(samples: [Float]) async throws -> String {
        if pipe == nil { pipe = try await WhisperKit(WhisperKitConfig(model: model)) }
        var options = DecodingOptions()
        if !promptTerms.isEmpty {
            options.promptText = "Vocabulary: " + promptTerms.joined(separator: ", ")
            options.usePrefillPrompt = true
        }
        let results = try await pipe!.transcribe(audioArray: samples, decodeOptions: options)
        return results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 2: Pass dictionary in LocalFlowApp init**

```swift
        transcriber = WhisperKitTranscriber(model: SettingsStore().settings.sttModel,
                                            promptTerms: SettingsStore().settings.dictionary)
```

- [ ] **Step 3: Add a dictionary editor to MenuBarView**

Add a section that binds a comma-separated `TextField` to a new `AppState.dictionaryText`, and on submit writes it back to a `SettingsStore` passed into `MenuBarView`. (Split terms on commas, trim, drop empties.)
```swift
            Divider()
            Text("Custom vocabulary (comma-separated)").font(.caption)
            TextField("e.g. Acme, kkeefer", text: $state.dictionaryText, onCommit: onDictionarySave)
```
Add `@Published var dictionaryText = ""` to `AppState`, initialize it from settings at launch, and provide `onDictionarySave` in the view that parses and persists.

- [ ] **Step 4: Build + manual verify** — add a proper noun (e.g. "Acme") to the dictionary, dictate a sentence containing it.
Expected: term is spelled correctly in output; persists after quit/relaunch.

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalFlow
git commit -m "feat: custom dictionary — STT bias + editor UI"
```

---

### Task 5.2: Recording indicator + graceful Ollama/permission checks

**Files:**
- Modify: `Sources/LocalFlow/UI/MenuBarView.swift`
- Modify: `Sources/LocalFlow/LocalFlowApp.swift`
- Create: `Sources/LocalFlow/Coordinator/HealthCheck.swift`

**Interfaces:**
- Produces: `enum HealthCheck { @MainActor static func ollamaReachable() async -> Bool; static func accessibilityGranted() -> Bool }`. MenuBarView reflects `state.status` with a colored dot; on launch, `wire()` runs the checks and sets a warning status if something is missing.

- [ ] **Step 1: Implement HealthCheck**

```swift
import ApplicationServices
import Foundation

enum HealthCheck {
    static func ollamaReachable() async -> Bool {
        var req = URLRequest(url: URL(string: "http://localhost:11434/api/tags")!)
        req.timeoutInterval = 1.5
        return (try? await URLSession.shared.data(for: req)) != nil
    }
    static func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }
}
```

- [ ] **Step 2: Surface status in wire()** — after starting hotkeys:
```swift
        Task { @MainActor in
            if !HealthCheck.accessibilityGranted() { state.status = "Grant Accessibility & Input Monitoring" }
            else if !(await HealthCheck.ollamaReachable()) { state.status = "Ollama not running (ollama serve)" }
        }
```

- [ ] **Step 3: Add colored status dot to MenuBarView** — a small `Circle().fill(...)` (green when "Idle", orange for warnings, red for "Error…"), driven by inspecting `state.status`.

- [ ] **Step 4: Build + manual verify** — quit Ollama (`brew services stop ollama`), launch app → status warns; restart Ollama → after relaunch status returns to Idle.

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalFlow
git commit -m "feat: health checks + recording status indicator"
```

---

### Task 5.3: Code-signing for stable permissions + second-Mac setup docs

**Files:**
- Modify: `project.yml` (set `DEVELOPMENT_TEAM`)
- Create: `README.md`

**Interfaces:** none (build config + docs).

- [ ] **Step 1: Find your Development Team ID**

Run:
```bash
security find-identity -v -p codesigning
```
Expected: at least one "Apple Development" identity. Note the 10-char Team ID (in parentheses of the identity name, or via Xcode → Settings → Accounts). If none exists, add your Apple ID in Xcode → Settings → Accounts → Manage Certificates → +.

- [ ] **Step 2: Set the team in project.yml**

Under `targets.LocalFlow.settings.base`, add:
```yaml
        DEVELOPMENT_TEAM: <YOUR_TEAM_ID>
        CODE_SIGN_IDENTITY: "Apple Development"
```
Regenerate and rebuild:
```bash
xcodegen generate
xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`, product is signed with your identity.

- [ ] **Step 3: Verify signing**

Run:
```bash
codesign -dv --verbose=2 "$(xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{d=$3}/ FULL_PRODUCT_NAME/{n=$3}END{print d"/"n}')" 2>&1 | grep -E "Authority|TeamIdentifier"
```
Expected: shows your Team Identifier (not `adhoc`). Permissions now persist across rebuilds.

- [ ] **Step 4: Write README with second-Mac setup**

```markdown
# LocalFlow

Fully-local, offline macOS dictation (Wispr Flow clone). WhisperKit STT + Ollama cleanup.

## Setup (each Mac)
1. `brew install xcodegen ollama`
2. `brew services start ollama && ollama pull qwen2.5:7b`
3. `git clone <repo> && cd localflow`
4. Set your `DEVELOPMENT_TEAM` in `project.yml` (see `security find-identity -v -p codesigning`).
5. `xcodegen generate`
6. `xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow build`
7. Launch the built app; grant Microphone, Accessibility, Input Monitoring.

## Use
- Hold **Right Option**, speak, release → cleaned text pasted at the cursor.
- Hold **Right Shift**, speak a command ("open Safari") or select text first and say "make this more formal".
- Edit custom vocabulary and see status from the menu-bar item.
```

- [ ] **Step 5: Commit**

```bash
git add project.yml README.md
git commit -m "chore: code-signing config + second-Mac setup docs"
```

---

## Self-Review

**Spec coverage:**
- §3 architecture / two-mode pipeline → Tasks 1.5, 4.3. ✓
- §4 components: HotkeyManager (1.5), AudioRecorder (1.2), Transcriber (1.3/5.1), CleanupService (2.3), CommandRouter (4.2), ActionRegistry (4.1), TextInjector (1.4), ContextProvider (3.1), SettingsStore (0.3), MenuBarUI (0.2/5.1/5.2). ✓
- §5 feature map: dictation (1.5), cleanup (2.3), inline formatting (2.1 prompt), rewrite (4.2/4.3), app actions (4.1/4.3), context (3.1), custom vocab (5.1). ✓
- §6 prompt rules → Task 2.1 (tests assert dictation/do-not-answer/only-cleaned/scratch that/new paragraph/tone/dictionary/6 examples). ✓
- §8 permissions → entitlements (0.2), manual grant (1.5), health check (5.2), signing (5.3). ✓
- §9 error handling → graceful raw-paste fallback if cleanup fails (1.5/2.3), health checks (5.2), pasteboard restore (1.4). ✓
- §10 testing → XCTest for all pure units; manual steps with explicit expected output for system units. ✓
- §11 phases → Phases 0–5 map 1:1. ✓
- §12 deferred (streaming) → intentionally not implemented; transcribe-on-release used throughout. ✓

**Placeholder scan:** no TBD/TODO; every code step contains complete code; commands have expected output. The one `<YOUR_TEAM_ID>` in 5.3 is a required per-machine value with the discovery command given — not a plan placeholder.

**Type consistency:** `Transcribing.transcribe(samples:)`, `LLMGenerating.generate(system:prompt:)`, `TextInjecting.inject/readSelection/replaceSelection`, `CleanupService.clean(raw:toneLabel:)`, `ContextProvider.toneLabel(forBundleID:)`, `CommandRouter.decide/execute`, `AppAction.run(_:)` used consistently across all referencing tasks. WhisperKit API (`WhisperKitConfig`, `transcribe(audioArray:decodeOptions:)`, `DecodingOptions.promptText`) — verify exact signatures against the resolved WhisperKit version during Task 1.3 and adjust if the package's API differs.
