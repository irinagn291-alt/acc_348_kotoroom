import WidgetKit
import SwiftUI

private struct Entry: TimelineEntry {
    let date: Date
    let month: MonthProgress?
    static let sample = Entry(date: .now, month: MonthProgress(year: 2026, month: 10, title: "October 2026", reviewed: 18, total: 32))
}
private struct DeskProvider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { .sample }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? .sample : current)
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [current], policy: .never))
    }
    private var current: Entry { Entry(date: .now, month: DeskSnapshot.readShared()?.focus) }
}
@main struct PiproomWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DeskSnapshot.widgetKind, provider: DeskProvider()) { entry in
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("PIPROOM").font(.caption2.monospaced().bold()).tracking(1.5)
                    Spacer()
                    Die().frame(width: 25, height: 25)
                }
                Spacer(minLength: 2)
                Text(entry.month?.title ?? "Photo desk")
                    .font(.system(.title3, design: .serif).weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
                if let month = entry.month {
                    Text("\(month.reviewed) of \(month.total) reviewed").font(.caption2.monospacedDigit())
                    ContactMeter(reviewed: month.reviewed, total: month.total, tint: .enamel)
                } else { Text("Open to choose a month").font(.caption) }
            }.foregroundStyle(Color.ink).containerBackground(Color.paper, for: .widget)
                .environment(\.locale, Locale(identifier: "en_US")).widgetURL(entry.month?.link ?? DeskSnapshot.home)
        }.configurationDisplayName("Monthly contact sheet")
            .description("See your progress and return to a month with one tap.")
            .supportedFamilies([.systemSmall])
    }
}
