import Foundation
import ImageIO
import CoreGraphics
import Darwin

enum ImageFileSupport {
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"
    ]

    static func isImage(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func listImages(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { isImage($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Pixel dimensions without decoding full image data.
    static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = props[kCGImagePropertyPixelHeight] as? CGFloat
        else { return nil }
        return CGSize(width: width, height: height)
    }

    /// The file's inode number — stable across renames/moves on the same
    /// volume, used to re-associate a canvas item with its file even if the
    /// filename on disk no longer matches what's in the sidecar.
    static func fileID(of url: URL) -> UInt64? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return UInt64(info.st_ino)
    }

    /// Files above this size are rejected before they ever reach the canvas.
    /// A very large RAW/TIFF/PSD scan decodes to a huge in-memory bitmap via
    /// NSImage, and the canvas can end up decoding many of these at once —
    /// enough of them can exhaust memory and crash the app.
    static let maxImageFileSizeBytes: Int64 = 150 * 1024 * 1024

    static func fileSize(of url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize else { return nil }
        return Int64(size)
    }

    /// A user-facing message if `url` is over the size limit, else nil.
    static func oversizeError(for url: URL) -> String? {
        guard let size = fileSize(of: url), size > maxImageFileSizeBytes else { return nil }
        let mb = Double(size) / 1_048_576
        let limitMB = maxImageFileSizeBytes / 1_048_576
        return "\"\(url.lastPathComponent)\" is \(String(format: "%.0f", mb)) MB. Please reduce it to under \(limitMB) MB and try again."
    }

    /// Checks every image already in `folder`; returns a message for the
    /// first oversized file found, or nil if all are within the limit.
    static func oversizeError(inFolder folder: URL) -> String? {
        for url in listImages(in: folder) {
            if let detail = oversizeError(for: url) {
                return "One or more files are too large to work with. \(detail)"
            }
        }
        return nil
    }

    /// Finds a filename in `folder` that doesn't collide with an existing file,
    /// appending " 2", " 3", etc. before the extension (Finder-style).
    static func availableFilename(for desiredName: String, in folder: URL) -> String {
        let fm = FileManager.default
        let base = (desiredName as NSString).deletingPathExtension
        let ext = (desiredName as NSString).pathExtension
        var candidate = desiredName
        var counter = 2
        while fm.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            counter += 1
        }
        return candidate
    }
}
