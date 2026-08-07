import SwiftUI

/// A flat, non-interactive rendering of the canvas at its full natural size,
/// used as the source for image export (whole canvas or a cropped region).
struct CanvasExportView: View {
    @ObservedObject var document: CanvasDocument
    let contentSize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            document.canvasColor?.color ?? Color.white
            ForEach(document.items) { item in
                CroppedImageView(document: document, item: item, width: item.width, height: item.height)
                    .position(x: item.x + item.width / 2, y: item.y + item.height / 2)
            }
        }
        .frame(width: contentSize.width, height: contentSize.height)
    }
}
