import SwiftUI
import CoreGraphics

enum PDFExport {
    enum ExportError: LocalizedError {
        case cannotCreateFile
        case noBoardsSelected

        var errorDescription: String? {
            switch self {
            case .cannotCreateFile: return "Couldn't create the PDF file."
            case .noBoardsSelected: return "Select at least one art board to export."
            }
        }
    }

    /// JPEG quality for photos in the PDF — the trade-off between file size
    /// and detail.
    enum ImageQuality: String, CaseIterable, Identifiable {
        case high = "High"
        case medium = "Medium"
        case small = "Small"

        var id: String { rawValue }

        var jpegQuality: CGFloat {
            switch self {
            case .high: return 0.85
            case .medium: return 0.75
            case .small: return 0.6
            }
        }
    }

    /// Writes `boardIndices` (in the order given) as the pages of one PDF,
    /// each page sized to its board. Pages are drawn directly rather than
    /// flattened into one picture each: backgrounds are plain fills, text is
    /// real (sharp, selectable) text, and each photo is embedded once as a
    /// JPEG of only its visible part. `dpi` caps how many pixels a photo
    /// gets per inch of page — never more than the original has — which is
    /// what keeps file sizes sensible (a 1920 × 1080 px board counts as a
    /// 26.7 × 15 inch page).
    @MainActor
    static func export(document: CanvasDocument, boardIndices: [Int], dpi: Double, quality: ImageQuality, to url: URL) throws {
        guard !boardIndices.isEmpty else { throw ExportError.noBoardsSelected }
        guard let consumer = CGDataConsumer(url: url as CFURL) else { throw ExportError.cannotCreateFile }

        // The context's own default page box matters even though every page
        // below sets its own via `beginPDFPage`'s dictionary — a zero-sized
        // default here was clipping every page's content to nothing,
        // regardless of the per-page override, producing correctly-counted
        // but entirely blank pages. Use the largest requested board as a
        // safe default.
        let maxSize = boardIndices.reduce(CGSize(width: 1, height: 1)) { partial, boardIndex in
            guard document.boardSizes.indices.contains(boardIndex) else { return partial }
            let size = document.boardDisplaySize(boardIndex)
            return CGSize(width: max(partial.width, size.width), height: max(partial.height, size.height))
        }
        var defaultBox = CGRect(origin: .zero, size: maxSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &defaultBox, nil) else {
            throw ExportError.cannotCreateFile
        }

        let pixelsPerPoint = max(dpi / 72.0, 0.1)
        for boardIndex in boardIndices {
            guard document.boardSizes.indices.contains(boardIndex) else { continue }
            let size = document.boardDisplaySize(boardIndex)
            let pageBox = CGRect(origin: .zero, size: size)
            let pageInfo = [kCGPDFContextMediaBox as String: NSValue(rect: pageBox)] as CFDictionary
            context.beginPDFPage(pageInfo)
            // Text with the default colour resolves against the current
            // appearance — pin it to light so dark mode can't turn it white.
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
                drawPage(document: document, boardIndex: boardIndex, size: size,
                         pixelsPerPoint: pixelsPerPoint, jpegQuality: quality.jpegQuality, in: context)
            }
            context.endPDFPage()
        }
        context.closePDF()
    }

    @MainActor
    private static func drawPage(document: CanvasDocument, boardIndex: Int, size: CGSize, pixelsPerPoint: CGFloat, jpegQuality: CGFloat, in context: CGContext) {
        context.saveGState()
        // Work in the canvas's own top-left, y-down coordinates.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        let page = CGRect(origin: .zero, size: size)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(page)
        context.setFillColor(NSColor(document.boardColor(boardIndex, fallback: .white)).cgColor)
        context.fill(page)

        for item in document.items(onBoard: boardIndex) {
            if item.kind == .text {
                context.saveGState()
                context.clip(to: item.frame)
                context.translateBy(x: item.x, y: item.y)
                TextItemDrawing.draw(item, size: CGSize(width: item.width, height: item.height), in: context)
                context.restoreGState()
            } else {
                drawImage(item, document: document, pixelsPerPoint: pixelsPerPoint, jpegQuality: jpegQuality, in: context)
            }
        }
        context.restoreGState()
    }

    /// Same placement as `CroppedImageView`: the crop says which part of
    /// the whole picture fills the card, so the whole picture spans
    /// `frame / crop` and is fitted (aspect kept) inside that, then clipped
    /// to the card.
    @MainActor
    private static func drawImage(_ item: CanvasItem, document: CanvasDocument, pixelsPerPoint: CGFloat, jpegQuality: CGFloat, in context: CGContext) {
        let url = document.folderURL.appendingPathComponent(item.filename)
        guard let pixelSize = PDFImageEmbedding.orientedPixelSize(of: url) else { return }

        let crop = item.cropRect
        let innerWidth = item.width / max(crop.width, 0.01)
        let innerHeight = item.height / max(crop.height, 0.01)
        let inner = CGRect(x: item.x - crop.minX * innerWidth, y: item.y - crop.minY * innerHeight,
                           width: innerWidth, height: innerHeight)

        let aspect = pixelSize.width / pixelSize.height
        let fitted: CGSize = aspect > inner.width / inner.height
            ? CGSize(width: inner.width, height: inner.width / aspect)
            : CGSize(width: inner.height * aspect, height: inner.height)
        let imageRect = CGRect(x: inner.midX - fitted.width / 2, y: inner.midY - fitted.height / 2,
                               width: fitted.width, height: fitted.height)

        PDFImageEmbedding.draw(url, imageRect: imageRect, clipRect: item.frame,
                               pixelsPerPoint: pixelsPerPoint, jpegQuality: jpegQuality, in: context)
    }
}
