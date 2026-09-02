import SwiftUI
import AppKit

/// Renders a text item's content — a text *field* doesn't wrap (only an
/// explicit Return breaks a line; anything wider than the frame just
/// clips, the same as an oversized image would), a text *box* wraps within
/// its given width, like a paragraph. Shared between the interactive canvas
/// card and the flat export renderer, mirroring `CroppedImageView`.
struct TextItemContentView: View {
    let item: CanvasItem
    let width: Double
    let height: Double
    /// Shows a small red "overset text" badge when a text box's content no
    /// longer fits its frame — on for the interactive canvas card, off for
    /// the flat export renderer (a badge has no place in an exported image).
    var showOverflowIndicator: Bool = false

    private var alignment: TextAlignment {
        switch item.textAlignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private var frameAlignment: Alignment {
        switch item.textAlignment {
        case .leading: return .topLeading
        case .center: return .top
        case .trailing: return .topTrailing
        }
    }

    var body: some View {
        Text(item.text)
            .font(.custom(item.fontName, size: item.fontSize))
            .fontWeight(item.isBold ? .bold : .regular)
            .italic(item.isItalic)
            .tracking(item.letterSpacing)
            .lineSpacing(max(item.lineSpacing - 1, 0) * item.fontSize)
            .foregroundStyle(item.textColor?.color ?? .primary)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: !item.isTextBox, vertical: false)
            .frame(width: width, height: height, alignment: frameAlignment)
            .clipped()
            .contentShape(Rectangle())
            .overlay(alignment: .bottomTrailing) {
                if showOverflowIndicator && isOverflowing {
                    Text("…")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 6))
                        // Pulled well clear of the right edge; shifted down
                        // by half its own height so the frame's bottom edge
                        // cuts straight through its vertical center.
                        .offset(x: -60, y: 16)
                        .allowsHitTesting(false)
                }
            }
    }

    /// Whether a text *box*'s content, laid out at its actual font/spacing
    /// settings, is taller than the frame it's been given — measured with
    /// `NSAttributedString` (matching `CroppedImageView`'s use of AppKit for
    /// exact rendering math) rather than trying to read SwiftUI `Text`'s own
    /// layout, which isn't exposed. Text fields don't wrap on their own, so
    /// overflow there is an accepted horizontal clip, not a badge-worthy state.
    private var isOverflowing: Bool {
        guard item.isTextBox, width > 0, height > 0, !item.text.isEmpty else { return false }
        let base = NSFont(name: item.fontName, size: item.fontSize) ?? NSFont.systemFont(ofSize: item.fontSize)
        var traits: NSFontTraitMask = []
        if item.isBold { traits.insert(.boldFontMask) }
        if item.isItalic { traits.insert(.italicFontMask) }
        let font = traits.isEmpty ? base : NSFontManager.shared.convert(base, toHaveTrait: traits)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = max(item.lineSpacing - 1, 0) * item.fontSize
        switch item.textAlignment {
        case .leading: paragraphStyle.alignment = .left
        case .center: paragraphStyle.alignment = .center
        case .trailing: paragraphStyle.alignment = .right
        }

        let attributed = NSAttributedString(string: item.text, attributes: [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .kern: item.letterSpacing
        ])
        let bounding = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return bounding.height > height + 0.5
    }
}
