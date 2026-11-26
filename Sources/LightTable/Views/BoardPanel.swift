import SwiftUI
import AppKit

/// The window's right-hand panel: a thumbnail of every art board, in order.
/// Drag its left edge to widen it and the thumbnails wrap side by side.
/// Click a thumbnail to jump to that board, drag one to reorder the boards,
/// or drop cards dragged from the canvas onto one to move them to that board
/// (the canvas side of that lives in `ImageCardView`'s move gesture, which
/// checks the frames this panel records on the document, all in the
/// window-wide "lightTableWindow" coordinate space).
struct BoardPanel: View {
    @ObservedObject var document: CanvasDocument
    @AppStorage(BoardPanel.widthKey) private var panelWidth: Double = BoardPanel.defaultWidth

    static let widthKey = "boardPanelWidth"
    static let defaultWidth: Double = 320
    static let minWidth: Double = 180
    static let thumbnailScale: Double = 0.15
    private static let padding: Double = 14
    private static let spacing: Double = 14

    @State private var widthBaseline: Double?
    @State private var cellFrames: [Int: CGRect] = [:]
    @State private var draggingIndex: Int?
    @State private var dragTranslation: CGSize = .zero
    @State private var dropSlot: Int?
    @State private var dropIndicator: CGRect?
    @State private var hoveredIndex: Int?

    /// The panel's current width, as the canvas's scroll handling needs it
    /// (read live from defaults, since that handler is installed once).
    static var currentWidth: Double {
        let stored = UserDefaults.standard.double(forKey: widthKey)
        return stored > 0 ? stored : defaultWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Art Boards")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Self.padding)
                .padding(.top, Self.padding)
                .padding(.bottom, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    grid
                        .padding(Self.padding)
                        .frame(maxWidth: .infinity)
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("lightTableWindow")) } action: {
                    document.boardPanelScrollFrame = $0
                }
                Divider()
                HStack {
                    Spacer()
                    Button {
                        addBoard(scrollingWith: proxy)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Add an art board at the end")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .frame(width: panelWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .leading) { resizeHandle }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("lightTableWindow")) } action: {
            document.boardPanelFrame = $0
        }
        .onDisappear {
            document.boardPanelFrame = .zero
            document.boardPanelScrollFrame = .zero
            document.boardPanelCellFrames = [:]
        }
    }

    /// Appends a board, makes it the active one, and brings it into view
    /// both here and on the canvas.
    private func addBoard(scrollingWith proxy: ScrollViewProxy) {
        document.addBoard()
        let index = document.boardSizes.count - 1
        guard let id = document.boardSizes.last?.id else { return }
        document.setActiveBoard(index)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .bottom) }
            NotificationCenter.default.post(name: .scrollToBoard, object: document, userInfo: ["index": index])
        }
    }

    // MARK: - Grid

    private var availableWidth: Double {
        max(panelWidth - Self.padding * 2 - 2, 40)
    }

    private var grid: some View {
        FlowLayout(spacing: Self.spacing) {
            ForEach(Array(document.boardSizes.enumerated()), id: \.element.id) { index, board in
                cell(index)
                    .opacity(draggingIndex == index ? 0.35 : 1)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("boardPanelGrid")) } action: { cellFrames[index] = $0 }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("lightTableWindow")) } action: {
                        document.boardPanelCellFrames[board.id] = $0
                    }
                    .onTapGesture {
                        document.setActiveBoard(index)
                        NotificationCenter.default.post(name: .scrollToBoard, object: document, userInfo: ["index": index])
                    }
                    .gesture(reorderGesture(index))
                    .onHover { hoveredIndex = $0 ? index : (hoveredIndex == index ? nil : hoveredIndex) }
                    .help("Board \(index + 1) — click to go to it, drag to reorder")
                    .id(board.id)
            }
        }
        .coordinateSpace(name: "boardPanelGrid")
        .overlay(alignment: .topLeading) { dragOverlay }
    }

    private func scale(for size: CGSize) -> Double {
        min(Self.thumbnailScale, availableWidth / max(size.width, 1))
    }

    private func cell(_ index: Int) -> some View {
        let size = document.boardDisplaySize(index)
        let scale = scale(for: size)
        let isDropHover = document.boardPanelDropTarget == index
        let isActive = document.activeBoardIndex == index
        let outline: Color = isDropHover || isActive ? .accentColor
            : (hoveredIndex == index ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.2))
        return VStack(spacing: 5) {
            BoardThumbnail(
                document: document,
                items: document.items(onBoard: index),
                boardSize: size,
                color: document.boardColor(index, fallback: Color(nsColor: .textBackgroundColor)),
                scale: scale
            )
            .equatable()
            .frame(width: size.width * scale, height: size.height * scale)
            .overlay(
                Rectangle()
                    .stroke(outline, lineWidth: isDropHover ? 4 : (isActive || hoveredIndex == index ? 2 : 1))
            )
            Text("\(index + 1)")
                .font(.caption.bold())
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Reordering

    private func reorderGesture(_ index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("boardPanelGrid"))
            .onChanged { value in
                draggingIndex = index
                dragTranslation = value.translation
                let (slot, indicator) = insertionSlot(at: value.location)
                // Dropping right where it already is changes nothing — no
                // indicator for those two slots.
                if slot == index || slot == index + 1 {
                    dropSlot = nil
                    dropIndicator = nil
                } else {
                    dropSlot = slot
                    dropIndicator = indicator
                }
            }
            .onEnded { _ in
                if let slot = dropSlot {
                    let destination = slot > index ? slot - 1 : slot
                    document.moveBoard(from: index, to: destination)
                }
                draggingIndex = nil
                dragTranslation = .zero
                dropSlot = nil
                dropIndicator = nil
            }
    }

    /// Where a dragged thumbnail would land if dropped at `point`: the
    /// position in the board order (0 = before the first), plus the line
    /// that shows it — beside the nearest thumbnail when it shares a row
    /// with others, above or below it when it's alone on its row.
    private func insertionSlot(at point: CGPoint) -> (Int, CGRect) {
        let frames = document.boardSizes.indices.compactMap { index in cellFrames[index].map { (index, $0) } }
        guard let (index, frame) = frames.min(by: { distance(point, $0.1) < distance(point, $1.1) }) else {
            return (0, .zero)
        }
        let sharesRow = frames.contains { $0.0 != index && $0.1.minY < frame.maxY && $0.1.maxY > frame.minY }
        let gap = Self.spacing / 2
        if sharesRow {
            let after = point.x > frame.midX
            let x = after ? frame.maxX + gap : frame.minX - gap
            return (after ? index + 1 : index, CGRect(x: x - 1.5, y: frame.minY, width: 3, height: frame.height))
        } else {
            let after = point.y > frame.midY
            let y = after ? frame.maxY + gap : frame.minY - gap
            return (after ? index + 1 : index, CGRect(x: frame.minX, y: y - 1.5, width: frame.width, height: 3))
        }
    }

    private func distance(_ point: CGPoint, _ rect: CGRect) -> Double {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    @ViewBuilder
    private var dragOverlay: some View {
        ZStack(alignment: .topLeading) {
            if let indicator = dropIndicator {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: indicator.width, height: indicator.height)
                    .offset(x: indicator.minX, y: indicator.minY)
            }
            if let index = draggingIndex, let frame = cellFrames[index], document.boardSizes.indices.contains(index) {
                cell(index)
                    .frame(width: frame.width, height: frame.height)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    .offset(x: frame.minX + dragTranslation.width, y: frame.minY + dragTranslation.height)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Resizing

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let baseline = widthBaseline ?? panelWidth
                        if widthBaseline == nil { widthBaseline = baseline }
                        let windowWidth = Double(NSApp.keyWindow?.frame.width ?? 2000)
                        let maxWidth = max(Self.minWidth, windowWidth - 360)
                        panelWidth = min(max(baseline - value.translation.width, Self.minWidth), maxWidth)
                    }
                    .onEnded { _ in widthBaseline = nil }
            )
    }
}

