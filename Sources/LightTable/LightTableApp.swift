import SwiftUI
import AppKit
import Sparkle

@main
struct LightTableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var recentDocuments = RecentDocumentsStore.shared
    @ObservedObject private var shadowSettings = ShadowSettings.shared

    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        WindowGroup(for: URL.self) { $requestedURL in
            RootView(requestedURL: $requestedURL)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About LightTable") {
                    openWindow(id: "about")
                }
                Button("Check for Updates…") {
                    updaterController.checkForUpdates(nil)
                }
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Select All") {
                    NotificationCenter.default.post(name: .selectAllItems, object: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
                Button("Duplicate") {
                    NotificationCenter.default.post(name: .duplicateSelected, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)
                Button("Crop") {
                    NotificationCenter.default.post(name: .cropSelected, object: nil)
                }
                Button("Remove from Canvas") {
                    NotificationCenter.default.post(name: .deleteSelected, object: nil)
                }
                Button("Delete from Folder") {
                    NotificationCenter.default.post(name: .deleteFromFolder, object: nil)
                }
                Divider()
                Button("Bring Forward") {
                    NotificationCenter.default.post(name: .bringForward, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)
                Button("Bring to Front") {
                    NotificationCenter.default.post(name: .bringToFront, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Send Backward") {
                    NotificationCenter.default.post(name: .sendBackward, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)
                Button("Send to Back") {
                    NotificationCenter.default.post(name: .sendToBack, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            }
            CommandGroup(after: .newItem) {
                Button("Open…") {
                    presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
                Menu("Open Recent") {
                    if recentDocuments.urls.isEmpty {
                        Text("No Recent Documents")
                    } else {
                        ForEach(recentDocuments.urls, id: \.self) { url in
                            Button(url.deletingPathExtension().lastPathComponent) {
                                openWindow(value: url)
                            }
                        }
                        Divider()
                        Button("Clear Menu") {
                            recentDocuments.clear()
                        }
                    }
                }
            }
            // Replaces (rather than adds after) .saveItem — its default
            // content is where "Close"/"Close All" are automatically
            // supplied from, and there's no separate placement to target
            // just those. Rebuilding the whole group here is what lets them
            // move to the bottom of the menu instead of their default spot
            // right after Open Recent.
            CommandGroup(replacing: .saveItem) {
                Button("Bulk Rename…") {
                    NotificationCenter.default.post(name: .bulkRename, object: nil)
                }
                Button("Save As…") {
                    NotificationCenter.default.post(name: .saveDocumentAs, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Package…") {
                    NotificationCenter.default.post(name: .packageDocument, object: nil)
                }
                Divider()
                Button("Close") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
                Button("Close All") {
                    for window in NSApp.windows where window.isVisible {
                        window.performClose(nil)
                    }
                }
                .keyboardShortcut("w", modifiers: [.command, .option])
            }
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Toggle Guides") {
                    NotificationCenter.default.post(name: .toggleShowGuides, object: nil)
                }
                Button("Change Guide Color…") {
                    NotificationCenter.default.post(name: .openGuideColorPicker, object: nil)
                }
                Divider()
                Button("Toggle Shadows") {
                    shadowSettings.enabled.toggle()
                }
                Button("Shadow Settings…") {
                    openWindow(id: "shadowSettings")
                }
                Button("Large Preview Background Settings…") {
                    openWindow(id: "previewBackground")
                }
                Divider()
                Button("Refresh and Reflow") {
                    NotificationCenter.default.post(name: .refreshAndReflow, object: nil)
                }
                // Without this, this whole run gets merged with the
                // system's own "Enter Full Screen" item right after it —
                // and since that item has an icon, AppKit reserves icon
                // space for every item sharing its run, indenting ours too.
                Divider()
            }
            CommandGroup(replacing: .help) {
                Button("LightTable Help") {
                    openWindow(id: "about")
                }
            }
        }

        Window("About LightTable", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("Shadow Settings", id: "shadowSettings") {
            ShadowSettingsView()
        }
        .windowResizability(.contentSize)

        Window("Large Preview Background", id: "previewBackground") {
            PreviewBackgroundSettingsView()
        }
        .windowResizability(.contentSize)
    }

    /// File > Open… — always opens in a new window (matching "New Window"
    /// and the toolbar's own "Open Folder…" button) rather than replacing
    /// whatever's in the frontmost window, so it can never look like it
    /// just discarded an already-open canvas.
    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openWindow(value: url)
    }
}
