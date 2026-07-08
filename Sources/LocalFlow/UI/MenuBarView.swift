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
