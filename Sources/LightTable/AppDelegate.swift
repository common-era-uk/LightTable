import AppKit

/// Bridges AppKit's "open these files" events (Dock icon drops, `open`
/// command, double-clicking a folder or a `.lt` document in Finder) into
/// SwiftUI's window-opening system. A View sets `openDocumentAction` once
/// (any window's RootView will do — the action itself isn't tied to a
/// specific window) so this delegate has something to call when an open
/// request arrives. The URL passed through may be either a folder (which
/// `RootView` then resolves to a specific `.lt` document) or a `.lt` file
/// itself (already unambiguous).
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var openDocumentAction: ((URL) -> Void)?

    /// The currently-visible blank ("open a folder") window can close
    /// itself via this, if one is registered.
    static var dismissBlankWindow: (() -> Void)?

    /// True for a short window after handling a drop, so a blank window
    /// that appears as a side effect of opening the requested folder (which
    /// happens asynchronously, slightly after) knows to close itself
    /// immediately instead of staying on screen. Expires quickly so a
    /// deliberate later "New Window" isn't affected.
    static var suppressNextBlankWindow = false

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.hasDirectoryPath || url.pathExtension.lowercased() == CanvasDocument.fileExtension {
            Self.suppressNextBlankWindow = true
            Self.openDocumentAction?(url)
            Self.dismissBlankWindow?()
            Self.dismissBlankWindow = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Self.suppressNextBlankWindow = false
            }
        }
    }
}
