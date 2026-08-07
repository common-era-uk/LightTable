import SwiftUI

struct RenamePanelView: View {
    @ObservedObject var document: CanvasDocument
    @Binding var isPresented: Bool

    @State private var baseName: String = "image"
    @State private var separator: String = "_"
    @State private var startNumber: Int = 1
    @State private var padding: Int = 3
    @State private var renameError: String?

    private var orderedItems: [CanvasItem] {
        document.readingOrder()
    }

    private var plannedNames: [(item: CanvasItem, newName: String)] {
        orderedItems.enumerated().map { offset, item in
            let ext = (item.filename as NSString).pathExtension
            let seq = String(format: "%0\(padding)d", startNumber + offset)
            let trimmedBase = baseName.trimmingCharacters(in: .whitespaces)
            let core = trimmedBase.isEmpty ? "image" : trimmedBase
            let newName = ext.isEmpty ? "\(core)\(separator)\(seq)" : "\(core)\(separator)\(seq).\(ext)"
            return (item, newName)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename in sequence order")
                .font(.title2.bold())
            Text("Order is computed top-to-bottom, left-to-right from each image's position on the canvas.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Form {
                TextField("Base name", text: $baseName)
                TextField("Separator", text: $separator)
                Stepper("Start at: \(startNumber)", value: $startNumber, in: 0...9999)
                Stepper("Digits: \(padding)", value: $padding, in: 1...6)
            }
            .frame(maxWidth: 360)

            Text("Preview")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plannedNames, id: \.item.id) { pair in
                        HStack {
                            Text(pair.item.filename)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            Text(pair.newName)
                        }
                        .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .frame(minHeight: 200, maxHeight: 320)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { applyRename() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(orderedItems.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520, height: 560)
        .alert("Some Files Couldn't Be Renamed", isPresented: Binding(
            get: { renameError != nil },
            set: { isPresented in if !isPresented { renameError = nil } }
        ), presenting: renameError) { _ in
            Button("OK") { renameError = nil }
        } message: { message in
            Text(message)
        }
    }

    private func applyRename() {
        let plan = plannedNames
        let fm = FileManager.default
        let folder = document.folderURL
        let undoSnapshot = document.captureSnapshot()

        // Phase 1: move everything to unique temp names to avoid collisions
        // when new names overlap with existing ones (e.g. renumbering).
        // Only items that actually moved get a temp-name entry, so a failure
        // here can never desync the model (updated below) from disk.
        var tempNames: [UUID: String] = [:]
        var failures = 0
        for pair in plan {
            let tempName = ".lighttable_tmp_\(UUID().uuidString)_\(pair.item.filename)"
            let from = folder.appendingPathComponent(pair.item.filename)
            let to = folder.appendingPathComponent(tempName)
            do {
                try fm.moveItem(at: from, to: to)
                tempNames[pair.item.id] = tempName
            } catch {
                failures += 1
            }
        }

        // Phase 2: move temp names to final names, updating the model only
        // for files that actually landed at their new name. Successful
        // (oldName, newName) pairs are kept so undo can reverse the actual
        // renames on disk, not just the in-memory filenames.
        var renamed: [(oldName: String, newName: String)] = []
        for pair in plan {
            guard let tempName = tempNames[pair.item.id] else { continue }
            let from = folder.appendingPathComponent(tempName)
            let to = folder.appendingPathComponent(pair.newName)
            do {
                try fm.moveItem(at: from, to: to)
                document.updateItem(pair.item.id) { $0.filename = pair.newName }
                renamed.append((oldName: pair.item.filename, newName: pair.newName))
            } catch {
                // Couldn't reach the final name — restore the original name
                // so the file isn't left stranded under a temp name.
                try? fm.moveItem(at: from, to: folder.appendingPathComponent(pair.item.filename))
                failures += 1
            }
        }

        if !renamed.isEmpty {
            document.registerUndo(undoSnapshot, actionName: "Rename") { _ in
                for pair in renamed {
                    let from = folder.appendingPathComponent(pair.newName)
                    let to = folder.appendingPathComponent(pair.oldName)
                    try? fm.moveItem(at: from, to: to)
                }
            }
        }

        document.save()
        if failures > 0 {
            renameError = "\(failures) file\(failures == 1 ? "" : "s") couldn't be renamed and kept its original name. The rest were renamed successfully."
        } else {
            isPresented = false
        }
    }
}
