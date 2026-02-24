import KeyboardShortcuts

@MainActor
final class HotkeyService {
    func bind(to viewModel: NotchDockViewModel) {
        KeyboardShortcuts.onKeyUp(for: .toggleExpand) {
            Task { @MainActor in
                viewModel.toggleExpand()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .toggleWorkspace) {
            Task { @MainActor in
                viewModel.toggleWorkspace(trigger: .hotkey)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .nextGroup) {
            Task { @MainActor in
                viewModel.focusNextGroup()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .previousGroup) {
            Task { @MainActor in
                viewModel.focusPreviousGroup()
            }
        }
    }
}

extension KeyboardShortcuts.Name {
    static let toggleExpand = Self("toggleExpand", default: .init(.space, modifiers: [.option]))
    static let toggleWorkspace = Self("toggleWorkspace", default: .init(.return, modifiers: [.option]))
    static let nextGroup = Self("nextGroup", default: .init(.rightArrow, modifiers: [.option]))
    static let previousGroup = Self("previousGroup", default: .init(.leftArrow, modifiers: [.option]))
}
