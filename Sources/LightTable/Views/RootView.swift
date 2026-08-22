import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RootView: View {
    /// Either a folder (resolved below to a specific `.lt` file) or a `.lt`
    /// file itself, already unambiguous — a Finder double-click or an
    /// "Open Recent" selection hands over a `.lt` URL directly, while
    /// "Open Folder…" and Dock/Finder folder drops hand over a directory.
    @Binding var requestedURL: URL?
    @State private var document: CanvasDocument?
    @State private var pendingResolution: PendingResolution?
    @State private var showSaveAsSheet = false
    @State private var hostWindow: NSWindow?
    @State private var openFolderError: String?
    @State private var packageError: String?
    @State private var instanceID = UUID()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            if let document {
                CanvasView(document: document, hostWindow: $hostWindow, onChangeFolder: openFolderInNewWindow)
            } else {
                openFolderPrompt
            }
        }
        .background(WindowAccessor(window: $hostWindow))
        .alert("Can't Open Folder", isPresented: Binding(
            get: { openFolderError != nil },
            set: { isPresented in if !isPresented { openFolderError = nil } }
        ), presenting: openFolderError) { _ in
            Button("OK") { openFolderError = nil }
        } message: { message in
            Text(message)
        }
        .alert("Can't Create Package", isPresented: Binding(
            get: { packageError != nil },
            set: { isPresented in if !isPresented { packageError = nil } }
        ), presenting: packageError) { _ in
            Button("OK") { packageError = nil }
        } message: { message in
            Text(message)
        }
        .sheet(item: $pendingResolution) { resolution in
            DocumentResolutionSheet(resolution: resolution) { ltFileURL in
                openDocument(at: ltFileURL)
            } onCancel: {
                pendingResolution = nil
                requestedURL = nil
            }
        }
        .sheet(isPresented: $showSaveAsSheet) {
            if let document {
                SaveAsSheet(currentName: document.ltFileURL.deletingPathExtension().lastPathComponent) { name in
                    showSaveAsSheet = false
                    performSaveAs(name: name)
                } onCancel: {
                    showSaveAsSheet = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveDocumentAs)) { _ in
            guard hostWindow != nil, hostWindow === NSApp.keyWindow, document != nil else { return }
            showSaveAsSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .packageDocument)) { _ in
            guard hostWindow != nil, hostWindow === NSApp.keyWindow, let document else { return }
            presentPackagePanel(for: document)
        }
        .onAppear {
            if requestedURL == nil, AppDelegate.suppressNextBlankWindow {
                // A document window was already opened for this same drop;
                // this blank window is just a same-launch side effect of
                // that, not something the user asked for — close it.
                dismissWindow()
                return
            }
            syncDocument()
            // Environment values like undoManager can be nil on the very
            // first appearance before the window is fully attached — re-sync
            // here rather than trusting whatever syncDocument saw earlier.
            document?.undoManager = undoManager
            // Any window's environment action works here — it's routed by
            // SwiftUI to the right WindowGroup regardless of which window
            // set it, so the AppDelegate always has a live one to call.
            AppDelegate.openDocumentAction = { url in openWindow(value: url) }
            if requestedURL == nil {
                AppDelegate.dismissBlankWindow = { dismissWindow() }
            }
        }
        .onChange(of: requestedURL) { _, _ in syncDocument() }
    }

    private func syncDocument() {
        guard let requestedURL else {
            document = nil
            pendingResolution = nil
            // Register as blank so that if a document opens somewhere else
            // (toolbar button, Open Recent, Dock drop) while this window is
            // just sitting on the "open a folder" prompt, it gets closed
            // instead of lingering as a leftover tab/window.
            BlankWindowRegistry.shared.register(instanceID) { [dismissWindow] in dismissWindow() }
            return
        }
        if requestedURL.hasDirectoryPath {
            resolveFolder(requestedURL)
        } else {
            openDocument(at: requestedURL)
        }
    }

    /// A folder isn't itself a document — it may hold zero, one, or several
    /// `.lt` canvases. One match opens directly; anything else (including a
    /// legacy hidden sidecar needing migration) is handled by a sheet.
    private func resolveFolder(_ folderURL: URL) {
        guard document?.folderURL != folderURL else { return }

        let ltFiles = ((try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { $0.pathExtension.lowercased() == CanvasDocument.fileExtension }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        if ltFiles.count == 1 {
            openDocument(at: ltFiles[0])
            return
        }

        BlankWindowRegistry.shared.register(instanceID) { [dismissWindow] in dismissWindow() }

        let legacyURL = folderURL.appendingPathComponent(CanvasDocument.legacySidecarName)
        let hasLegacy = FileManager.default.fileExists(atPath: legacyURL.path)
        pendingResolution = PendingResolution(
            folderURL: folderURL,
            existingLTFiles: ltFiles,
            legacyJSONURL: hasLegacy ? legacyURL : nil
        )
    }

    private func openDocument(at ltFileURL: URL) {
        pendingResolution = nil
        guard document?.ltFileURL != ltFileURL else {
            BlankWindowRegistry.shared.unregister(instanceID)
            BlankWindowRegistry.shared.dismissOthers(except: instanceID)
            return
        }
        if let error = ImageFileSupport.oversizeError(inFolder: ltFileURL.deletingLastPathComponent()) {
            document = nil
            openFolderError = error
            // Deferred: this can run from requestedURL's own onChange, so
            // resetting it synchronously here would mutate the binding
            // mid-update.
            DispatchQueue.main.async { self.requestedURL = nil }
            return
        }

        // Undo steps registered against whatever document was previously
        // open (if any) no longer target anything meaningful once it's
        // swapped out — e.g. after Save As switches this window to the new
        // copy — so they'd otherwise sit inert in the Edit menu.
        undoManager?.removeAllActions()

        document = CanvasDocument(ltFileURL: ltFileURL)
        document?.undoManager = undoManager
        if requestedURL != ltFileURL {
            requestedURL = ltFileURL
        }
        BlankWindowRegistry.shared.unregister(instanceID)
        BlankWindowRegistry.shared.dismissOthers(except: instanceID)
    }

    /// Writes a copy of the current document's `.lt` file under a new name
    /// in the same folder, then switches this window over to editing that
    /// copy — the images themselves are shared, not duplicated.
    private func performSaveAs(name: String) {
        guard let document else { return }
        let sanitized = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !sanitized.isEmpty else { return }

        let desiredName = "\(sanitized).\(CanvasDocument.fileExtension)"
        let finalName = ImageFileSupport.availableFilename(for: desiredName, in: document.folderURL)
        let destinationURL = document.folderURL.appendingPathComponent(finalName)

        guard (try? FileManager.default.copyItem(at: document.ltFileURL, to: destinationURL)) != nil else { return }
        openDocument(at: destinationURL)
    }

    /// Lets the user pick any destination (unlike Save As or Rename, this
    /// one's meant to leave the synced folder entirely) and bundles the
    /// document into a standalone, shareable zip there.
    private func presentPackagePanel(for document: CanvasDocument) {
        let panel = NSSavePanel()
        panel.directoryURL = document.folderURL
        panel.nameFieldStringValue = "\(document.ltFileURL.deletingPathExtension().lastPathComponent).zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.prompt = "Package"
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            try document.packageForSharing(to: destinationURL)
        } catch {
            packageError = error.localizedDescription
        }
    }

    private var openFolderPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Open a folder to start a light table")
                .font(.title3)
            Button("Open Folder…") {
                chooseFolder()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func chooseFolder() {
        if let url = pickFolder() {
            requestedURL = url
        }
    }

    /// Used by the canvas toolbar's "Open Folder…" button — opens the chosen
    /// folder in a new window rather than replacing this one, since swapping
    /// out an already-open canvas in place was confusing (looked like the
    /// current session had vanished).
    private func openFolderInNewWindow() {
        if let url = pickFolder() {
            openWindow(value: url)
        }
    }
}
