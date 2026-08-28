import Foundation
import CoreGraphics

enum ItemKind: String, Codable {
    case image
    case text
}

enum TextAlignmentOption: String, Codable, CaseIterable, Identifiable {
    case leading, center, trailing

    var id: String { rawValue }
}

struct CanvasItem: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: ItemKind
    var filename: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    // Crop rect, normalized 0...1 within the original (uncropped) image.
    // Unused for text items.
    var cropX: Double
    var cropY: Double
    var cropWidth: Double
    var cropHeight: Double
    /// The file's inode number on disk, used to re-associate this item with
    /// its file after a rename (filenames alone aren't stable). Optional so
    /// older sidecar files without it still decode fine; reconcile fills it
    /// in on next load. nil (missing key) decodes safely via Codable's
    /// default `decodeIfPresent` for Optional properties. Unused for text.
    var fileID: UInt64?
    /// Which art board this item belongs to — an index into
    /// `CanvasDocument.boardSizes`. `x`/`y` are local to that board's own
    /// origin, not global canvas coordinates. Missing key (older single-board
    /// `.lt` files) decodes to 0, matching migration into a single Board 1.
    var boardIndex: Int

    // MARK: - Text-only fields (ignored for `.image` items)

    var text: String
    /// A text *box* wraps its content within `width`, like a paragraph; a
    /// text *field* doesn't wrap on its own (only an explicit Return breaks
    /// a line).
    var isTextBox: Bool
    var fontName: String
    /// The font size at the item's current `height` — resizing the item's
    /// frame (the same corner-drag used for images) scales this
    /// proportionally, so changing text size works the same way as scaling
    /// an image.
    var fontSize: Double
    var isBold: Bool
    var isItalic: Bool
    var letterSpacing: Double
    /// A multiplier on the font's natural line height (1.0 = normal).
    var lineSpacing: Double
    var textAlignment: TextAlignmentOption
    /// nil means the default (primary/label) text color.
    var textColor: RGBAColor?

    init(
        id: UUID = UUID(),
        kind: ItemKind = .image,
        filename: String = "",
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        cropX: Double = 0,
        cropY: Double = 0,
        cropWidth: Double = 1,
        cropHeight: Double = 1,
        fileID: UInt64? = nil,
        boardIndex: Int = 0,
        text: String = "",
        isTextBox: Bool = false,
        fontName: String = "Helvetica",
        fontSize: Double = 36,
        isBold: Bool = false,
        isItalic: Bool = false,
        letterSpacing: Double = 0,
        lineSpacing: Double = 1.2,
        textAlignment: TextAlignmentOption = .leading,
        textColor: RGBAColor? = nil
    ) {
        self.id = id
        self.kind = kind
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
        self.boardIndex = boardIndex
        self.text = text
        self.isTextBox = isTextBox
        self.fontName = fontName
        self.fontSize = fontSize
        self.isBold = isBold
        self.isItalic = isItalic
        self.letterSpacing = letterSpacing
        self.lineSpacing = lineSpacing
        self.textAlignment = textAlignment
        self.textColor = textColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decodeIfPresent(ItemKind.self, forKey: .kind) ?? .image
        filename = try container.decodeIfPresent(String.self, forKey: .filename) ?? ""
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        cropX = try container.decode(Double.self, forKey: .cropX)
        cropY = try container.decode(Double.self, forKey: .cropY)
        cropWidth = try container.decode(Double.self, forKey: .cropWidth)
        cropHeight = try container.decode(Double.self, forKey: .cropHeight)
        fileID = try container.decodeIfPresent(UInt64.self, forKey: .fileID)
        boardIndex = try container.decodeIfPresent(Int.self, forKey: .boardIndex) ?? 0
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        isTextBox = try container.decodeIfPresent(Bool.self, forKey: .isTextBox) ?? false
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? "Helvetica"
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 36
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        letterSpacing = try container.decodeIfPresent(Double.self, forKey: .letterSpacing) ?? 0
        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 1.2
        textAlignment = try container.decodeIfPresent(TextAlignmentOption.self, forKey: .textAlignment) ?? .leading
        textColor = try container.decodeIfPresent(RGBAColor.self, forKey: .textColor)
    }

    var frame: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var cropRect: CGRect {
        CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
    }
}
