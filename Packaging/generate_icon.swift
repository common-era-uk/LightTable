import AppKit

// Editable source for the app icon. Run with:
//   swift Packaging/generate_icon.swift Packaging/Resources/LightTable_icon_1024.png
// then rebuild the .iconset/.icns from that PNG (see build_app.sh comments,
// or just re-run the iconutil steps used when this file was last regenerated).

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()

let cornerRadius: CGFloat = size * 0.225
let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
let clipPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
clipPath.addClip()

// Full-bleed sunset gradient — the same gradient that used to sit inside
// the old card's photo inset, now filling the entire icon.
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.55, alpha: 1.0),
    NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.42, alpha: 1.0),
    NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.48, alpha: 1.0),
    NSColor(calibratedRed: 0.18, green: 0.16, blue: 0.30, alpha: 1.0)
], atLocations: [0.0, 0.4, 0.72, 1.0], colorSpace: .deviceRGB)!
gradient.draw(in: bgRect, angle: -90)

// Sun disc — size/position tuned interactively; final values below.
let sunRadius = size * 0.11 * 1.2 * 1.1 * 1.05
let sunCenter = CGPoint(x: size * 0.5, y: size * 0.53)
NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.85, alpha: 0.95).setFill()
NSBezierPath(ovalIn: CGRect(x: sunCenter.x - sunRadius, y: sunCenter.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2)).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode icon")
}

let outputPath = CommandLine.arguments[1]
try! png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
