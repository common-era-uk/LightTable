import SwiftUI

/// Describes what's needed to turn a folder the user picked (or dropped)
/// into a specific `.lt` document — shown as a sheet by `RootView` whenever
/// a folder doesn't resolve unambiguously to exactly one canvas.
struct PendingResolution: Identifiable {
    let id = UUID()
    let folderURL: URL
    /// Every `.lt` file already in the folder (may be empty).
    let existingLTFiles: [URL]
    /// A legacy hidden sidecar found in the folder, if any — only relevant
    /// when `existingLTFiles` is empty (a folder that already has a real
    /// `.lt` file has already been migrated, or never needed to be).
    let legacyJSONURL: URL?
}

struct DocumentResolutionSheet: View {
    let resolution: PendingResolution
    let onResolved: (URL) -> Void
    let onCancel: () -> Void

    @State private var newName: String = ""

    private var isMigrating: Bool {
        resolution.existingLTFiles.isEmpty && resolution.legacyJSONURL != nil
    }

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if resolution.existingLTFiles.isEmpty {
                emptyFolderContent
            } else {
                chooseContent
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            newName = resolution.folderURL.lastPathComponent
        }
    }

    @ViewBuilder
    private var emptyFolderContent: some View {
        if isMigrating {
            Text("Upgrade This Folder")
                .font(.title2.bold())
            Text("This folder uses LightTable's older format. Choose a name for its new canvas file:")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Text("New Canvas")
                .font(.title2.bold())
            Text("Choose a name for this folder's canvas:")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        nameField
        HStack {
            Spacer()
            Button("Cancel") { onCancel() }
                .keyboardShortcut(.cancelAction)
            Button(isMigrating ? "Upgrade" : "Create") { confirmCreateOrMigrate() }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
        }
    }

    private var chooseContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a Canvas")
                .font(.title2.bold())
            Text("This folder has more than one LightTable canvas:")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(resolution.existingLTFiles, id: \.self) { url in
                    Button {
                        onResolved(url)
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.grid.2x2")
                            Text(url.deletingPathExtension().lastPathComponent)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }

            Divider()

            Text("Or create a new one:")
                .font(.callout)
                .foregroundStyle(.secondary)
            nameField
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { confirmCreateOrMigrate() }
                    .disabled(trimmedName.isEmpty)
            }
        }
    }

    private var nameField: some View {
        HStack {
            TextField("Canvas name", text: $newName)
                .textFieldStyle(.roundedBorder)
            Text(".\(CanvasDocument.fileExtension)")
                .foregroundStyle(.secondary)
        }
    }

    private func confirmCreateOrMigrate() {
        let sanitized = trimmedName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !sanitized.isEmpty else { return }

        let desiredName = "\(sanitized).\(CanvasDocument.fileExtension)"
        let finalName = ImageFileSupport.availableFilename(for: desiredName, in: resolution.folderURL)
        let destinationURL = resolution.folderURL.appendingPathComponent(finalName)

        if let legacyJSONURL = resolution.legacyJSONURL {
            try? CanvasDocument.migrateLegacySidecar(from: legacyJSONURL, to: destinationURL)
        }
        onResolved(destinationURL)
    }
}
