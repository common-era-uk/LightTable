import Foundation
import CoreGraphics
import AppKit
import SwiftUI

/// A Codable stand-in for `Color`/`NSColor`, so a custom canvas background
/// can be persisted in the sidecar. `nil` (never constructed with this type
/// at all — see `CanvasDocument.canvasColor`) means "use the system default,"
/// not "use black."
struct RGBAColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(color: Color) {
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        red = Double(resolved.redComponent)
        green = Double(resolved.greenComponent)
        blue = Double(resolved.blueComponent)
        alpha = Double(resolved.alphaComponent)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

/// A single ruler guide. `position` is an X (vertical guide) or Y
/// (horizontal guide) coordinate in canvas-logical units — which array it's
/// stored in (`CanvasDocument.verticalGuides`/`horizontalGuides`) determines
/// which axis it applies to.
struct Guide: Codable, Equatable, Identifiable {
    var id: UUID
    var position: Double

    init(id: UUID = UUID(), position: Double) {
        self.id = id
        self.position = position
    }
}

struct CanvasLayout: Codable {
    var items: [CanvasItem]
    var canvasWidth: Double?
    var canvasHeight: Double?
    var canvasColor: RGBAColor?
    /// Files (by inode) that were deliberately removed from the canvas —
    /// still present in the folder, but should not be auto-imported again
    /// by `loadAndReconcile`/`refreshFromDisk` until dragged back on.
    var excludedFileIDs: Set<UInt64>?
    var verticalGuides: [Guide]?
    var horizontalGuides: [Guide]?
    /// nil means the default blue.
    var guideColor: RGBAColor?
}

@MainActor
final class CanvasDocument: ObservableObject {
    /// The `.lt` file itself — this, not the folder, is the document's real
    /// identity. Multiple `.lt` files (independent canvases, each with their
    /// own items/layout) can share the same folder of images.
    let ltFileURL: URL
    var folderURL: URL { ltFileURL.deletingLastPathComponent() }
    @Published var items: [CanvasItem] = []
    @Published var selectedIDs: Set<UUID> = []
    @Published var canvasWidth: Double = 1600
    @Published var canvasHeight: Double = 1000
    /// nil means "use the system default background," not a specific color.
    @Published var canvasColor: RGBAColor?
    /// Inodes of files removed from the canvas via plain Delete (kept in the
    /// folder, just excluded from auto-import). See `CanvasLayout.excludedFileIDs`.
    @Published var excludedFileIDs: Set<UInt64> = []
    /// Live, uncommitted translation applied to all selected items while a
    /// group drag is in progress (visual preview only).
    @Published var groupDragOffset: CGSize = .zero
    /// Live, uncommitted group-scale state while ⌘-dragging a corner handle
    /// with multiple items selected — the whole selection scales as one
    /// rigid block from `groupResizeAnchor` (a fixed point shared by every
    /// selected card, so gaps between cards scale proportionally instead of
    /// each card drifting from its own independent anchor). Every other
    /// selected card previews itself via `groupResizeAnchor`/`groupResizeScale`;
    /// `groupResizeSourceID` is the card actually being dragged, so it can
    /// skip this and use its own precise live rect instead.
    @Published var groupResizeScale: CGFloat?
    @Published var groupResizeAnchor: CGPoint?
    @Published var groupResizeSourceID: UUID?
    @Published var importError: String?
    @Published var verticalGuides: [Guide] = []
    @Published var horizontalGuides: [Guide] = []
    @Published var selectedGuideID: UUID?
    /// nil means the default blue.
    @Published var guideColor: RGBAColor?

    /// The hosting window's undo manager (set by the view layer once the
    /// window is attached). Weak since NSUndoManager doesn't own its target.
    weak var undoManager: UndoManager? {
        didSet { undoManager?.levelsOfUndo = 10 }
    }

    static let minCanvasDimension: Double = 800
    static let maxCanvasDimension: Double = 6000

    /// Filename extension for a canvas document.
    static let fileExtension = "lt"
    /// The legacy hidden sidecar name, from before `.lt` files existed —
    /// still checked for and migrated when found. See `migrateLegacySidecar`.
    static let legacySidecarName = ".lighttable.json"

    // MARK: - Undo

