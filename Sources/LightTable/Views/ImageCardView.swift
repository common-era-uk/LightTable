import SwiftUI
import AppKit

enum CardCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

struct ImageCardView: View {
    @ObservedObject var document: CanvasDocument
    let itemID: UUID
    @Binding var cropModeItemID: UUID?
    let showFilenames: Bool
    let zoom: CGFloat

    @State private var liveRect: CGRect?
    @State private var dragBaseline: CGRect?
    @ObservedObject private var shadowSettings = ShadowSettings.shared

    private let minSize: Double = 40

    private var item: CanvasItem? {
        document.items.first { $0.id == itemID }
    }

    var body: some View {
        if let item {
            let isSelected = document.selectedIDs.contains(itemID)
            let groupOffset = isSelected ? document.groupDragOffset : .zero
            let rect = currentRect(for: item, isSelected: isSelected).offsetBy(dx: groupOffset.width, dy: groupOffset.height)

            ZStack(alignment: .topLeading) {
                CroppedImageView(document: document, item: item, width: rect.width, height: rect.height)
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
                    .onTapGesture(count: 2) { cropModeItemID = itemID }
                    .onTapGesture { selectOnTap() }

                if isSelected {
                    ForEach(CardCorner.allCases, id: \.self) { corner in
                        handle(corner, rect: rect)
                    }
                }

                if showFilenames {
                    filenameLabel(item.filename, rect: rect)
                }
            }
            .frame(width: rect.width, height: rect.height, alignment: .topLeading)
            .position(x: rect.midX, y: rect.midY)
        }
    }

    /// The card's rect before any group-move offset: its own live drag rect
    /// while being actively resized, a live-preview scaled rect while it's a
    /// bystander to another selected card's ⌘-group-resize, or just its
    /// stored frame otherwise.
    private func currentRect(for item: CanvasItem, isSelected: Bool) -> CGRect {
        if let liveRect {
            return liveRect
        }
        if isSelected,
           let sourceID = document.groupResizeSourceID, sourceID != itemID,
           let scale = document.groupResizeScale,
           let corner = document.groupResizeCorner {
            return Self.scaledRect(from: item.frame, corner: corner, scale: scale, minSize: minSize)
        }
        return item.frame
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

    /// Dragging a card that's part of the current selection moves the whole
    /// group together; dragging an unselected card selects just that one.
    /// Snapping is computed from this card's own edges (the one under the
    /// cursor), then applied as one shared offset to the whole group.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
            .onChanged { value in
                if !document.selectedIDs.contains(itemID) {
                    document.selectedIDs = [itemID]
                    document.selectedGuideID = nil
                }
                let baseline = item?.frame ?? .zero
                document.groupDragOffset = snappedOffset(clampedGroupOffset(value.translation), baseline: baseline)
            }
            .onEnded { value in
                let ids = document.selectedIDs
                let baseline = item?.frame ?? .zero
                let offset = snappedOffset(clampedGroupOffset(value.translation), baseline: baseline)
                document.registerUndoCheckpoint(actionName: "Move")
                document.updateItems(ids) { current in
                    current.x += offset.width
                    current.y += offset.height
                }
                document.groupDragOffset = .zero
                document.save()
            }
    }

    /// Pulls `offset` so `baseline`'s edges land exactly on a nearby guide
    /// (within a screen-space threshold that adjusts for zoom) — checks both
    /// edges on each axis independently, snapping to whichever is closer.
    private func snappedOffset(_ offset: CGSize, baseline: CGRect) -> CGSize {
        let liveRect = baseline.offsetBy(dx: offset.width, dy: offset.height)
        let threshold = 8.0 / max(zoom, 0.01)

        var dx = offset.width
        if let match = Self.nearestGuideMatch(document.verticalGuides, edges: [liveRect.minX, liveRect.maxX], threshold: threshold) {
            dx += match.guidePosition - match.edgeValue
        }
        var dy = offset.height
        if let match = Self.nearestGuideMatch(document.horizontalGuides, edges: [liveRect.minY, liveRect.maxY], threshold: threshold) {
            dy += match.guidePosition - match.edgeValue
        }
        return CGSize(width: dx, height: dy)
    }

    /// The closest (guide, edge) pairing within `threshold`, or nil if none
    /// of `edges` comes close enough to any guide.
    private static func nearestGuideMatch(_ guides: [Guide], edges: [Double], threshold: Double) -> (edgeValue: Double, guidePosition: Double)? {
        var best: (edgeValue: Double, guidePosition: Double, distance: Double)?
        for guide in guides {
            for edge in edges {
                let distance = abs(edge - guide.position)
                if distance <= threshold, best == nil || distance < best!.distance {
                    best = (edge, guide.position, distance)
                }
            }
        }
        guard let best else { return nil }
        return (best.edgeValue, best.guidePosition)
    }

