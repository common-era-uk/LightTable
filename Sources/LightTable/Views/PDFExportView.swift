import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PDFExportView: View {
    @ObservedObject var document: CanvasDocument
    @Binding var isPresented: Bool

    @State private var includedBoards: Set<Int>
    @State private var exportAllBoards = true
    @State private var dpi: Int = 150
    @State private var quality: PDFExport.ImageQuality = .medium
    @State private var exportError: String?

    private static let dpiOptions = [72, 96, 150, 300]

    init(document: CanvasDocument, isPresented: Binding<Bool>) {
        self.document = document
        self._isPresented = isPresented
        _includedBoards = State(initialValue: Set(document.boardSizes.indices))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export as PDF")
                .font(.title2.bold())
            Text("Each included art board becomes one page, in order.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle("All art boards (\(document.boardSizes.count))", isOn: $exportAllBoards)

            if !exportAllBoards {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(document.boardSizes.indices, id: \.self) { index in
                            Toggle("Art Board \(index + 1)", isOn: boardBinding(index))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 20)
                }
                .frame(maxHeight: 200)
            }

            HStack {
                Text("Resolution:")
                Picker("", selection: $dpi) {
                    ForEach(Self.dpiOptions, id: \.self) { option in
                        Text("\(option) dpi").tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }

            HStack {
                Text("Image quality:")
                Picker("", selection: $quality) {
                    ForEach(PDFExport.ImageQuality.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }
            Text("Text stays sharp at any resolution. Resolution and quality only affect photos — lower either for a smaller file.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") { export() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!exportAllBoards && includedBoards.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .alert("Can't Export PDF", isPresented: Binding(
            get: { exportError != nil },
            set: { isPresented in if !isPresented { exportError = nil } }
        ), presenting: exportError) { _ in
            Button("OK") { exportError = nil }
        } message: { message in
            Text(message)
        }
    }

    private func boardBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { includedBoards.contains(index) },
            set: { isOn in
                if isOn { includedBoards.insert(index) } else { includedBoards.remove(index) }
            }
        )
    }

    private func export() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.directoryURL = document.folderURL
        panel.nameFieldStringValue = "\(document.ltFileURL.deletingPathExtension().lastPathComponent).pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let ordered = document.boardSizes.indices.filter { exportAllBoards || includedBoards.contains($0) }
        do {
            try PDFExport.export(document: document, boardIndices: ordered, dpi: Double(dpi), quality: quality, to: url)
            isPresented = false
        } catch {
            exportError = error.localizedDescription
        }
    }
}