    struct UndoSnapshot {
        let items: [CanvasItem]
        let canvasWidth: Double
        let canvasHeight: Double
        let verticalGuides: [Guide]
        let horizontalGuides: [Guide]
    }

    /// Exposed (not just used internally) so a multi-step action like a bulk
    /// rename can capture "before" up front and only register the undo step
    /// once it knows what actually succeeded.
    func captureSnapshot() -> UndoSnapshot {
        UndoSnapshot(items: items, canvasWidth: canvasWidth, canvasHeight: canvasHeight, verticalGuides: verticalGuides, horizontalGuides: horizontalGuides)
    }

    /// Registers an undo step using a snapshot captured *before* the caller's
    /// mutation. `extraUndo` reverses any side effect the plain items/canvas
    /// snapshot can't undo by itself — a filesystem change (a rename, a
    /// trash, a copy) or another published property (like `excludedFileIDs`)
    /// — and is run, via the (weakly-held) target, before the snapshot is
    /// restored.
    func registerUndo(_ snapshot: UndoSnapshot, actionName: String, extraUndo: ((CanvasDocument) -> Void)? = nil) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            extraUndo?(target)
            target.items = snapshot.items
            target.canvasWidth = snapshot.canvasWidth
            target.canvasHeight = snapshot.canvasHeight
            target.verticalGuides = snapshot.verticalGuides
            target.horizontalGuides = snapshot.horizontalGuides
            target.selectedIDs = []
            target.selectedGuideID = nil
            target.save()
        }
        undoManager.setActionName(actionName)
    }

    /// Convenience for the common case: snapshot the current (pre-mutation)
    /// state right now and register it as an undo step.
    func registerUndoCheckpoint(actionName: String, extraUndo: ((CanvasDocument) -> Void)? = nil) {
        registerUndo(captureSnapshot(), actionName: actionName, extraUndo: extraUndo)
    }

    init(ltFileURL: URL) {
        self.ltFileURL = ltFileURL
        loadAndReconcile()
        RecentDocumentsStore.shared.record(ltFileURL)
    }

    /// Copies a legacy hidden `.lighttable.json`'s content into a new
    /// visible `.lt` file at `destinationURL` (same schema, just relocated
    /// and renamed) and removes the old file. Static since it runs during
    /// folder resolution, before a `CanvasDocument` exists.
    static func migrateLegacySidecar(from legacyURL: URL, to destinationURL: URL) throws {
        let data = try Data(contentsOf: legacyURL)
        try data.write(to: destinationURL, options: .atomic)
        try? FileManager.default.removeItem(at: legacyURL)
    }

    /// Bundles this document — the `.lt` file plus every image it actually
    /// references (not every file that happens to be in the folder) — into
    /// a standalone `.zip` at `destinationZipURL`, self-contained enough to
    /// share outside of whatever's keeping the original folder in sync
    /// (Dropbox, etc.) between people who already have it.
    func packageForSharing(to destinationZipURL: URL) throws {
        let fm = FileManager.default
        let packageName = destinationZipURL.deletingPathExtension().lastPathComponent
        let stagingRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stagingDir = stagingRoot.appendingPathComponent(packageName)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stagingRoot) }

        try fm.copyItem(at: ltFileURL, to: stagingDir.appendingPathComponent(ltFileURL.lastPathComponent))

        var copiedFilenames = Set<String>()
        for item in items where !copiedFilenames.contains(item.filename) {
            copiedFilenames.insert(item.filename)
            let source = folderURL.appendingPathComponent(item.filename)
            guard fm.fileExists(atPath: source.path) else { continue }
            try fm.copyItem(at: source, to: stagingDir.appendingPathComponent(item.filename))
        }

        if fm.fileExists(atPath: destinationZipURL.path) {
            try fm.removeItem(at: destinationZipURL)
        }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", stagingDir.path, destinationZipURL.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw NSError(domain: "LightTable", code: 1, userInfo: [NSLocalizedDescriptionKey: "Couldn't create the zip archive."])
        }
    }

    // MARK: - Load / import / reconcile

    /// Reads the sidecar layout (if any), scans the folder for images, drops
    /// entries whose files vanished, and grid-places any images that are new.
    ///
    /// Files are matched to sidecar entries primarily by inode (`fileID`),
    /// which survives renames on the same volume — falling back to filename
    /// only for older sidecar entries that predate `fileID`. This means a
    /// rename (whether done through the app or in Finder) never looks like
    /// "file deleted, new file appeared" and loses its position/size/crop.
    func loadAndReconcile() {
        var existing: [CanvasItem] = []
        if let data = try? Data(contentsOf: ltFileURL),
           let layout = try? JSONDecoder().decode(CanvasLayout.self, from: data) {
            existing = layout.items
            canvasWidth = min(max(layout.canvasWidth ?? canvasWidth, Self.minCanvasDimension), Self.maxCanvasDimension)
            canvasHeight = min(max(layout.canvasHeight ?? canvasHeight, Self.minCanvasDimension), Self.maxCanvasDimension)
            canvasColor = layout.canvasColor
            excludedFileIDs = layout.excludedFileIDs ?? []
            verticalGuides = layout.verticalGuides ?? []
            horizontalGuides = layout.horizontalGuides ?? []
            guideColor = layout.guideColor
        }

        let filesOnDisk = ImageFileSupport.listImages(in: folderURL)
        var urlByFileID: [UInt64: URL] = [:]
        var urlByFilename: [String: URL] = [:]
        for url in filesOnDisk {
            urlByFilename[url.lastPathComponent] = url
            if let fileID = ImageFileSupport.fileID(of: url) {
                urlByFileID[fileID] = url
            }
        }

        var matchedFilenames = Set<String>()
        var result: [CanvasItem] = []
        for var item in existing {
            let matchedURL: URL?
            if let fileID = item.fileID, let url = urlByFileID[fileID] {
                matchedURL = url
            } else {
                matchedURL = urlByFilename[item.filename]
            }
            guard let url = matchedURL, !matchedFilenames.contains(url.lastPathComponent) else { continue }
            item.filename = url.lastPathComponent
            if item.fileID == nil {
                item.fileID = ImageFileSupport.fileID(of: url)
            }
            matchedFilenames.insert(url.lastPathComponent)
            result.append(item)
        }

        let newFiles = filesOnDisk.filter { !matchedFilenames.contains($0.lastPathComponent) && !isExcluded($0) }
        if !newFiles.isEmpty {
            let startIndex = result.count
            for (offset, url) in newFiles.enumerated() {
                var item = Self.gridPlacement(index: startIndex + offset, filename: url.lastPathComponent, fileURL: url)
                item.fileID = ImageFileSupport.fileID(of: url)
                result.append(item)
            }
        }

        items = result
        save()
    }

    private func isExcluded(_ url: URL) -> Bool {
        guard let fileID = ImageFileSupport.fileID(of: url) else { return false }
        return excludedFileIDs.contains(fileID)
    }

    /// `crop` defaults to the full image (0...1) for brand-new imports. When
    /// re-flowing an already-cropped item (see `refreshFromDisk`), passing
    /// its existing crop keeps the card's own aspect ratio matching the
    /// crop's aspect ratio — required for `CroppedImageView`'s math to stay
    /// correct (the same invariant `CropView.applyCrop` maintains).
    private static func gridPlacement(index: Int, filename: String, fileURL: URL, crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> CanvasItem {
        let columns = 6
        let cellWidth: Double = 240
        let cellHeight: Double = 240
        let spacing: Double = 48
        let margin: Double = 90

        let col = index % columns
        let row = index / columns

        var width = cellWidth
        var height = cellHeight
        if let pixelSize = ImageFileSupport.pixelSize(of: fileURL), pixelSize.width > 0, pixelSize.height > 0 {
            let croppedWidth = pixelSize.width * crop.width
            let croppedHeight = pixelSize.height * crop.height
            if croppedHeight > 0 {
                let aspect = croppedWidth / croppedHeight
                if aspect >= 1 {
                    width = cellWidth
                    height = cellWidth / aspect
                } else {
                    height = cellHeight
                    width = cellHeight * aspect
                }
            }
        }

        let x = margin + Double(col) * (cellWidth + spacing)
        let y = margin + Double(row) * (cellHeight + spacing)

        return CanvasItem(
            filename: filename, x: x, y: y, width: width, height: height,
            cropX: crop.minX, cropY: crop.minY, cropWidth: crop.width, cropHeight: crop.height
        )
    }

    /// Re-reads the folder from disk and re-flows every image into a fresh
    /// grid, resizing the canvas to fit. Items whose files are gone (e.g.
    /// deleted during culling) are dropped; existing crops are preserved for
    /// files that are matched (by inode, then filename). Useful for
    /// regrouping after a round of deletions has left gaps in a manually
    /// arranged layout.
    func refreshFromDisk() {
        let filesOnDisk = ImageFileSupport.listImages(in: folderURL).filter { !isExcluded($0) }
        var urlByFileID: [UInt64: URL] = [:]
        var urlByFilename: [String: URL] = [:]
        for url in filesOnDisk {
            urlByFilename[url.lastPathComponent] = url
            if let fileID = ImageFileSupport.fileID(of: url) {
                urlByFileID[fileID] = url
            }
        }

        var existingByFilename: [String: CanvasItem] = [:]
        for item in items {
            let matchedURL: URL?
            if let fileID = item.fileID, let url = urlByFileID[fileID] {
                matchedURL = url
            } else {
                matchedURL = urlByFilename[item.filename]
            }
            if let url = matchedURL {
                existingByFilename[url.lastPathComponent] = item
            }
        }

        var result: [CanvasItem] = []
        for (index, url) in filesOnDisk.enumerated() {
            let filename = url.lastPathComponent
            let existing = existingByFilename[filename]
            var placed = Self.gridPlacement(index: index, filename: filename, fileURL: url, crop: existing?.cropRect ?? CGRect(x: 0, y: 0, width: 1, height: 1))
            if let existing {
                placed.id = existing.id
            }
            placed.fileID = ImageFileSupport.fileID(of: url)
            result.append(placed)
        }

        registerUndoCheckpoint(actionName: "Refresh")

        items = result
        selectedIDs = []
        groupDragOffset = .zero

        let maxX = items.reduce(0.0) { max($0, $1.x + $1.width) }
        let maxY = items.reduce(0.0) { max($0, $1.y + $1.height) }
        canvasWidth = min(max(maxX + 200, Self.minCanvasDimension), Self.maxCanvasDimension)
        canvasHeight = min(max(maxY + 200, Self.minCanvasDimension), Self.maxCanvasDimension)

        save()
    }

    // MARK: - Persistence

    func save() {
        let layout = CanvasLayout(
            items: items, canvasWidth: canvasWidth, canvasHeight: canvasHeight, canvasColor: canvasColor,
            excludedFileIDs: excludedFileIDs, verticalGuides: verticalGuides, horizontalGuides: horizontalGuides,
            guideColor: guideColor
        )
        guard let data = try? JSONEncoder().encode(layout) else { return }
        try? data.write(to: ltFileURL, options: .atomic)
    }

    // MARK: - Mutations

    func updateItem(_ id: UUID, _ transform: (inout CanvasItem) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        transform(&items[idx])
    }

    func updateItems(_ ids: Set<UUID>, _ transform: (inout CanvasItem) -> Void) {
        for idx in items.indices where ids.contains(items[idx].id) {
            transform(&items[idx])
        }
    }

    private static func defaultCardSize(for url: URL) -> (width: Double, height: Double) {
        var width = 240.0
        var height = 240.0
        if let pixelSize = ImageFileSupport.pixelSize(of: url), pixelSize.width > 0, pixelSize.height > 0 {
            let aspect = pixelSize.width / pixelSize.height
            if aspect >= 1 { height = width / aspect } else { width = height * aspect }
        }
        return (width, height)
    }

    func addImage(fromDropped sourceURL: URL, at point: CGPoint) {
        if let error = ImageFileSupport.oversizeError(for: sourceURL) {
            importError = error
            return
        }

        // Dragging a file that's already sitting in this same folder — most
        // likely one previously removed from the canvas via plain Delete —
        // just re-adds it in place rather than copying a "name 2" duplicate,
        // since the original file was never touched.
        if sourceURL.deletingLastPathComponent().standardizedFileURL == folderURL.standardizedFileURL,
           let fileID = ImageFileSupport.fileID(of: sourceURL) {
            let size = Self.defaultCardSize(for: sourceURL)
            let item = CanvasItem(
                filename: sourceURL.lastPathComponent,
                x: max(point.x - size.width / 2, 0),
                y: max(point.y - size.height / 2, 0),
                width: size.width,
                height: size.height,
                fileID: fileID
            )

            let wasExcluded = excludedFileIDs.contains(fileID)
            registerUndoCheckpoint(actionName: "Add Image") { target in
                if wasExcluded { target.excludedFileIDs.insert(fileID) }
            }

            excludedFileIDs.remove(fileID)
            items.append(item)
            selectedIDs = [item.id]
            save()
            return
        }

        let desiredName = sourceURL.lastPathComponent
        let finalName = ImageFileSupport.availableFilename(for: desiredName, in: folderURL)
        let destURL = folderURL.appendingPathComponent(finalName)

        let isAccessingScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if isAccessingScope { sourceURL.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            NSSound.beep()
            return
        }

        let size = Self.defaultCardSize(for: destURL)
        let item = CanvasItem(
            filename: finalName,
            x: max(point.x - size.width / 2, 0),
            y: max(point.y - size.height / 2, 0),
            width: size.width,
            height: size.height,
            fileID: ImageFileSupport.fileID(of: destURL)
        )

        registerUndoCheckpoint(actionName: "Add Image") { _ in
            try? FileManager.default.trashItem(at: destURL, resultingItemURL: nil)
        }

        items.append(item)
        selectedIDs = [item.id]
        save()
    }

    /// Removes the selected items from the canvas without touching their
    /// files — they stay in the folder but are marked "excluded" so a later
    /// re-scan (opening the folder again, or Refresh) won't automatically
    /// re-add them. Dragging the file back onto the canvas from Finder
    /// clears the exclusion. This is the plain-Delete behavior; ⌘-Delete
    /// uses `deleteItems` instead, which actually trashes the file.
    func removeFromCanvas(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let removedFileIDs = Set(items.filter { ids.contains($0.id) }.compactMap { $0.fileID })

        registerUndoCheckpoint(actionName: "Remove from Canvas") { target in
            target.excludedFileIDs.subtract(removedFileIDs)
        }

        items.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
        excludedFileIDs.formUnion(removedFileIDs)
        save()
    }

    /// Moves the file(s) to Trash (recoverable) and removes them from the canvas.
    /// Undoing restores both the canvas card and the actual file from Trash.
    func deleteItems(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        var trashedPairs: [(original: URL, trashed: URL)] = []
        for id in ids {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            let fileURL = folderURL.appendingPathComponent(item.filename)
            var resultingURL: NSURL?
            if (try? FileManager.default.trashItem(at: fileURL, resultingItemURL: &resultingURL)) != nil,
               let trashedURL = resultingURL as URL? {
                trashedPairs.append((original: fileURL, trashed: trashedURL))
            }
        }

        registerUndoCheckpoint(actionName: "Delete") { _ in
            for pair in trashedPairs {
                try? FileManager.default.moveItem(at: pair.trashed, to: pair.original)
            }
        }

        items.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
        save()
    }

    /// Copies each selected item's file (named with a "-copy" suffix, or
    /// "-copy-2" etc. if that's already taken) and adds the copy to the
    /// canvas just offset from the original — same position/size/crop to
    /// start, so e.g. two different crops of the same image can be tried
    /// side by side. The originals are left untouched.
    func duplicateItems(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let fm = FileManager.default
        let targets = items.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        var newItems: [CanvasItem] = []
        var copiedURLs: [URL] = []

        for item in targets {
            let sourceURL = folderURL.appendingPathComponent(item.filename)
            let newName = ImageFileSupport.duplicateFilename(for: item.filename, in: folderURL)
            let destURL = folderURL.appendingPathComponent(newName)
            guard (try? fm.copyItem(at: sourceURL, to: destURL)) != nil else { continue }

            copiedURLs.append(destURL)
            var newItem = item
            newItem.id = UUID()
            newItem.filename = newName
            newItem.fileID = ImageFileSupport.fileID(of: destURL)
            newItem.x += 24
            newItem.y += 24
            newItems.append(newItem)
        }
        guard !newItems.isEmpty else { return }

        registerUndoCheckpoint(actionName: "Duplicate") { _ in
            for url in copiedURLs {
                try? fm.trashItem(at: url, resultingItemURL: nil)
            }
        }

        items.append(contentsOf: newItems)
        selectedIDs = Set(newItems.map { $0.id })
        save()
    }

    // MARK: - Layering (z-order)
    //
    // `items`' array order is the stacking order the canvas renders in
    // (later entries on top), so these just reorder the array.

    func bringToFront(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        registerUndoCheckpoint(actionName: "Bring to Front")
        let selected = items.filter { ids.contains($0.id) }
        let rest = items.filter { !ids.contains($0.id) }
        items = rest + selected
        save()
    }

    func sendToBack(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        registerUndoCheckpoint(actionName: "Send to Back")
        let selected = items.filter { ids.contains($0.id) }
        let rest = items.filter { !ids.contains($0.id) }
        items = selected + rest
        save()
    }

    /// Moves each selected item one step up, past its immediate unselected
    /// neighbor above (if any) — processed top-down so a multi-item
    /// selection each steps forward by one without leapfrogging itself.
    func bringForward(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        registerUndoCheckpoint(actionName: "Bring Forward")
        var result = items
        var index = result.count - 2
        while index >= 0 {
            if ids.contains(result[index].id), !ids.contains(result[index + 1].id) {
                result.swapAt(index, index + 1)
            }
            index -= 1
        }
        items = result
        save()
    }

    /// Mirror of `bringForward`: moves each selected item one step down,
    /// past its immediate unselected neighbor below, processed bottom-up.
    func sendBackward(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        registerUndoCheckpoint(actionName: "Send Backward")
        var result = items
        var index = 1
        while index < result.count {
            if ids.contains(result[index].id), !ids.contains(result[index - 1].id) {
                result.swapAt(index, index - 1)
            }
            index += 1
        }
        items = result
        save()
    }

    // MARK: - Guides

    @discardableResult
    func addVerticalGuide(at x: Double) -> UUID {
        registerUndoCheckpoint(actionName: "Add Guide")
        let guide = Guide(position: x)
        verticalGuides.append(guide)
        selectedGuideID = guide.id
        selectedIDs = []
        save()
        return guide.id
    }

    @discardableResult
    func addHorizontalGuide(at y: Double) -> UUID {
        registerUndoCheckpoint(actionName: "Add Guide")
        let guide = Guide(position: y)
        horizontalGuides.append(guide)
        selectedGuideID = guide.id
        selectedIDs = []
        save()
        return guide.id
    }

    func moveGuide(_ id: UUID, to position: Double) {
        registerUndoCheckpoint(actionName: "Move Guide")
        if let idx = verticalGuides.firstIndex(where: { $0.id == id }) {
            verticalGuides[idx].position = position
        } else if let idx = horizontalGuides.firstIndex(where: { $0.id == id }) {
            horizontalGuides[idx].position = position
        }
        save()
    }

    func removeGuide(_ id: UUID) {
        let existed = verticalGuides.contains { $0.id == id } || horizontalGuides.contains { $0.id == id }
        guard existed else { return }
        registerUndoCheckpoint(actionName: "Remove Guide")
        verticalGuides.removeAll { $0.id == id }
        horizontalGuides.removeAll { $0.id == id }
        if selectedGuideID == id { selectedGuideID = nil }
        save()
    }

    func clearAllGuides() {
        guard !verticalGuides.isEmpty || !horizontalGuides.isEmpty else { return }
        registerUndoCheckpoint(actionName: "Clear All Guides")
        verticalGuides.removeAll()
        horizontalGuides.removeAll()
        selectedGuideID = nil
        save()
    }

    // MARK: - Reading order

    /// Top-to-bottom rows, left-to-right within a row, computed from current
    /// card positions on the canvas.
    func readingOrder() -> [CanvasItem] {
        readingOrderRows().flatMap { $0 }
    }

    /// Same grouping as `readingOrder()`, but keeping each row separate so
    /// up/down navigation can find the item in the neighboring row closest
    /// to the current one's horizontal position.
    func readingOrderRows() -> [[CanvasItem]] {
        Self.rowGroupedReadingOrder(items)
    }

    /// Clusters `items` into visual rows by y-proximity, then sorts each row
    /// left-to-right — the core of reading order, factored out so it can
    /// also be applied to an arbitrary subset (see `createGrid`).
    private static func rowGroupedReadingOrder(_ items: [CanvasItem]) -> [[CanvasItem]] {
        guard !items.isEmpty else { return [] }
        let sortedByY = items.sorted { $0.y < $1.y }
        let avgHeight = items.reduce(0.0) { $0 + $1.height } / Double(items.count)
        let rowThreshold = max(avgHeight * 0.5, 20)

        var rows: [[CanvasItem]] = []
        var currentRow: [CanvasItem] = []
        var currentRowY = sortedByY.first!.y

        for item in sortedByY {
            if item.y - currentRowY > rowThreshold {
                rows.append(currentRow)
                currentRow = []
                currentRowY = item.y
            }
            currentRow.append(item)
        }
        if !currentRow.isEmpty { rows.append(currentRow) }

        return rows.map { row in row.sorted { $0.x < $1.x } }
    }

    // MARK: - Create Grid

    private struct GridEntry {
        let id: UUID
        let width: Double
    }

    private static func rowWidth(_ entries: [GridEntry], gap: Double) -> Double {
        guard !entries.isEmpty else { return 0 }
        return entries.reduce(0.0) { $0 + $1.width } + gap * Double(entries.count - 1)
    }

    /// Re-flows the selected items into a clean, justified grid: every image
    /// is resized to a shared height (the average of their current
    /// heights), with each one's own width following from its existing
    /// aspect ratio — so portrait and landscape images sit at the same
    /// height per row instead of a uniform cell size distorting anything.
    ///
    /// Row membership starts from the images' *existing* rows (by current
    /// y-position), not a from-scratch repack — an already-tidy 5-then-4
    /// arrangement stays 5-then-4 instead of shuffling into 6-then-3 just
    /// because there happened to be a sliver of width left over. Existing
    /// rows only get merged into one output row when they jointly still fit
    /// the canvas width (so a short trailing row, e.g. one straggler,
    /// settles into the row above it rather than sitting alone), and an
    /// existing row wider than the canvas on its own is the only case that
    /// gets split, item by item. The grid starts at the selection's own
    /// top-left corner, so it replaces the selected images roughly where
    /// they already were.
    func createGrid(_ ids: Set<UUID>, spacing: Double, isPercentage: Bool) {
        let targets = items.filter { ids.contains($0.id) }
        guard targets.count >= 2 else { return }

        let existingRows = Self.rowGroupedReadingOrder(targets)
        let commonHeight = targets.reduce(0.0) { $0 + $1.height } / Double(targets.count)
        let gap = isPercentage ? commonHeight * (spacing / 100) : spacing

        let originX = targets.map(\.x).min() ?? 0
        let originY = targets.map(\.y).min() ?? 0
        let maxRowWidth = max(canvasWidth - originX, commonHeight)

        func entries(for row: [CanvasItem]) -> [GridEntry] {
            row.map { item in
                let aspect = item.height > 0 ? item.width / item.height : 1
                return GridEntry(id: item.id, width: commonHeight * aspect)
            }
        }

        var outputRows: [[GridEntry]] = []
        var current: [GridEntry] = []

        for row in existingRows {
            let rowEntries = entries(for: row)
            let width = Self.rowWidth(rowEntries, gap: gap)

            if width > maxRowWidth {
                // This one existing row alone doesn't fit — flush whatever
                // was building, then wrap just this row's own items.
                if !current.isEmpty { outputRows.append(current); current = [] }
                for entry in rowEntries {
                    let projected = current.isEmpty ? entry.width : Self.rowWidth(current, gap: gap) + gap + entry.width
                    if projected > maxRowWidth, !current.isEmpty {
                        outputRows.append(current)
                        current = []
                    }
                    current.append(entry)
                }
                continue
            }

            let projected = current.isEmpty ? width : Self.rowWidth(current, gap: gap) + gap + width
            if projected > maxRowWidth, !current.isEmpty {
                outputRows.append(current)
                current = rowEntries
            } else {
                current.append(contentsOf: rowEntries)
            }
        }
        if !current.isEmpty { outputRows.append(current) }

        registerUndoCheckpoint(actionName: "Create Grid")

        var cursorY = originY
        var maxY = originY
        for row in outputRows {
            var cursorX = originX
            for entry in row {
                updateItem(entry.id) { current in
                    current.x = cursorX
                    current.y = cursorY
                    current.width = entry.width
                    current.height = commonHeight
                }
                cursorX += entry.width + gap
            }
            cursorY += commonHeight + gap
            maxY = cursorY - gap
        }

        canvasHeight = max(canvasHeight, maxY + 90)
        selectedIDs = ids
        save()
    }
}
