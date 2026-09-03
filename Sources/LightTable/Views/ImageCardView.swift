import SwiftUI
import AppKit

enum CardCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

struct ImageCardView: View {
    @ObservedObject var document: CanvasDocument
    let itemID: UUID
    @Binding var cropModeItemID: UUID?
    @Binding var textFormatItemID: UUID?
    let showFilenames: Bool
    let zoom: CGFloat
    /// Where this item's board's local (0,0) lands in the shared,
    /// multi-board display space — all interactive math below works in that
    /// shared space (matching where guides and the drag gesture's own
    /// "canvas" coordinate space live), only converting back to the item's
    /// board-local storage at the point it's committed.
    let boardOrigin: CGPoint

    @State private var liveRect: CGRect?
    @State private var dragBaseline: CGRect?
    @State private var groupResizeBBoxBaseline: CGRect?
    @State private var groupResizeOriginsSnapshot: [CGPoint]?
    /// Whether the in-progress single-item resize is a true proportional
    /// scale (⌘ or ⌥ held on a text item, or any drag on an image) rather
    /// than a text item's free independent-width/height resize — decides
    /// whether `onEnded` also scales `fontSize`.
    @State private var isTextScaleMode = false
    /// Whether a file dragged from Finder is currently hovering this card —
    /// drawn as a highlighted bounding box so the drop-to-replace target is
    /// obvious before the file is actually dropped.
    @State private var isReplaceDropTargeted = false
    @ObservedObject private var shadowSettings = ShadowSettings.shared

    private let minSize: Double = 40

    private var item: CanvasItem? {
        document.items.first { $0.id == itemID }
    }

    var body: some View {
        if let item {
            if item.kind == .text, textFormatItemID == itemID {
                editingTextCard(item: item)
            } else {
                interactiveCard(item: item)
            }
        }
    }

    /// The normal, interactive card — selectable, draggable, resizable, with
    /// its context menu — used for every item except a text item currently
    /// being edited inline (see `editingTextCard`), which swaps out all of
    /// this for a plain live text editor so clicks and drags inside it go
    /// straight to the text view instead of competing with these gestures.
    private func interactiveCard(item: CanvasItem) -> some View {
        let isSelected = document.selectedIDs.contains(itemID)
        let groupOffset = isSelected ? document.groupDragOffset : .zero
        let rect = currentRect(for: item, isSelected: isSelected).offsetBy(dx: groupOffset.width, dy: groupOffset.height)

        return ZStack(alignment: .topLeading) {
                cardContent(item: item, rect: rect)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                    .shadow(
                        color: shadowSettings.enabled ? Color(.sRGBLinear, white: 0, opacity: shadowSettings.opacity) : .clear,
                        radius: shadowSettings.enabled ? shadowSettings.blur * (isSelected ? 3 : 1) : 0,
                        x: shadowSettings.enabled ? shadowSettings.offset.width : 0,
                        y: shadowSettings.enabled ? shadowSettings.offset.height : 0
                    )
                    .gesture(moveGesture)
                    .onTapGesture(count: 2) {
                        if item.kind == .text { beginEditingText() } else { cropModeItemID = itemID }
                    }
                    .onTapGesture { selectOnTap() }
                    .contextMenu {
                        if document.selectedIDs.contains(itemID), document.selectedIDs.count > 1 {
                            Button("Create Grid…") {
                                NotificationCenter.default.post(name: .createGrid, object: nil)
                            }
                            Divider()
                        }
                        Button(item.kind == .text ? "Edit Text" : "Crop") {
                            let targets = contextMenuTargets()
                            if targets.count == 1, let id = targets.first {
                                if item.kind == .text { beginEditingText() } else { cropModeItemID = id }
                            }
                        }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                        Button("Duplicate") {
                            document.duplicateItems(contextMenuTargets())
                        }
                        .keyboardShortcut("d", modifiers: .command)
                        Button("Remove from Canvas") {
                            document.removeFromCanvas(contextMenuTargets())
                        }
                        .keyboardShortcut(.delete, modifiers: [])
                        if previewTargetsIncludeImage {
                            Button("Delete from Folder") {
                                document.deleteItems(contextMenuTargets())
                            }
                            .keyboardShortcut(.delete, modifiers: .command)
                        }
                        Divider()
                        Button("Bring Forward") {
                            document.bringForward(contextMenuTargets())
                        }
                        .keyboardShortcut("]", modifiers: .command)
                        Button("Bring to Front") {
                            document.bringToFront(contextMenuTargets())
                        }
                        .keyboardShortcut("]", modifiers: [.command, .shift])
                        Button("Send Backward") {
                            document.sendBackward(contextMenuTargets())
                        }
                        .keyboardShortcut("[", modifiers: .command)
                        Button("Send to Back") {
                            document.sendToBack(contextMenuTargets())
                        }
                        .keyboardShortcut("[", modifiers: [.command, .shift])
                    }

                if isSelected {
                    ForEach(CardCorner.allCases, id: \.self) { corner in
                        handle(corner, rect: rect)
                    }
                }

                if showFilenames, item.kind == .image {
                    filenameLabel(item.filename, rect: rect)
                }
            }
            .frame(width: rect.width, height: rect.height, alignment: .topLeading)
            .position(x: rect.midX, y: rect.midY)
    }

