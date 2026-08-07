import SwiftUI
import AppKit

enum GuideOrientation {
    case vertical, horizontal
}

/// A not-yet-committed guide being dragged in from a ruler zone — rendered
/// as a live preview, only turned into a real `Guide` on drop.
struct PendingGuide: Equatable {
    let orientation: GuideOrientation
    var position: Double
}

/// Renders every guide line plus the drag-in preview, inside the canvas's
/// scaled/panned content space. Deliberately takes plain values and
/// closures rather than `@ObservedObject var document`, so it doesn't need
/// to observe every unrelated change (like the live card-drag offset) that
/// `document` publishes.
struct GuideLinesLayer: View {
    let verticalGuides: [Guide]
    let horizontalGuides: [Guide]
    let selectedGuideID: UUID?
    let pendingGuide: PendingGuide?
    let contentSize: CGSize
    let guideColor: Color
    let zoom: CGFloat
    let panOffset: CGSize
    let rulerThickness: Double

    let onSelectGuide: (UUID) -> Void
    let onMoveGuide: (UUID, Double) -> Void
    let onRemoveGuide: (UUID) -> Void

    @State private var draggingGuideID: UUID?
    @State private var draggingGuideBaseline: Double?
    @State private var draggingGuideLivePosition: Double?

    var body: some View {
        ForEach(verticalGuides) { guide in
            guideLine(orientation: .vertical, guide: guide)
        }
        ForEach(horizontalGuides) { guide in
            guideLine(orientation: .horizontal, guide: guide)
        }
        if let pendingGuide {
            pendingGuideLine(pendingGuide)
        }
    }

    /// The visible line is thin, but its hit area is wider (matching the
    /// canvas edge handles' own visible-line-inside-a-fatter-hit-rect
    /// pattern) so it's actually possible to grab.
    private func guideLine(orientation: GuideOrientation, guide: Guide) -> some View {
        let isSelected = selectedGuideID == guide.id
        let isDragging = draggingGuideID == guide.id
        let position = isDragging ? (draggingGuideLivePosition ?? guide.position) : guide.position
        let visibleWidth: CGFloat = isSelected ? 2.5 : 1.5
        let hitWidth: CGFloat = 10

        return Group {
            switch orientation {
            case .vertical:
                Rectangle()
                    .fill(guideColor.opacity(0.001))
                    .overlay(Rectangle().fill(guideColor).frame(width: visibleWidth))
                    .frame(width: hitWidth, height: contentSize.height)
                    .contentShape(Rectangle())
                    .position(x: position, y: contentSize.height / 2)
            case .horizontal:
                Rectangle()
                    .fill(guideColor.opacity(0.001))
                    .overlay(Rectangle().fill(guideColor).frame(height: visibleWidth))
                    .frame(width: contentSize.width, height: hitWidth)
                    .contentShape(Rectangle())
                    .position(x: contentSize.width / 2, y: position)
            }
        }
        .gesture(guideDragGesture(id: guide.id, orientation: orientation))
        .onTapGesture { onSelectGuide(guide.id) }
        .onHover { hovering in
            guard draggingGuideID == nil else { return }
            if hovering {
                (orientation == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }

    private func pendingGuideLine(_ pending: PendingGuide) -> some View {
        Group {
            switch pending.orientation {
            case .vertical:
                Rectangle()
                    .fill(guideColor.opacity(0.6))
                    .frame(width: 1.5, height: contentSize.height)
                    .position(x: pending.position, y: contentSize.height / 2)
            case .horizontal:
                Rectangle()
                    .fill(guideColor.opacity(0.6))
                    .frame(width: contentSize.width, height: 1.5)
                    .position(x: contentSize.width / 2, y: pending.position)
            }
        }
        .allowsHitTesting(false)
    }

    /// Dragging an existing guide repositions it live; dropping it back over
    /// the ruler (its screen position ends up under `rulerThickness`) deletes
    /// it instead of committing a new position — the same "drag back to the
    /// ruler to remove it" convention used when creating one.
    private func guideDragGesture(id: UUID, orientation: GuideOrientation) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas"))
            .onChanged { value in
                if selectedGuideID != id {
                    onSelectGuide(id)
                }
                // Set explicitly on every tick rather than relying on hover
                // tracking, which doesn't reliably keep firing mid-drag.
                (orientation == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()

                let baseline: Double
                if draggingGuideID == id, let existing = draggingGuideBaseline {
                    baseline = existing
                } else {
                    let stored = orientation == .vertical
                        ? verticalGuides.first { $0.id == id }?.position
                        : horizontalGuides.first { $0.id == id }?.position
                    baseline = stored ?? 0
                    draggingGuideBaseline = baseline
                    draggingGuideID = id
                }

                let delta = orientation == .vertical ? value.translation.width : value.translation.height
                draggingGuideLivePosition = baseline + delta
            }
            .onEnded { _ in
                defer {
                    draggingGuideID = nil
                    draggingGuideLivePosition = nil
                    draggingGuideBaseline = nil
                    NSCursor.arrow.set()
                }
                guard let livePosition = draggingGuideLivePosition else { return }
                let screenPosition = orientation == .vertical
                    ? panOffset.width + livePosition * zoom
                    : panOffset.height + livePosition * zoom
                if screenPosition < rulerThickness {
                    onRemoveGuide(id)
                } else {
                    onMoveGuide(id, livePosition)
                }
            }
    }
}
