import Foundation
import CoreGraphics
import Combine

/// The image cards' drop-shadow appearance, shared app-wide (not per-folder,
/// unlike canvas/guide color) and persisted across launches via UserDefaults
/// — this is a rendering preference, not part of any one canvas's content.
@MainActor
final class ShadowSettings: ObservableObject {
    static let shared = ShadowSettings()

    @Published var enabled: Bool { didSet { persist() } }
    /// How far the shadow is cast from the card, in points at 100% zoom.
    @Published var distance: Double { didSet { persist() } }
    /// Direction the shadow is cast, in degrees clockwise from straight
    /// down (0°) — so a shadow "falling" normally needs no angle at all.
    @Published var angle: Double { didSet { persist() } }
    /// Blur radius applied to an unselected card; selected cards use a
    /// larger multiple of this to keep their existing "lifted" emphasis.
    @Published var blur: Double { didSet { persist() } }
    @Published var opacity: Double { didSet { persist() } }

    static let defaultDistance: Double = 0
    static let defaultAngle: Double = 0
    static let defaultBlur: Double = 2
    static let defaultOpacity: Double = 0.33

    /// The shadow's offset in view-space points, derived from `distance` and
    /// `angle` (0° = straight down, increasing clockwise).
    var offset: CGSize {
        let radians = angle * .pi / 180
        return CGSize(width: distance * sin(radians), height: distance * cos(radians))
    }

    private enum Keys {
        static let enabled = "shadowEnabled"
        static let distance = "shadowDistance"
        static let angle = "shadowAngle"
        static let blur = "shadowBlur"
        static let opacity = "shadowOpacity"
    }

    private init() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        distance = defaults.object(forKey: Keys.distance) as? Double ?? Self.defaultDistance
        angle = defaults.object(forKey: Keys.angle) as? Double ?? Self.defaultAngle
        blur = defaults.object(forKey: Keys.blur) as? Double ?? Self.defaultBlur
        opacity = defaults.object(forKey: Keys.opacity) as? Double ?? Self.defaultOpacity
    }

    func resetToDefaults() {
        distance = Self.defaultDistance
        angle = Self.defaultAngle
        blur = Self.defaultBlur
        opacity = Self.defaultOpacity
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: Keys.enabled)
        defaults.set(distance, forKey: Keys.distance)
        defaults.set(angle, forKey: Keys.angle)
        defaults.set(blur, forKey: Keys.blur)
        defaults.set(opacity, forKey: Keys.opacity)
    }
}
