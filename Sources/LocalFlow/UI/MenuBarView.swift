import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState
    var onDictionarySave: (String) -> Void = { _ in }

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
            Text("Custom vocabulary (comma-separated)").font(.caption)
            TextField("e.g. Acme, kkeefer", text: $state.dictionaryText)
                .onSubmit { onDictionarySave(state.dictionaryText) }
            Text("Saved terms bias dictation and cleanup starting next launch.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(8)
        .frame(width: 320)
    }
}
