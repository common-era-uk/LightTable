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

/// A single, app-wide clipboard for canvas items — deliberately not routed
/// through `NSPasteboard`, since what's being carried (a `CanvasItem` plus,
/// for images, a reference to its file in a specific document's folder) has
/// no useful representation outside LightTable itself. A plain shared
/// singleton is enough to support copy/cut in one document's window and
/// paste in another's, same as `NSPasteboard` would, without the
/// serialization overhead.
final class CanvasClipboard {
    static let shared = CanvasClipboard()
    private init() {}

    struct Payload {
        enum Mode { case copy, cut }
        var mode: Mode
        /// A value-type snapshot taken at copy/cut time — later edits to the
        /// original item (or its removal, in the cut case) don't affect it.
        var items: [CanvasItem]
        /// Where `items`' image files actually live, so a paste — possibly
        /// into a different document/window — can find them.
        var sourceFolderURL: URL
    }

    var payload: Payload?
}

/// A single ruler guide. `position` is an X (vertical guide) or Y
/// (horizontal guide) coordinate in the shared multi-board display space
/// (see `CanvasDocument.boardOrigins`) — which array it's stored in
/// (`CanvasDocument.verticalGuides`/`horizontalGuides`) determines which axis
/// it applies to. Guides are shared across every art board rather than
/// scoped to one, for simplicity.
struct Guide: Codable, Equatable, Identifiable {
    var id: UUID
    var position: Double

    init(id: UUID = UUID(), position: Double) {
        self.id = id
        self.position = position
    }
}

/// A single art board's stored (nominal) size — its *actual* on-screen
/// extent may be larger, if content currently exceeds this (see
/// `CanvasDocument.boardDisplaySize`), the same "stored vs. displayed" split
/// the single-canvas model used before art boards existed.
/// A stable per-board identity (`id`) matters even though boards render in
/// plain array order — without it, a `ForEach` keyed by array index alone
/// can hand a stale, previously-cached view (and its already-attached
/// context menu) to whichever board now happens to occupy that index after
/// an add/delete/move, showing the right menu for the wrong board.
struct BoardSize: Codable, Equatable, Identifiable {
    var id: UUID
    var width: Double
    var height: Double
    /// nil means "use `CanvasDocument.canvasColor`" (which itself falls back
    /// to the system default) — the same two-tier fallback the single
    /// shared canvas color already used, just with a per-board override
    /// layered on top.
    var color: RGBAColor?

    init(id: UUID = UUID(), width: Double, height: Double, color: RGBAColor? = nil) {
        self.id = id
        self.width = width
        self.height = height
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        color = try container.decodeIfPresent(RGBAColor.self, forKey: .color)
    }
}

enum BoardSizeMode: String, Codable {
    /// Each board sizes itself independently, auto-extending to fit its own
    /// content — the original single-canvas behavior, just per board.
    case auto
    /// Every board shares one fixed size (`fixedBoardWidth`/`fixedBoardHeight`)
    /// and never resizes itself.
    case fixed
}

/// Input/display unit for the Fixed board size dialog. Board sizes are
/// always stored internally in points (PDF's native unit, 72pt = 1 inch) —
/// this only affects how a size is typed in and shown back.
enum BoardSizeUnit: String, Codable, CaseIterable, Identifiable {
    case inches, centimeters, pixels

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inches: return "in"
        case .centimeters: return "cm"
        case .pixels: return "px"
        }
    }

    func points(from value: Double) -> Double {
        switch self {
        case .inches: return value * 72
        case .centimeters: return value * 72 / 2.54
        case .pixels: return value
        }
    }

    func value(fromPoints points: Double) -> Double {
        switch self {
        case .inches: return points / 72
        case .centimeters: return points * 2.54 / 72
        case .pixels: return points
        }
    }
}

/// A named preset for the Fixed board size dialog, in points.
struct BoardSizePreset: Identifiable {
    let id = UUID()
    let name: String
    let width: Double
    let height: Double

