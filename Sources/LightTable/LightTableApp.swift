import SwiftUI

@main
struct LightTableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var recentFolders = RecentFoldersStore.shared

    var body: some Scene {
        WindowGroup(for: URL.self) { $folderURL in
            RootView(folderURL: $folderURL)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About LightTable") {
                    openWindow(id: "about")
                }
            }
            CommandGroup(after: .newItem) {
                Menu("Open Recent") {
                    if recentFolders.urls.isEmpty {
                        Text("No Recent Folders")
                    } else {
                        ForEach(recentFolders.urls, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                openWindow(value: url)
                            }
                        }
                        Divider()
                        Button("Clear Menu") {
                            recentFolders.clear()
                        }
                    }
                }
            }
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Toggle Guides") {
                    NotificationCenter.default.post(name: .toggleShowGuides, object: nil)
                }
                Button("Change Guide Color…") {
                    NotificationCenter.default.post(name: .openGuideColorPicker, object: nil)
                }
            }
        }

        Window("About LightTable", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
