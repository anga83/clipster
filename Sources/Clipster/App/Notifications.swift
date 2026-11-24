import Foundation

extension Notification.Name {
    static let openMainWindow = Notification.Name("com.clipster.openMainWindow")
    static let clipsterDidWritePasteboard = Notification.Name("com.clipster.didWritePasteboard")
    static let clipsterPauseClipboardMonitoring = Notification.Name("com.clipster.pauseClipboardMonitoring")
    static let clipsterResumeClipboardMonitoring = Notification.Name("com.clipster.resumeClipboardMonitoring")
}
