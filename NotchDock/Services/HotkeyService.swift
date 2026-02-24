import KeyboardShortcuts

@MainActor
final class HotkeyService {
    func bind(to viewModel: NotchDockViewModel) {
        KeyboardShortcuts.onKeyUp(for: .toggleExpand) {
            Task { @MainActor in
                viewModel.toggleExpand()
            }
        }
    }
}

extension KeyboardShortcuts.Name {
    static let toggleExpand = Self("toggleExpand", default: .init(.space, modifiers: [.option]))
}
