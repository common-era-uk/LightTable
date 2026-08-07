import Foundation

/// Lets the app-level View menu (in `LightTableApp`) reach the frontmost
/// canvas window without SwiftUI's `@FocusedBinding`/`.focusedSceneValue`
/// machinery — which turned out to carry real per-frame cost once attached
/// to a view (`CanvasView`) that's already re-rendering continuously during
/// a drag. A plain notification only does anything at the moment a menu
/// item is actually clicked, so it has no ongoing cost.
extension Notification.Name {
    static let toggleShowGuides = Notification.Name("LightTable.toggleShowGuides")
    static let openGuideColorPicker = Notification.Name("LightTable.openGuideColorPicker")
}
