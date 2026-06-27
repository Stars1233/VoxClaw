import SwiftUI
import WidgetKit

// Minimal placeholder widget — proves the extension target builds and embeds.
// Control Center control, interactive widget, and Live Activity are added next.

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry { PlaceholderEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .never))
    }
}

struct VoxClawWidgetEntryView: View {
    var entry: PlaceholderEntry
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "waveform")
            Text("VoxClaw")
                .font(.caption)
        }
    }
}

struct VoxClawWidget: Widget {
    let kind = "VoxClawWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlaceholderProvider()) { entry in
            VoxClawWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("VoxClaw")
        .description("VoxClaw.")
    }
}

@main
struct VoxClawWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoxClawWidget()
    }
}
