import Cocoa
import SwiftUI

final class HostingViewController<V: View>: NSViewController {
    private let rootView: V

    init(rootView: V) {
        self.rootView = rootView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 540))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let hosting = NSHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // NSPopover defaults to a vibrant material; force an opaque window chrome.
        if let window = view.window {
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.appearance = NSApp.effectiveAppearance
        }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}
