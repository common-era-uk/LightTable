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
                let logicalY = (value.location.y - panOffset.height) / zoom
                onPendingGuideChanged(PendingGuide(orientation: .horizontal, position: logicalY))
            }
            .onEnded { value in
                defer {
                    onPendingGuideChanged(nil)
                    NSCursor.arrow.set()
                }
                guard value.location.y >= rulerThickness else { return }
                let logicalY = (value.location.y - panOffset.height) / zoom
                onAddHorizontalGuide(logicalY)
            }
    }

    private var leftRulerDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("viewport"))
            .onChanged { value in
                NSCursor.crosshair.set()
                let logicalX = (value.location.x - panOffset.width) / zoom
                onPendingGuideChanged(PendingGuide(orientation: .vertical, position: logicalX))
            }
            .onEnded { value in
                defer {
                    onPendingGuideChanged(nil)
                    NSCursor.arrow.set()
                }
                guard value.location.x >= rulerThickness else { return }
                let logicalX = (value.location.x - panOffset.width) / zoom
                onAddVerticalGuide(logicalX)
            }
    }
}
