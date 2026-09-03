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

/// A small triangular pointer drawn alongside the formatting panel, tracking
/// the vertical center of the text item it's editing — stands in for the
/// arrow a real `NSPopover` would draw. The panel is a plain positioned
/// overlay rather than an actual `.popover`, since a real popover closes
/// itself on any click back in the text view it's attached to, including a
/// single click that's only meant to reposition the cursor.
struct TextFormattingPanelArrow: Shape {
    let pointsLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsLeft {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

/// The compact formatting controls shown in a popover while a text item is
/// being edited inline on the canvas (see `LiveTextEditorView`) — the
/// direct-manipulation replacement for the old modal "Edit Text" sheet.
/// Every control writes straight to the document as it changes; there's no
/// separate Apply step, since the canvas itself already shows the live
/// result as you type.
struct TextFormattingPopoverView: View {
    @ObservedObject var document: CanvasDocument
    let itemID: UUID

    @State private var fontPanelCoordinator: FontPanelCoordinator?
    @State private var colorPanelCoordinator: TextColorPanelCoordinator?

    private var item: CanvasItem? {
        document.items.first { $0.id == itemID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let item {
                HStack {
                    Text("\(item.fontName), \(Int(item.fontSize))pt")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(item.fontName)
                    Spacer(minLength: 8)
                    Button("Change Font…") { showFontPanel(for: item) }
                        .fixedSize()
                }

                HStack(spacing: 10) {
                    formatButton("B", weight: .bold, isOn: boldBinding)
                    formatButton("I", italic: true, isOn: italicBinding)
                    Spacer()
                    Picker("", selection: alignmentBinding) {
                        Image(systemName: "text.alignleft").tag(TextAlignmentOption.leading)
                        Image(systemName: "text.aligncenter").tag(TextAlignmentOption.center)
                        Image(systemName: "text.alignright").tag(TextAlignmentOption.trailing)
                        Image(systemName: "text.justify").tag(TextAlignmentOption.justify)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                    Button {
                        showColorPanel(for: item)
                    } label: {
                        Circle().fill(item.textColor?.color ?? .primary).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.secondary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .help("Text colour")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Letter Spacing")
                        Spacer()
                        Text(String(format: "%.1f", item.letterSpacing)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: letterSpacingBinding, in: -5...20, onEditingChanged: { editing in
                        if !editing { document.save() }
                    })

                    HStack {
                        Text("Line Height")
                        Spacer()
                        Text(String(format: "%.1f×", item.lineSpacing)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: lineSpacingBinding, in: 0.8...2.5, onEditingChanged: { editing in
                        if !editing { document.save() }
                    })
                }
            }
        }
        .padding(16)
        .frame(width: 330)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    /// A plain, unambiguous on/off button for Bold/Italic — a filled accent
    /// background when active, a light outline otherwise — rather than a
    /// `Toggle`, whose default macOS rendering outside a Form/List reads as
    /// little more than an unlabeled checkbox at this size.
    private func formatButton(_ label: String, weight: Font.Weight = .regular, italic: Bool = false, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(.system(size: 14, weight: weight))
                .italic(italic)
                .frame(width: 30, height: 26)
                .foregroundStyle(isOn.wrappedValue ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn.wrappedValue ? Color.accentColor : Color.secondary.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }

    private var boldBinding: Binding<Bool> {
        Binding(get: { item?.isBold ?? false }, set: { newValue in
            document.updateItem(itemID) { $0.isBold = newValue }
            document.save()
        })
    }

    private var italicBinding: Binding<Bool> {
        Binding(get: { item?.isItalic ?? false }, set: { newValue in
            document.updateItem(itemID) { $0.isItalic = newValue }
            document.save()
        })
    }

    private var alignmentBinding: Binding<TextAlignmentOption> {
        Binding(get: { item?.textAlignment ?? .leading }, set: { newValue in
            document.updateItem(itemID) { $0.textAlignment = newValue }
            document.save()
        })
    }

    private var letterSpacingBinding: Binding<Double> {
        Binding(get: { item?.letterSpacing ?? 0 }, set: { newValue in
            document.updateItem(itemID) { $0.letterSpacing = newValue }
        })
    }

    private var lineSpacingBinding: Binding<Double> {
        Binding(get: { item?.lineSpacing ?? 1.2 }, set: { newValue in
            document.updateItem(itemID) { $0.lineSpacing = newValue }
        })
    }

    private func showFontPanel(for item: CanvasItem) {
        let coordinator = FontPanelCoordinator { newFont in
            document.updateItem(itemID) { current in
                current.fontName = newFont.fontName
                current.fontSize = newFont.pointSize
            }
            document.save()
        }
        fontPanelCoordinator = coordinator
        let manager = NSFontManager.shared
        manager.target = coordinator
        manager.action = #selector(FontPanelCoordinator.changeFont(_:))
        if let currentFont = NSFont(name: item.fontName, size: item.fontSize) {
            manager.setSelectedFont(currentFont, isMultiple: false)
        }
        manager.orderFrontFontPanel(nil)
    }

    private func showColorPanel(for item: CanvasItem) {
        let coordinator = TextColorPanelCoordinator { newColor in
            document.updateItem(itemID) { $0.textColor = RGBAColor(color: newColor) }
            document.save()
        }
        colorPanelCoordinator = coordinator
        let panel = NSColorPanel.shared
        panel.setTarget(coordinator)
        panel.setAction(#selector(TextColorPanelCoordinator.colorChanged(_:)))
        panel.color = NSColor(item.textColor?.color ?? .primary)
        panel.orderFront(nil)
    }
}
