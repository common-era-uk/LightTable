import SwiftUI

/// Renders a canvas item's image with its non-destructive crop applied.
/// Shared between the interactive canvas card and the flat export renderer.
/// Self-contained (owns its own frame/clip/alignment) rather than relying on
/// every caller to specify `alignment: .topLeading` on their wrapping
/// `.frame()` — the oversized inner image is positioned by an explicit
/// offset computed relative to a top-left origin, and SwiftUI's default
/// frame alignment is `.center`, which silently added an extra shift on
/// top of that offset for any crop that wasn't itself centered.
struct CroppedImageView: View {
    let document: CanvasDocument
    let item: CanvasItem
    let width: Double
    let height: Double

    var body: some View {
        let fileURL = document.folderURL.appendingPathComponent(item.filename)
        Group {
            if let nsImage = ImageCache.shared.image(for: fileURL) {
                let crop = item.cropRect
                let innerWidth = width / max(crop.width, 0.01)
                let innerHeight = height / max(crop.height, 0.01)
                let offsetX = -crop.minX * innerWidth
                let offsetY = -crop.minY * innerHeight

                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: innerWidth, height: innerHeight)
                    .offset(x: offsetX, y: offsetY)
                    .background(Color.black.opacity(0.05))
            } else {
                Rectangle().fill(Color.gray.opacity(0.3))
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
    }
}
