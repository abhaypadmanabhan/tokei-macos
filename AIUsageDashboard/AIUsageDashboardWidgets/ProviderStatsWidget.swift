import WidgetKit
import SwiftUI
import AIUsageDashboardCore

struct ProviderStatsWidget: Widget {
    let kind: String = "AIUsageDashboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProviderTimelineProvider()) { entry in
            ProviderStatsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AI Usage")
        .description("Shows today's AI usage across providers.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ProviderTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProviderEntry {
        ProviderEntry(date: Date(), providerName: "Claude", tokenCount: 0, confidence: .localParsed)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProviderEntry) -> Void) {
        completion(ProviderEntry(date: Date(), providerName: "Claude", tokenCount: 0, confidence: .localParsed))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProviderEntry>) -> Void) {
        let entry = ProviderEntry(date: Date(), providerName: "Claude", tokenCount: 0, confidence: .localParsed)
        completion(Timeline(entries: [entry], policy: .atEnd))
    }
}

struct ProviderEntry: TimelineEntry {
    let date: Date
    let providerName: String
    let tokenCount: Int
    let confidence: MetricConfidence
}

struct ProviderStatsWidgetEntryView: View {
    var entry: ProviderEntry

    var body: some View {
        VStack(alignment: .leading) {
            Text(entry.providerName)
                .font(.headline)
            Text("\(entry.tokenCount) tokens")
                .font(.title)
            Text(entry.confidence.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
