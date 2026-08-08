import SwiftUI

/// A large, centered preview of a single card, dismissed the same way it was
/// opened — pressing Space again, pressing Escape, or clicking anywhere —
/// mirroring macOS's own Quick Look/Preview spacebar behavior.
struct PreviewOverlayView: View {
    let document: CanvasDocument
    let item: CanvasItem
    let containerSize: CGSize
    let onDismiss: () -> Void

    @ObservedObject private var backgroundSettings = PreviewBackgroundSettings.shared

    private var previewSize: CGSize {
        let aspect = max(item.width, 1) / max(item.height, 1)
        let maxWidth = containerSize.width * 0.85
        let maxHeight = containerSize.height * 0.85
        var width = maxWidth
        var height = width / aspect
        if height > maxHeight {
            height = maxHeight
            width = height * aspect
        }
        return CGSize(width: width, height: height)
    }

    var body: some View {
        ZStack {
            backgroundSettings.color.opacity(backgroundSettings.opacity)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                CroppedImageView(document: document, item: item, width: previewSize.width, height: previewSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.5), radius: 24)

                if backgroundSettings.showFilename {
                    Text(item.filename)
                        .font(.callout)
                        .foregroundStyle(backgroundSettings.filenameColor.opacity(0.85))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .transition(.opacity)
    }
}
