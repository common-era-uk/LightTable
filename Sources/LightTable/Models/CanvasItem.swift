import Foundation
import CoreGraphics

struct CanvasItem: Identifiable, Codable, Equatable {
    var id: UUID
    var filename: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    // Crop rect, normalized 0...1 within the original (uncropped) image.
    var cropX: Double
    var cropY: Double
    var cropWidth: Double
    var cropHeight: Double
    /// The file's inode number on disk, used to re-associate this item with
    /// its file after a rename (filenames alone aren't stable). Optional so
    /// older sidecar files without it still decode fine; reconcile fills it
    /// in on next load. nil (missing key) decodes safely via Codable's
    /// default `decodeIfPresent` for Optional properties.
    var fileID: UInt64?

    init(
        id: UUID = UUID(),
        filename: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        cropX: Double = 0,
        cropY: Double = 0,
        cropWidth: Double = 1,
        cropHeight: Double = 1,
        fileID: UInt64? = nil
    ) {
        self.id = id
        self.filename = filename
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.cropX = cropX
        self.cropY = cropY
        self.cropWidth = cropWidth
        self.cropHeight = cropHeight
        self.fileID = fileID
    }

    var frame: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var cropRect: CGRect {
        CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
    }
}
