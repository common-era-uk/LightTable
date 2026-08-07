import SwiftUI
import AppKit

struct RootView: View {
    @Binding var folderURL: URL?
    @State private var document: CanvasDocument?
    @State private var hostWindow: NSWindow?
    @State private var openFolderError: String?
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
        .onAppear {
            if folderURL == nil, AppDelegate.suppressNextBlankWindow {
                // A folder window was already opened for this same drop;
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
            AppDelegate.openFolderAction = { url in openWindow(value: url) }
            if folderURL == nil {
                AppDelegate.dismissBlankWindow = { dismissWindow() }
            }
        }
        .onChange(of: folderURL) { _, _ in syncDocument() }
    }

    private func syncDocument() {
        guard let folderURL else {
            document = nil
            // Register as blank so that if a folder opens somewhere else
            // (toolbar button, Open Recent, Dock drop) while this window is
            // just sitting on the "open a folder" prompt, it gets closed
            // instead of lingering as a leftover tab/window.
            BlankWindowRegistry.shared.register(instanceID) { [dismissWindow] in dismissWindow() }
            return
        }
        if document?.folderURL != folderURL {
            if let error = ImageFileSupport.oversizeError(inFolder: folderURL) {
                document = nil
                openFolderError = error
                // Deferred: this runs from folderURL's own onChange, so
                // resetting it synchronously here would mutate the binding
                // mid-update.
                DispatchQueue.main.async { self.folderURL = nil }
                return
            }
            document = CanvasDocument(folderURL: folderURL)
            document?.undoManager = undoManager
        }
        BlankWindowRegistry.shared.unregister(instanceID)
        BlankWindowRegistry.shared.dismissOthers(except: instanceID)
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
            folderURL = url
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
