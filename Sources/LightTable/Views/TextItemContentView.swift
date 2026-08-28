import SwiftUI

/// Renders a text item's content — a text *field* doesn't wrap (only an
/// explicit Return breaks a line; anything wider than the frame just
/// clips, the same as an oversized image would), a text *box* wraps within
/// its given width, like a paragraph. Shared between the interactive canvas
/// card and the flat export renderer, mirroring `CroppedImageView`.
struct TextItemContentView: View {
    let item: CanvasItem
    let width: Double
    let height: Double

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
    }
}
