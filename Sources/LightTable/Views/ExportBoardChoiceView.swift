import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum ExportImageFormatChoice: String, CaseIterable, Identifiable {
    case png, jpeg

    var id: String { rawValue }
    var label: String { self == .png ? "PNG" : "JPEG" }
    var fileExtension: String { self == .png ? "png" : "jpg" }
    var contentType: UTType { self == .png ? .png : .jpeg }
}

/// Shown by "Save Whole Canvas…" when there's more than one art board —
/// lets the user pick a single board to export, or every board at once as
/// separate files, instead of always flattening the whole stacked canvas
/// into one image.
struct ExportBoardChoiceView: View {
    @ObservedObject var document: CanvasDocument
    @Binding var isPresented: Bool

    private enum Target: Hashable {
        case board(Int)
        case all
    }

    @State private var target: Target = .board(0)
    @State private var format: ExportImageFormatChoice = .png
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Whole Canvas")
                .font(.title2.bold())
            Text("Choose which art board to save as an image, or save every board as its own file.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: $target) {
                ForEach(document.boardSizes.indices, id: \.self) { index in
                    Text("Art Board \(index + 1)").tag(Target.board(index))
                }
                Text("All Boards (separate files)").tag(Target.all)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Picker("Format", selection: $format) {
                ForEach(ExportImageFormatChoice.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") { export() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
        .alert("Can't Export", isPresented: Binding(
            get: { exportError != nil },
            set: { isPresented in if !isPresented { exportError = nil } }
        ), presenting: exportError) { _ in
            Button("OK") { exportError = nil }
        } message: { message in
            Text(message)
        }
    }

    private func export() {
        switch target {
        case .board(let index):
            exportSingle(boardIndex: index)
        case .all:
            exportAll()
        }
    }

    private func exportSingle(boardIndex: Int) {
        guard let image = renderBoardImage(boardIndex) else {
            exportError = "Couldn't render that board."
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.directoryURL = document.folderURL
        let baseName = "\(document.ltFileURL.deletingPathExtension().lastPathComponent) - Board \(boardIndex + 1)"
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard writeImage(image, to: url) else {
            exportError = "Couldn't write the image file."
            return
        }
        isPresented = false
    }

    private func exportAll() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = document.folderURL
        guard panel.runModal() == .OK, let destFolder = panel.url else { return }

        var failures = 0
        for index in document.boardSizes.indices {
            guard let image = renderBoardImage(index) else { failures += 1; continue }
            let baseName = "\(document.ltFileURL.deletingPathExtension().lastPathComponent) - Board \(index + 1)"
            let finalName = ImageFileSupport.availableFilename(for: "\(baseName).\(format.fileExtension)", in: destFolder)
            let url = destFolder.appendingPathComponent(finalName)
            if !writeImage(image, to: url) { failures += 1 }
        }
        if failures > 0 {
            exportError = "\(failures) board\(failures == 1 ? "" : "s") couldn't be exported. The rest were saved successfully."
        } else {
            isPresented = false
        }
    }

    private func renderBoardImage(_ boardIndex: Int) -> CGImage? {
        let size = document.boardDisplaySize(boardIndex)
        let renderer = ImageRenderer(content: SingleBoardExportView(document: document, boardIndex: boardIndex, size: size))
        renderer.scale = 2
        return renderer.cgImage
    }

    private func writeImage(_ image: CGImage, to url: URL) -> Bool {
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        let fileType: NSBitmapImageRep.FileType = format == .jpeg ? .jpeg : .png
        let properties: [NSBitmapImageRep.PropertyKey: Any] = format == .jpeg ? [.compressionFactor: 0.9] : [:]
        guard let data = bitmapRep.representation(using: fileType, properties: properties) else { return false }
        return (try? data.write(to: url)) != nil
    }
}
