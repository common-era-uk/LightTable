import SwiftUI
import AppKit

/// Handles a sidebar template click for this window: picks the page,
/// checks the image count, offers to convert the pages to 1920 × 1080 if
/// needed, asks for the photographer's name if the template has one, then
/// applies it. A modifier so `CanvasView.body` doesn't grow any further.
struct LayoutTemplateCommands: ViewModifier {
    @ObservedObject var document: CanvasDocument
    let hostWindow: NSWindow?
    /// The page nearest the middle of the visible canvas — used when
    /// nothing is selected.
    let pageInView: () -> Int

    private struct Pending {
        let template: LayoutTemplate
        let boardIndex: Int
    }

    @State private var pending: Pending?
    @State private var showResizeConfirm = false
    @State private var showNamePrompt = false
    @State private var errorMessage: String?
    @AppStorage("lastPhotographerName") private var lastPhotographerName = ""

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .applyLayoutTemplate)) { note in
                guard hostWindow != nil, hostWindow === NSApp.keyWindow,
                      let id = note.object as? String,
                      let template = LayoutTemplate.named(id) else { return }
                begin(template)
            }
            .alert("Change Page Size?", isPresented: $showResizeConfirm, presenting: pending) { _ in
                Button("Change Pages and Apply") { askNameOrApply() }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: { _ in
                Text("Layout templates are designed for 1920 × 1080 pages. Every page in this canvas will be set to a fixed 1920 × 1080 px. Images on other pages aren't moved. You can undo this.")
            }
            .alert("Can't Apply Layout", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ), presenting: errorMessage) { _ in
                Button("OK") { errorMessage = nil }
            } message: { message in
                Text(message)
            }
            .sheet(isPresented: $showNamePrompt) {
                PhotographerNamePrompt(initialName: initialName) { name in
                    showNamePrompt = false
                    lastPhotographerName = name
                    apply(photographerName: name)
                } onCancel: {
                    showNamePrompt = false
                    pending = nil
                }
            }
    }

    private var initialName: String {
        guard let pending else { return lastPhotographerName }
        return document.templatePhotographerName(onBoard: pending.boardIndex) ?? lastPhotographerName
    }

    private func begin(_ template: LayoutTemplate) {
        let selectedBoards = Set(document.items.filter { document.selectedIDs.contains($0.id) }.map(\.boardIndex))
        let boardIndex: Int
        if selectedBoards.count > 1 {
            errorMessage = "The selection is spread across more than one page. Select images on just one page, then try again."
            return
        } else if let only = selectedBoards.first {
            boardIndex = only
        } else {
            boardIndex = pageInView()
        }

        do {
            try document.checkLayoutTemplate(template, boardIndex: boardIndex)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        pending = Pending(template: template, boardIndex: boardIndex)
        if document.hasLayoutTemplatePageSize {
            askNameOrApply()
        } else {
            showResizeConfirm = true
        }
    }

    private func askNameOrApply() {
        guard let pending else { return }
        if pending.template.requiresPhotographerName {
            // Deferred: this can run from the resize alert's button, and a
            // sheet requested while that alert is still dismissing never
            // appears.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { showNamePrompt = true }
        } else {
            apply(photographerName: nil)
        }
    }

    private func apply(photographerName: String?) {
        guard let pending else { return }
        self.pending = nil
        do {
            try document.applyLayoutTemplate(pending.template, toBoard: pending.boardIndex, photographerName: photographerName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PhotographerNamePrompt: View {
    let onApply: (String) -> Void
    let onCancel: () -> Void
    @State private var name: String
    @FocusState private var isFocused: Bool

    init(initialName: String, onApply: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onApply = onApply
        self.onCancel = onCancel
        _name = State(initialValue: initialName)
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Photographer's Name")
                .font(.title3.bold())
            Text("Shown under the image on the title page, in capitals.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { if !trimmed.isEmpty { onApply(trimmed) } }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { onApply(trimmed) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { isFocused = true }
    }
}
