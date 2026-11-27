import Foundation
import Combine

@MainActor
final class TimelineNavigationCoordinator: ObservableObject {
    struct Request: Equatable {
        let id: UUID
        let itemID: UUID
    }

    @Published private(set) var request: Request?

    func show(itemID: UUID) {
        request = Request(id: UUID(), itemID: itemID)
    }

    func consume(_ request: Request) {
        guard self.request?.id == request.id else { return }
        self.request = nil
    }
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("com.clipster.openMainWindow")
    static let clipsterDidWritePasteboard = Notification.Name("com.clipster.didWritePasteboard")
    static let clipsterPauseClipboardMonitoring = Notification.Name("com.clipster.pauseClipboardMonitoring")
    static let clipsterResumeClipboardMonitoring = Notification.Name("com.clipster.resumeClipboardMonitoring")
}
