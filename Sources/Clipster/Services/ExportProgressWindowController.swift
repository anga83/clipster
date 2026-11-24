import AppKit

@MainActor
final class ExportProgressWindowController {
    private let window: NSWindow
    private let statusLabel = NSTextField(labelWithString: "Preparing backup ...")
    private let progressIndicator = NSProgressIndicator()

    init(title: String = "Clipster Backup Export") {
        let contentRect = NSRect(x: 0, y: 0, width: 380, height: 120)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        window.title = title
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.isEnabled = false

        let containerView = NSView(frame: contentRect)

        statusLabel.frame = NSRect(x: 20, y: 70, width: 340, height: 22)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        progressIndicator.frame = NSRect(x: 20, y: 40, width: 340, height: 18)
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.isIndeterminate = false
        progressIndicator.doubleValue = 0
        progressIndicator.controlSize = .regular

        containerView.addSubview(statusLabel)
        containerView.addSubview(progressIndicator)
        window.contentView = containerView
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func update(status: String, progress: Double) {
        progressIndicator.isIndeterminate = false
        progressIndicator.stopAnimation(nil)
        statusLabel.stringValue = status
        progressIndicator.doubleValue = max(0, min(100, progress * 100))
    }

    func showIndeterminate(status: String) {
        statusLabel.stringValue = status
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(nil)
    }

    func close() {
        window.orderOut(nil)
    }
}
