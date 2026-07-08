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
