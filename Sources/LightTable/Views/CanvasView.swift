import SwiftUI
import UniformTypeIdentifiers
import AppKit

private enum ResizableEdge {
    case right, bottom
}

/// Bridges `NSColorPanel`'s Objective-C target-action mechanism (there's no
/// closure-based API) into a Swift closure, so the toolbar's color button
/// can drive it directly instead of using SwiftUI's `ColorPicker` — which
/// only ever renders as a swatch filled with the current color, not the
/// small fixed rainbow-wheel icon that's wanted here.
private final class ColorPanelCoordinator: NSObject {
    let onChange: (Color) -> Void

    init(onChange: @escaping (Color) -> Void) {
        self.onChange = onChange
    }

    @objc func colorChanged(_ sender: NSColorPanel) {
        onChange(Color(nsColor: sender.color))
    }
}

struct CanvasView: View {
    @ObservedObject var document: CanvasDocument
    @Binding var hostWindow: NSWindow?
    var onChangeFolder: () -> Void

    @State private var cropModeItemID: UUID?
    @State private var showRenameSheet = false
    @State private var previewItemID: UUID?
    @State private var isSpaceDown = false
    @State private var spacePanBaseline: CGSize?
    @State private var spacePanVelocity: CGSize = .zero
    @State private var spacePanLastTranslation: CGSize = .zero
    @State private var spacePanLastSampleTime: Date = Date()
    @State private var spacePanMomentumTimer: Timer?
    @State private var showFilenames = false
    @State private var showGuides = true
    @State private var colorPanelCoordinator: ColorPanelCoordinator?
    @State private var exportFormatCoordinator: ExportFormatCoordinator?
    @State private var keyMonitor: Any?
    @State private var scrollMonitor: Any?
    @State private var zoom: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var viewportSize: CGSize = .zero

    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?

    @State private var widthDragBaseline: Double?
    @State private var heightDragBaseline: Double?
    @State private var draggingEdge: ResizableEdge?

    @State private var pendingGuide: PendingGuide?

    private let minZoom: CGFloat = 0.2
    private let maxZoom: CGFloat = 3.0
    private let rulerThickness: Double = 14

    private var contentSize: CGSize {
        let extents = document.items.reduce(into: (maxX: 0.0, maxY: 0.0)) { acc, item in
            acc.maxX = max(acc.maxX, item.x + item.width)
            acc.maxY = max(acc.maxY, item.y + item.height)
        }
        return CGSize(
            width: max(extents.maxX + 200, document.canvasWidth),
            height: max(extents.maxY + 200, document.canvasHeight)
        )
    }

    /// Where the canvas content currently lands on screen, in the outer
    /// (untransformed) viewport's own coordinate space.
    private var canvasScreenRect: CGRect {
        CGRect(
            x: panOffset.width,
            y: panOffset.height,
            width: contentSize.width * zoom,
            height: contentSize.height * zoom
        )
    }

    /// The region of canvas-logical space currently visible in the viewport,
    /// derived by inverting the pan/zoom transform.
    private var visibleCanvasRect: CGRect {
        let rect = CGRect(
            x: -panOffset.width / zoom,
            y: -panOffset.height / zoom,
            width: viewportSize.width / zoom,
            height: viewportSize.height / zoom
        )
        return rect.intersection(CGRect(origin: .zero, size: contentSize))
    }

    /// Every card's left/right edges, offered to `RulerZones` so a guide
    /// being dragged in from the ruler can snap to them, the same way cards
    /// snap to guides.
    private var cardEdgesX: [Double] {
        document.items.flatMap { [$0.x, $0.x + $0.width] }
    }

    private var cardEdgesY: [Double] {
        document.items.flatMap { [$0.y, $0.y + $0.height] }
    }

    private var marqueeRect: CGRect? {
        guard let start = marqueeStart, let current = marqueeCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor)

