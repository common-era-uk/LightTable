import SwiftUI

/// A single straight line, drawn within whatever frame it's given — used so
/// a dashed smart-alignment guide can reuse `GuideLinesLayer`'s proven
/// `.frame(width:height:).position(x:y:)` placement idiom instead of trying
/// to draw at absolute canvas coordinates directly (which would need its
/// own, easy-to-get-wrong frame/alignment bookkeeping).
private struct StraightLineShape: Shape {
    let isVertical: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isVertical {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return path
    }
}

/// Renders the live smart-alignment guides (see `CanvasDocument.activeSmartGuides`)
/// inside the canvas's scaled/panned content space, alongside
/// `GuideLinesLayer`. Purely a read of transient state — no interaction, no
/// gestures, nothing to persist.
struct SmartGuideLayer: View {
    let guides: [SmartAlignmentGuide]

    /// Pink for "matches another item," green for "matches the board's own
    /// center" — different enough at a glance to tell which kind of
    /// alignment just happened without reading anything.
    private func color(for kind: SmartAlignmentGuideKind) -> Color {
        switch kind {
        case .sibling: return Color(red: 0.95, green: 0.15, blue: 0.55)
        case .boardCenter: return Color(red: 0.2, green: 0.75, blue: 0.3)
        }
    }

    var body: some View {
        ForEach(Array(guides.enumerated()), id: \.offset) { _, guide in
            let length = max(guide.end - guide.start, 0)
            let mid = (guide.start + guide.end) / 2
            let lineColor = color(for: guide.kind)
            switch guide.orientation {
            case .vertical:
                StraightLineShape(isVertical: true)
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: 1, height: length)
                    .position(x: guide.position, y: mid)
            case .horizontal:
                StraightLineShape(isVertical: false)
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: length, height: 1)
                    .position(x: mid, y: guide.position)
            }
        }
        .allowsHitTesting(false)
    }
}
