import SwiftUI
import WidgetKit

/// Watch face complication: one tap opens the scoreboard, ready to count.
struct LauncherEntry: TimelineEntry {
    let date: Date
}

struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry { LauncherEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
        completion(LauncherEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        // Static launcher – nothing to refresh.
        completion(Timeline(entries: [LauncherEntry(date: .now)], policy: .never))
    }
}

struct LauncherComplicationView: View {
    @Environment(\.widgetFamily) private var family
    private let ballColor = Color(red: 0.86, green: 1.0, blue: 0.31)

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "tennisball.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ballColor)
                    .widgetAccentable()
            }
        case .accessoryCorner:
            Image(systemName: "tennisball.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ballColor)
                .widgetAccentable()
                .widgetLabel("Padel")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "tennisball.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(ballColor)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Pointcheck")
                        .font(.headline)
                    Text("Match zählen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        default:
            // accessoryInline
            Label("Padel zählen", systemImage: "tennisball.fill")
        }
    }
}

@main
struct PointcheckWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PointcheckLauncher", provider: LauncherProvider()) { _ in
            LauncherComplicationView()
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Pointcheck")
        .description("Öffnet direkt den Padel-Zähler.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}
