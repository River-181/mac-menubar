import KeyboardShortcuts

@MainActor
final class HotkeyService {
    func bind(to viewModel: NotchDockViewModel) {
        KeyboardShortcuts.onKeyUp(for: .toggleExpand) {
            Task { @MainActor in
                viewModel.toggleExpand()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .undoLastAction) {
            Task { @MainActor in
                await viewModel.undoLastDangerousAction()
            }
        }
    }
}

extension KeyboardShortcuts.Name {
    static let toggleExpand = Self("toggleExpand", default: .init(.space, modifiers: [.option]))
    static let undoLastAction = Self("undoLastAction", default: .init(.z, modifiers: [.option, .command]))
}
