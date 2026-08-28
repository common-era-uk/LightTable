import SwiftUI

/// A flat, non-interactive rendering of the whole (multi-board) canvas at
/// its full natural size, used as the source for the toolbar's "Save Visible
/// Area"/"Save Whole Canvas" image export. Items render at their board's
/// origin in the shared display space (see `CanvasDocument.boardOrigins`).
struct CanvasExportView: View {
    @ObservedObject var document: CanvasDocument
    let contentSize: CGSize

    var body: some View {
        let origins = document.boardOrigins()
        ZStack(alignment: .topLeading) {
            ForEach(Array(document.boardSizes.enumerated()), id: \.element.id) { index, _ in
                let origin = origins.indices.contains(index) ? origins[index] : .zero
                let size = document.boardDisplaySize(index)
                document.boardColor(index, fallback: .white)
                    .frame(width: size.width, height: size.height)
                    .position(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
            }
            ForEach(document.items) { item in
                let origin = origins.indices.contains(item.boardIndex) ? origins[item.boardIndex] : .zero
                exportContent(for: item)
                    .position(x: origin.x + item.x + item.width / 2, y: origin.y + item.y + item.height / 2)
            }
        }
        .frame(width: contentSize.width, height: contentSize.height)
    }

    @ViewBuilder
    private func exportContent(for item: CanvasItem) -> some View {
        if item.kind == .text {
            TextItemContentView(item: item, width: item.width, height: item.height)
        } else {
            CroppedImageView(document: document, item: item, width: item.width, height: item.height)
        }
    }
}

/// A flat, non-interactive rendering of a single art board, in that board's
/// own local coordinates — the source for one page of a PDF export.
struct SingleBoardExportView: View {
    @ObservedObject var document: CanvasDocument
    let boardIndex: Int
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            document.boardColor(boardIndex, fallback: .white)
            ForEach(document.items(onBoard: boardIndex)) { item in
                exportContent(for: item)
                    .position(x: item.x + item.width / 2, y: item.y + item.height / 2)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func exportContent(for item: CanvasItem) -> some View {
        if item.kind == .text {
            TextItemContentView(item: item, width: item.width, height: item.height)
        } else {
            CroppedImageView(document: document, item: item, width: item.width, height: item.height)
        }
    }
}
