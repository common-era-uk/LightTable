import Foundation

/// Tracks small bits of the key window's canvas state that the View menu
/// needs to reflect — whether 2+ images are selected (so "Create Grid…" can
/// gray itself out), and whether guides/smart guides are currently on (so
/// their menu items can read "Turn X Off" instead of a static "Toggle X").
/// Updated by `CanvasView` at discrete moments (selection changes, a toggle
/// actually firing, window activation) rather than through `focusedSceneValue`,
/// which carries real per-frame cost once attached to a view that's already
/// re-rendering continuously during a drag — see the perf note in
/// `GuideNotifications.swift`.
final class MenuSelectionState: ObservableObject {
    static let shared = MenuSelectionState()
    @Published var hasMultipleSelected = false
    @Published var showGuides = true
    @Published var smartGuidesEnabled = true
    private init() {}
}
