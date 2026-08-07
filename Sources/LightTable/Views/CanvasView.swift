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
    @State private var showFilenames = false
    @State private var showGuides = true
    @State private var colorPanelCoordinator: ColorPanelCoordinator?
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
                        onPendingGuideChanged: { pendingGuide = $0 },
                        onAddVerticalGuide: { x in document.addVerticalGuide(at: x) },
                        onAddHorizontalGuide: { y in document.addHorizontalGuide(at: y) }
                    )
                }
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
        .navigationTitle(document.folderURL.lastPathComponent)
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
                Button("Delete", systemImage: "trash") {
                    if let guideID = document.selectedGuideID {
                        document.removeGuide(guideID)
                    } else {
                        document.removeFromCanvas(document.selectedIDs)
                    }
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
        .onAppear {
            installKeyMonitor()
            installScrollMonitor()
            // hostWindow may already be set by the time this fires, or may
            // only arrive later via WindowAccessor's async assignment — the
            // onChange below covers that second case.
            hostWindow?.representedURL = document.folderURL
        }
        .onDisappear {
            removeKeyMonitor()
            removeScrollMonitor()
        }
        .onChange(of: hostWindow) { _, newWindow in
            // Setting this gives the window a proxy icon and lets the user
            // ⌘-click (or right-click the proxy icon) the title bar to see
            // the folder's full path, exactly like Finder/any document window.
            newWindow?.representedURL = document.folderURL
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
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canCreateDirectories = true
        let suffix = cropToVisible ? " (visible)" : ""
        panel.nameFieldStringValue = "\(document.folderURL.lastPathComponent)\(suffix).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let bitmapRep = NSBitmapImageRep(cgImage: finalImage)
        let isJPEG = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        let fileType: NSBitmapImageRep.FileType = isJPEG ? .jpeg : .png
        guard let data = bitmapRep.representation(using: fileType, properties: [:]) else { return }
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === hostWindow else { return event }
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
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
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
