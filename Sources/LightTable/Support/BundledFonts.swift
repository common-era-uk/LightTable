import AppKit
import CoreText

/// Makes the fonts the layout templates use available even on a Mac that
/// doesn't have them installed. Each bundled font is registered for this
/// app only — and only when no font of that name is already installed, so
/// an installed copy always wins and nothing gets registered twice.
enum BundledFonts {
    static func register() {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for url in files where ["otf", "ttf"].contains(url.pathExtension.lowercased()) {
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
            let names = descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
            guard !names.isEmpty, names.contains(where: { NSFont(name: $0, size: 12) == nil }) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
