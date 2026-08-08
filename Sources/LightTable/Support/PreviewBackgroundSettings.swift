import SwiftUI
import Combine

/// The backdrop shown behind a large image preview (Space bar), shared
/// app-wide and persisted across launches via UserDefaults — same rationale
/// as `ShadowSettings`: a rendering preference, not canvas content.
@MainActor
final class PreviewBackgroundSettings: ObservableObject {
    static let shared = PreviewBackgroundSettings()

    @Published var color: Color { didSet { persist() } }
    @Published var opacity: Double { didSet { persist() } }
    @Published var showFilename: Bool { didSet { persist() } }
    @Published var filenameColor: Color { didSet { persist() } }

    static let defaultColor = Color.black
    static let defaultOpacity: Double = 0.85
    static let defaultShowFilename = true
    static let defaultFilenameColor = Color.white

    private enum Keys {
        static let color = "previewBackgroundColor"
        static let opacity = "previewBackgroundOpacity"
        static let showFilename = "previewShowFilename"
        static let filenameColor = "previewFilenameColor"
    }

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.color),
           let stored = try? JSONDecoder().decode(RGBAColor.self, from: data) {
            color = stored.color
        } else {
            color = Self.defaultColor
        }
        opacity = defaults.object(forKey: Keys.opacity) as? Double ?? Self.defaultOpacity
        showFilename = defaults.object(forKey: Keys.showFilename) as? Bool ?? Self.defaultShowFilename
        if let data = defaults.data(forKey: Keys.filenameColor),
           let stored = try? JSONDecoder().decode(RGBAColor.self, from: data) {
            filenameColor = stored.color
        } else {
            filenameColor = Self.defaultFilenameColor
        }
    }

    func resetToDefaults() {
        color = Self.defaultColor
        opacity = Self.defaultOpacity
        showFilename = Self.defaultShowFilename
        filenameColor = Self.defaultFilenameColor
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(RGBAColor(color: color)) {
            defaults.set(data, forKey: Keys.color)
        }
        defaults.set(opacity, forKey: Keys.opacity)
        defaults.set(showFilename, forKey: Keys.showFilename)
        if let data = try? JSONEncoder().encode(RGBAColor(color: filenameColor)) {
            defaults.set(data, forKey: Keys.filenameColor)
        }
    }
}
