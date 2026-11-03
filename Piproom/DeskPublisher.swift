import Foundation
import WatchConnectivity
import WidgetKit

@MainActor final class DeskPublisher: NSObject, WCSessionDelegate {
    private var current: DeskSnapshot?
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    func publish(_ value: DeskSnapshot) {
        guard value != current, let data = try? JSONEncoder().encode(value) else { return }
        if let url = DeskSnapshot.sharedFile {
            do {
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                if current == nil || current?.focus != value.focus { WidgetCenter.shared.reloadTimelines(ofKind: DeskSnapshot.widgetKind) }
            } catch { return }
        }
        current = value
        send()
    }
    private func send() {
        guard WCSession.isSupported(), let current, let data = try? JSONEncoder().encode(current) else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(["desk": data])
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.send() }
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.send() } }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.send() } }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