                ZStack(alignment: .topLeading) {
                    document.canvasColor?.color ?? Color(nsColor: .textBackgroundColor)
                    ForEach(document.items) { item in
                        ImageCardView(document: document, itemID: item.id, cropModeItemID: $cropModeItemID, showFilenames: showFilenames, zoom: zoom)
                    }
                    if let rect = marqueeRect {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.15))
                            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                    }
                    Rectangle()
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        .frame(width: contentSize.width, height: contentSize.height)
                        .allowsHitTesting(false)

                    if showGuides {
                        GuideLinesLayer(
                            verticalGuides: document.verticalGuides,
                            horizontalGuides: document.horizontalGuides,
                            selectedGuideID: document.selectedGuideID,
                            pendingGuide: pendingGuide,
                            contentSize: contentSize,
                            guideColor: document.guideColor?.color ?? .blue,
                            zoom: zoom,
                            panOffset: panOffset,
                            rulerThickness: rulerThickness,
                            cardEdgesX: cardEdgesX,
                            cardEdgesY: cardEdgesY,
                            onSelectGuide: { id in
                                document.selectedGuideID = id
                                document.selectedIDs = []
                            },
                            onMoveGuide: { id, position in document.moveGuide(id, to: position) },
                            onRemoveGuide: { id in document.removeGuide(id) }
                        )
                    }
                }
                .frame(width: contentSize.width, height: contentSize.height)
                .coordinateSpace(name: "canvas")
                .onDrop(of: [.fileURL], delegate: CanvasDropDelegate(document: document))
                .gesture(marqueeGesture)
                .scaleEffect(zoom)
                .position(
                    x: contentSize.width / 2 * zoom + panOffset.width,
                    y: contentSize.height / 2 * zoom + panOffset.height
                )

                // Edge handles live in the outer, untransformed coordinate
                // space (not inside the scaled/offset content) so their own
                // drag translation stays stable regardless of zoom/pan.
                rightEdgeHandle
                bottomEdgeHandle
                if showGuides {
                    RulerZones(
                        viewportSize: viewportSize,
                        zoom: zoom,
                        panOffset: panOffset,
                        rulerThickness: rulerThickness,
                        cardEdgesX: cardEdgesX,
                        cardEdgesY: cardEdgesY,
                        onPendingGuideChanged: { pendingGuide = $0 },
                        onAddVerticalGuide: { x in document.addVerticalGuide(at: x) },
                        onAddHorizontalGuide: { y in document.addHorizontalGuide(at: y) }
                    )
                }
                spacePanOverlay
            }
            .coordinateSpace(name: "viewport")
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .clipped()
            .onTapGesture {
                document.selectedIDs = []
                document.selectedGuideID = nil
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): updateEdgeCursor(hovering: location)
                case .ended: updateEdgeCursor(hovering: nil)
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0 }
        }
        .navigationTitle(document.ltFileURL.deletingPathExtension().lastPathComponent)
        .toolbar {
            ToolbarItemGroup {
                Text("\(Int(zoom * 100))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.leading, 8)
                Button("Zoom Out", systemImage: "minus.magnifyingglass") {
                    setZoom(zoom - 0.25)
                }
                .keyboardShortcut("-", modifiers: .command)
                .help("Zoom out")
                Button("Zoom In", systemImage: "plus.magnifyingglass") {
                    setZoom(zoom + 0.25)
                }
                .keyboardShortcut("=", modifiers: .command)
                .help("Zoom in")
                Button("Reset View", systemImage: "arrow.up.left.and.down.right.magnifyingglass") {
                    zoom = 1
                    panOffset = .zero
                }
                .keyboardShortcut("0", modifiers: .command)
                .help("Reset zoom and position")
                guidesToggle
                filenamesToggle
                Button("Canvas Color", systemImage: "paintpalette.fill") {
                    showColorPanel()
                }
                .symbolRenderingMode(.multicolor)
                .help("Set a custom canvas background color")
                Divider()
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    document.duplicateItems(document.selectedIDs)
                }
                .disabled(document.selectedIDs.isEmpty)
                .help("Duplicate the selected image(s), each as a new \"-copy\" file added to the canvas")
                Button("Crop", systemImage: "crop") {
                    if let id = document.selectedIDs.first, document.selectedIDs.count == 1 {
                        cropModeItemID = id
                    }
                }
                .disabled(document.selectedIDs.count != 1)
                .help("Crop the selected image")
                Button("Delete", systemImage: "trash") {
                    performDelete()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(document.selectedIDs.isEmpty && document.selectedGuideID == nil)
                .help("Remove from canvas, keeping the file in the folder. ⌘-Delete also moves the file to Trash. Deletes the selected guide instead if one is selected.")
                Divider()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    document.refreshFromDisk()
                }
                .help("Re-read this folder and re-flow all images into a fresh grid, resizing the canvas to fit — handy for regrouping after deleting several images")
                Button("Save Visible Area…", systemImage: "viewfinder") {
                    exportCanvas(cropToVisible: true)
                }
                .disabled(document.items.isEmpty)
                .help("Save visible area as an image")
                Button("Save Whole Canvas…", systemImage: "square.and.arrow.down.on.square") {
                    exportCanvas(cropToVisible: false)
                }
                .disabled(document.items.isEmpty)
                .help("Save whole canvas as an image")
                Divider()
                Button("Open Folder…", systemImage: "folder") {
                    onChangeFolder()
                }
                .help("Open a different folder")
                Button("Rename All…", systemImage: "r.square.on.square") {
                    showRenameSheet = true
                }
                .disabled(document.items.isEmpty)
                .help("Rename all images in sequence")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleShowGuides)) { _ in
            guard hostWindow != nil, hostWindow === NSApp.keyWindow else { return }
            showGuides.toggle()
            if !showGuides { document.selectedGuideID = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGuideColorPicker)) { _ in
            guard hostWindow != nil, hostWindow === NSApp.keyWindow else { return }
            showGuideColorPanel()
        }
        .modifier(EditMenuCommands(
            document: document,
            hostWindow: hostWindow,
            cropModeItemID: $cropModeItemID,
            showRenameSheet: $showRenameSheet,
            performDelete: performDelete
        ))
        .onReceive(NotificationCenter.default.publisher(for: .refreshAndReflow)) { _ in
            guard hostWindow != nil, hostWindow === NSApp.keyWindow else { return }
            document.refreshFromDisk()
        }
        .onAppear {
            installKeyMonitor()
            installScrollMonitor()
            // hostWindow may already be set by the time this fires, or may
            // only arrive later via WindowAccessor's async assignment — the
            // onChange below covers that second case.
            hostWindow?.representedURL = document.ltFileURL
        }
        .onDisappear {
            removeKeyMonitor()
            removeScrollMonitor()
            spacePanMomentumTimer?.invalidate()
        }
        .onChange(of: hostWindow) { _, newWindow in
            // Setting this gives the window a proxy icon and lets the user
            // ⌘-click (or right-click the proxy icon) the title bar to see
            // the .lt file's full path, exactly like any document window.
            newWindow?.representedURL = document.ltFileURL
        }
        .sheet(isPresented: cropSheetBinding) {
            if let id = cropModeItemID {
                CropView(document: document, itemID: id, isPresented: cropSheetBinding)
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            RenamePanelView(document: document, isPresented: $showRenameSheet)
        }
        .alert("Can't Add Image", isPresented: Binding(
            get: { document.importError != nil },
            set: { isPresented in if !isPresented { document.importError = nil } }
        ), presenting: document.importError) { _ in
            Button("OK") { document.importError = nil }
        } message: { message in
            Text(message)
        }
        .overlay {
            if let previewItemID, let item = document.items.first(where: { $0.id == previewItemID }) {
                PreviewOverlayView(document: document, item: item, containerSize: viewportSize) {
                    self.previewItemID = nil
                }
            }
        }
    }

    private var cropSheetBinding: Binding<Bool> {
        Binding(
            get: { cropModeItemID != nil },
            set: { if !$0 { cropModeItemID = nil } }
        )
    }

    /// A single, stable button (no `.buttonStyle()` override, so it looks
    /// and behaves exactly like the other plain toolbar buttons) with a
    /// background applied only in the active state — an approximation of
    /// the same darkening the other toolbar buttons show natively on hover
    /// (that's AppKit toolbar chrome applied automatically to a plain
    /// button; there's no SwiftUI-exposed style to read and reuse directly,
    /// so this hand-tunes a circle to match it). Only the background value
    /// changes between states (not the button's style/identity), so
    /// there's no pop-in when toggling.
    private var guidesToggle: some View {
        Button("Guides", systemImage: "grid") {
            showGuides.toggle()
            if !showGuides { document.selectedGuideID = nil }
        }
        .frame(width: 22, height: 22)
        .background(showGuides ? Color.primary.opacity(0.12) : Color.clear, in: Circle())
        .help(showGuides ? "Hide guides" : "Show guides and the ruler strips used to create them")
    }

    private var filenamesToggle: some View {
        Button("Filenames", systemImage: "text.below.photo") {
            showFilenames.toggle()
        }
        .frame(width: 22, height: 22)
        .background(showFilenames ? Color.primary.opacity(0.12) : Color.clear, in: Circle())
        .help(showFilenames ? "Hide filenames" : "Show filenames under each image")
    }

    /// Opens the system color panel seeded with the canvas's current
    /// background (the system default when no custom color has been set
    /// yet), routing live changes back into `document.canvasColor`.
    private func showColorPanel() {
        openColorPanel(current: document.canvasColor?.color ?? Color(nsColor: .textBackgroundColor)) { newColor in
            document.canvasColor = RGBAColor(color: newColor)
            document.save()
        }
    }

    /// Same as `showColorPanel`, but for the guide color (default blue when
    /// unset). Triggered from the View menu via `openGuideColorPicker`.
    private func showGuideColorPanel() {
        openColorPanel(current: document.guideColor?.color ?? .blue) { newColor in
            document.guideColor = RGBAColor(color: newColor)
            document.save()
        }
    }

    private func openColorPanel(current: Color, onChange: @escaping (Color) -> Void) {
        let coordinator = ColorPanelCoordinator(onChange: onChange)
        colorPanelCoordinator = coordinator

        let panel = NSColorPanel.shared
        panel.setTarget(coordinator)
        panel.setAction(#selector(ColorPanelCoordinator.colorChanged(_:)))
        panel.color = NSColor(current)
        panel.orderFront(nil)
    }

    /// Shared by the toolbar's Delete button and the Edit menu's Delete
    /// item: deletes the selected guide if one is selected, else removes
    /// the selected cards from the canvas (keeping their files).
    private func performDelete() {
        if let guideID = document.selectedGuideID {
            document.removeGuide(guideID)
        } else {
            document.removeFromCanvas(document.selectedIDs)
        }
    }

    // MARK: - Marquee (click-drag) multi-select

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
            .onChanged { value in
                if marqueeStart == nil { marqueeStart = value.startLocation }
                marqueeCurrent = value.location
            }
            .onEnded { _ in
                if let rect = marqueeRect {
                    let matched = document.items.filter { $0.frame.intersects(rect) }
                    document.selectedIDs = Set(matched.map { $0.id })
                    document.selectedGuideID = nil
                }
                marqueeStart = nil
                marqueeCurrent = nil
            }
    }

    // MARK: - Space-drag panning

    /// While Space is held, a transparent layer sits on top of everything
    /// else in the viewport (cards, guides, edge handles) so a click-drag
    /// anywhere pans the canvas instead of moving a card or marquee-selecting
    /// — it only takes over hit-testing while `isSpaceDown`, so it's
    /// otherwise invisible to every gesture beneath it.
    private var spacePanOverlay: some View {
        Color.clear
            .frame(width: viewportSize.width, height: viewportSize.height)
            .contentShape(Rectangle())
            .gesture(spacePanGesture)
            .allowsHitTesting(isSpaceDown)
    }

    private var spacePanGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("viewport"))
            .onChanged { value in
                NSCursor.closedHand.set()
                if spacePanBaseline == nil {
                    spacePanMomentumTimer?.invalidate()
                    spacePanBaseline = panOffset
                    spacePanLastTranslation = .zero
                    spacePanLastSampleTime = Date()
                    spacePanVelocity = .zero
                }
                let baseline = spacePanBaseline ?? panOffset
                panOffset = CGSize(width: baseline.width + value.translation.width, height: baseline.height + value.translation.height)

                // Sample velocity from the translation delta since the last
                // tick, so a released drag can carry on with the same
                // trailing speed — matching the trackpad's own momentum.
                let now = Date()
                let dt = now.timeIntervalSince(spacePanLastSampleTime)
                if dt > 0.008 {
                    spacePanVelocity = CGSize(
                        width: (value.translation.width - spacePanLastTranslation.width) / dt,
                        height: (value.translation.height - spacePanLastTranslation.height) / dt
                    )
                    spacePanLastTranslation = value.translation
                    spacePanLastSampleTime = now
                }
            }
            .onEnded { _ in
                spacePanBaseline = nil
                NSCursor.openHand.set()
                startSpacePanMomentum()
            }
    }

    /// Carries the pan on after release with the drag's trailing velocity,
    /// decaying by friction every frame until it's imperceptible — the same
    /// deceleration feel as a trackpad swipe's momentum scrolling.
    private func startSpacePanMomentum() {
        spacePanMomentumTimer?.invalidate()
        guard abs(spacePanVelocity.width) > 20 || abs(spacePanVelocity.height) > 20 else { return }

        let friction = 0.93
        let frameInterval = 1.0 / 60.0
        spacePanMomentumTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { timer in
            spacePanVelocity = CGSize(width: spacePanVelocity.width * friction, height: spacePanVelocity.height * friction)
            panOffset = CGSize(
                width: panOffset.width + spacePanVelocity.width * frameInterval,
                height: panOffset.height + spacePanVelocity.height * frameInterval
            )
            if abs(spacePanVelocity.width) < 3, abs(spacePanVelocity.height) < 3 {
                timer.invalidate()
            }
        }
    }

    // MARK: - Guides
    //
    // Rendering and gesture handling live in `GuideLinesLayer` and
    // `RulerZones` (separate `Equatable` views) rather than here, so a card
    // drag — which changes `document.groupDragOffset` continuously, and
    // this view holds `@ObservedObject var document` — doesn't force
    // reconstructing every guide's gesture recognizers on every frame.

    private var topRulerHitRect: CGRect {
        CGRect(x: 0, y: 0, width: viewportSize.width, height: rulerThickness)
    }

    private var leftRulerHitRect: CGRect {
        CGRect(x: 0, y: 0, width: rulerThickness, height: viewportSize.height)
    }

    // MARK: - Canvas edge resize handles

    private let edgeHitWidth: Double = 20
    /// Edges are inset away from the corners so the left/right and top/bottom
    /// hit regions never overlap and fight over the same drag.
    private var edgeInset: Double { edgeHitWidth * 2 }

    private var rightEdgeHitRect: CGRect {
        let rect = canvasScreenRect
        return CGRect(
            x: rect.maxX - edgeHitWidth / 2,
            y: rect.minY + edgeInset / 2,
            width: edgeHitWidth,
            height: max(rect.height - edgeInset, 0)
        )
    }

    private var bottomEdgeHitRect: CGRect {
        let rect = canvasScreenRect
        return CGRect(
            x: rect.minX + edgeInset / 2,
            y: rect.maxY - edgeHitWidth / 2,
            width: max(rect.width - edgeInset, 0),
            height: edgeHitWidth
        )
    }

    private var rightEdgeHandle: some View {
        let rect = canvasScreenRect
        return Rectangle()
            .fill(Color.secondary.opacity(0.001))
            .overlay(Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 3))
            .frame(width: edgeHitWidth, height: max(rect.height - edgeInset, 0))
            .contentShape(Rectangle())
            .position(x: rect.maxX, y: rect.midY)
            .gesture(rightEdgeDragGesture)
    }

    private var bottomEdgeHandle: some View {
        let rect = canvasScreenRect
        return Rectangle()
            .fill(Color.secondary.opacity(0.001))
            .overlay(Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 3))
            .frame(width: max(rect.width - edgeInset, 0), height: edgeHitWidth)
            .contentShape(Rectangle())
            .position(x: rect.midX, y: rect.maxY)
            .gesture(bottomEdgeDragGesture)
    }

    /// Single source of truth for the resize cursor: hit-tests the same
    /// rects the handles are drawn at, and forces the cursor to stay put
    /// during an active drag regardless of where the mouse strays.
    private func updateEdgeCursor(hovering location: CGPoint?) {
        if isSpaceDown {
            (spacePanBaseline != nil ? NSCursor.closedHand : NSCursor.openHand).set()
            return
        }
        if let draggingEdge {
            (draggingEdge == .right ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
            return
        }
        guard let location else {
            NSCursor.arrow.set()
            return
        }
        if showGuides, topRulerHitRect.contains(location) || leftRulerHitRect.contains(location) {
            NSCursor.crosshair.set()
        } else if rightEdgeHitRect.contains(location) {
            NSCursor.resizeLeftRight.set()
        } else if bottomEdgeHitRect.contains(location) {
            NSCursor.resizeUpDown.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    /// Both edge gestures use the default (outer, screen-space) coordinate
    /// space deliberately — it's never itself rescaled/reoffset mid-gesture.

    private var rightEdgeDragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                draggingEdge = .right
                // Baseline is the edge's actual on-screen position
                // (contentSize, which can exceed canvasWidth when images
                // already extend past it), not the raw stored canvasWidth —
                // otherwise a drag has to first "catch up" to where the
                // edge visually is before anything appears to move.
                let baseline = widthDragBaseline ?? contentSize.width
                if widthDragBaseline == nil {
                    widthDragBaseline = baseline
                    document.registerUndoCheckpoint(actionName: "Resize Canvas")
                }
                let growth = value.translation.width / zoom
                document.canvasWidth = min(max(baseline + growth, CanvasDocument.minCanvasDimension), CanvasDocument.maxCanvasDimension)
            }
            .onEnded { _ in
                widthDragBaseline = nil
                draggingEdge = nil
                updateEdgeCursor(hovering: nil)
                document.save()
            }
    }

    private var bottomEdgeDragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                draggingEdge = .bottom
                let baseline = heightDragBaseline ?? contentSize.height
                if heightDragBaseline == nil {
                    heightDragBaseline = baseline
                    document.registerUndoCheckpoint(actionName: "Resize Canvas")
                }
                let growth = value.translation.height / zoom
                document.canvasHeight = min(max(baseline + growth, CanvasDocument.minCanvasDimension), CanvasDocument.maxCanvasDimension)
            }
            .onEnded { _ in
                heightDragBaseline = nil
                draggingEdge = nil
                updateEdgeCursor(hovering: nil)
                document.save()
            }
    }

    // MARK: - Export

    private func exportCanvas(cropToVisible: Bool) {
        let exportScale: CGFloat = 2
        let renderer = ImageRenderer(content: CanvasExportView(document: document, contentSize: contentSize))
        renderer.scale = exportScale
        guard let fullImage = renderer.cgImage else { return }

        var finalImage = fullImage
        if cropToVisible {
            let rect = visibleCanvasRect
            let pixelRect = CGRect(
                x: rect.minX * exportScale,
                y: rect.minY * exportScale,
                width: rect.width * exportScale,
                height: rect.height * exportScale
            )
            if let cropped = fullImage.cropping(to: pixelRect) {
                finalImage = cropped
            }
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        let suffix = cropToVisible ? " (visible)" : ""
        let baseName = "\(document.ltFileURL.deletingPathExtension().lastPathComponent)\(suffix)"
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(baseName).png"
        let formatCoordinator = ExportFormatCoordinator(panel: panel, baseName: baseName)
        exportFormatCoordinator = formatCoordinator
        panel.accessoryView = formatCoordinator.makeAccessoryView()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let bitmapRep = NSBitmapImageRep(cgImage: finalImage)
        let isJPEG = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        let fileType: NSBitmapImageRep.FileType = isJPEG ? .jpeg : .png
        let properties: [NSBitmapImageRep.PropertyKey: Any] = isJPEG ? [.compressionFactor: 0.9] : [:]
        guard let data = bitmapRep.representation(using: fileType, properties: properties) else { return }
        try? data.write(to: url)
    }

    /// Changes zoom while keeping the logical point currently at the center
    /// of the viewport fixed on screen.
    private func setZoom(_ value: CGFloat) {
        let newZoom = min(max(value, minZoom), maxZoom)
        guard newZoom != zoom else { return }

        let viewport = viewportSize
        guard viewport != .zero else {
            zoom = newZoom
            return
        }

        let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let logicalPoint = CGPoint(
            x: (center.x - panOffset.width) / zoom,
            y: (center.y - panOffset.height) / zoom
        )
        panOffset = CGSize(
            width: center.x - logicalPoint.x * newZoom,
            height: center.y - logicalPoint.y * newZoom
        )
        zoom = newZoom
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            guard event.window === hostWindow else { return event }

            // Releasing Space always clears the pan-tool state, even if a
            // sheet opened while it was held, so it can never get stuck on.
            if event.keyCode == 49, event.type == .keyUp {
                if isSpaceDown {
                    isSpaceDown = false
                    NSCursor.arrow.set()
                }
                return event
            }
            guard event.type == .keyDown else { return event }

            if event.keyCode == 51 || event.keyCode == 117 {
                if let guideID = document.selectedGuideID {
                    document.removeGuide(guideID)
                    return nil
                }
                if !document.selectedIDs.isEmpty {
                    if event.modifierFlags.contains(.command) {
                        document.deleteItems(document.selectedIDs)
                    } else {
                        document.removeFromCanvas(document.selectedIDs)
                    }
                    return nil
                }
            }

            guard cropModeItemID == nil, !showRenameSheet else { return event }

            // Space toggles a large preview of the single selected card,
            // closed again with Space or Escape — like Quick Look. Holding
            // it instead (no card open for preview) arms a pan tool so
            // click-drag anywhere on the canvas pans it, like a touchpad
            // swipe — the `isARepeat` guard keeps the OS's key-repeat from
            // re-toggling the preview on every tick while held.
            if event.keyCode == 49 {
                guard !event.isARepeat else { return nil }
                if previewItemID != nil {
                    previewItemID = nil
                    return nil
                }
                if document.selectedIDs.count == 1 {
                    previewItemID = document.selectedIDs.first
                    return nil
                }
                isSpaceDown = true
                NSCursor.openHand.set()
                return nil
            }
            if event.keyCode == 53, previewItemID != nil {
                previewItemID = nil
                return nil
            }

            // While previewing, left/right step through the canvas's
            // reading order instead of nudging — reaching the end of a row
            // naturally continues onto the next one, since reading order is
            // already flattened row by row. Up/down instead jump a whole
            // row, landing on whichever card in that row is horizontally
            // closest to the current one.
            if let currentPreviewID = previewItemID {
                guard [123, 124, 125, 126].contains(event.keyCode) else { return event }
                if event.keyCode == 123 || event.keyCode == 124 {
                    let order = document.readingOrder()
                    guard let index = order.firstIndex(where: { $0.id == currentPreviewID }) else { return event }
                    let nextIndex = event.keyCode == 124 ? index + 1 : index - 1
                    guard order.indices.contains(nextIndex) else { return nil }
                    previewItemID = order[nextIndex].id
                    document.selectedIDs = [order[nextIndex].id]
                } else {
                    let rows = document.readingOrderRows()
                    guard let rowIndex = rows.firstIndex(where: { row in row.contains { $0.id == currentPreviewID } }),
                          let current = rows[rowIndex].first(where: { $0.id == currentPreviewID }) else { return event }
                    let targetRowIndex = event.keyCode == 125 ? rowIndex + 1 : rowIndex - 1
                    guard rows.indices.contains(targetRowIndex), let closest = rows[targetRowIndex].min(by: {
                        abs($0.frame.midX - current.frame.midX) < abs($1.frame.midX - current.frame.midX)
                    }) else { return nil }
                    previewItemID = closest.id
                    document.selectedIDs = [closest.id]
                }
                return nil
            }

            let step: Double = event.modifierFlags.contains(.shift) ? 10 : 1
            switch event.keyCode {
            case 123: nudgeSelection(dx: -step, dy: 0); return nil
            case 124: nudgeSelection(dx: step, dy: 0); return nil
            case 125: nudgeSelection(dx: 0, dy: step); return nil
            case 126: nudgeSelection(dx: 0, dy: -step); return nil
            default: break
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// Moves every selected card by the same offset, clamped so the group's
    /// leading/top edge can't cross 0 — same clamp used for drag-moves.
    /// Registered as its own undo step per key press, matching how each
    /// discrete drag-move is its own step.
    private func nudgeSelection(dx: Double, dy: Double) {
        let ids = document.selectedIDs
        let selected = document.items.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        let minX = selected.map(\.x).min() ?? 0
        let minY = selected.map(\.y).min() ?? 0
        let clampedDx = max(dx, -minX)
        let clampedDy = max(dy, -minY)
        guard clampedDx != 0 || clampedDy != 0 else { return }

        document.registerUndoCheckpoint(actionName: "Nudge")
        document.updateItems(ids) { current in
            current.x += clampedDx
            current.y += clampedDy
        }
        document.save()
    }

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard event.window === hostWindow else { return event }
            guard cropModeItemID == nil, !showRenameSheet else { return event }

            if event.modifierFlags.contains(.command) {
                let sensitivity: CGFloat = 0.0025
                setZoom(zoom * (1 + event.scrollingDeltaY * sensitivity))
            } else {
                panOffset = CGSize(
                    width: panOffset.width + event.scrollingDeltaX,
                    height: panOffset.height + event.scrollingDeltaY
                )
            }
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        scrollMonitor = nil
    }
}

private struct CanvasDropDelegate: DropDelegate {
    let document: CanvasDocument

    func performDrop(info: DropInfo) -> Bool {
        let location = info.location
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }

        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, ImageFileSupport.isImage(url) else { return }
                DispatchQueue.main.async {
                    document.addImage(fromDropped: url, at: location)
                }
            }
        }
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }
}

