import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Puts one image into a PDF page as compactly as possible: only the part
/// that's actually visible, at no more than the resolution the export asks
/// for (and never above the original's own), JPEG-compressed. A CGImage
/// backed by JPEG data is written into the PDF as-is rather than
/// re-encoded losslessly, which is what keeps photo-heavy PDFs small.
enum PDFImageEmbedding {
    /// The image's pixel size with its EXIF orientation applied — what's
    /// actually seen on screen.
    static func orientedPixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// Draws the image at `url` as if its whole picture filled `imageRect`,
    /// showing only what falls inside `clipRect`. `context` must use
    /// top-left, y-down coordinates (the page transform `PDFExport` sets up).
    static func draw(_ url: URL, imageRect: CGRect, clipRect: CGRect, pixelsPerPoint: CGFloat, jpegQuality: CGFloat, in context: CGContext) {
        let visible = imageRect.intersection(clipRect)
        guard !visible.isNull, visible.width > 0, visible.height > 0, imageRect.width > 0, imageRect.height > 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let fullSize = orientedPixelSize(of: url) else { return }

        // Decode (and orient) the whole picture only as large as this
        // placement needs at the requested density, capped at the original.
        let neededLongSide = max(imageRect.width, imageRect.height) * pixelsPerPoint
        let maxPixel = min(ceil(neededLongSide), max(fullSize.width, fullSize.height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 1),
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return }

        // Keep just the visible region's pixels.
        let pixelWidth = CGFloat(decoded.width)
        let pixelHeight = CGFloat(decoded.height)
        let cropPixels = CGRect(
            x: floor((visible.minX - imageRect.minX) / imageRect.width * pixelWidth),
            y: floor((visible.minY - imageRect.minY) / imageRect.height * pixelHeight),
            width: 0, height: 0
        )
        let cropMaxX = min(ceil((visible.maxX - imageRect.minX) / imageRect.width * pixelWidth), pixelWidth)
        let cropMaxY = min(ceil((visible.maxY - imageRect.minY) / imageRect.height * pixelHeight), pixelHeight)
        let pixelRect = CGRect(x: max(cropPixels.minX, 0), y: max(cropPixels.minY, 0),
                               width: cropMaxX - max(cropPixels.minX, 0), height: cropMaxY - max(cropPixels.minY, 0))
        guard pixelRect.width >= 1, pixelRect.height >= 1, let cropped = decoded.cropping(to: pixelRect) else { return }

        // Where those whole pixels land on the page (a hair larger than
        // `visible` from the rounding, trimmed again by the clip below).
        let drawRect = CGRect(
            x: imageRect.minX + pixelRect.minX / pixelWidth * imageRect.width,
            y: imageRect.minY + pixelRect.minY / pixelHeight * imageRect.height,
            width: pixelRect.width / pixelWidth * imageRect.width,
            height: pixelRect.height / pixelHeight * imageRect.height
        )

        let image = hasAlpha(cropped) ? cropped : (jpegBacked(cropped, quality: jpegQuality) ?? cropped)

        context.saveGState()
        context.clip(to: clipRect)
        // The page is y-down; an image draws y-up, so flip locally.
        context.translateBy(x: drawRect.minX, y: drawRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: drawRect.width, height: drawRect.height))
        context.restoreGState()
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    private static func jpegBacked(_ image: CGImage, quality: CGFloat) -> CGImage? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
