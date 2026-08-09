import SwiftUI
import AppKit

struct AboutView: View {
    private enum Section: String, CaseIterable {
        case gettingStarted = "Getting Started"
        case details = "Details"
        case exporting = "Exporting"
    }

    @State private var selectedSection: Section = .gettingStarted
    @State private var hoveredSection: Section?
    @State private var showChangelog = false
    @State private var changelogText = ""

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private let intro = "LightTable is a visual tool for working with folders of images. Use it to edit, sequence, re-order, make moodboards or just to compare images and play. Start by opening a folder full of images (low res is best). LightTable will create a canvas with all images in the folder laid out in a grid. Alternatively, open an empty folder and drag images onto the canvas – they will be automatically copied to the folder as well. From here you can move, resize, preview, crop and delete images."

    private let gettingStartedLeft: [(title: String, detail: String)] = [
        ("Open a folder", "Choose a folder full of images, or drag one onto the LightTable Dock icon. To start a blank LightTable, create or open an empty folder. When you drag images onto your LightTable, they're automatically copied into the folder."),
        ("Pan the canvas", "Scroll or swipe with two fingers on the trackpad. You can also hold Space and click-drag anywhere on the canvas to pan it the same way."),
        ("Zoom in / out", "Hold ⌘ and scroll, or use the + / − buttons in the toolbar."),
        ("Move an image", "Click and drag it. Drag on empty canvas to select multiple. With one or more selected, the arrow keys nudge them by 1pt — hold Shift for 10pt."),
        ("Resize an image", "Drag a corner handle — the aspect ratio stays locked. With multiple images selected, hold ⌘ while dragging a handle to scale all of them together, by the same amount."),
    ]

    private let gettingStartedRight: [(title: String, detail: String)] = [
        ("Preview an image", "Select a single image and press Space to see it large, like Quick Look. While previewing, the left/right arrow keys step to the next or previous image in canvas reading order, and up/down jump a row, landing on whichever image is closest horizontally. Press Space or Escape again, or click, to close it."),
        ("Crop an image", "Double-click it to open the crop tool. \"Apply\" saves the crop on the canvas without touching the file. \"Apply & Export\" also writes a cropped copy into the canvas folder, named with a \"-crop\" suffix."),
        ("Delete an image", "Select it and press Delete (or the toolbar's Delete button) to remove it from the canvas — the file stays in the folder and won't be re-added automatically; drag it back onto the canvas to bring it back. Press ⌘-Delete instead to also move the file to Trash."),
        ("Undo", "Press ⌘Z to undo your last change — move, resize, crop, delete, rename, and more — up to 10 steps back. Undoing a delete restores the file from Trash."),
    ]

    private let detailsTips: [(title: String, detail: String)] = [
        ("Show filenames", "Toggle the \"Filenames\" button in the toolbar to show or hide each image's filename underneath it."),
        ("Canvas color", "Click the palette icon in the toolbar to pick a custom canvas background color. It's remembered per folder and used when exporting too."),
        ("Shadows", "Use View > Toggle Shadows to turn image drop shadows on or off, and View > Shadow Settings… to adjust their distance, angle, blur, and opacity. This applies across the whole app, not just one folder."),
        ("Large preview background", "Use View > Large Preview Background Settings… to set the color and opacity behind a large image preview, plus whether its filename label shows and what color it is."),
        ("Guides", "Drag in from the top or left edge to place a guide line. Click one to select it (Delete removes it), or drag it to reposition — drag it back to the edge to remove it. Images snap to guides when moved or resized nearby. Toggle the \"Guides\" toolbar button (or View > Toggle Guides) to hide them and their ruler strips; change their color with View > Change Guide Color."),
    ]

    private let exportingTips: [(title: String, detail: String)] = [
        ("Rename images", "Use the rename panel to number files in their canvas reading order."),
        ("Refresh", "Use the Refresh button in the toolbar to re-read the folder and re-flow every image into a fresh grid, resizing the canvas to fit — handy after deleting several images to regroup what's left."),
        ("Export", "Use \"Save Visible Area\" or \"Save Whole Canvas\" to export a flattened image. Choose PNG or JPEG with the format control in the save panel."),
    ]

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
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showChangelog.toggle()
                    }
                } label: {
                    Text("View Changelog")
                        .font(.caption)
                        .underline()
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack(alignment: .top, spacing: 28) {
                sidebar
                    .frame(width: 150, alignment: .leading)

                ScrollView {
                    Group {
                        if showChangelog {
                            changelogContent
                        } else {
                            sectionContent
                        }
                    }
                    .id(showChangelog ? "changelog" : selectedSection.rawValue)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(height: contentHeight)
            }
        }
        .padding(28)
        .frame(width: 820)
        .onAppear(perform: loadChangelog)
    }

    /// Fixed so switching sections or opening the changelog never resizes
    /// the window — the content area scrolls internally instead of the
    /// whole window growing/shrinking to fit whatever's currently showing.
    private let contentHeight: CGFloat = 420

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Section.allCases, id: \.self) { section in
                let isActive = !showChangelog && selectedSection == section
                let isHighlighted = isActive || hoveredSection == section
                Text(section.rawValue)
                    .font(.system(size: 15, weight: isActive ? .bold : .regular))
                    .foregroundStyle(isHighlighted ? Color.primary : Color.secondary)
                    .contentShape(Rectangle())
                    .onHover { hovering in hoveredSection = hovering ? section : nil }
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedSection = section
                            showChangelog = false
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .gettingStarted:
            VStack(alignment: .leading, spacing: 16) {
                Text(intro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(gettingStartedLeft, id: \.title) { tip($0.title, $0.detail) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(gettingStartedRight, id: \.title) { tip($0.title, $0.detail) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .details:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(detailsTips, id: \.title) { tip($0.title, $0.detail) }
            }
        case .exporting:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(exportingTips, id: \.title) { tip($0.title, $0.detail) }
            }
        }
    }

    private var changelogContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parsedChangelog.enumerated()), id: \.offset) { _, line in
                changelogLine(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum ChangelogLine {
        case heading(String)
        case version(String)
        case bullet(String)
        case text(String)
    }

    private var parsedChangelog: [ChangelogLine] {
        changelogText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                if line.hasPrefix("## ") { return .version(String(line.dropFirst(3))) }
                if line.hasPrefix("# ") { return .heading(String(line.dropFirst(2))) }
                if line.hasPrefix("- ") { return .bullet(String(line.dropFirst(2))) }
                return .text(line)
            }
    }

    @ViewBuilder
    private func changelogLine(_ line: ChangelogLine) -> some View {
        switch line {
        case .heading(let text):
            Text(text)
                .font(.title3.bold())
                .padding(.top, 4)
        case .version(let text):
            Text(text)
                .font(.headline)
                .padding(.top, 10)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        case .text(let text):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func loadChangelog() {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            changelogText = "Changelog unavailable."
            return
        }
        changelogText = text
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