private enum ExportImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg

    var id: String { rawValue }
    var label: String { self == .png ? "PNG" : "JPEG" }
    var fileExtension: String { self == .png ? "png" : "jpg" }
    var contentType: UTType { self == .png ? .png : .jpeg }
}

/// A save panel accessory letting the user pick PNG or JPEG — updates the
/// panel's allowed type and the name field's extension to match, in place
/// like Preview's own export panel. Built as a plain `NSPopUpButton` with
/// target-action rather than a SwiftUI `Picker` in an `NSHostingView`: a
/// `.menu`-style `Picker` embedded as an `NSSavePanel` accessory view didn't
/// reliably respond to clicks — this mirrors the same target-action
/// bridging pattern already used for the canvas/guide color pickers.
private final class ExportFormatCoordinator: NSObject {
    let panel: NSSavePanel
    let baseName: String

    init(panel: NSSavePanel, baseName: String) {
        self.panel = panel
        self.baseName = baseName
    }

    func makeAccessoryView() -> NSView {
        let label = NSTextField(labelWithString: "Format:")

        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.addItems(withTitles: ExportImageFormat.allCases.map(\.label))
        popUp.target = self
        popUp.action = #selector(formatChanged(_:))

        let stack = NSStackView(views: [label, popUp])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 44))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        let format = ExportImageFormat.allCases[sender.indexOfSelectedItem]
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
    }
}

