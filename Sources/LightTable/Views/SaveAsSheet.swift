import SwiftUI

/// Prompts for a name and writes a copy of the current `.lt` document under
/// it, in the same folder — the `.lt` always has to sit alongside the images
/// it references, so there's no location picker, just a name.
struct SaveAsSheet: View {
    let currentName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String

    init(currentName: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.currentName = currentName
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: "\(currentName) copy")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save As")
                .font(.title2.bold())
            Text("Creates a new canvas with a copy of this one's current layout, in the same folder. The images themselves aren't duplicated.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Canvas name", text: $name)
                    .textFieldStyle(.roundedBorder)
                Text(".\(CanvasDocument.fileExtension)")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(trimmedName) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
