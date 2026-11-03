import SwiftUI
import WatchConnectivity

@MainActor private final class WristDesk: NSObject, ObservableObject, WCSessionDelegate {
    @Published var desk: DeskSnapshot?
    private let cache = URL.applicationSupportDirectory.appending(path: "desk.json")
    override init() {
        super.init()
        if let data = try? Data(contentsOf: cache) { desk = try? JSONDecoder().decode(DeskSnapshot.self, from: data) }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    private func accept(_ data: Data?) {
        guard let data, let value = try? JSONDecoder().decode(DeskSnapshot.self, from: data) else { return }
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        try? data.write(to: cache, options: .atomic)
        desk = value
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext["desk"] as? Data
        Task { @MainActor in self.accept(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String:Any]) {
        let data = context["desk"] as? Data
        Task { @MainActor in self.accept(data) }
    }
}

@main struct PiproomWatchApp: App {
    var body: some Scene { WindowGroup { WristView().environment(\.locale, Locale(identifier: "en_US")) } }
}
private struct WristView: View {
    @StateObject private var source = WristDesk()
    @State private var selected: String?
    @State private var rolls = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let desk = source.desk
        let month = desk?.candidates.first { $0.id == selected } ?? desk?.focus
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("PIPROOM").font(.caption2.monospaced().bold()).tracking(1.4)
                    Spacer()
                    Die().frame(width: 26, height: 26).rotationEffect(.degrees(Double(rolls) * 360))
                }
                if let month {
                    Text(month.title).font(.system(.title3, design: .serif).weight(.medium))
                    ContactMeter(reviewed: month.reviewed, total: month.total, tint: .paper)
                    Text("\(month.reviewed) of \(month.total) reviewed").font(.caption2.monospacedDigit())
                    Text("In bin: \(desk?.binCount ?? 0)").font(.caption2).foregroundStyle(Color.faded)
                    if let candidates = desk?.candidates, !candidates.isEmpty {
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.32)) {
                                selected = candidates.randomElement()?.id
                                rolls += 1
                            }
                        } label: { Label("Roll a month", systemImage: "die.face.5") }
                        .font(.caption).tint(.table)
                    }
                } else {
                    Text("Photo desk").font(.system(.title3, design: .serif))
                    Text(desk == nil ? "Open Piproom on your paired iPhone to sync." : "Choose a month on your iPhone.").font(.caption2)
                }
            }.padding(.horizontal, 4)
        }.foregroundStyle(Color.paper).background(Color.felt.ignoresSafeArea())
        .userActivity(DeskSnapshot.activity, isActive: month != nil) { activity in
            activity.title = "Review \(month?.title ?? "photos")"
            activity.userInfo = ["url": month?.link.absoluteString ?? DeskSnapshot.home.absoluteString]
            activity.isEligibleForHandoff = true
        }
    }
}
