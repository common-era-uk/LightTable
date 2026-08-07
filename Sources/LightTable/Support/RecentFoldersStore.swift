import Foundation

/// Tracks recently opened canvas folders for the File > Open Recent menu,
/// persisted across launches via UserDefaults. Not sandboxed, so plain paths
/// are enough — no security-scoped bookmarks needed.
@MainActor
final class RecentFoldersStore: ObservableObject {
    static let shared = RecentFoldersStore()

    @Published private(set) var urls: [URL] = []

    private let defaultsKey = "recentFolders"
    private let maxCount = 10

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        urls = paths.map(URL.init(fileURLWithPath:)).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func record(_ url: URL) {
        urls.removeAll { $0 == url }
        urls.insert(url, at: 0)
        if urls.count > maxCount {
            urls.removeLast(urls.count - maxCount)
        }
        persist()
    }

    func clear() {
        urls = []
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(urls.map { $0.path }, forKey: defaultsKey)
    }
}
