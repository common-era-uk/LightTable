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

    /// Renders `boardIndices` (in the order given) as sequential pages of one
    /// PDF, each page sized to that board's own points-based size — pages
    /// can vary in size when boards do (Auto mode), which PDF supports
    /// natively. `dpi` controls the pixel density baked into each page's
    /// raster content, independent of the page's physical size — higher
    /// values look sharper without changing how big the page prints. 72 dpi
    /// matches the app's own on-screen editing resolution (1 point = 1 pixel).
    @MainActor
    static func export(document: CanvasDocument, boardIndices: [Int], dpi: Double, to url: URL) throws {
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

        let scale = max(dpi / 72.0, 0.1)
        for boardIndex in boardIndices {
            guard document.boardSizes.indices.contains(boardIndex) else { continue }
            let size = document.boardDisplaySize(boardIndex)
            let pageBox = CGRect(x: 0, y: 0, width: size.width, height: size.height)

            let renderer = ImageRenderer(content: SingleBoardExportView(document: document, boardIndex: boardIndex, size: size))
            renderer.scale = scale
            guard let cgImage = renderer.cgImage else { continue }

            let pageInfo = [kCGPDFContextMediaBox as String: NSValue(rect: pageBox)] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.draw(cgImage, in: pageBox)
            context.endPDFPage()
        }
        context.closePDF()
    }
}
