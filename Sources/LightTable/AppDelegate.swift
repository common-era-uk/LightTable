import AppKit

/// Bridges AppKit's "open these files" events (Dock icon drops, `open`
/// command) into SwiftUI's window-opening system. A View sets
/// `openFolderAction` once (any window's RootView will do — the action
/// itself isn't tied to a specific window) so this delegate has something
/// to call when an open request arrives.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var openFolderAction: ((URL) -> Void)?

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
        for url in urls where url.hasDirectoryPath {
            Self.suppressNextBlankWindow = true
            Self.openFolderAction?(url)
            Self.dismissBlankWindow?()
            Self.dismissBlankWindow = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Self.suppressNextBlankWindow = false
            }
        }
    }
}
