import AppKit

@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private var cache: [String: NSImage] = [:]

    func image(for url: URL) -> NSImage? {
        let key = url.path
        if let cached = cache[key] {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache[key] = image
        return image
    }
}
