import SwiftUI
import AppKit
import CoreText

/// Renders a text item's content when it *isn't* being edited — a text
/// *field* doesn't wrap (only an explicit Return breaks a line; anything
/// wider than the frame just clips, the same as an oversized image would),
/// a text *box* wraps within its given width, like a paragraph. Shared
/// between the interactive canvas card and the flat export renderer,
/// mirroring `CroppedImageView`.
///
/// Draws directly with Core Text into a `Canvas` rather than using SwiftUI's
/// own `Text` — needed for real paragraph justification (`TextAlignment` has
/// no justified case), and it keeps every alignment pixel-for-pixel
/// consistent with `LiveTextEditorView`'s line-height model (see
/// `CanvasItem.resolvedLineHeight`), so line spacing doesn't visibly shift
/// when entering or leaving inline editing. A `Canvas`, unlike an embedded
/// `NSTextView`, has no real view of its own to intercept the card's own
/// click/drag/double-click gestures (an embedded `NSTextView` was tried here
/// first and reliably swallowed them regardless of
/// `isEditable`/`isSelectable`/a `hitTest` override).
struct TextItemContentView: View {
    let item: CanvasItem
    let width: Double
    let height: Double
    /// Shows a small red "overset text" badge when the content no longer
    /// fits its frame — on for the interactive canvas card, off for the flat
    /// export renderer (a badge has no place in an exported image).
    var showOverflowIndicator: Bool = false

    var body: some View {
        CoreTextRenderView(item: item)
            .frame(width: width, height: height, alignment: .topLeading)
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

    /// Whether the content, laid out at its actual font/spacing settings, no
    /// longer fits the frame it's been given — measured with
    /// `NSAttributedString`, using the exact same paragraph style
    /// `CoreTextRenderView` actually draws with. A text *box* wraps at
    /// `width`, so only its height can overflow; a text *field* never
    /// wraps, so its natural, unconstrained size is measured directly and
    /// either dimension — too wide, or too tall from an explicit Return —
    /// counts as overset.
    private var isOverflowing: Bool {
        guard width > 0, height > 0, !item.text.isEmpty else { return false }
        let attributed = CoreTextRenderView.attributedString(for: item)
        let measureWidth = item.isTextBox ? width : Double.greatestFiniteMagnitude
        let bounding = attributed.boundingRect(
            with: CGSize(width: measureWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        )
        if item.isTextBox {
            return bounding.height > height + 0.5
        }
        return bounding.width > width + 0.5 || bounding.height > height + 0.5
    }
}

/// Draws a text item's content directly with Core Text into a `Canvas` —
/// pure drawing, with no backing `NSView` of its own, so it can never
/// interfere with the card's own gestures the way an embedded `NSTextView`
/// did.
private struct CoreTextRenderView: View {
    let item: CanvasItem

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cgContext in
                Self.draw(item: item, size: size, in: cgContext)
            }
        }
    }

    /// The exact paragraph style this item renders with — shared with
    /// `TextItemContentView`'s overflow measurement (so the two can never
    /// disagree about how tall the content actually is) and built on
    /// `CanvasItem.resolvedLineHeight`, the same line-height model
    /// `LiveTextEditorView` uses while editing.
    static func paragraphStyle(for item: CanvasItem) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = item.nsTextAlignment
        let lineHeight = item.resolvedLineHeight
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        return paragraph
    }

    static func attributedString(for item: CanvasItem) -> NSAttributedString {
        NSAttributedString(string: item.text, attributes: [
            .font: item.resolvedFont,
            .foregroundColor: NSColor(item.textColor?.color ?? .primary),
            .paragraphStyle: paragraphStyle(for: item),
            .kern: item.letterSpacing
        ])
    }

    private static func draw(item: CanvasItem, size: CGSize, in cgContext: CGContext) {
        guard !item.text.isEmpty, size.width > 0, size.height > 0 else { return }

        let attributed = attributedString(for: item)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)

        // A text box wraps and fills the given width; a field never wraps,
        // so its natural (unconstrained) width governs how it's positioned
        // within the frame — matching a plain, left/center/right-aligned
        // block, same as the old SwiftUI `Text`-based rendering did via
        // `.fixedSize(horizontal: true, ...)` plus a per-alignment frame.
        let containerWidth: CGFloat
        let originX: CGFloat
        if item.isTextBox {
            containerWidth = size.width
            originX = 0
        } else {
            let naturalSize = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRange(location: 0, length: 0), nil,
                CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude), nil
            )
            containerWidth = max(naturalSize.width, 1)
            switch item.textAlignment {
            case .leading, .justify: originX = 0
            case .center: originX = (size.width - containerWidth) / 2
            case .trailing: originX = size.width - containerWidth
            }
        }

        // Tall enough to lay out every line without Core Text truncating it
        // internally — any overflow past the item's actual frame is left to
        // the caller's `.clipped()`, matching how overset content already
        // works (and what the overset badge measures).
        let neededHeight = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude), nil
        ).height
        let containerHeight = max(size.height, neededHeight)

        cgContext.saveGState()
        // Core Text always lays text into a bottom-left-origin space, but
        // this Canvas's context (like every other SwiftUI drawing surface)
        // is top-left with Y increasing downward — flipping here converts
        // between the two so the first line lands at the visual top rather
        // than the bottom (or upside down).
        cgContext.translateBy(x: 0, y: size.height)
        cgContext.scaleBy(x: 1, y: -1)
        let path = CGPath(rect: CGRect(x: originX, y: size.height - containerHeight, width: containerWidth, height: containerHeight), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, cgContext)
        cgContext.restoreGState()
    }
}
