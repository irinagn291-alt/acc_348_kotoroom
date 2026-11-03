import SwiftUI
import UserNotifications

struct ReviewReminder: Equatable {
    let month: MonthProgress
    let lastSwipe: Date
    func delivery(calendar: Calendar = .current) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: 3, to: lastSwipe) else { return nil }
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day)
    }
}

@MainActor final class QuietReminders: ObservableObject {
    static let shared = QuietReminders()
    private static let id = "piproom.unfinished-month"
    private let center = UNUserNotificationCenter.current()
    private let preference = "quietReviewReminders"
    @Published private(set) var enabled: Bool
    @Published private(set) var denied = false
    @Published private(set) var changing = false
    @Published private(set) var scheduled: Date?
    @Published private(set) var error: String?
    private var review: ReviewReminder?
    private var hasLibraryState = false
    private var pendingRefresh = false
    private var reconciling = false
    private init() { enabled = UserDefaults.standard.bool(forKey: preference) }

    func setEnabled(_ wanted: Bool) async {
        guard !changing else { return }
        changing = true
        defer { changing = false }
        error = nil
        if wanted {
            do {
                guard try await center.requestAuthorization(options: [.alert]) else {
                    denied = true; return
                }
            } catch { self.error = "Notifications are unavailable. Try again later."; return }
        }
        enabled = wanted
        UserDefaults.standard.set(wanted, forKey: preference)
        refresh()
    }

    func update(_ value: ReviewReminder?) {
        guard !hasLibraryState || review != value else { return }
        review = value
        hasLibraryState = true
        refresh()
    }

    // Serialize reconciliation so a late scheduling callback cannot re-arm a disabled reminder.
    func refresh() {
        pendingRefresh = true
        guard !reconciling else { return }
        reconciling = true
        Task {
            while pendingRefresh {
                pendingRefresh = false
                let settings = await center.notificationSettings()
                denied = settings.authorizationStatus == .denied
                guard hasLibraryState || !enabled else { continue }
                let allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
                guard enabled, allowed, let review, let date = review.delivery(), date > Date() else {
                    center.removePendingNotificationRequests(withIdentifiers: [Self.id])
                    if !enabled || self.review == nil || !allowed {
                        center.removeDeliveredNotifications(withIdentifiers: [Self.id])
                    }
                    scheduled = nil
                    continue
                }
                let content = UNMutableNotificationContent()
                content.title = "Your contact sheet is waiting"
                content.body = "Pick up your \(review.month.title) review when you have a moment."
                content.interruptionLevel = .passive
                content.userInfo = ["url": review.month.link.absoluteString]
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                do {
                    try await center.add(UNNotificationRequest(identifier: Self.id, content: content, trigger: trigger))
                    scheduled = date
                    error = nil
                } catch {
                    scheduled = nil
                    self.error = "The reminder could not be scheduled. Try again in Settings."
                }
            }
            reconciling = false
        }
    }
}

struct ReminderSettings: View {
    @ObservedObject private var reminders = QuietReminders.shared
    @Environment(\.openURL) private var openURL
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SmallPrint("Photo atelier / Preferences").foregroundStyle(Color.faded)
                Text("Quiet reminders").font(.system(.largeTitle, design: .serif).weight(.medium))
                PaperCard {
                    Toggle("Remind me to continue", isOn: Binding(get: { reminders.enabled }, set: { wanted in
                        Task { await reminders.setEnabled(wanted) }
                    })).tint(.felt).font(.headline).disabled(reminders.changing).accessibilityIdentifier("reminderToggle")
                    Divider()
                    Text("One silent reminder at 6 PM, three days after your last swipe. Finishing the month cancels it.")
                        .font(.subheadline)
                }
                if reminders.denied {
                    Text("Notification access is off in iPhone Settings.")
                    Button("Open notification settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }.buttonStyle(.bordered)
                } else if let date = reminders.scheduled {
                    Label(date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: .init(identifier: "en_US"))), systemImage: "bell.badge")
                        .accessibilityIdentifier("scheduledReminder")
                } else if reminders.enabled {
                    Text("A reminder will be set when you leave a month unfinished.").font(.subheadline)
                }
                if let error = reminders.error { Text(error).font(.footnote) }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Felt()).navigationBarTitleDisplayMode(.inline)
            .onAppear { reminders.refresh() }
    }
}

@MainActor final class DeskRoute: ObservableObject {
    static let shared = DeskRoute()
    struct Request { let id = UUID(); let url: URL }
    @Published var request: Request?
    func open(_ url: URL) { if url.scheme == "piproom" { request = Request(url: url) } }
}

final class ReminderDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let value = response.notification.request.content.userInfo["url"] as? String
        Task { @MainActor in
            if let value, let url = URL(string: value) { DeskRoute.shared.open(url) }
            completionHandler()
        }
    }
}
