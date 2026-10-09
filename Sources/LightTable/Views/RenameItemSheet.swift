import SwiftUI

/// Presents `RenameItemSheet` whenever `itemID` is set. A modifier rather
/// than another `.sheet` on `CanvasView.body`, which is already at the limit
/// of what the type checker will accept in one expression.
struct RenameItemSheetModifier: ViewModifier {
    @ObservedObject var document: CanvasDocument
    @Binding var itemID: UUID?

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { itemID != nil },
            set: { if !$0 { itemID = nil } }
        )) {
            if let id = itemID, let item = document.items.first(where: { $0.id == id }) {
                RenameItemSheet(document: document, itemID: id, filename: item.filename) {
                    itemID = nil
                }
            }
        }
    }
}

/// Renames a single image's file. The extension is fixed (shown beside the
/// field) so a rename can't accidentally change the file's type.
struct RenameItemSheet: View {
    @ObservedObject var document: CanvasDocument
    let itemID: UUID
    let filename: String
    let onClose: () -> Void

    @State private var baseName: String
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private let fileExtension: String

    init(document: CanvasDocument, itemID: UUID, filename: String, onClose: @escaping () -> Void) {
        self.document = document
        self.itemID = itemID
        self.filename = filename
        self.onClose = onClose
        let ns = filename as NSString
        self.fileExtension = ns.pathExtension
        self._baseName = State(initialValue: ns.deletingPathExtension)
    }

    private var newFilename: String {
        let trimmed = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return fileExtension.isEmpty ? trimmed : "\(trimmed).\(fileExtension)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename File")
                .font(.title3.bold())
            Text("Renames the file in the folder; the card keeps its place on the canvas.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                TextField("Name", text: $baseName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(apply)
                if !fileExtension.isEmpty {
                    Text(".\(fileExtension)")
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { isFocused = true }
    }

    private func apply() {
        do {
            try document.renameFile(of: itemID, to: newFilename)
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
