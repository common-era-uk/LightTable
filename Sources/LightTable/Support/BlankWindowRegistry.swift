import Foundation

/// Tracks every window currently showing the blank "open a folder" prompt,
/// so opening a folder anywhere in the app — the toolbar button, File > Open
/// Recent, a Dock drop, tabbed or not — can close any of them left behind
/// (most commonly the window you get at launch, once you've opened your
/// first folder). Separate from `AppDelegate`'s own `suppressNextBlankWindow`
/// mechanism, which solves a narrower, timing-sensitive race specific to a
/// Dock drop arriving before that launch window has even appeared; this
/// registry instead handles the steady-state case where a blank window is
/// already fully visible when a folder is opened some other way.
@MainActor
final class BlankWindowRegistry {
    static let shared = BlankWindowRegistry()

    private var dismissers: [UUID: () -> Void] = [:]

    private init() {}

    func register(_ id: UUID, dismiss: @escaping () -> Void) {
        dismissers[id] = dismiss
    }

    func unregister(_ id: UUID) {
        dismissers.removeValue(forKey: id)
    }

    func dismissOthers(except exceptID: UUID) {
        for (id, dismiss) in dismissers where id != exceptID {
            dismiss()
        }
        dismissers = dismissers.filter { $0.key == exceptID }
    }
}