/// Bundles the Edit-menu-triggered notification handlers (crop, delete
/// variants, layering, duplicate, select all, bulk rename) into their own
/// `ViewModifier` rather than another decade of chained `.onReceive` calls
/// directly on `CanvasView.body` — past a certain number of chained
/// modifiers on one expression, the type checker times out trying to infer
/// the whole thing at once.
private struct EditMenuCommands: ViewModifier {
    let document: CanvasDocument
    let hostWindow: NSWindow?
    @Binding var cropModeItemID: UUID?
    @Binding var showRenameSheet: Bool
    let performDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .cropSelected)) { _ in
                guard isKeyWindow else { return }
                if let id = document.selectedIDs.first, document.selectedIDs.count == 1 {
                    cropModeItemID = id
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .deleteSelected)) { _ in
                guard isKeyWindow else { return }
                performDelete()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deleteFromFolder)) { _ in
                guard isKeyWindow else { return }
                document.deleteItems(document.selectedIDs)
            }
            .onReceive(NotificationCenter.default.publisher(for: .bringForward)) { _ in
                guard isKeyWindow else { return }
                document.bringForward(document.selectedIDs)
            }
            .onReceive(NotificationCenter.default.publisher(for: .bringToFront)) { _ in
                guard isKeyWindow else { return }
                document.bringToFront(document.selectedIDs)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sendBackward)) { _ in
                guard isKeyWindow else { return }
                document.sendBackward(document.selectedIDs)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sendToBack)) { _ in
                guard isKeyWindow else { return }
                document.sendToBack(document.selectedIDs)
            }
            .onReceive(NotificationCenter.default.publisher(for: .duplicateSelected)) { _ in
                guard isKeyWindow else { return }
                document.duplicateItems(document.selectedIDs)
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectAllItems)) { _ in
                guard isKeyWindow else { return }
                document.selectedIDs = Set(document.items.map(\.id))
                document.selectedGuideID = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .bulkRename)) { _ in
                guard isKeyWindow else { return }
                showRenameSheet = true
            }
    }

    private var isKeyWindow: Bool {
        hostWindow != nil && hostWindow === NSApp.keyWindow
    }
}