/// A miniature of one art board — its background and everything on it,
/// drawn at full size and scaled down. Equatable so the panel doesn't
/// redraw every thumbnail on each unrelated change (a card being dragged,
/// say); it only redraws when that board's own content changes.
private struct BoardThumbnail: View, Equatable {
    let document: CanvasDocument
    let items: [CanvasItem]
    let boardSize: CGSize
    let color: Color
    let scale: Double

    static func == (lhs: BoardThumbnail, rhs: BoardThumbnail) -> Bool {
        lhs.items == rhs.items && lhs.boardSize == rhs.boardSize && lhs.color == rhs.color && lhs.scale == rhs.scale
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            color
            ForEach(items) { item in
                Group {
                    if item.kind == .text {
                        TextItemContentView(item: item, width: item.width, height: item.height)
                    } else {
                        CroppedImageView(document: document, item: item, width: item.width, height: item.height)
                    }
                }
                .offset(x: item.x, y: item.y)
            }
        }
        .frame(width: boardSize.width, height: boardSize.height, alignment: .topLeading)
        .clipped()
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: boardSize.width * scale, height: boardSize.height * scale, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
    }
}

/// Lays its children out left to right, wrapping onto a new row when the
/// next one wouldn't fit; each row is centred.
private struct FlowLayout: Layout {
    var spacing: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * Double(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: Double = 0
        var height: Double = 0
    }

    private func rows(for subviews: Subviews, width: Double) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, needed > width {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// What follows the cursor while cards dragged from the canvas are over the
/// Art Boards panel — the canvas itself is clipped at the panel's edge, so
/// without this the cards would seem to slide underneath it. Drawn at the
/// panel's thumbnail scale, in their own arrangement.
struct BoardPanelDragPreview: View {
    @ObservedObject var document: CanvasDocument

    var body: some View {
        if let location = document.boardPanelDragPreview {
            let dragged = document.items.filter { document.selectedIDs.contains($0.id) }
            let minX = dragged.map(\.x).min() ?? 0
            let minY = dragged.map(\.y).min() ?? 0
            let width = (dragged.map { $0.x + $0.width }.max() ?? 0) - minX
            let height = (dragged.map { $0.y + $0.height }.max() ?? 0) - minY
            let scale = min(BoardPanel.thumbnailScale, 160 / max(width, height, 1))
            ZStack(alignment: .topLeading) {
                ForEach(dragged) { item in
                    Group {
                        if item.kind == .text {
                            TextItemContentView(item: item, width: item.width, height: item.height)
                        } else {
                            CroppedImageView(document: document, item: item, width: item.width, height: item.height)
                        }
                    }
                    .offset(x: item.x - minX, y: item.y - minY)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width * scale, height: height * scale, alignment: .topLeading)
            .opacity(0.85)
            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
            .offset(x: location.x - width * scale / 2, y: location.y - height * scale / 2)
            .allowsHitTesting(false)
        }
    }
}
