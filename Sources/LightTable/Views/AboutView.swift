import SwiftUI
import AppKit

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private let tips: [(title: String, detail: String)] = [
        ("Open a folder", "Choose a folder full of images, or drag one onto the LightTable Dock icon. To start a blank LightTable, create or open an empty folder. When you drag images onto your LightTable, they're automatically copied into the folder."),
        ("Pan the canvas", "Scroll or swipe with two fingers on the trackpad."),
        ("Zoom in / out", "Hold ⌘ and scroll, or use the + / − buttons in the toolbar."),
        ("Move an image", "Click and drag it. Drag on empty canvas to select multiple."),
        ("Resize an image", "Drag a corner handle — the aspect ratio stays locked. With multiple images selected, hold ⌘ while dragging a handle to scale all of them together, by the same amount."),
        ("Guides", "Drag in from the top or left edge to place a guide line. Click one to select it (Delete removes it), or drag it to reposition — drag it back to the edge to remove it. Images snap to guides when moved or resized nearby. Toggle the \"Guides\" toolbar button (or View > Toggle Guides) to hide them and their ruler strips; change their color with View > Change Guide Color."),
        ("Show filenames", "Toggle the \"Filenames\" button in the toolbar to show or hide each image's filename underneath it."),
        ("Canvas color", "Click the palette icon in the toolbar to pick a custom canvas background color. It's remembered per folder and used when exporting too."),
        ("Shadows", "Use View > Show Shadows to turn image drop shadows on or off, and View > Shadow Settings… to adjust their distance, angle, blur, and opacity. This applies across the whole app, not just one folder."),
        ("Crop an image", "Double-click it to open the crop tool. \"Apply\" saves the crop on the canvas without touching the file. \"Apply & Export\" also writes a cropped copy into the canvas folder, named with a \"-crop\" suffix."),
        ("Delete an image", "Select it and press Delete (or the toolbar's Delete button) to remove it from the canvas — the file stays in the folder and won't be re-added automatically; drag it back onto the canvas to bring it back. Press ⌘-Delete instead to also move the file to Trash."),
        ("Undo", "Press ⌘Z to undo your last change — move, resize, crop, delete, rename, and more — up to 10 steps back. Undoing a delete restores the file from Trash."),
        ("Rename images", "Use the rename panel to number files in their canvas reading order."),
        ("Refresh", "Use the Refresh button in the toolbar to re-read the folder and re-flow every image into a fresh grid, resizing the canvas to fit — handy after deleting several images to regroup what's left."),
        ("Export", "Use \"Save Visible Area\" or \"Save Whole Canvas\" to export a flattened image."),
    ]

    private let columnCount = 3

    private func column(_ index: Int) -> ArraySlice<(title: String, detail: String)> {
        let perColumn = Int((Double(tips.count) / Double(columnCount)).rounded(.up))
        let start = min(index * perColumn, tips.count)
        let end = min(start + perColumn, tips.count)
        return tips[start..<end]
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                Text("LightTable")
                    .font(.title.bold())
                Text("Version \(version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Created by Kevin Moore")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("How to use")
                    .font(.headline)

                HStack(alignment: .top, spacing: 24) {
                    ForEach(0..<columnCount, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(column(index), id: \.title) { tip($0.title, $0.detail) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
        .frame(width: 940)
    }

    private func tip(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.bold())
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
