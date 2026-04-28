import SwiftUI
#if os(macOS)
import AppKit

struct WindowTitlebarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: view.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }

        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(
            calibratedRed: 253.0 / 255.0,
            green: 251.0 / 255.0,
            blue: 248.0 / 255.0,
            alpha: 1
        )

        window.toolbar = nil
    }
}
#endif
