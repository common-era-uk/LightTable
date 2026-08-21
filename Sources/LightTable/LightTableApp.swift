import SwiftUI
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
                Button("Duplicate") {
                    NotificationCenter.default.post(name: .duplicateSelected, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)
                Button("Crop") {
                    NotificationCenter.default.post(name: .cropSelected, object: nil)
                }
                Button("Delete") {
                    NotificationCenter.default.post(name: .deleteSelected, object: nil)
                }
                Divider()
                Button("Select All") {
                    NotificationCenter.default.post(name: .selectAllItems, object: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
                Button("Bulk Rename…") {
                    NotificationCenter.default.post(name: .bulkRename, object: nil)
                }
            }
            CommandGroup(after: .newItem) {
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
            CommandGroup(after: .saveItem) {
                Button("Save As…") {
                    NotificationCenter.default.post(name: .saveDocumentAs, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
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
}