    /// A text item currently being edited inline — a live, styled
    /// `NSTextView` filling the card's frame — `CanvasView` shows a floating
    /// formatting panel alongside it (see `TextFormattingPopoverView`)
    /// instead of the old modal sheet. None of `interactiveCard`'s
    /// selection/drag/resize gestures are attached here, so every click and
    /// drag goes straight to normal text editing (placing the cursor,
    /// selecting a range) instead of competing with them.
    private func editingTextCard(item: CanvasItem) -> some View {
        let rect = currentRect(for: item, isSelected: true)
        return LiveTextEditorView(
            text: textBinding,
            font: item.resolvedFont,
            textColor: item.textColor?.color ?? .primary,
            tracking: item.letterSpacing,
            lineSpacing: item.lineSpacing,
            alignment: item.nsTextAlignment,
            wraps: item.isTextBox,
            onFocusLost: { document.save() }
        )
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .clipped()
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.accentColor, lineWidth: 3)
        )
        .position(x: rect.midX, y: rect.midY)
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { document.items.first { $0.id == itemID }?.text ?? "" },
            set: { newValue in document.updateItem(itemID) { $0.text = newValue } }
        )
    }

    /// Registers one "Edit Text" undo step and enters inline editing —
    /// shared by the double-click gesture and the context menu's "Edit
    /// Text" button.
    private func beginEditingText() {
        document.registerUndoCheckpoint(actionName: "Edit Text")
        textFormatItemID = itemID
    }

    @ViewBuilder
    private func cardContent(item: CanvasItem, rect: CGRect) -> some View {
        if item.kind == .text {
            TextItemContentView(item: item, width: rect.width, height: rect.height, showOverflowIndicator: true)
        } else {
            CroppedImageView(document: document, item: item, width: rect.width, height: rect.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 4)
                        .opacity(isReplaceDropTargeted ? 1 : 0)
                )
                .background(
                    Color.accentColor.opacity(isReplaceDropTargeted ? 0.15 : 0)
                )
                .onDrop(of: [.fileURL], isTargeted: $isReplaceDropTargeted) { providers in
                    // Dropping a file directly onto an existing image card
                    // replaces its content in place (same size/position)
                    // instead of adding a new card — this handler, nested
                    // inside the canvas's own file-drop target, takes
                    // priority over it whenever the drop lands on a card.
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url, ImageFileSupport.isImage(url) else { return }
                        DispatchQueue.main.async {
                            document.replaceImage(itemID, with: url)
                        }
                    }
                    return true
                }
        }
    }

    /// The card's rect (in the shared display space) before any group-move
    /// offset: its own live drag rect while being actively resized, a
    /// live-preview scaled rect while it's a bystander to another selected
    /// card's ⌘-group-resize, or just its stored (board-local) frame shifted
    /// to its board's origin otherwise.
    private func currentRect(for item: CanvasItem, isSelected: Bool) -> CGRect {
        if let liveRect {
            return liveRect
        }
        if isSelected,
           let sourceID = document.groupResizeSourceID, sourceID != itemID,
           let scale = document.groupResizeScale,
           let anchor = document.groupResizeAnchor {
            return Self.transformedRect(item.frame.offsetBy(dx: boardOrigin.x, dy: boardOrigin.y), anchor: anchor, scale: scale)
        }
        return item.frame.offsetBy(dx: boardOrigin.x, dy: boardOrigin.y)
    }

    private func filenameLabel(_ filename: String, rect: CGRect) -> some View {
        HStack {
            Text(filename)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
            Spacer(minLength: 0)
        }
        .frame(width: rect.width)
        .position(x: rect.width / 2, y: rect.height + 16)
        .allowsHitTesting(false)
    }

    private func handle(_ corner: CardCorner, rect: CGRect) -> some View {
        let position: CGPoint
        switch corner {
        case .topLeft: position = .zero
        case .topRight: position = CGPoint(x: rect.width, y: 0)
        case .bottomLeft: position = CGPoint(x: 0, y: rect.height)
        case .bottomRight: position = CGPoint(x: rect.width, y: rect.height)
        }
        return Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: 14, height: 14)
            .position(position)
            .gesture(cornerDragGesture(corner))
    }

    private func selectOnTap() {
        // A plain click on a different card while another text item is being
        // edited inline ends that editing session (a double-click is needed
        // to start editing this one instead).
        if let current = textFormatItemID, current != itemID {
            textFormatItemID = nil
            document.save()
        }
        document.selectedGuideID = nil
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) || modifiers.contains(.command) {
            if document.selectedIDs.contains(itemID) {
                document.selectedIDs.remove(itemID)
            } else {
                document.selectedIDs.insert(itemID)
            }
        } else {
            document.selectedIDs = [itemID]
        }
    }

    /// What a context-menu action should act on: the whole current
    /// selection if this card is already part of it (right-clicking a
    /// member of a multi-selection acts on the group, same as Finder),
    /// otherwise just this card — selecting it first, so the result matches
    /// what's visibly highlighted once the menu closes.
    private func contextMenuTargets() -> Set<UUID> {
        if document.selectedIDs.contains(itemID) {
            return document.selectedIDs
        }
        document.selectedGuideID = nil
        document.selectedIDs = [itemID]
        return [itemID]
    }

    /// Whether `contextMenuTargets()` would include at least one image —
    /// read-only preview of that same target set, so "Delete from Folder"
    /// (which only means anything for a file) can be hidden when the whole
    /// selection is text, without the side effect of actually selecting.
    private var previewTargetsIncludeImage: Bool {
        let ids = document.selectedIDs.contains(itemID) ? document.selectedIDs : [itemID]
        return document.items.contains { ids.contains($0.id) && $0.kind == .image }
    }

    /// Dragging a card that's part of the current selection moves the whole
    /// group together; dragging an unselected card selects just that one.
    /// Snapping is computed from this card's own edges (the one under the
    /// cursor), then applied as one shared offset to the whole group. A card
    /// dragged past its board's boundary lands on whichever board it's now
    /// over, reassigned at the end of the drag (see `onEnded`) — not live,
    /// so the whole group doesn't jitter as it crosses.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
            .onChanged { value in
                if !document.selectedIDs.contains(itemID) {
                    document.selectedIDs = [itemID]
                    document.selectedGuideID = nil
                }
                let baseline = (item?.frame ?? .zero).offsetBy(dx: boardOrigin.x, dy: boardOrigin.y)
                document.groupDragOffset = snappedOffset(clampedGroupOffset(axisConstrained(value.translation)), baseline: baseline)
            }
            .onEnded { value in
                let ids = document.selectedIDs
                let baseline = (item?.frame ?? .zero).offsetBy(dx: boardOrigin.x, dy: boardOrigin.y)
                let offset = snappedOffset(clampedGroupOffset(axisConstrained(value.translation)), baseline: baseline)
                document.registerUndoCheckpoint(actionName: "Move")

                let origins = document.boardOrigins()
                let sizes = document.boardSizes.indices.map { document.boardDisplaySize($0) }
                for id in ids {
                    document.updateItem(id) { current in
                        let oldOrigin = origins.indices.contains(current.boardIndex) ? origins[current.boardIndex] : .zero
                        let globalX = current.x + oldOrigin.x + offset.width
                        let globalY = current.y + oldOrigin.y + offset.height
                        let globalCenter = CGPoint(x: globalX + current.width / 2, y: globalY + current.height / 2)
                        let newBoard = CanvasDocument.boardIndex(at: globalCenter, origins: origins, sizes: sizes)
                        let newOrigin = origins.indices.contains(newBoard) ? origins[newBoard] : .zero
                        current.boardIndex = newBoard
                        current.x = globalX - newOrigin.x
                        current.y = globalY - newOrigin.y
                    }
                }
                document.groupDragOffset = .zero
                document.save()
            }
    }

    /// Holding ⇧ while dragging restricts movement to a straight horizontal
    /// or vertical line — whichever axis has moved further from the drag's
    /// start dominates, re-evaluated on every update so it tracks the
    /// gesture's actual direction rather than locking to an initial guess.
    private func axisConstrained(_ translation: CGSize) -> CGSize {
        guard NSEvent.modifierFlags.contains(.shift) else { return translation }
        if abs(translation.width) >= abs(translation.height) {
            return CGSize(width: translation.width, height: 0)
        } else {
            return CGSize(width: 0, height: translation.height)
        }
    }

    /// Pulls `offset` so `baseline`'s edges land exactly on a nearby guide
    /// (within a screen-space threshold that adjusts for zoom) — checks both
    /// edges on each axis independently, snapping to whichever is closer.
    private func snappedOffset(_ offset: CGSize, baseline: CGRect) -> CGSize {
        let liveRect = baseline.offsetBy(dx: offset.width, dy: offset.height)
        let threshold = 8.0 / max(zoom, 0.01)

        var dx = offset.width
        if let match = Self.nearestGuideMatch(document.verticalGuides.map(\.position) + boardEdgeXPositions, edges: [liveRect.minX, liveRect.maxX], threshold: threshold) {
            dx += match.guidePosition - match.edgeValue
        }
        var dy = offset.height
        if let match = Self.nearestGuideMatch(document.horizontalGuides.map(\.position) + boardEdgeYPositions, edges: [liveRect.minY, liveRect.maxY], threshold: threshold) {
            dy += match.guidePosition - match.edgeValue
        }
        return CGSize(width: dx, height: dy)
    }

    /// This card's own board's rect in the shared display space — used so a
    /// move or resize can snap to the board's own edges, not just guides
    /// (e.g. scaling an image to exactly fill its board top-to-bottom).
    private var currentBoardRect: CGRect {
        guard let item else { return .zero }
        return CGRect(origin: boardOrigin, size: document.boardDisplaySize(item.boardIndex))
    }

    private var boardEdgeXPositions: [Double] {
        let rect = currentBoardRect
        return [rect.minX, rect.maxX]
    }

    private var boardEdgeYPositions: [Double] {
        let rect = currentBoardRect
        return [rect.minY, rect.maxY]
    }

    /// The closest (position, edge) pairing within `threshold`, or nil if
    /// none of `edges` comes close enough to any candidate `positions` —
    /// guide positions and board-edge positions are merged into one list by
    /// the caller, so both snap the same way.
    private static func nearestGuideMatch(_ positions: [Double], edges: [Double], threshold: Double) -> (edgeValue: Double, guidePosition: Double)? {
        var best: (edgeValue: Double, guidePosition: Double, distance: Double)?
        for position in positions {
            for edge in edges {
                let distance = abs(edge - position)
                if distance <= threshold, best == nil || distance < best!.distance {
                    best = (edge, position, distance)
                }
            }
        }
        guard let best else { return nil }
        return (best.edgeValue, best.guidePosition)
    }

    /// Clamps a group move on two different bases per axis:
    /// - Horizontally, each card still can't cross its *own* board's local
    ///   left edge — X never changes which board a card is on, so a board's
    ///   own rect (always at local x=0) is a hard, per-board bound, exactly
    ///   like the original single-canvas rule.
    /// - Vertically, the bound is the *global* top of the whole stacked
    ///   canvas (board 1's own top edge), not each card's own board's local
    ///   top — a card sitting on board 2 needs to stay draggable all the way
    ///   up past board 1's top edge (crossing into board 1 along the way),
    ///   not just to the top of board 2's own local space.
    ///
    /// Either way, nothing auto-extends up or to the left, so going past
    /// either bound would push a card permanently off. The whole group is
    /// clamped together (by whichever card would hit a bound first) rather
    /// than clamping each card individually, which would distort the group.
    private func clampedGroupOffset(_ translation: CGSize) -> CGSize {
        let ids = document.selectedIDs.contains(itemID) ? document.selectedIDs : [itemID]
        let selected = document.items.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return translation }
        let origins = document.boardOrigins()
        func globalOriginY(of item: CanvasItem) -> Double {
            origins.indices.contains(item.boardIndex) ? origins[item.boardIndex].y : 0
        }
        let minX = selected.map { $0.x }.min() ?? 0
        let minGlobalY = selected.map { $0.y + globalOriginY(of: $0) }.min() ?? 0
        return CGSize(
            width: max(translation.width, -minX),
            height: max(translation.height, -minGlobalY)
        )
    }

    /// Plain drag resizes just this card, anchored at the corner opposite the
    /// one being dragged — or at the card's own center if ⌥ is held, growing
    /// symmetrically in both directions. Holding ⌘ while multiple cards are
    /// selected instead scales the whole selection as one rigid block: every
    /// selected card (this one included) is scaled from a single shared
    /// anchor point — the group bounding box's fixed corner, or its center
    /// if ⌥ is also held — so gaps between cards scale proportionally
    /// instead of each card drifting from its own independent anchor.
    /// Resizing never moves a card to a different board (only a plain drag
    /// does), so all of this works in the shared display space and just
    /// subtracts this card's own (unchanged) board origin back out at commit.
    private func cornerDragGesture(_ corner: CardCorner) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
            .onChanged { value in
                let baseline = dragBaseline ?? (item?.frame ?? .zero).offsetBy(dx: boardOrigin.x, dy: boardOrigin.y)
                if dragBaseline == nil { dragBaseline = baseline }

                let isCenterScale = NSEvent.modifierFlags.contains(.option)
                let isGroupScale = NSEvent.modifierFlags.contains(.command)
                    && document.selectedIDs.count > 1
                    && document.selectedIDs.contains(itemID)

                if isGroupScale {
                    let origins = groupResizeOriginsSnapshot ?? document.boardOrigins()
                    if groupResizeOriginsSnapshot == nil { groupResizeOriginsSnapshot = origins }
                    let bboxBaseline = groupResizeBBoxBaseline ?? Self.boundingBox(of: document.selectedIDs, items: document.items, origins: origins, fallback: baseline)
                    if groupResizeBBoxBaseline == nil { groupResizeBBoxBaseline = bboxBaseline }

                    let selected = document.items.filter { document.selectedIDs.contains($0.id) }
                    let minScale = selected.reduce(0.0) { partial, card in
                        max(partial, minSize / max(card.width, 1), minSize / max(card.height, 1))
                    }
                    let scale = Self.groupScaleFactor(
                        bboxBaseline: bboxBaseline, corner: corner,
                        dx: value.translation.width, dy: value.translation.height,
                        isCenterScale: isCenterScale, minScale: minScale
                    )
                    let anchor = isCenterScale
                        ? CGPoint(x: bboxBaseline.midX, y: bboxBaseline.midY)
                        : Self.fixedAnchor(of: bboxBaseline, corner: corner)

                    document.groupResizeScale = scale
                    document.groupResizeAnchor = anchor
                    document.groupResizeSourceID = itemID
                    liveRect = Self.transformedRect(baseline, anchor: anchor, scale: scale)
                } else {
                    groupResizeBBoxBaseline = nil
                    groupResizeOriginsSnapshot = nil
                    document.groupResizeScale = nil
                    document.groupResizeAnchor = nil
                    document.groupResizeSourceID = nil

                    let isTextItem = item?.kind == .text
                    let isCommandScale = NSEvent.modifierFlags.contains(.command)
                    if isTextItem, !isCenterScale, !isCommandScale {
                        // Plain drag on a text item: reshape the box freely
                        // (independent width/height) rather than locking
                        // aspect ratio — for accommodating wrapped text.
                        isTextScaleMode = false
                        liveRect = freeResizeRect(baseline: baseline, corner: corner, dx: value.translation.width, dy: value.translation.height)
                    } else {
                        // ⌘ or ⌥ on a text item is a true proportional scale
                        // (font size included, applied in onEnded below) —
                        // same math images always use.
                        isTextScaleMode = isTextItem
                        liveRect = adjustedRect(baseline: baseline, corner: corner, dx: value.translation.width, dy: value.translation.height, isCenterScale: isCenterScale)
                    }
                }
            }
            .onEnded { _ in
                if let scale = document.groupResizeScale, let anchor = document.groupResizeAnchor {
                    document.registerUndoCheckpoint(actionName: "Scale Selection")
                    let origins = groupResizeOriginsSnapshot ?? document.boardOrigins()
                    for id in document.selectedIDs {
                        guard let target = document.items.first(where: { $0.id == id }) else { continue }
                        let origin = origins.indices.contains(target.boardIndex) ? origins[target.boardIndex] : .zero
                        let globalFrame = target.frame.offsetBy(dx: origin.x, dy: origin.y)
                        let transformed = Self.transformedRect(globalFrame, anchor: anchor, scale: scale)
                        let localFrame = transformed.offsetBy(dx: -origin.x, dy: -origin.y)
                        document.updateItem(id) { current in
                            current.x = localFrame.minX
                            current.y = localFrame.minY
                            current.width = localFrame.width
                            current.height = localFrame.height
                            if current.kind == .text {
                                current.fontSize = max(current.fontSize * scale, 4)
                            }
                        }
                    }
                } else if let rect = liveRect {
                    document.registerUndoCheckpoint(actionName: "Resize")
                    let localRect = rect.offsetBy(dx: -boardOrigin.x, dy: -boardOrigin.y)
                    let fontScale = (isTextScaleMode && dragBaseline != nil && dragBaseline!.height > 0) ? rect.height / dragBaseline!.height : 1
                    document.updateItem(itemID) { current in
                        current.x = localRect.minX
                        current.y = localRect.minY
                        current.width = localRect.width
                        current.height = localRect.height
                        if isTextScaleMode {
                            current.fontSize = max(current.fontSize * fontScale, 4)
                        }
                    }
                }
                liveRect = nil
                dragBaseline = nil
                isTextScaleMode = false
                groupResizeBBoxBaseline = nil
                groupResizeOriginsSnapshot = nil
                document.groupResizeScale = nil
                document.groupResizeAnchor = nil
                document.groupResizeSourceID = nil
                document.save()
            }
    }

    /// Resizes `baseline` from `corner`, changing width and height
    /// independently rather than locking aspect ratio — used for a plain
    /// (no-modifier) drag on a text item, so its box can be reshaped freely
    /// to accommodate wrapped text. Growing from a left/top corner is
    /// capped so the new left/top edge never crosses 0, same as the
    /// aspect-locked version.
    private func freeResizeRect(baseline: CGRect, corner: CardCorner, dx: Double, dy: Double) -> CGRect {
        let isRight = corner == .topRight || corner == .bottomRight
        let isBottom = corner == .bottomLeft || corner == .bottomRight

        var minX = baseline.minX
        var maxX = baseline.maxX
        var minY = baseline.minY
        var maxY = baseline.maxY

        if isRight {
            maxX = max(baseline.maxX + dx, baseline.minX + minSize)
        } else {
            minX = min(max(baseline.minX + dx, 0), baseline.maxX - minSize)
        }
        if isBottom {
            maxY = max(baseline.maxY + dy, baseline.minY + minSize)
        } else {
            minY = min(max(baseline.minY + dy, 0), baseline.maxY - minSize)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The union of every selected card's frame in the shared display space
    /// (each offset by its own board's origin), captured once at the start
    /// of a group-scale drag so the whole selection scales from one stable
    /// rectangle rather than one that shifts as cards are transformed.
    private static func boundingBox(of ids: Set<UUID>, items: [CanvasItem], origins: [CGPoint], fallback: CGRect) -> CGRect {
        let frames = items.filter { ids.contains($0.id) }.map { item -> CGRect in
            let origin = origins.indices.contains(item.boardIndex) ? origins[item.boardIndex] : .zero
            return item.frame.offsetBy(dx: origin.x, dy: origin.y)
        }
        guard let first = frames.first else { return fallback }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    /// The point that stays fixed while scaling `rect` from `corner` — the
    /// corner diagonally opposite the one being dragged.
    private static func fixedAnchor(of rect: CGRect, corner: CardCorner) -> CGPoint {
        let isRight = corner == .topRight || corner == .bottomRight
        let isBottom = corner == .bottomLeft || corner == .bottomRight
        return CGPoint(x: isRight ? rect.minX : rect.maxX, y: isBottom ? rect.minY : rect.maxY)
    }

    /// Scales `rect` by `scale` about `anchor` — the single formula shared by
    /// every selected card during a group scale, whether `anchor` is a fixed
    /// corner or (⌥ held) the group's center.
    private static func transformedRect(_ rect: CGRect, anchor: CGPoint, scale: CGFloat) -> CGRect {
        let width = rect.width * scale
        let height = rect.height * scale
        let x = anchor.x + (rect.minX - anchor.x) * scale
        let y = anchor.y + (rect.minY - anchor.y) * scale
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The uniform scale factor that dragging `corner` of `bboxBaseline` by
    /// (dx, dy) implies — growing from the opposite corner, or symmetrically
    /// from the center if `isCenterScale`. Clamped so the fixed side(s) never
    /// cross the canvas's left/top edges (or, when centered, so the whole
    /// box stays within them) and so no selected card would drop below
    /// `minScale`.
    private static func groupScaleFactor(bboxBaseline: CGRect, corner: CardCorner, dx: Double, dy: Double, isCenterScale: Bool, minScale: Double) -> CGFloat {
        guard bboxBaseline.width > 0, bboxBaseline.height > 0 else { return 1 }
        let isRight = corner == .topRight || corner == .bottomRight
        let isBottom = corner == .bottomLeft || corner == .bottomRight

        if isCenterScale {
            let widthRaw = bboxBaseline.width + 2 * (isRight ? dx : -dx)
            let heightRaw = bboxBaseline.height + 2 * (isBottom ? dy : -dy)
            let center = CGPoint(x: bboxBaseline.midX, y: bboxBaseline.midY)
            let maxScaleX = center.x > 0 ? (2 * center.x) / bboxBaseline.width : .infinity
            let maxScaleY = center.y > 0 ? (2 * center.y) / bboxBaseline.height : .infinity
            var scale = max(widthRaw / bboxBaseline.width, heightRaw / bboxBaseline.height, minScale)
            scale = min(scale, maxScaleX, maxScaleY)
            return max(scale, minScale)
        } else {
            let widthRaw = bboxBaseline.width + (isRight ? dx : -dx)
            let heightRaw = bboxBaseline.height + (isBottom ? dy : -dy)
            var scale = max(widthRaw / bboxBaseline.width, heightRaw / bboxBaseline.height, minScale)
            if !isRight { scale = min(scale, bboxBaseline.maxX / bboxBaseline.width) }
            if !isBottom { scale = min(scale, bboxBaseline.maxY / bboxBaseline.height) }
            return max(scale, minScale)
        }
    }

    /// Resizes `baseline` from `corner`, keeping its aspect ratio locked and
    /// the opposite corner anchored in place. Growing from a left/top corner
    /// is capped so the new left/top edge never crosses 0 — the canvas only
    /// auto-extends on the right/bottom, so the left/top edges are hard
    /// bounds rather than something that can grow to meet the card. If the
    /// free corner lands near a guide, snaps to it (see `snappedScale`).
    private func adjustedRect(baseline: CGRect, corner: CardCorner, dx: Double, dy: Double, isCenterScale: Bool) -> CGRect {
        guard baseline.width > 0, baseline.height > 0 else { return baseline }

        let minScaleForCenter = max(minSize / baseline.width, minSize / baseline.height)
        if isCenterScale {
            let scale = Self.groupScaleFactor(bboxBaseline: baseline, corner: corner, dx: dx, dy: dy, isCenterScale: true, minScale: minScaleForCenter)
            let anchor = CGPoint(x: baseline.midX, y: baseline.midY)
            return Self.transformedRect(baseline, anchor: anchor, scale: scale)
        }

        let isRight = corner == .topRight || corner == .bottomRight
        let isBottom = corner == .bottomLeft || corner == .bottomRight

        let widthRaw = baseline.width + (isRight ? dx : -dx)
        let heightRaw = baseline.height + (isBottom ? dy : -dy)

        let minScale = max(minSize / baseline.width, minSize / baseline.height)
        var scale = max(widthRaw / baseline.width, heightRaw / baseline.height, minScale)

        if !isRight {
            scale = min(scale, baseline.maxX / baseline.width)
        }
        if !isBottom {
            scale = min(scale, baseline.maxY / baseline.height)
        }
        scale = max(scale, minScale)

        if let snapped = snappedScale(baseline: baseline, corner: corner, currentScale: scale, minScale: minScale) {
            scale = snapped
        }

        let width = baseline.width * scale
        let height = baseline.height * scale

        let x = isRight ? baseline.minX : baseline.maxX - width
        let y = isBottom ? baseline.minY : baseline.maxY - height

        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// If the corner's free edges (given the drag's current unsnapped
    /// `currentScale`) land close to a guide, returns the scale that would
    /// put it exactly there — whichever axis is closer (a vertical guide
    /// pins width, a horizontal guide pins height), with the other dimension
    /// then following from the locked aspect ratio, per the user's call to
    /// keep this simple rather than trying to satisfy both at once.
    private func snappedScale(baseline: CGRect, corner: CardCorner, currentScale: Double, minScale: Double) -> Double? {
        let isRight = corner == .topRight || corner == .bottomRight
        let isBottom = corner == .bottomLeft || corner == .bottomRight
        let threshold = 8.0 / max(zoom, 0.01)

        let freeX = isRight ? baseline.minX + baseline.width * currentScale : baseline.maxX - baseline.width * currentScale
        let freeY = isBottom ? baseline.minY + baseline.height * currentScale : baseline.maxY - baseline.height * currentScale

        let vMatch = Self.nearestGuideMatch(document.verticalGuides.map(\.position) + boardEdgeXPositions, edges: [freeX], threshold: threshold)
        let hMatch = Self.nearestGuideMatch(document.horizontalGuides.map(\.position) + boardEdgeYPositions, edges: [freeY], threshold: threshold)
        guard vMatch != nil || hMatch != nil else { return nil }

        let useVertical: Bool
        if let v = vMatch, let h = hMatch {
            useVertical = abs(v.guidePosition - v.edgeValue) <= abs(h.guidePosition - h.edgeValue)
        } else {
            useVertical = vMatch != nil
        }

        var scale: Double
        if useVertical, let v = vMatch {
            scale = (isRight ? (v.guidePosition - baseline.minX) : (baseline.maxX - v.guidePosition)) / baseline.width
        } else if let h = hMatch {
            scale = (isBottom ? (h.guidePosition - baseline.minY) : (baseline.maxY - h.guidePosition)) / baseline.height
        } else {
            return nil
        }

        if !isRight { scale = min(scale, baseline.maxX / baseline.width) }
        if !isBottom { scale = min(scale, baseline.maxY / baseline.height) }
        return max(scale, minScale)
    }
}
