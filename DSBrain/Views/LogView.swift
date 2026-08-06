import SwiftUI
import AppKit

struct LogView: View {
    let lines: [String]
    @State private var isExpanded = false

    private var logText: String {
        lines.joined(separator: "\n")
    }

    var body: some View {
        AccordionSection(
            title: "Server Log",
            badge: lines.isEmpty ? nil : "\(lines.count)",
            isExpanded: $isExpanded
        ) {
            SelectableLogTextView(text: logText, isVisible: isExpanded)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(height: 120)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Read-only text view with sticky auto-scroll (on by default; pauses when user scrolls up).
private struct SelectableLogTextView: NSViewRepresentable {
    let text: String
    let isVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = LogTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.attach(to: scrollView, textView: textView)
        context.coordinator.scheduleScrollToEndIfNeeded()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let becameVisible = isVisible && !context.coordinator.wasVisible
        context.coordinator.wasVisible = isVisible
        context.coordinator.syncText(text)

        // First expand (or re-expand): jump to latest while auto-scroll is the default.
        if becameVisible {
            context.coordinator.autoScrollEnabled = true
            context.coordinator.scheduleScrollToEndIfNeeded()
        }
    }

    final class Coordinator {
        private weak var scrollView: NSScrollView?
        private weak var textView: LogTextView?
        /// Default on: follow new lines until the user scrolls away from the bottom.
        var autoScrollEnabled = true
        var wasVisible = false
        private var observing = false
        private let bottomSlop: CGFloat = 28

        func attach(to scrollView: NSScrollView, textView: LogTextView) {
            self.scrollView = scrollView
            self.textView = textView

            guard !observing else { return }
            observing = true
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func syncText(_ text: String) {
            guard let textView else { return }
            guard textView.string != text else { return }

            let selected = textView.selectedRange()
            textView.string = text

            if selected.length > 0, NSMaxRange(selected) <= text.utf16.count {
                textView.setSelectedRange(selected)
            }

            if autoScrollEnabled {
                scheduleScrollToEndIfNeeded()
            }
        }

        func scheduleScrollToEndIfNeeded() {
            guard autoScrollEnabled else { return }
            // Layout may not be ready on first paint / accordion expand.
            DispatchQueue.main.async { [weak self] in
                self?.scrollToEnd()
                DispatchQueue.main.async { [weak self] in
                    self?.scrollToEnd()
                }
            }
        }

        private func scrollToEnd() {
            guard autoScrollEnabled, let textView else { return }
            textView.scrollToEndOfDocument(nil)
        }

        @objc private func boundsDidChange(_ notification: Notification) {
            guard let scrollView, let textView else { return }
            let nearBottom = isNearBottom(scrollView: scrollView, textView: textView)
            autoScrollEnabled = nearBottom
        }

        private func isNearBottom(scrollView: NSScrollView, textView: NSTextView) -> Bool {
            let visible = scrollView.contentView.bounds
            let docHeight = textView.bounds.height
            guard docHeight > visible.height else { return true }
            let distanceFromBottom = docHeight - visible.maxY
            return distanceFromBottom <= bottomSlop
        }
    }
}

private final class LogTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandA = flags == .command && event.charactersIgnoringModifiers == "a"
        let isControlA = flags == .control && event.charactersIgnoringModifiers == "a"
        if isCommandA || isControlA {
            selectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
