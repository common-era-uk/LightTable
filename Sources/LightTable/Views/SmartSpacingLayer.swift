import SwiftUI

/// A double-headed arrow spanning whatever frame it's given — the "these
/// two gaps are equal" indicator, drawn once per matched gap (see
/// `CanvasDocument.activeSpacingGaps`).
private struct DoubleArrowShape: Shape {
    let isHorizontal: Bool
    // 125% larger than the original 4pt.
    let headSize: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isHorizontal {
            let y = rect.midY
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            path.move(to: CGPoint(x: rect.minX + headSize, y: y - headSize))
            path.addLine(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.minX + headSize, y: y + headSize))
            path.move(to: CGPoint(x: rect.maxX - headSize, y: y - headSize))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX - headSize, y: y + headSize))
        } else {
            let x = rect.midX
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.move(to: CGPoint(x: x - headSize, y: rect.minY + headSize))
            path.addLine(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x + headSize, y: rect.minY + headSize))
            path.move(to: CGPoint(x: x - headSize, y: rect.maxY - headSize))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + headSize, y: rect.maxY - headSize))
        }
        return path
    }
}

/// Renders the live equal-spacing indicators inside the canvas's
/// scaled/panned content space, alongside `SmartGuideLayer`. Same pink as
/// a sibling alignment guide, since it's still "matches another item" —
/// just shown as an arrow across a gap instead of a line across an edge.
struct SmartSpacingLayer: View {
    let gaps: [SmartSpacingGap]
    private let color = Color(red: 0.95, green: 0.15, blue: 0.55)

    var body: some View {
        ForEach(Array(gaps.enumerated()), id: \.offset) { _, gap in
            let length = max(gap.end - gap.start, 0)
            switch gap.axis {
            case .horizontal:
                DoubleArrowShape(isHorizontal: true)
                    .stroke(color, lineWidth: 1)
                    .frame(width: length, height: 20)
                    .position(x: (gap.start + gap.end) / 2, y: gap.cross)
            case .vertical:
                DoubleArrowShape(isHorizontal: false)
                    .stroke(color, lineWidth: 1)
                    .frame(width: 20, height: length)
                    .position(x: gap.cross, y: (gap.start + gap.end) / 2)
            }
        }
        .allowsHitTesting(false)
    }
}
