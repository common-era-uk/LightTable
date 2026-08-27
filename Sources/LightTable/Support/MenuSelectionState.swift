import Foundation

/// Tracks whether the key window's canvas currently has 2+ images selected,
/// so the View menu's "Create Grid…" item can gray itself out accordingly.
/// Updated by `CanvasView` via `.onChange(of: document.selectedIDs)` (which
/// only fires when the selection set actually changes, not on every
/// re-render/drag frame) and on window-activation, rather than through
/// `focusedSceneValue` — see the perf note in `GuideNotifications.swift`.
final class MenuSelectionState: ObservableObject {
    static let shared = MenuSelectionState()
    @Published var hasMultipleSelected = false
    private init() {}
}
