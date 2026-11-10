import SwiftUI
import AppKit

/// Presents `AutoPagesSheet` when the "Auto-Translate to Pages…" command
/// fires for this window. A modifier rather than more chained calls on
/// `CanvasView.body`, which is already at the type checker's limit.
struct AutoPagesModifier: ViewModifier {
    @ObservedObject var document: CanvasDocument
    let hostWindow: NSWindow?
    @State private var isShowing = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .autoTranslateToPages)) { _ in
                guard hostWindow != nil, hostWindow === NSApp.keyWindow else { return }
                let hasImages = document.items.contains { document.selectedIDs.contains($0.id) && $0.kind == .image }
                if hasImages { isShowing = true }
            }
            .sheet(isPresented: $isShowing) {
                AutoPagesSheet(
                    document: document,
                    imageCount: document.items.filter { document.selectedIDs.contains($0.id) && $0.kind == .image }.count,
                    onCreate: { options, unit in
                        isShowing = false
                        document.autoTranslateToPages(document.selectedIDs, options: options, unit: unit)
                    },
                    onCancel: { isShowing = false }
                )
            }
    }
}

struct AutoPagesSheet: View {
    @ObservedObject var document: CanvasDocument
    let imageCount: Int
    let onCreate: (PageLayoutOptions, BoardSizeUnit) -> Void
    let onCancel: () -> Void

    @State private var unit: BoardSizeUnit
    @State private var pageWidth: Double
    @State private var pageHeight: Double
    @State private var linkMargins = true
    @State private var marginAll: Double
    @State private var marginTop: Double
    @State private var marginRight: Double
    @State private var marginBottom: Double
    @State private var marginLeft: Double
    @State private var gap: Double
    @State private var groupingPercent: Double = 35

    /// Defaults to 1920 × 1080 px with 100 px margins and a 140 px gap — or
    /// the canvas's own size and unit if it's already in Fixed mode.
    init(document: CanvasDocument, imageCount: Int, onCreate: @escaping (PageLayoutOptions, BoardSizeUnit) -> Void, onCancel: @escaping () -> Void) {
        self.document = document
        self.imageCount = imageCount
        self.onCreate = onCreate
        self.onCancel = onCancel
        let startUnit: BoardSizeUnit = document.boardSizeMode == .fixed ? document.boardSizeUnit : .pixels
        let startWidth = document.boardSizeMode == .fixed ? document.fixedBoardWidth : 1920
        let startHeight = document.boardSizeMode == .fixed ? document.fixedBoardHeight : 1080
        let margin = Self.rounded(startUnit.value(fromPoints: 100))
        _unit = State(initialValue: startUnit)
        _pageWidth = State(initialValue: Self.rounded(startUnit.value(fromPoints: startWidth)))
        _pageHeight = State(initialValue: Self.rounded(startUnit.value(fromPoints: startHeight)))
        _marginAll = State(initialValue: margin)
        _marginTop = State(initialValue: margin)
        _marginRight = State(initialValue: margin)
        _marginBottom = State(initialValue: margin)
        _marginLeft = State(initialValue: margin)
        _gap = State(initialValue: Self.rounded(startUnit.value(fromPoints: 140)))
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private var options: PageLayoutOptions {
        func points(_ value: Double) -> Double { unit.points(from: max(value, 0)) }
        return PageLayoutOptions(
            pageWidth: points(pageWidth),
            pageHeight: points(pageHeight),
            marginTop: points(linkMargins ? marginAll : marginTop),
            marginRight: points(linkMargins ? marginAll : marginRight),
            marginBottom: points(linkMargins ? marginAll : marginBottom),
            marginLeft: points(linkMargins ? marginAll : marginLeft),
            gap: points(gap),
            groupingPercent: groupingPercent
        )
    }

    private var pageCount: Int {
        document.previewPageCount(for: document.selectedIDs, groupingPercent: groupingPercent)
    }

    private var isValid: Bool {
        let o = options
        return o.pageWidth > o.marginLeft + o.marginRight && o.pageHeight > o.marginTop + o.marginBottom
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Auto-Translate to Pages")
                .font(.title2.bold())
            Text("Turns this layout into fixed pages. Images that sit close together share a page, in reading order — top row first, left to right. Each page's images are resized to one height to fit inside the margins. The canvas switches to Fixed board size; undo puts everything back.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Page size:")
                numberField($pageWidth)
                Text("×")
                numberField($pageHeight)
                Picker("", selection: $unit) {
                    ForEach(BoardSizeUnit.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 70)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Margins:")
                    Toggle("Link all four", isOn: $linkMargins)
                        .toggleStyle(.checkbox)
                }
                if linkMargins {
                    HStack {
                        Text("All sides")
                            .frame(width: 60, alignment: .leading)
                        numberField($marginAll)
                        Text(unit.label).foregroundStyle(.secondary)
                    }
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                        GridRow {
                            Text("Top"); numberField($marginTop)
                            Text("Bottom"); numberField($marginBottom)
                        }
                        GridRow {
                            Text("Left"); numberField($marginLeft)
                            Text("Right"); numberField($marginRight)
                        }
                    }
                }
            }

            HStack {
                Text("Gap between images on a page:")
                numberField($gap)
                Text(unit.label).foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Group images closer than:")
                    numberField($groupingPercent)
                    Text("% of an image's width")
                        .foregroundStyle(.secondary)
                }
                Text("Higher puts more images on each page; lower splits them up. \(imageCount) image\(imageCount == 1 ? "" : "s") → \(pageCount) page\(pageCount == 1 ? "" : "s").")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Create Pages") { onCreate(options, unit) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || pageCount == 0)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: unit) { oldUnit, newUnit in convert(from: oldUnit, to: newUnit) }
    }

    private func numberField(_ value: Binding<Double>) -> some View {
        TextField("", value: value, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 70)
    }

    /// Re-expresses every length in the newly chosen unit, so changing the
    /// unit relabels the same physical sizes instead of reinterpreting them.
    private func convert(from oldUnit: BoardSizeUnit, to newUnit: BoardSizeUnit) {
        func convert(_ value: Double) -> Double {
            Self.rounded(newUnit.value(fromPoints: oldUnit.points(from: value)))
        }
        pageWidth = convert(pageWidth)
        pageHeight = convert(pageHeight)
        marginAll = convert(marginAll)
        marginTop = convert(marginTop)
        marginRight = convert(marginRight)
        marginBottom = convert(marginBottom)
        marginLeft = convert(marginLeft)
        gap = convert(gap)
    }
}
