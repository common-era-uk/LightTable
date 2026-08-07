import Foundation
import ImageIO
import CoreGraphics

enum ImageExport {
    enum ExportError: LocalizedError {
        case cannotLoadSource
        case cannotCropImage
        case cannotWriteDestination

        var errorDescription: String? {
            switch self {
            case .cannotLoadSource: return "Couldn't read the original image."
            case .cannotCropImage: return "Couldn't crop the image."
            case .cannotWriteDestination: return "Couldn't write the exported file. This image format may not support saving."
            }
        }
    }

    /// Bakes `cropRect` (normalized 0...1, top-left origin — same convention
    /// as `CanvasItem.cropRect`) into the actual pixels of `sourceURL` and
    /// writes the result to `destinationURL`, overwriting it if present.
    /// The source file itself is never touched.
    static func exportCroppedImage(sourceURL: URL, cropRect: CGRect, to destinationURL: URL) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw ExportError.cannotLoadSource
        }

        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height

        var x = Int((cropRect.minX * Double(pixelWidth)).rounded())
        var y = Int((cropRect.minY * Double(pixelHeight)).rounded())
        var w = Int((cropRect.width * Double(pixelWidth)).rounded())
        var h = Int((cropRect.height * Double(pixelHeight)).rounded())
        x = min(max(x, 0), max(pixelWidth - 1, 0))
        y = min(max(y, 0), max(pixelHeight - 1, 0))
        w = min(max(w, 1), pixelWidth - x)
        h = min(max(h, 1), pixelHeight - y)

        guard let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
            throw ExportError.cannotCropImage
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        let sourceType = CGImageSourceGetType(source) ?? "public.jpeg" as CFString

        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, sourceType, 1, nil) else {
            throw ExportError.cannotWriteDestination
        }
        CGImageDestinationAddImage(destination, cropped, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.cannotWriteDestination
        }
    }
}
