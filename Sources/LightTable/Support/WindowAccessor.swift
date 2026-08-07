import SwiftUI
import AppKit

/// Grabs a reliable reference to this view's own hosting NSWindow, used to
/// scope app-wide NSEvent monitors (scroll/delete) to only this window —
/// otherwise, with multiple windows open, whichever window's monitor was
/// installed first swallows every event regardless of which window is key.
///
/// AppKit reports `nsView.window` as nil transiently during some SwiftUI
/// relayouts even after the view is properly attached, so this only ever
/// adopts a non-nil window — a later spurious nil reading must never
/// clobber an already-known-good reference.
struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let realWindow = view.window {
                self.window = realWindow
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let realWindow = nsView.window, self.window !== realWindow {
                self.window = realWindow
            }
        }
    }
}
