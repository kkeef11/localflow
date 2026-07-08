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
