import Foundation
import CoreGraphics

/// A built-in page layout for the sidebar. Applying one repositions the
/// images already on a page into `imageSlots` (left-to-right) and adds the
/// template's own text — it never adds or removes images. Frames are in
/// the 1920 × 1080 page space these templates are designed for.
struct LayoutTemplate: Identifiable {
    enum SlotMode {
        /// The whole image, scaled to fit inside the slot and centred.
        case fit
        /// The image cropped to cover the slot exactly, crop centred.
        case fill
    }

    struct ImageSlot {
        let frame: CGRect
        let mode: SlotMode
    }

    struct TextElement {
        let text: String
        let frame: CGRect
        let fontName: String
        let fontSize: Double
        let letterSpacing: Double
        /// Replaced by the photographer's name (in capitals) when applied.
        let isPhotographerName: Bool
    }

    let id: String
    let name: String
    let imageSlots: [ImageSlot]
    let texts: [TextElement]
    let backgroundColor: RGBAColor?

    static let pageSize = CGSize(width: 1920, height: 1080)

    var requiresPhotographerName: Bool {
        texts.contains { $0.isPhotographerName }
    }
}

extension LayoutTemplate {
    private static let pageBackgroundTitle = RGBAColor(red: 0.9214347, green: 0.9214347, blue: 0.9214347, alpha: 0.8470588)
    private static let pageBackgroundClosing = RGBAColor(red: 0.9019608, green: 0.9019608, blue: 0.9019608, alpha: 0.8470588)

    static let all: [LayoutTemplate] = [
        LayoutTemplate(
            id: "title",
            name: "Title",
            imageSlots: [
                ImageSlot(frame: CGRect(x: 459.20, y: 164.40, width: 1001.60, height: 751.20), mode: .fit),
            ],
            texts: [
                TextElement(text: "COMMON ERA", frame: CGRect(x: 728.07, y: 58.87, width: 463.86, height: 59.76),
                            fontName: "APKArchivr21-Regular", fontSize: 48, letterSpacing: 0, isPhotographerName: false),
                TextElement(text: "EDVINAS BRUZAS", frame: CGRect(x: 459.77, y: 961.37, width: 994.67, height: 48.64),
                            fontName: "PublicoTextMono-Roman", fontSize: 40, letterSpacing: 1.465916895604396, isPhotographerName: true),
            ],
            backgroundColor: pageBackgroundTitle
        ),
        LayoutTemplate(
            id: "two-portraits",
            name: "Two Portraits",
            imageSlots: [
                ImageSlot(frame: CGRect(x: 229.83, y: 99.97, width: 660.05, height: 880.06), mode: .fit),
                ImageSlot(frame: CGRect(x: 1030.12, y: 99.97, width: 660.05, height: 880.06), mode: .fit),
            ],
            texts: [],
            backgroundColor: nil
        ),
        LayoutTemplate(
            id: "half-bleed-left",
            name: "Half Bleed Left",
            imageSlots: [
                ImageSlot(frame: CGRect(x: 0, y: 0, width: 960, height: 1080), mode: .fill),
                ImageSlot(frame: CGRect(x: 1109.98, y: 99.97, width: 660.05, height: 880.06), mode: .fit),
            ],
            texts: [],
            backgroundColor: nil
        ),
        LayoutTemplate(
            id: "full-bleed",
            name: "Full Bleed",
            imageSlots: [
                ImageSlot(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), mode: .fill),
            ],
            texts: [],
            backgroundColor: nil
        ),
        LayoutTemplate(
            id: "half-bleed-right",
            name: "Half Bleed Right",
            imageSlots: [
                ImageSlot(frame: CGRect(x: 149.98, y: 99.97, width: 660.05, height: 880.06), mode: .fit),
                ImageSlot(frame: CGRect(x: 960, y: 0, width: 960, height: 1080), mode: .fill),
            ],
            texts: [],
            backgroundColor: nil
        ),
        LayoutTemplate(
            id: "single-landscape",
            name: "Single Landscape",
            imageSlots: [
                ImageSlot(frame: CGRect(x: 370.29, y: 97.72, width: 1179.42, height: 884.56), mode: .fit),
            ],
            texts: [],
            backgroundColor: nil
        ),
        LayoutTemplate(
            id: "three-portraits",
            name: "Three Portraits",
            imageSlots: [
                ImageSlot(frame: CGRect(x: 140.34, y: 211.81, width: 492.28, height: 656.37), mode: .fit),
                ImageSlot(frame: CGRect(x: 713.86, y: 211.81, width: 492.28, height: 656.37), mode: .fit),
                ImageSlot(frame: CGRect(x: 1287.38, y: 211.81, width: 492.28, height: 656.37), mode: .fit),
            ],
            texts: [],
            backgroundColor: nil
        ),
        LayoutTemplate(
            id: "closing",
            name: "Closing",
            imageSlots: [],
            texts: [
                TextElement(text: "COMMONERA.CO.UK", frame: CGRect(x: 568.09, y: 496.15, width: 783.81, height: 87.71),
                            fontName: "APKArchivr21-Regular", fontSize: 64, letterSpacing: 0, isPhotographerName: false),
            ],
            backgroundColor: pageBackgroundClosing
        ),
    ]

    static func named(_ id: String) -> LayoutTemplate? {
        all.first { $0.id == id }
    }

    /// Where an image with width/height `aspect` lands in `slot`, and the
    /// crop it needs — fit keeps the whole image inside the slot, fill crops
    /// it (centred) to cover the slot exactly.
    static func placement(of slot: ImageSlot, imageAspect aspect: Double) -> (frame: CGRect, crop: CGRect) {
        let box = slot.frame
        let aspect = aspect > 0 ? aspect : 1
        let boxAspect = box.width / max(box.height, 0.0001)
        switch slot.mode {
        case .fit:
            let size = aspect > boxAspect
                ? CGSize(width: box.width, height: box.width / aspect)
                : CGSize(width: box.height * aspect, height: box.height)
            let frame = CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
            return (frame, CGRect(x: 0, y: 0, width: 1, height: 1))
        case .fill:
            let crop: CGRect
            if aspect > boxAspect {
                let width = boxAspect / aspect
                crop = CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
            } else {
                let height = aspect / boxAspect
                crop = CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
            }
            return (box, crop)
        }
    }
}
