import SwiftUI
import AppKit
import Sparkle

@main
struct LightTableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var recentDocuments = RecentDocumentsStore.shared
    @ObservedObject private var shadowSettings = ShadowSettings.shared
    @ObservedObject private var menuSelectionState = MenuSelectionState.shared

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
                // Standard text-editing actions, dispatched up the responder
                // chain the normal AppKit way — lets ⌘X/⌘C/⌘V work in any
                // text field/editor (e.g. the text item formatting sheet)
                // even though the canvas itself has no clipboard concept of
                // its own. This group otherwise replaces Cut/Copy/Paste
                // entirely, so without these, focusing a text field had no
                // menu-level Copy/Paste at all.
                Button("Cut") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)
                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)
                Button("Paste") {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: .command)
                Divider()
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
                .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Remove from Canvas") {
                    NotificationCenter.default.post(name: .deleteSelected, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [])
                Button("Delete from Folder") {
                    NotificationCenter.default.post(name: .deleteFromFolder, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: .command)
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
                Divider()
                Button("Insert Text Field") {
                    NotificationCenter.default.post(name: .insertTextField, object: nil)
                }
                Button("Insert Text Box") {
                    NotificationCenter.default.post(name: .insertTextBox, object: nil)
                }
            }
            // "New Window" itself stays the automatic default content of
            // .newItem (adding after, not replacing it, so its real
            // behavior is never reimplemented here) — but everything from
            // "Open…" through "Close All" lives in this one group with it.
            // SwiftUI/AppKit inserts its own automatic separator at the
            // boundary between two *different* named placements, on top of
            // any Divider() already placed there, which produced doubled-up
            // separators when this content used to be split across a
            // separate `.newItem`-placed group and a `.saveItem`-placed one.
            // One group means every separator here is exactly the one
            // `Divider()` written for it — .saveItem's own default content
            // (Close/Close All) is suppressed below with an empty
            // replacement, since it's placed here at the bottom instead.
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
                Divider()
                Button("Set Art Board Size…") {
                    NotificationCenter.default.post(name: .openBoardSizeDialog, object: nil)
                }
                Divider()
                Button("Save As…") {
                    NotificationCenter.default.post(name: .saveDocumentAs, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Export as PDF…") {
                    NotificationCenter.default.post(name: .exportPDF, object: nil)
                }
                Button("Package…") {
                    NotificationCenter.default.post(name: .packageDocument, object: nil)
                }
                Button("Bulk Rename…") {
                    NotificationCenter.default.post(name: .bulkRename, object: nil)
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
            // Empty — just suppresses .saveItem's own default content
            // (Close/Close All), which are placed above instead, at the
            // bottom of the .newItem group.
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Create Grid…") {
                    NotificationCenter.default.post(name: .createGrid, object: nil)
                }
                .disabled(!menuSelectionState.hasMultipleSelected)
                Divider()
                Button("Toggle Guides") {
                    NotificationCenter.default.post(name: .toggleShowGuides, object: nil)
                }
                Button("Change Guide Colour…") {
                    NotificationCenter.default.post(name: .openGuideColorPicker, object: nil)
                }
                Button("Clear All Guides") {
                    NotificationCenter.default.post(name: .clearAllGuides, object: nil)
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
