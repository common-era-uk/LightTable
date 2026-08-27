import SwiftUI
import AppKit

private enum Corner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

private enum AspectPreset: Equatable {
    case freeform, original, square, fourFive, threeFour, fiveSeven, nineSixteen, custom
}

struct CropView: View {
    @ObservedObject var document: CanvasDocument
    let itemID: UUID
    @Binding var isPresented: Bool

    @State private var cropRect: CGRect
    @State private var dragBaseline: CGRect?
    @State private var aspectPreset: AspectPreset = .freeform
    @State private var isPortrait = true
    @State private var customRatioW: Double = 1
    @State private var customRatioH: Double = 1
    @State private var exportError: String?
    @State private var draggingCorner: Corner?

    private let minSize: Double = 0.05
    let displaySize: CGSize

    init(document: CanvasDocument, itemID: UUID, isPresented: Binding<Bool>) {
        self.document = document
        self.itemID = itemID
        self._isPresented = isPresented
        let item = document.items.first { $0.id == itemID }
        self._cropRect = State(initialValue: item?.cropRect ?? CGRect(x: 0, y: 0, width: 1, height: 1))

        let maxBox = CGSize(width: 680, height: 520)
        if let item,
           let pixelSize = ImageFileSupport.pixelSize(of: document.folderURL.appendingPathComponent(item.filename)),
           pixelSize.width > 0, pixelSize.height > 0 {
            let imageAspect = pixelSize.width / pixelSize.height
            let boxAspect = maxBox.width / maxBox.height
            if imageAspect > boxAspect {
                self.displaySize = CGSize(width: maxBox.width, height: maxBox.width / imageAspect)
            } else {
                self.displaySize = CGSize(width: maxBox.height * imageAspect, height: maxBox.height)
            }
        } else {
            self.displaySize = CGSize(width: 480, height: 480)
        }
    }

    private var item: CanvasItem? {
        document.items.first { $0.id == itemID }
    }

    /// True pixel aspect ratio (width/height) of the original, uncropped
    /// image — displaySize was constructed to exactly match it.
    private var nativeAspect: Double {
        displaySize.width / displaySize.height
    }

