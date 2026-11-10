import Foundation
import CoreGraphics

/// Settings for "Auto-translate to pages". Every length is in points (the
/// unit boards are stored in); the sheet converts from whatever unit it
/// shows.
struct PageLayoutOptions: Equatable {
    var pageWidth: Double = 1920
    var pageHeight: Double = 1080
    var marginTop: Double = 100
    var marginRight: Double = 100
    var marginBottom: Double = 100
    var marginLeft: Double = 100
    /// Space between neighbouring images on one page.
    var gap: Double = 140
    /// Two neighbouring images in a row share a page when the space between
    /// them is under this percentage of the average image width.
    var groupingPercent: Double = 35
}

/// The geometry behind "Auto-translate to pages", kept free of any document
/// types so it can be tested on its own.
enum PageLayout {
    struct Entry {
        let id: UUID
        let frame: CGRect
    }

    /// Splits `entries` (one board's worth, in that board's own coordinates)
    /// into pages: rows top-to-bottom, left-to-right within a row, with each
    /// row cut into groups wherever the gap between neighbours is wider than
    /// the grouping threshold. Stacked images fall into separate rows, so
    /// they end up on separate pages.
    static func pages(from entries: [Entry], groupingPercent: Double) -> [[UUID]] {
        guard !entries.isEmpty else { return [] }
        let averageWidth = entries.reduce(0.0) { $0 + $1.frame.width } / Double(entries.count)
        let threshold = averageWidth * groupingPercent / 100

        var pages: [[UUID]] = []
        for row in rows(of: entries) {
            var group: [Entry] = []
            var groupRight = -Double.infinity
            for entry in row {
                if !group.isEmpty, entry.frame.minX - groupRight > threshold {
                    pages.append(group.map(\.id))
                    group = []
                    groupRight = -Double.infinity
                }
                group.append(entry)
                groupRight = max(groupRight, entry.frame.maxX)
            }
            if !group.isEmpty { pages.append(group.map(\.id)) }
        }
        return pages
    }

    /// Visual rows by y-proximity, each sorted left-to-right. Mirrors
    /// `CanvasDocument.rowGroupedReadingOrder` (the same rule the preview's
    /// arrow-key navigation and Create Grid use), so a page sequence always
    /// matches the reading order people already see.
    static func rows(of entries: [Entry]) -> [[Entry]] {
        guard !entries.isEmpty else { return [] }
        let sortedByY = entries.sorted { $0.frame.minY < $1.frame.minY }
        let averageHeight = entries.reduce(0.0) { $0 + $1.frame.height } / Double(entries.count)
        let rowThreshold = max(averageHeight * 0.5, 20)

        var rows: [[Entry]] = []
        var currentRow: [Entry] = []
        var currentRowY = sortedByY[0].frame.minY
        for entry in sortedByY {
            if entry.frame.minY - currentRowY > rowThreshold {
                rows.append(currentRow)
                currentRow = []
                currentRowY = entry.frame.minY
            }
            currentRow.append(entry)
        }
        if !currentRow.isEmpty { rows.append(currentRow) }
        return rows.map { $0.sorted { $0.frame.minX < $1.frame.minX } }
    }

    /// Places images with the given width/height `aspects` side by side on
    /// one page: all at one shared height, as large as fits inside the
    /// margins, and the whole row centred both ways in the margin box.
    /// Returns one frame per aspect, in order.
    static func layout(aspects: [Double], options: PageLayoutOptions) -> [CGRect] {
        guard !aspects.isEmpty else { return [] }
        let safeAspects = aspects.map { $0 > 0 ? $0 : 1 }
        let contentX = options.marginLeft
        let contentY = options.marginTop
        let contentWidth = max(options.pageWidth - options.marginLeft - options.marginRight, 1)
        let contentHeight = max(options.pageHeight - options.marginTop - options.marginBottom, 1)

        let totalGap = options.gap * Double(safeAspects.count - 1)
        let widthForImages = max(contentWidth - totalGap, 1)
        let height = min(contentHeight, widthForImages / safeAspects.reduce(0, +))

        let rowWidth = safeAspects.reduce(0.0) { $0 + $1 * height } + totalGap
        var x = contentX + (contentWidth - rowWidth) / 2
        let y = contentY + (contentHeight - height) / 2

        return safeAspects.map { aspect in
            let frame = CGRect(x: x, y: y, width: aspect * height, height: height)
            x += frame.width + options.gap
            return frame
        }
    }
}