    static let all: [BoardSizePreset] = [
        BoardSizePreset(name: "US Letter", width: 612, height: 792),
        BoardSizePreset(name: "A4", width: 595, height: 842),
        BoardSizePreset(name: "A3", width: 842, height: 1191),
        BoardSizePreset(name: "Square (10×10 in)", width: 720, height: 720),
        BoardSizePreset(name: "Instagram Post (1080×1080 px)", width: 1080, height: 1080),
        BoardSizePreset(name: "Instagram Story (1080×1920 px)", width: 1080, height: 1920),
        BoardSizePreset(name: "HD (1920×1080 px)", width: 1920, height: 1080),
    ]
}

struct CanvasLayout: Codable {
    var items: [CanvasItem]
    /// Legacy single-canvas size, read for migration into `boardSizes` when
    /// `boardSizes` itself is absent (a pre-art-board `.lt` file).
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
    var boardSizes: [BoardSize]?
    var boardSizeMode: BoardSizeMode?
    var fixedBoardWidth: Double?
    var fixedBoardHeight: Double?
    var boardSizeUnit: BoardSizeUnit?
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
    /// One entry per art board, index-aligned with `CanvasItem.boardIndex`.
    /// Each board's `x`/`y` coordinates are local to that board's own
    /// top-left origin — see `boardOrigins()` for how boards are stacked
    /// into one shared display space.
    @Published var boardSizes: [BoardSize] = [BoardSize(width: 1600, height: 1000)]
    @Published var boardSizeMode: BoardSizeMode = .auto
    /// US Letter, in points — the default the Fixed size dialog starts from.
    @Published var fixedBoardWidth: Double = 612
    @Published var fixedBoardHeight: Double = 792
    @Published var boardSizeUnit: BoardSizeUnit = .inches
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
    /// skip this and use its own precise live rect instead. All in the
    /// shared display space (see `boardOrigins()`), not board-local.
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
    /// Vertical space between stacked art boards in the shared display space.
    static let boardGap: Double = 180
    /// Extra room a board auto-extends beyond its actual content, matching
    /// the single-canvas model's own auto-extend margin.
    static let boardMargin: Double = 160

    /// Filename extension for a canvas document.
    static let fileExtension = "lt"
    /// The legacy hidden sidecar name, from before `.lt` files existed —
    /// still checked for and migrated when found. See `migrateLegacySidecar`.
    static let legacySidecarName = ".lighttable.json"

    // MARK: - Board layout

    /// Items belonging to one board, in `items`' own order (so z-order is
    /// preserved when filtering down to a single board).
    func items(onBoard index: Int) -> [CanvasItem] {
        items.filter { $0.boardIndex == index }
    }

    /// A board's displayed size: the larger of its stored (nominal) size and
    /// its actual content extent plus a margin — mirrors the single-canvas
    /// model's own "stored vs. displayed" split, just scoped per board.
    func boardDisplaySize(_ index: Int) -> CGSize {
        guard boardSizes.indices.contains(index) else { return CGSize(width: 800, height: 600) }
        let stored = boardSizes[index]
        // Fixed boards never auto-extend, even if content is dragged past
        // their edge — that content just sits past the boundary un-clipped
        // on screen (and gets clipped for real at PDF export), rather than
        // silently growing what's supposed to be a locked page size.
        guard boardSizeMode == .auto else { return CGSize(width: stored.width, height: stored.height) }
        let boardItems = items(onBoard: index)
        let maxX = boardItems.reduce(0.0) { max($0, $1.x + $1.width) }
        let maxY = boardItems.reduce(0.0) { max($0, $1.y + $1.height) }
        return CGSize(width: max(maxX + Self.boardMargin, stored.width), height: max(maxY + Self.boardMargin, stored.height))
    }

    /// Each board's top-left origin in the shared display space — boards
    /// stack vertically with `boardGap` between them, each horizontally
    /// centered within the widest board.
    func boardOrigins() -> [CGPoint] {
        let sizes = boardSizes.indices.map { boardDisplaySize($0) }
        let maxWidth = sizes.map(\.width).max() ?? 0
        var origins: [CGPoint] = []
        var y: Double = 0
        for size in sizes {
            origins.append(CGPoint(x: (maxWidth - size.width) / 2, y: y))
            y += size.height + Self.boardGap
        }
        return origins
    }

    /// The full shared display space's size — every board's rect plus gaps.
    func stackedContentSize() -> CGSize {
        let sizes = boardSizes.indices.map { boardDisplaySize($0) }
        let maxWidth = sizes.map(\.width).max() ?? 0
        let totalHeight = sizes.reduce(0.0) { $0 + $1.height } + Self.boardGap * Double(max(sizes.count - 1, 0))
        return CGSize(width: maxWidth, height: totalHeight)
    }

