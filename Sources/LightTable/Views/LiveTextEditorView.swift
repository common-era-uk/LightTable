import SwiftUI
import AppKit

/// A borderless, AppKit-backed text editor for editing a text item's
/// content directly in place on the canvas, replacing the old modal "Edit
/// Text" sheet. SwiftUI's `TextEditor` always wraps and can't be configured
/// not to — but a text *field* needs to grow without wrapping (only an
/// explicit Return breaks a line), so this wraps `NSTextView` directly,
/// configured to either wrap within `width` (a box) or grow freely (a
/// field), matching the two layouts `TextItemContentView` renders when the
/// item isn't being edited.
struct LiveTextEditorView: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let textColor: Color
    let tracking: Double
    let lineSpacing: Double
    let alignment: NSTextAlignment
    let wraps: Bool
    /// Called whenever the text view stops being first responder, for any
    /// reason — a click elsewhere, a formatting control taking focus, or
    /// Escape — so the just-typed text gets flushed to disk. Deliberately
    /// doesn't end the editing session itself (that stays driven by explicit
    /// user actions the canvas already handles), since focus can leave the
    /// text view without the user meaning to stop editing at all.
    let onFocusLost: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onFocusLost: onFocusLost)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = !wraps
        if let container = textView.textContainer {
            container.widthTracksTextView = wraps
            if !wraps {
                container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            }
        }
        textView.string = text
        applyStyle(to: textView)
        DispatchQueue.main.async {
            guard let window = textView.window else { return }
            window.makeFirstResponder(textView)
            let end = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
        }
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.text = $text
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selectedRange)
        }
        applyStyle(to: textView)
    }

    private func applyStyle(to textView: NSTextView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        // Pins the exact line height (ascender/descender only, no font
        // leading) rather than leaving `NSLayoutManager` to compute its own
        // "natural" one — the same `min == max == this value` constraint
        // `CoreTextRenderView` feeds Core Text for the static display, via
        // `CanvasItem.resolvedLineHeight`, so line spacing can't visibly
        // shift when entering or leaving inline editing.
        let lineHeight = (font.ascender - font.descender) * lineSpacing
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        let nsColor = NSColor(textColor)
        textView.font = font
        textView.textColor = nsColor
        textView.defaultParagraphStyle = paragraph
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: nsColor, .paragraphStyle: paragraph, .kern: tracking
        ]
        textView.typingAttributes = attributes
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        let onFocusLost: () -> Void

        init(text: Binding<String>, onFocusLost: @escaping () -> Void) {
            self.text = text
            self.onFocusLost = onFocusLost
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func textDidEndEditing(_ notification: Notification) {
            onFocusLost()
        }
    }
}