    /// Clamps a group move so no selected card's left or top edge can cross
    /// 0 — the canvas only auto-extends on the right/bottom, so going
    /// negative would push cards permanently off-screen. The whole group is
    /// clamped together (by whichever card would hit the edge first) rather
    /// than clamping each card individually, which would distort the group.
    private func clampedGroupOffset(_ translation: CGSize) -> CGSize {
        let ids = document.selectedIDs.contains(itemID) ? document.selectedIDs : [itemID]
        let selected = document.items.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return translation }
        let minX = selected.map { $0.x }.min() ?? 0
        let minY = selected.map { $0.y }.min() ?? 0
        return CGSize(
            width: max(translation.width, -minX),
            height: max(translation.height, -minY)
        )
    }

    /// Plain drag resizes just this card. Holding ⌘ while multiple cards are
    /// selected also broadcasts a scale factor (derived from this card's own
    /// resize) via the document, so every other selected card can preview
    /// and then commit the same proportional scale from its own matching
    /// corner — each keeps its own aspect ratio and position anchor, only
    /// the resize itself is shared.
    private func cornerDragGesture(_ corner: CardCorner) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
            .onChanged { value in
                let baseline = dragBaseline ?? (item?.frame ?? .zero)
                if dragBaseline == nil { dragBaseline = baseline }
                let newRect = adjustedRect(baseline: baseline, corner: corner, dx: value.translation.width, dy: value.translation.height)
                liveRect = newRect

                let isGroupScale = NSEvent.modifierFlags.contains(.command)
                    && document.selectedIDs.count > 1
                    && document.selectedIDs.contains(itemID)
                    && baseline.width > 0
                if isGroupScale {
                    document.groupResizeScale = newRect.width / baseline.width
                    document.groupResizeCorner = corner
                    document.groupResizeSourceID = itemID
                } else {
                    document.groupResizeScale = nil
                    document.groupResizeCorner = nil
                    document.groupResizeSourceID = nil
                }
            }
            .onEnded { _ in
                if let rect = liveRect {
                    let scale = document.groupResizeScale
                    let activeCorner = document.groupResizeCorner
                    document.registerUndoCheckpoint(actionName: scale != nil ? "Scale Selection" : "Resize")

                    if let scale, let activeCorner {
                        for id in document.selectedIDs {
                            if id == itemID {
                                document.updateItem(id) { current in
                                    current.x = rect.minX
                                    current.y = rect.minY
                                    current.width = rect.width
                                    current.height = rect.height
                                }
                            } else if let target = document.items.first(where: { $0.id == id }) {
                                let scaled = Self.scaledRect(from: target.frame, corner: activeCorner, scale: scale, minSize: minSize)
                                document.updateItem(id) { current in
                                    current.x = scaled.minX
                                    current.y = scaled.minY
                                    current.width = scaled.width
                                    current.height = scaled.height
                                }
                            }
                        }
                    } else {
                        document.updateItem(itemID) { current in
                            current.x = rect.minX
                            current.y = rect.minY
                            current.width = rect.width
                            current.height = rect.height
                        }
                    }
                }
                liveRect = nil
                dragBaseline = nil
                document.groupResizeScale = nil
                document.groupResizeCorner = nil
                document.groupResizeSourceID = nil
                document.save()
            }
    }

    /// Scales `frame` by `scale`, anchored at its corner opposite `corner`
    /// (matching the anchor semantics of `adjustedRect`), clamped so it
    /// never crosses the canvas's left/top edges.
    private static func scaledRect(from frame: CGRect, corner: CardCorner, scale: CGFloat, minSize: Double) -> CGRect {
        let width = max(frame.width * scale, minSize)
        let height = max(frame.height * scale, minSize)
        let isRight = corner == .topRight || corner == .bottomRight
        let isBottom = corner == .bottomLeft || corner == .bottomRight
        let x = max(isRight ? frame.minX : frame.maxX - width, 0)
        let y = max(isBottom ? frame.minY : frame.maxY - height, 0)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Resizes `baseline` from `corner`, keeping its aspect ratio locked and
    /// the opposite corner anchored in place. Growing from a left/top corner
    /// is capped so the new left/top edge never crosses 0 — the canvas only
    /// auto-extends on the right/bottom, so the left/top edges are hard
    /// bounds rather than something that can grow to meet the card. If the
    /// free corner lands near a guide, snaps to it (see `snappedScale`).
    private func adjustedRect(baseline: CGRect, corner: CardCorner, dx: Double, dy: Double) -> CGRect {
        guard baseline.width > 0, baseline.height > 0 else { return baseline }

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

        let vMatch = Self.nearestGuideMatch(document.verticalGuides, edges: [freeX], threshold: threshold)
        let hMatch = Self.nearestGuideMatch(document.horizontalGuides, edges: [freeY], threshold: threshold)
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