    /// The currently-locked true aspect ratio (width/height), or nil when
    /// freeform. Each named preset stores a "portrait" (<=1) canonical
    /// ratio; the orientation toggle flips it.
    private var targetAspect: Double? {
        let canonical: Double
        switch aspectPreset {
        case .freeform:
            return nil
        case .original:
            canonical = nativeAspect <= 1 ? nativeAspect : 1 / nativeAspect
        case .square:
            canonical = 1
        case .fourFive:
            canonical = 4.0 / 5.0
        case .threeFour:
            canonical = 3.0 / 4.0
        case .fiveSeven:
            canonical = 5.0 / 7.0
        case .nineSixteen:
            canonical = 9.0 / 16.0
        case .custom:
            let raw = customRatioW / max(customRatioH, 0.0001)
            canonical = raw <= 1 ? raw : 1 / raw
        }
        return isPortrait ? canonical : 1 / canonical
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Crop")
                .font(.title2.bold())
            Text("Drag corners to crop. The original file is not modified. Use \"Apply & Export\" to save a copy of the cropped version (into the same folder).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            if let item {
                let fileURL = document.folderURL.appendingPathComponent(item.filename)
                ZStack(alignment: .topLeading) {
                    if let nsImage = ImageCache.shared.image(for: fileURL) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle().fill(Color.gray.opacity(0.3))
                    }

                    cropOverlay
                }
                .frame(width: displaySize.width, height: displaySize.height)
                .coordinateSpace(name: "cropArea")
                .clipped()
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): updateCropCursor(hovering: location)
                    case .ended: updateCropCursor(hovering: nil)
                    }
                }
            }

            aspectControls

            HStack {
                Button("Reset") {
                    aspectPreset = .freeform
                    cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Apply & Export…") { applyCrop(alsoExport: true) }
                    .help("Save the crop and also write a cropped copy of the file, named with a \"-crop\" suffix, into the canvas folder")
                Button("Apply") { applyCrop(alsoExport: false) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: max(displaySize.width + 80, 610), height: displaySize.height + 260 + (aspectPreset == .custom ? 30 : 0))
        .alert("Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { isPresented in if !isPresented { exportError = nil } }
        ), presenting: exportError) { _ in
            Button("OK") { exportError = nil }
        } message: { message in
            Text(message)
        }
    }

    private var aspectControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                presetButton("Freeform", preset: .freeform)
                presetButton("Original", preset: .original)
                presetButton("1:1", preset: .square)
                presetButton("4:5", preset: .fourFive)
                presetButton("3:4", preset: .threeFour)
                presetButton("5:7", preset: .fiveSeven)
                presetButton("9:16", preset: .nineSixteen)
                presetButton("Custom…", preset: .custom)
                Spacer()
                Button("Rotate", systemImage: "rectangle.portrait.rotate") {
                    isPortrait.toggle()
                    applyAspectToCropRect()
                }
                .disabled(aspectPreset == .freeform)
                .labelStyle(.iconOnly)
                .help("Switch between portrait and landscape")
            }

            if aspectPreset == .custom {
                HStack(spacing: 6) {
                    TextField("", value: $customRatioW, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 40)
                        .onChange(of: customRatioW) { _, _ in applyAspectToCropRect() }
                    Text(":")
                    TextField("", value: $customRatioH, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 40)
                        .onChange(of: customRatioH) { _, _ in applyAspectToCropRect() }
                    Text("custom ratio (width : height)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func presetButton(_ title: String, preset: AspectPreset) -> some View {
        let isActive = aspectPreset == preset
        if isActive {
            Button(title) {
                aspectPreset = preset
                applyAspectToCropRect()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button(title) {
                aspectPreset = preset
                applyAspectToCropRect()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    /// Reshapes the current crop rect to match `targetAspect`, keeping its
    /// center fixed, clamped to stay within the image bounds. Called
    /// whenever a preset or the orientation toggle changes.
    private func applyAspectToCropRect() {
        guard let target = targetAspect else { return }
        let normalizedAspect = target / nativeAspect
        let center = CGPoint(x: cropRect.midX, y: cropRect.midY)

        var newWidth = cropRect.height * normalizedAspect
        var newHeight = cropRect.height
        if newWidth > 1 {
            newWidth = 1
            newHeight = newWidth / normalizedAspect
        }
        if newHeight > 1 {
            newHeight = 1
            newWidth = newHeight * normalizedAspect
        }

        var newRect = CGRect(x: center.x - newWidth / 2, y: center.y - newHeight / 2, width: newWidth, height: newHeight)
        newRect.origin.x = min(max(newRect.origin.x, 0), 1 - newRect.width)
        newRect.origin.y = min(max(newRect.origin.y, 0), 1 - newRect.height)
        cropRect = newRect
    }

    /// The crop rect in the display box's own point space — shared by the
    /// overlay's drawing and the cursor hit-testing so they always agree on
    /// where the corners actually are.
    private var rectInView: CGRect {
        CGRect(
            x: cropRect.minX * displaySize.width,
            y: cropRect.minY * displaySize.height,
            width: cropRect.width * displaySize.width,
            height: cropRect.height * displaySize.height
        )
    }

    private func cornerPosition(_ corner: Corner) -> CGPoint {
        let rect = rectInView
        switch corner {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    /// Single source of truth for the crop cursor: hit-tests the same corner
    /// positions the handles are drawn at, and keeps the cursor pinned to
    /// whichever corner is actively being dragged regardless of where the
    /// mouse strays mid-drag.
    private func updateCropCursor(hovering location: CGPoint?) {
        if let draggingCorner {
            setResizeCursor(for: draggingCorner)
            return
        }
        guard let location else {
            NSCursor.arrow.set()
            return
        }
        let hitRadius: Double = 12
        for corner in Corner.allCases {
            let center = cornerPosition(corner)
            if abs(location.x - center.x) <= hitRadius, abs(location.y - center.y) <= hitRadius {
                setResizeCursor(for: corner)
                return
            }
        }
        NSCursor.arrow.set()
    }

    private func setResizeCursor(for corner: Corner) {
        if #available(macOS 15.0, *) {
            switch corner {
            case .topLeft, .bottomRight:
                NSCursor.frameResize(position: .topLeft, directions: .all).set()
            case .topRight, .bottomLeft:
                NSCursor.frameResize(position: .topRight, directions: .all).set()
            }
        } else {
            NSCursor.crosshair.set()
        }
    }

    private var cropOverlay: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: rectInView.width, height: rectInView.height)
                .contentShape(Rectangle())
                .position(x: rectInView.midX, y: rectInView.midY)
                .gesture(moveGesture)

            handle(.topLeft).position(x: rectInView.minX, y: rectInView.minY)
            handle(.topRight).position(x: rectInView.maxX, y: rectInView.minY)
            handle(.bottomLeft).position(x: rectInView.minX, y: rectInView.maxY)
            handle(.bottomRight).position(x: rectInView.maxX, y: rectInView.maxY)
        }
    }

    private func handle(_ corner: Corner) -> some View {
        Circle()
            .fill(Color.accentColor)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .frame(width: 14, height: 14)
            .shadow(radius: 2)
            .gesture(cornerDragGesture(corner))
    }

    /// Both gestures use the crop box's own named coordinate space rather
    /// than each handle's local space — the handles move as a direct result
    /// of the drag, and reading translation from a coordinate space that's
    /// itself moving under the gesture is what caused the handles to jitter.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("cropArea"))
            .onChanged { value in
                let baseline = dragBaseline ?? cropRect
                if dragBaseline == nil { dragBaseline = cropRect }
                let dx = value.translation.width / displaySize.width
                let dy = value.translation.height / displaySize.height
                var newRect = baseline
                newRect.origin.x = min(max(baseline.minX + dx, 0), 1 - baseline.width)
                newRect.origin.y = min(max(baseline.minY + dy, 0), 1 - baseline.height)
                cropRect = newRect
            }
            .onEnded { _ in dragBaseline = nil }
    }

    private func cornerDragGesture(_ corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("cropArea"))
            .onChanged { value in
                draggingCorner = corner
                let baseline = dragBaseline ?? cropRect
                if dragBaseline == nil { dragBaseline = baseline }
                let dx = value.translation.width / displaySize.width
                let dy = value.translation.height / displaySize.height
                let isCenterScale = NSEvent.modifierFlags.contains(.option)
                if let target = targetAspect {
                    let normalizedAspect = target / nativeAspect
                    cropRect = isCenterScale
                        ? centerScaledRectAspectLocked(baseline: baseline, corner: corner, dx: dx, dy: dy, normalizedAspect: normalizedAspect)
                        : adjustedRectAspectLocked(baseline: baseline, corner: corner, dx: dx, dy: dy, normalizedAspect: normalizedAspect)
                } else {
                    cropRect = isCenterScale
                        ? centerScaledRect(baseline: baseline, corner: corner, dx: dx, dy: dy)
                        : adjustedRect(baseline: baseline, corner: corner, dx: dx, dy: dy)
                }
            }
            .onEnded { _ in
                dragBaseline = nil
                draggingCorner = nil
                updateCropCursor(hovering: nil)
            }
    }

    private func adjustedRect(baseline: CGRect, corner: Corner, dx: Double, dy: Double) -> CGRect {
        var minX = baseline.minX
        var minY = baseline.minY
        var maxX = baseline.maxX
        var maxY = baseline.maxY

        switch corner {
        case .topLeft:
            minX = min(max(baseline.minX + dx, 0), baseline.maxX - minSize)
            minY = min(max(baseline.minY + dy, 0), baseline.maxY - minSize)
        case .topRight:
            maxX = max(min(baseline.maxX + dx, 1), baseline.minX + minSize)
            minY = min(max(baseline.minY + dy, 0), baseline.maxY - minSize)
        case .bottomLeft:
            minX = min(max(baseline.minX + dx, 0), baseline.maxX - minSize)
            maxY = max(min(baseline.maxY + dy, 1), baseline.minY + minSize)
        case .bottomRight:
            maxX = max(min(baseline.maxX + dx, 1), baseline.minX + minSize)
            maxY = max(min(baseline.maxY + dy, 1), baseline.minY + minSize)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Freeform version of `adjustedRect` for ⌥-drag: grows symmetrically
    /// from `baseline`'s center instead of anchoring the opposite corner,
    /// clamped so the rect never leaves the unit square.
    private func centerScaledRect(baseline: CGRect, corner: Corner, dx: Double, dy: Double) -> CGRect {
        let isRight = corner == .topRight || corner == .bottomRight
        let isBottom = corner == .bottomLeft || corner == .bottomRight
        let center = CGPoint(x: baseline.midX, y: baseline.midY)

        var newWidth = baseline.width + 2 * (isRight ? dx : -dx)
        var newHeight = baseline.height + 2 * (isBottom ? dy : -dy)

        let maxWidth = 2 * min(center.x, 1 - center.x)
        let maxHeight = 2 * min(center.y, 1 - center.y)
        newWidth = min(max(newWidth, minSize), max(maxWidth, minSize))
        newHeight = min(max(newHeight, minSize), max(maxHeight, minSize))

        return CGRect(x: center.x - newWidth / 2, y: center.y - newHeight / 2, width: newWidth, height: newHeight)
    }

    /// Resizes `baseline` from `corner`, keeping `normalizedAspect` (in
    /// cropRect's normalized units) locked and the opposite corner
    /// anchored, clamped so the rect never leaves the unit square.
    private func adjustedRectAspectLocked(baseline: CGRect, corner: Corner, dx: Double, dy: Double, normalizedAspect: Double) -> CGRect {
        let isRight = corner == .topRight || corner == .bottomRight
        let isBottom = corner == .bottomLeft || corner == .bottomRight

        let widthRaw = baseline.width + (isRight ? dx : -dx)
        let heightRaw = baseline.height + (isBottom ? dy : -dy)

        let scale = max(widthRaw / baseline.width, heightRaw / baseline.height, minSize / baseline.width, minSize / baseline.height)
        var newWidth = baseline.width * scale
        var newHeight = newWidth / normalizedAspect

        let anchorX = isRight ? baseline.minX : baseline.maxX
        let anchorY = isBottom ? baseline.minY : baseline.maxY

        let maxWidthFromBounds = isRight ? 1 - anchorX : anchorX
        let maxHeightFromBounds = isBottom ? 1 - anchorY : anchorY

        if newWidth > maxWidthFromBounds {
            newWidth = maxWidthFromBounds
            newHeight = newWidth / normalizedAspect
        }
        if newHeight > maxHeightFromBounds {
            newHeight = maxHeightFromBounds
            newWidth = newHeight * normalizedAspect
        }
        newWidth = max(newWidth, minSize)
        newHeight = max(newHeight, minSize)

        let x = isRight ? anchorX : anchorX - newWidth
        let y = isBottom ? anchorY : anchorY - newHeight

        return CGRect(x: x, y: y, width: newWidth, height: newHeight)
    }

    /// Aspect-locked version of `adjustedRectAspectLocked` for ⌥-drag: grows
    /// symmetrically from `baseline`'s center, keeping `normalizedAspect`
    /// locked, clamped so the rect never leaves the unit square.
    private func centerScaledRectAspectLocked(baseline: CGRect, corner: Corner, dx: Double, dy: Double, normalizedAspect: Double) -> CGRect {
        let isRight = corner == .topRight || corner == .bottomRight
        let isBottom = corner == .bottomLeft || corner == .bottomRight
        let center = CGPoint(x: baseline.midX, y: baseline.midY)

        let widthRaw = baseline.width + 2 * (isRight ? dx : -dx)
        let heightRaw = baseline.height + 2 * (isBottom ? dy : -dy)
        let scale = max(widthRaw / baseline.width, heightRaw / baseline.height, minSize / baseline.width, minSize / baseline.height)
        var newWidth = baseline.width * scale
        var newHeight = newWidth / normalizedAspect

        let maxWidthFromBounds = 2 * min(center.x, 1 - center.x)
        let maxHeightFromBounds = 2 * min(center.y, 1 - center.y)

        if newWidth > maxWidthFromBounds {
            newWidth = maxWidthFromBounds
            newHeight = newWidth / normalizedAspect
        }
        if newHeight > maxHeightFromBounds {
            newHeight = maxHeightFromBounds
            newWidth = newHeight * normalizedAspect
        }
        newWidth = max(newWidth, minSize)
        newHeight = max(newHeight, minSize)

        return CGRect(x: center.x - newWidth / 2, y: center.y - newHeight / 2, width: newWidth, height: newHeight)
    }

    private func applyCrop(alsoExport: Bool) {
        guard let item else { isPresented = false; return }
        let fileURL = document.folderURL.appendingPathComponent(item.filename)
        let aspect: Double
        if let pixelSize = ImageFileSupport.pixelSize(of: fileURL), pixelSize.width > 0, pixelSize.height > 0 {
            let croppedWidth = cropRect.width * pixelSize.width
            let croppedHeight = cropRect.height * pixelSize.height
            aspect = croppedHeight > 0 ? croppedWidth / croppedHeight : 1
        } else {
            aspect = cropRect.width / max(cropRect.height, 0.01)
        }

        document.registerUndoCheckpoint(actionName: "Crop")
        document.updateItem(itemID) { current in
            current.cropX = cropRect.minX
            current.cropY = cropRect.minY
            current.cropWidth = cropRect.width
            current.cropHeight = cropRect.height
            current.height = aspect > 0 ? current.width / aspect : current.height
        }
        document.save()

        guard alsoExport else {
            isPresented = false
            return
        }

        let base = (item.filename as NSString).deletingPathExtension
        let ext = (item.filename as NSString).pathExtension
        let croppedFilename = ext.isEmpty ? "\(base)-crop" : "\(base)-crop.\(ext)"
        let destinationURL = document.folderURL.appendingPathComponent(croppedFilename)
        do {
            try ImageExport.exportCroppedImage(sourceURL: fileURL, cropRect: cropRect, to: destinationURL)
            isPresented = false
        } catch {
            exportError = error.localizedDescription
        }
    }
}