    /// Which board's rect a point in the shared display space falls within —
    /// the board whose rect contains it, or the closest one by vertical
    /// distance if the point is in a gap or past every board.
    func boardIndex(at point: CGPoint) -> Int {
        Self.boardIndex(at: point, origins: boardOrigins(), sizes: boardSizes.indices.map { boardDisplaySize($0) })
    }

    /// Same as `boardIndex(at:)`, but against an explicit `origins`/`sizes`
    /// snapshot rather than recomputing from live state — static so it's
    /// safe to call while an in-progress mutation (e.g. `updateItem`'s inout
    /// transform) already holds exclusive access to `items`.
    static func boardIndex(at point: CGPoint, origins: [CGPoint], sizes: [CGSize]) -> Int {
        guard !origins.isEmpty else { return 0 }
        for (index, origin) in origins.enumerated() {
            let rect = CGRect(origin: origin, size: sizes[index])
            if rect.minY <= point.y, point.y <= rect.maxY { return index }
        }
        // In a gap between boards, or above the first/below the last: pick
        // whichever board's own rect is vertically closest to the point,
        // rather than always defaulting to one end.
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, origin) in origins.enumerated() {
            let rect = CGRect(origin: origin, size: sizes[index])
            let distance = point.y < rect.minY ? rect.minY - point.y : point.y - rect.maxY
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    // MARK: - Board management

    /// Appends a new, empty board below the last one.
    func addBoard() {
        registerUndoCheckpoint(actionName: "Add Art Board")
        let size = boardSizeMode == .fixed
            ? BoardSize(width: fixedBoardWidth, height: fixedBoardHeight)
            : BoardSize(width: 1600, height: 1000)
        boardSizes.append(size)
        save()
    }

    /// Removes a board and everything on it from the canvas (files stay
    /// untouched in the folder, same as plain "Remove from Canvas" —
    /// dragging one back onto the canvas brings it back). Every later
    /// board's index shifts down by one. Refuses to remove the only board.
    func deleteBoard(at index: Int) {
        guard boardSizes.count > 1, boardSizes.indices.contains(index) else { return }
        registerUndoCheckpoint(actionName: "Delete Art Board") { target in
            target.excludedFileIDs.subtract(Set(self.items(onBoard: index).compactMap { $0.fileID }))
        }
        let removedFileIDs = Set(items(onBoard: index).compactMap { $0.fileID })
        items.removeAll { $0.boardIndex == index }
        for i in items.indices where items[i].boardIndex > index {
            items[i].boardIndex -= 1
        }
        excludedFileIDs.formUnion(removedFileIDs)
        boardSizes.remove(at: index)
        selectedIDs = []
        save()
    }

    /// Moves board `from` so it lands at position `to` (both 0-based),
    /// shifting the boards in between and remapping every item's
    /// `boardIndex` to match.
    func moveBoard(from: Int, to: Int) {
        guard boardSizes.indices.contains(from), (0..<boardSizes.count).contains(to), from != to else { return }
        registerUndoCheckpoint(actionName: "Move Art Board")

        var order = Array(boardSizes.indices)
        let moved = order.remove(at: from)
        order.insert(moved, at: to)
        // `order[newIndex]` is the *old* index now living at `newIndex`; invert
        // it so we can look up each old index's new home directly.
        var newIndexForOldIndex: [Int: Int] = [:]
        for (newIndex, oldIndex) in order.enumerated() {
            newIndexForOldIndex[oldIndex] = newIndex
        }

        boardSizes = order.map { boardSizes[$0] }
        for i in items.indices {
            if let newIndex = newIndexForOldIndex[items[i].boardIndex] {
                items[i].boardIndex = newIndex
            }
        }
        save()
    }

    /// A board's background — its own override if it has one, else the
    /// shared `canvasColor`, else `fallback` (the system default).
    func boardColor(_ index: Int, fallback: Color) -> Color {
        guard boardSizes.indices.contains(index) else { return fallback }
        return boardSizes[index].color?.color ?? canvasColor?.color ?? fallback
    }

    /// Sets (or clears, passing nil) just this board's own background color
    /// override. Not part of the undo stack, matching `canvasColor`/
    /// `guideColor`, which also aren't step-by-step undoable.
    func setBoardColor(_ color: Color?, at index: Int) {
        guard boardSizes.indices.contains(index) else { return }
        boardSizes[index].color = color.map { RGBAColor(color: $0) }
        save()
    }

    /// Switches sizing mode. Switching to Fixed immediately locks every
    /// board to `fixedBoardWidth`/`fixedBoardHeight`; content that no longer
    /// fits simply sits past the edge on screen (nothing is clipped or
    /// scaled) until PDF export, which clips to the page like a real print
    /// boundary. Not part of the undo stack, matching `canvasColor`/
    /// `guideColor`, which also aren't step-by-step undoable.
    func setBoardSizeMode(_ mode: BoardSizeMode) {
        boardSizeMode = mode
        if mode == .fixed {
            applyFixedSizeToAllBoards()
        }
        save()
    }

    func setFixedBoardSize(width: Double, height: Double, unit: BoardSizeUnit) {
        fixedBoardWidth = width
        fixedBoardHeight = height
        boardSizeUnit = unit
        if boardSizeMode == .fixed {
            applyFixedSizeToAllBoards()
        }
        save()
    }

    /// Updates every board's width/height in place, preserving each board's
    /// own `id` — mapping to a freshly-constructed `BoardSize` instead would
    /// give every board the same (newly generated) id, which broke the
    /// board `ForEach`'s identity and made SwiftUI collapse the view down to
    /// just one board.
    private func applyFixedSizeToAllBoards() {
        for index in boardSizes.indices {
            boardSizes[index].width = fixedBoardWidth
            boardSizes[index].height = fixedBoardHeight
        }
    }

    // MARK: - Undo

    struct UndoSnapshot {
        let items: [CanvasItem]
        let boardSizes: [BoardSize]
        let verticalGuides: [Guide]
        let horizontalGuides: [Guide]
    }

    /// Exposed (not just used internally) so a multi-step action like a bulk
    /// rename can capture "before" up front and only register the undo step
    /// once it knows what actually succeeded.
    func captureSnapshot() -> UndoSnapshot {
        UndoSnapshot(items: items, boardSizes: boardSizes, verticalGuides: verticalGuides, horizontalGuides: horizontalGuides)
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
            target.boardSizes = snapshot.boardSizes
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
        var loadedLayout: CanvasLayout?
        if let data = try? Data(contentsOf: ltFileURL),
           let layout = try? JSONDecoder().decode(CanvasLayout.self, from: data) {
            loadedLayout = layout
            existing = layout.items
            canvasColor = layout.canvasColor
            excludedFileIDs = layout.excludedFileIDs ?? []
            verticalGuides = layout.verticalGuides ?? []
            horizontalGuides = layout.horizontalGuides ?? []
            guideColor = layout.guideColor
            boardSizeMode = layout.boardSizeMode ?? .auto
            fixedBoardWidth = layout.fixedBoardWidth ?? fixedBoardWidth
            fixedBoardHeight = layout.fixedBoardHeight ?? fixedBoardHeight
            boardSizeUnit = layout.boardSizeUnit ?? .inches
            if let sizes = layout.boardSizes, !sizes.isEmpty {
                boardSizes = sizes
            }
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
            // Text items have no file on disk to reconcile against — they'd
            // never match and would otherwise get silently dropped by the
            // file-matching logic below, which is only meaningful for images.
            guard item.kind == .image else {
                result.append(item)
                continue
            }
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

        // New files land on the last board — same rule `refreshFromDisk` uses
        // for files that were never on the canvas at all.
        let newFiles = filesOnDisk.filter { !matchedFilenames.contains($0.lastPathComponent) && !isExcluded($0) }
        if !newFiles.isEmpty {
            let lastBoard = max(boardSizes.count - 1, 0)
            let startIndex = result.filter { $0.boardIndex == lastBoard }.count
            for (offset, url) in newFiles.enumerated() {
                var item = Self.gridPlacement(index: startIndex + offset, filename: url.lastPathComponent, fileURL: url, boardIndex: lastBoard)
                item.fileID = ImageFileSupport.fileID(of: url)
                result.append(item)
            }
        }

        items = result

        // Migrating a pre-art-board file: nothing was ever a board's stored
        // size before, so use the larger of the old single-canvas size and
        // the actual content extent, so nothing already on the canvas gets
        // clipped by the new Board 1.
        if loadedLayout?.boardSizes == nil {
            let maxX = items.reduce(0.0) { max($0, $1.x + $1.width) }
            let maxY = items.reduce(0.0) { max($0, $1.y + $1.height) }
            let legacyWidth = loadedLayout?.canvasWidth ?? boardSizes.first?.width ?? 1600
            let legacyHeight = loadedLayout?.canvasHeight ?? boardSizes.first?.height ?? 1000
            boardSizes = [BoardSize(width: max(legacyWidth, maxX), height: max(legacyHeight, maxY))]
        }

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
    private static func gridPlacement(index: Int, filename: String, fileURL: URL, crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), boardIndex: Int = 0) -> CanvasItem {
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
            cropX: crop.minX, cropY: crop.minY, cropWidth: crop.width, cropHeight: crop.height,
            boardIndex: boardIndex
        )
    }

    /// Re-reads the folder from disk and re-flows every image into a fresh
    /// grid, resizing its board to fit. Runs per board — each board's own
    /// existing items are re-gridded back onto that same board; files that
    /// were never on the canvas at all land on the last board. Items whose
    /// files are gone (e.g. deleted during culling) are dropped; existing
    /// crops are preserved for files that are matched (by inode, then
    /// filename). Useful for regrouping after a round of deletions has left
    /// gaps in a manually arranged layout.
    func refreshFromDisk() {
        // Text items have no file to re-flow against — untouched by this,
        // same as images that were excluded from auto-import.
        let textItems = items.filter { $0.kind == .text }

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
        for item in items where item.kind == .image {
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

        let lastBoard = max(boardSizes.count - 1, 0)
        var placedByBoard: [Int: [CanvasItem]] = [:]
        for url in filesOnDisk {
            let filename = url.lastPathComponent
            let existing = existingByFilename[filename]
            let boardIndex = existing?.boardIndex ?? lastBoard
            var placed = Self.gridPlacement(
                index: placedByBoard[boardIndex]?.count ?? 0, filename: filename, fileURL: url,
                crop: existing?.cropRect ?? CGRect(x: 0, y: 0, width: 1, height: 1), boardIndex: boardIndex
            )
            if let existing {
                placed.id = existing.id
            }
            placed.fileID = ImageFileSupport.fileID(of: url)
            placedByBoard[boardIndex, default: []].append(placed)
        }

        registerUndoCheckpoint(actionName: "Refresh")

        items = placedByBoard.sorted { $0.key < $1.key }.flatMap(\.value) + textItems
        selectedIDs = []
        groupDragOffset = .zero

        for boardIndex in placedByBoard.keys {
            let boardItems = placedByBoard[boardIndex] ?? []
            let maxX = boardItems.reduce(0.0) { max($0, $1.x + $1.width) }
            let maxY = boardItems.reduce(0.0) { max($0, $1.y + $1.height) }
            guard boardSizes.indices.contains(boardIndex) else { continue }
            if boardSizeMode == .auto {
                boardSizes[boardIndex].width = min(max(maxX + 200, Self.minCanvasDimension), Self.maxCanvasDimension)
                boardSizes[boardIndex].height = min(max(maxY + 200, Self.minCanvasDimension), Self.maxCanvasDimension)
            }
        }

        save()
    }

    // MARK: - Persistence

    func save() {
        let layout = CanvasLayout(
            items: items, canvasWidth: boardSizes.first?.width, canvasHeight: boardSizes.first?.height, canvasColor: canvasColor,
            excludedFileIDs: excludedFileIDs, verticalGuides: verticalGuides, horizontalGuides: horizontalGuides,
            guideColor: guideColor, boardSizes: boardSizes, boardSizeMode: boardSizeMode,
            fixedBoardWidth: fixedBoardWidth, fixedBoardHeight: fixedBoardHeight, boardSizeUnit: boardSizeUnit
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

    /// `point` is local to `boardIndex`'s own origin — the view layer
    /// resolves a raw drop location (in the shared display space) to a board
    /// + local point before calling this.
    func addImage(fromDropped sourceURL: URL, at point: CGPoint, boardIndex: Int) {
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
                fileID: fileID,
                boardIndex: boardIndex
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
            fileID: ImageFileSupport.fileID(of: destURL),
            boardIndex: boardIndex
        )

        registerUndoCheckpoint(actionName: "Add Image") { _ in
            try? FileManager.default.trashItem(at: destURL, resultingItemURL: nil)
        }

        items.append(item)
        selectedIDs = [item.id]
        save()
    }

    /// Adds a new text field (default: doesn't wrap, grows with its
    /// content — a return key starts a new line) or text box (wraps within
    /// its width, for paragraphs), centered on `point` — local to
    /// `boardIndex`'s own origin, same convention as `addImage`.
    @discardableResult
    func addTextItem(isBox: Bool, at point: CGPoint, boardIndex: Int) -> UUID {
        let size = isBox ? CGSize(width: 320, height: 160) : CGSize(width: 240, height: 44)
        let item = CanvasItem(
            kind: .text,
            x: max(point.x - size.width / 2, 0),
            y: max(point.y - size.height / 2, 0),
            width: size.width,
            height: size.height,
            boardIndex: boardIndex,
            text: isBox ? "Paragraph text" : "Text",
            isTextBox: isBox,
            fontSize: isBox ? 18 : 32
        )

        registerUndoCheckpoint(actionName: isBox ? "Add Text Box" : "Add Text Field")
        items.append(item)
        selectedIDs = [item.id]
        save()
        return item.id
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
    /// Text items have no file, so they're just removed from the canvas —
    /// same as `removeFromCanvas` for them.
    func deleteItems(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        var trashedPairs: [(original: URL, trashed: URL)] = []
        for id in ids {
            guard let item = items.first(where: { $0.id == id }), item.kind == .image else { continue }
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
    /// side by side. The originals are left untouched. Text items have no
    /// file to copy — they're just duplicated as data, same offset.
    func duplicateItems(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let fm = FileManager.default
        let targets = items.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        var newItems: [CanvasItem] = []
        var copiedURLs: [URL] = []

        for item in targets {
            var newItem = item
            newItem.id = UUID()
            newItem.x += 24
            newItem.y += 24

            if item.kind == .image {
                let sourceURL = folderURL.appendingPathComponent(item.filename)
                let newName = ImageFileSupport.duplicateFilename(for: item.filename, in: folderURL)
                let destURL = folderURL.appendingPathComponent(newName)
                guard (try? fm.copyItem(at: sourceURL, to: destURL)) != nil else { continue }
                copiedURLs.append(destURL)
                newItem.filename = newName
                newItem.fileID = ImageFileSupport.fileID(of: destURL)
            }
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

    /// Replaces an existing image card's file content in place — same
    /// position/size, crop reset to the full new image — used when a file
    /// from Finder is dropped directly onto a card rather than empty canvas.
    /// If `sourceURL` isn't already inside this document's folder, it's
    /// copied in first, same as a normal drop. The old file is trashed
    /// (undo-ably) unless some other item still references it.
    func replaceImage(_ itemID: UUID, with sourceURL: URL) {
        guard let item = items.first(where: { $0.id == itemID }), item.kind == .image else { return }
        if let error = ImageFileSupport.oversizeError(for: sourceURL) {
            importError = error
            return
        }

        let oldFileID = item.fileID

        let isAlreadyLocal = sourceURL.deletingLastPathComponent().standardizedFileURL == folderURL.standardizedFileURL
        // A file already inside the folder might still be a different card's
        // own image (e.g. dragged a second time from the project folder's
        // own Finder window after an earlier replace copied it in) — every
        // item needs a distinct file, since reconciliation on reload can
        // only represent one item per filename, so that case still needs a
        // fresh copy rather than reusing the claimed file directly.
        let isClaimedByAnotherItem = items.contains {
            $0.id != itemID && $0.kind == .image && $0.filename == sourceURL.lastPathComponent
        }

        let finalName: String
        let destURL: URL
        var copiedNewFile = false
        if isAlreadyLocal, !isClaimedByAnotherItem {
            finalName = sourceURL.lastPathComponent
            destURL = sourceURL
        } else if isAlreadyLocal {
            finalName = ImageFileSupport.duplicateFilename(for: sourceURL.lastPathComponent, in: folderURL)
            destURL = folderURL.appendingPathComponent(finalName)
            guard (try? FileManager.default.copyItem(at: sourceURL, to: destURL)) != nil else {
                NSSound.beep()
                return
            }
            copiedNewFile = true
        } else {
            finalName = ImageFileSupport.availableFilename(for: sourceURL.lastPathComponent, in: folderURL)
            destURL = folderURL.appendingPathComponent(finalName)
            let isAccessingScope = sourceURL.startAccessingSecurityScopedResource()
            defer { if isAccessingScope { sourceURL.stopAccessingSecurityScopedResource() } }
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                copiedNewFile = true
            } catch {
                NSSound.beep()
                return
            }
        }

        let newFileID = ImageFileSupport.fileID(of: destURL)

        // The old file's data is left untouched on disk — only this card
        // stops referencing it. If nothing else on the canvas still points
        // at it (e.g. a duplicate), it's excluded the same way a plain
        // Remove from Canvas works, so a later Refresh doesn't silently
        // re-add it as a new, unrelated card.
        let oldFileStillUsed = items.contains { $0.id != itemID && $0.kind == .image && $0.fileID == oldFileID }
        let shouldExcludeOldFile = !oldFileStillUsed && newFileID != oldFileID && oldFileID != nil

        registerUndoCheckpoint(actionName: "Replace Image") { target in
            if copiedNewFile {
                try? FileManager.default.trashItem(at: destURL, resultingItemURL: nil)
            }
            if shouldExcludeOldFile, let oldFileID {
                target.excludedFileIDs.remove(oldFileID)
            }
        }

        if shouldExcludeOldFile, let oldFileID {
            excludedFileIDs.insert(oldFileID)
        }

        updateItem(itemID) { current in
            current.filename = finalName
            current.fileID = newFileID
            current.cropX = 0
            current.cropY = 0
            current.cropWidth = 1
            current.cropHeight = 1
        }
        save()
    }

    // MARK: - Clipboard

    /// Snapshots the current selection into the shared clipboard without
    /// touching the canvas — a later paste (here or in another document's
    /// window) duplicates each item, copying image files anew each time.
    func copySelectedToClipboard() {
        let targets = items.filter { selectedIDs.contains($0.id) }
        guard !targets.isEmpty else { return }
        CanvasClipboard.shared.payload = CanvasClipboard.Payload(mode: .copy, items: targets, sourceFolderURL: folderURL)
    }

    /// Snapshots the current selection into the shared clipboard, then
    /// removes it from this canvas the same (non-destructive) way plain
    /// Delete does — the file itself stays on disk until a paste lands
    /// somewhere, so undoing a cut with nothing pasted yet still works.
    func cutSelectedToClipboard() {
        let targets = items.filter { selectedIDs.contains($0.id) }
        guard !targets.isEmpty else { return }
        CanvasClipboard.shared.payload = CanvasClipboard.Payload(mode: .cut, items: targets, sourceFolderURL: folderURL)
        removeFromCanvas(selectedIDs)
    }

    /// Pastes the clipboard's items centered on `point` (local to
    /// `boardIndex`'s own origin, same convention as `addImage`/
    /// `addTextItem`), preserving their arrangement relative to one another.
    /// A copied image is duplicated into a fresh file every paste, like
    /// `duplicateItems`. A cut image pasted back into its *own* source
    /// document is just repositioned — no file copy — matching a real move;
    /// pasted into a different document (or copied a second time after
    /// that), it falls back to copying the file across, since the original
    /// document's own reference to it is already gone.
    func pasteFromClipboard(at point: CGPoint, boardIndex: Int) {
        guard let payload = CanvasClipboard.shared.payload, !payload.items.isEmpty else { return }
        let fm = FileManager.default
        let isSameDocument = payload.sourceFolderURL.standardizedFileURL == folderURL.standardizedFileURL

        let minX = payload.items.map(\.x).min() ?? 0
        let minY = payload.items.map(\.y).min() ?? 0
        let maxX = payload.items.map { $0.x + $0.width }.max() ?? 0
        let maxY = payload.items.map { $0.y + $0.height }.max() ?? 0
        let dx = point.x - (minX + maxX) / 2
        let dy = point.y - (minY + maxY) / 2

        var newItems: [CanvasItem] = []
        var copiedURLs: [URL] = []

        for original in payload.items {
            var newItem = original
            newItem.id = UUID()
            newItem.x = max(original.x + dx, 0)
            newItem.y = max(original.y + dy, 0)
            newItem.boardIndex = boardIndex

            if original.kind == .image {
                if payload.mode == .cut, isSameDocument {
                    if let fileID = original.fileID { excludedFileIDs.remove(fileID) }
                } else {
                    let sourceFileURL = payload.sourceFolderURL.appendingPathComponent(original.filename)
                    guard fm.fileExists(atPath: sourceFileURL.path) else { continue }
                    let newName = ImageFileSupport.duplicateFilename(for: original.filename, in: folderURL)
                    let destURL = folderURL.appendingPathComponent(newName)
                    guard (try? fm.copyItem(at: sourceFileURL, to: destURL)) != nil else { continue }
                    copiedURLs.append(destURL)
                    newItem.filename = newName
                    newItem.fileID = ImageFileSupport.fileID(of: destURL)
                }
            }
            newItems.append(newItem)
        }
        guard !newItems.isEmpty else { return }

        registerUndoCheckpoint(actionName: payload.mode == .cut ? "Paste (Move)" : "Paste") { _ in
            for url in copiedURLs {
                try? fm.trashItem(at: url, resultingItemURL: nil)
            }
        }

        items.append(contentsOf: newItems)
        selectedIDs = Set(newItems.map { $0.id })
        save()

        // A cut can only really "move" once — any further paste (here or
        // elsewhere) duplicates instead, since the original slot is gone.
        if payload.mode == .cut {
            CanvasClipboard.shared.payload?.mode = .copy
        }
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
    /// card positions on the canvas — board by board, in board order, so a
    /// multi-board document reads through board 1 entirely before board 2.
    func readingOrder() -> [CanvasItem] {
        readingOrderRows().flatMap { $0 }
    }

    /// Same grouping as `readingOrder()`, but keeping each row separate so
    /// up/down navigation can find the item in the neighboring row closest
    /// to the current one's horizontal position. Row groups never span a
    /// board boundary.
    func readingOrderRows() -> [[CanvasItem]] {
        boardSizes.indices.flatMap { Self.rowGroupedReadingOrder(items(onBoard: $0)) }
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
    /// Only items on the same board as the first selected item participate
    /// — a selection spanning multiple boards silently drops the strays,
    /// since a grid can't sensibly span a board boundary.
    ///
    /// Row membership starts from the images' *existing* rows (by current
    /// y-position), not a from-scratch repack — an already-tidy 5-then-4
    /// arrangement stays 5-then-4 instead of shuffling into 6-then-3 just
    /// because there happened to be a sliver of width left over. Existing
    /// rows only get merged into one output row when they jointly still fit
    /// the board width (so a short trailing row, e.g. one straggler,
    /// settles into the row above it rather than sitting alone), and an
    /// existing row wider than the board on its own is the only case that
    /// gets split, item by item. The grid starts at the selection's own
    /// top-left corner, so it replaces the selected images roughly where
    /// they already were.
    func createGrid(_ ids: Set<UUID>, spacing: Double, isPercentage: Bool) {
        // Text items don't participate — a grid re-flow only makes sense
        // for photos.
        let allTargets = items.filter { ids.contains($0.id) && $0.kind == .image }
        guard let boardIndex = allTargets.first?.boardIndex else { return }
        let targets = allTargets.filter { $0.boardIndex == boardIndex }
        guard targets.count >= 2, boardSizes.indices.contains(boardIndex) else { return }

        let existingRows = Self.rowGroupedReadingOrder(targets)
        let commonHeight = targets.reduce(0.0) { $0 + $1.height } / Double(targets.count)
        let gap = isPercentage ? commonHeight * (spacing / 100) : spacing

        let originX = targets.map(\.x).min() ?? 0
        let originY = targets.map(\.y).min() ?? 0
        let maxRowWidth = max(boardSizes[boardIndex].width - originX, commonHeight)

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

        if boardSizeMode == .auto {
            boardSizes[boardIndex].height = max(boardSizes[boardIndex].height, maxY + 90)
        }
        selectedIDs = Set(targets.map(\.id))
        save()
    }
}
