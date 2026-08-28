import SwiftUI
import AppKit

/// Bridges `NSFontManager`'s target-action mechanism (there's no
/// closure-based API, like `NSColorPanel`) into a Swift closure — the same
/// bridging pattern `CanvasView`'s `ColorPanelCoordinator` uses for the
/// canvas/guide color pickers.
private final class FontPanelCoordinator: NSObject {
    let onChange: (NSFont) -> Void

    init(onChange: @escaping (NSFont) -> Void) {
        self.onChange = onChange
    }

    @objc func changeFont(_ sender: NSFontManager?) {
        guard let sender else { return }
        let base = NSFont(name: "Helvetica", size: 12) ?? NSFont.systemFont(ofSize: 12)
        onChange(sender.convert(base))
    }
}

private final class TextColorPanelCoordinator: NSObject {
    let onChange: (Color) -> Void

    init(onChange: @escaping (Color) -> Void) {
        self.onChange = onChange
    }

    @objc func colorChanged(_ sender: NSColorPanel) {
        onChange(Color(nsColor: sender.color))
    }
}

/// Edits a text item's content and formatting — content, font (via the
/// system font panel), size, bold/italic, letter spacing, line height,
/// alignment, and color. Opened by double-clicking a text item, taking the
/// place of `CropView` for image items.
struct TextFormatSheet: View {
    @ObservedObject var document: CanvasDocument
    let itemID: UUID
    @Binding var isPresented: Bool

    @State private var text: String
    @State private var fontName: String
    @State private var fontSize: Double
    @State private var isBold: Bool
    @State private var isItalic: Bool
    @State private var letterSpacing: Double
    @State private var lineSpacing: Double
    @State private var textAlignment: TextAlignmentOption
    @State private var textColor: Color
    @State private var fontPanelCoordinator: FontPanelCoordinator?
    @State private var colorPanelCoordinator: TextColorPanelCoordinator?

    init(document: CanvasDocument, itemID: UUID, isPresented: Binding<Bool>) {
        self.document = document
        self.itemID = itemID
        self._isPresented = isPresented
        let item = document.items.first { $0.id == itemID }
        _text = State(initialValue: item?.text ?? "")
        _fontName = State(initialValue: item?.fontName ?? "Helvetica")
        _fontSize = State(initialValue: item?.fontSize ?? 36)
        _isBold = State(initialValue: item?.isBold ?? false)
        _isItalic = State(initialValue: item?.isItalic ?? false)
        _letterSpacing = State(initialValue: item?.letterSpacing ?? 0)
        _lineSpacing = State(initialValue: item?.lineSpacing ?? 1.2)
        _textAlignment = State(initialValue: item?.textAlignment ?? .leading)
        _textColor = State(initialValue: item?.textColor?.color ?? .primary)
    }

    private var isTextBox: Bool {
        document.items.first { $0.id == itemID }?.isTextBox ?? false
    }

    /// The font with bold/italic traits baked in, via the same
    /// `NSFontManager` trait conversion the font panel itself uses — so the
    /// editor below shows live formatting instead of a separate plain
    /// editor plus a read-only preview.
    private var styledFont: NSFont {
        let base = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        var traits: NSFontTraitMask = []
        if isBold { traits.insert(.boldFontMask) }
        if isItalic { traits.insert(.italicFontMask) }
        guard !traits.isEmpty else { return base }
        return NSFontManager.shared.convert(base, toHaveTrait: traits)
    }

    private var swiftUIAlignment: TextAlignment {
        switch textAlignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isTextBox ? "Edit Text Box" : "Edit Text Field")
                .font(.title2.bold())

            TextEditor(text: $text)
                .font(Font(styledFont as CTFont))
                .foregroundStyle(textColor)
                .tracking(letterSpacing)
                .lineSpacing(max(lineSpacing - 1, 0) * fontSize)
                .multilineTextAlignment(swiftUIAlignment)
                .frame(height: isTextBox ? 180 : 90)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            HStack {
                Text("\(fontName), \(Int(fontSize))pt")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Change Font…") { showFontPanel() }
            }

            HStack(spacing: 16) {
                Toggle("Bold", isOn: $isBold)
                Toggle("Italic", isOn: $isItalic)
                Spacer()
                Picker("", selection: $textAlignment) {
                    Image(systemName: "text.alignleft").tag(TextAlignmentOption.leading)
                    Image(systemName: "text.aligncenter").tag(TextAlignmentOption.center)
                    Image(systemName: "text.alignright").tag(TextAlignmentOption.trailing)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
                Button {
                    showColorPanel()
                } label: {
                    Circle().fill(textColor).frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .help("Text colour")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Letter Spacing")
                    Spacer()
                    Text(String(format: "%.1f", letterSpacing)).foregroundStyle(.secondary).monospacedDigit()
                }
                Slider(value: $letterSpacing, in: -5...20)

                HStack {
                    Text("Line Height")
                    Spacer()
                    Text(String(format: "%.1f×", lineSpacing)).foregroundStyle(.secondary).monospacedDigit()
                }
                Slider(value: $lineSpacing, in: 0.8...2.5)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { apply() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func showFontPanel() {
        let coordinator = FontPanelCoordinator { newFont in
            fontName = newFont.fontName
            fontSize = newFont.pointSize
        }
        fontPanelCoordinator = coordinator
        let manager = NSFontManager.shared
        manager.target = coordinator
        manager.action = #selector(FontPanelCoordinator.changeFont(_:))
        if let currentFont = NSFont(name: fontName, size: fontSize) {
            manager.setSelectedFont(currentFont, isMultiple: false)
        }
        manager.orderFrontFontPanel(nil)
    }

    private func showColorPanel() {
        let coordinator = TextColorPanelCoordinator { newColor in
            textColor = newColor
        }
        colorPanelCoordinator = coordinator
        let panel = NSColorPanel.shared
        panel.setTarget(coordinator)
        panel.setAction(#selector(TextColorPanelCoordinator.colorChanged(_:)))
        panel.color = NSColor(textColor)
        panel.orderFront(nil)
    }

    private func apply() {
        document.registerUndoCheckpoint(actionName: "Edit Text")
        document.updateItem(itemID) { current in
            current.text = text
            current.fontName = fontName
            current.fontSize = fontSize
            current.isBold = isBold
            current.isItalic = isItalic
            current.letterSpacing = letterSpacing
            current.lineSpacing = lineSpacing
            current.textAlignment = textAlignment
            current.textColor = RGBAColor(color: textColor)
        }
        document.save()
        isPresented = false
    }
}
