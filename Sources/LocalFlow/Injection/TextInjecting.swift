@MainActor
protocol TextInjecting {
    func inject(_ text: String)
    func readSelection() -> String?
    func replaceSelection(with text: String)
}
