import SwiftUI
import AppKit

/// The thin drag-in strips along the canvas's top/left edges that create
/// guides, living in the outer (unscaled) viewport space. Like
/// `GuideLinesLayer`, this takes plain values and closures rather than
/// `@ObservedObject var document`.
struct RulerZones: View {
    let viewportSize: CGSize
    let zoom: CGFloat
    let panOffset: CGSize
    let rulerThickness: Double
    /// Card edges (in canvas-logical space) that a guide being dragged in
    /// snaps to when brought close, same threshold as card-to-guide snapping.
    let cardEdgesX: [Double]
    let cardEdgesY: [Double]

    let onPendingGuideChanged: (PendingGuide?) -> Void
    let onAddVerticalGuide: (Double) -> Void
    let onAddHorizontalGuide: (Double) -> Void

    var body: some View {
        topRulerZone
        leftRulerZone
    }

    private var topRulerZone: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.001))
            .overlay(Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 3), alignment: .bottom)
            .frame(width: viewportSize.width, height: rulerThickness)
            .contentShape(Rectangle())
            .position(x: viewportSize.width / 2, y: rulerThickness / 2)
            .gesture(topRulerDragGesture)
    }

    private var leftRulerZone: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.001))
            .overlay(Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 3), alignment: .trailing)
            .frame(width: rulerThickness, height: viewportSize.height)
            .contentShape(Rectangle())
            .position(x: rulerThickness / 2, y: viewportSize.height / 2)
            .gesture(leftRulerDragGesture)
    }

    /// Both ruler drag gestures use the "viewport" (outer, untransformed)
    /// coordinate space so `value.location` tracks the pointer across the
    /// whole canvas as it's dragged in from the ruler, not just within the
    /// ruler's own thin strip. The cursor is set explicitly on every tick
    /// rather than relying on hover tracking, which doesn't reliably keep
    /// firing mid-drag.
    private var topRulerDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("viewport"))
            .onChanged { value in
                NSCursor.crosshair.set()
                let logicalY = snapped((value.location.y - panOffset.height) / zoom, to: cardEdgesY)
                onPendingGuideChanged(PendingGuide(orientation: .horizontal, position: logicalY))
            }
            .onEnded { value in
                defer {
                    onPendingGuideChanged(nil)
                    NSCursor.arrow.set()
                }
                guard value.location.y >= rulerThickness else { return }
                let logicalY = snapped((value.location.y - panOffset.height) / zoom, to: cardEdgesY)
                onAddHorizontalGuide(logicalY)
            }
    }

    private var leftRulerDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("viewport"))
            .onChanged { value in
                NSCursor.crosshair.set()
                let logicalX = snapped((value.location.x - panOffset.width) / zoom, to: cardEdgesX)
                onPendingGuideChanged(PendingGuide(orientation: .vertical, position: logicalX))
            }
            .onEnded { value in
                defer {
                    onPendingGuideChanged(nil)
                    NSCursor.arrow.set()
                }
                guard value.location.x >= rulerThickness else { return }
                let logicalX = snapped((value.location.x - panOffset.width) / zoom, to: cardEdgesX)
                onAddVerticalGuide(logicalX)
            }
    }

    /// Pulls `value` onto the closest entry in `edges` if one is within a
    /// screen-space threshold (adjusted for zoom) — same threshold cards use
    /// to snap to guides, applied here to snap a new guide to card edges.
    private func snapped(_ value: Double, to edges: [Double]) -> Double {
        let threshold = 8.0 / max(zoom, 0.01)
        guard let nearest = edges.min(by: { abs($0 - value) < abs($1 - value) }),
              abs(nearest - value) <= threshold else {
            return value
        }
        return nearest
    }
}
