import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState
    var onDictionarySave: (String) -> Void = { _ in }
    var onShowSetup: () -> Void = {}

    /// Maps a free-form `AppState.status` string to a status-dot color. Pure and testable in
    /// isolation from SwiftUI: green means fully ready ("Idle"), red flags a hard failure
    /// ("Error…" prefix, matching `DictationController`'s error surfacing), and orange covers
    /// everything else — the two health-check warnings from `wire()` as well as transient
    /// in-flight states like "Recording…" or "Transcribing…".
    static func statusDotColor(for status: String) -> Color {
        if status == "Idle" { return .green }
        if status.hasPrefix("Error") { return .red }
        return .orange
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Self.statusDotColor(for: state.status))
                    .frame(width: 8, height: 8)
                Text("LocalFlow — \(state.status)")
            }
            if let notice = state.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            if state.setup.requiredItemsMissing || state.setup.summary != nil {
                Button("Finish setup…") { onShowSetup() }
            }
            Divider()
            if state.history.isEmpty {
                Text("No dictations yet").foregroundStyle(.secondary)
            } else {
                ForEach(state.history.prefix(5), id: \.self) { item in
                    Text(item).lineLimit(1)
                }
            }
            Divider()
            Text("Custom vocabulary (comma-separated)").font(.caption)
            TextField("e.g. Acme, kkeefer", text: $state.dictionaryText)
                .onSubmit { onDictionarySave(state.dictionaryText) }
            Text("Saved terms bias dictation and cleanup starting next launch.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("Setup…") { onShowSetup() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(8)
        .frame(width: 320)
    }
}
