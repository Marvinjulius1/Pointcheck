import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

private let green = Color(red: 0.19, green: 0.84, blue: 0.35)
private let red = Color(red: 1.0, green: 0.27, blue: 0.23)
private let ball = Color(red: 0.86, green: 1.0, blue: 0.31)

/// Minimal line chart without dependencies.
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let low = values.min() ?? 0, high = values.max() ?? 1
            let span = max(high - low, 1)
            let points = values.enumerated().map { index, value in
                CGPoint(x: proxy.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)),
                        y: proxy.size.height * (1 - CGFloat((value - low) / span)))
            }
            if points.count > 1 {
                Path { path in
                    path.move(to: points[0])
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                Path { path in
                    path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                    for point in points { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: points[points.count - 1].x, y: proxy.size.height))
                }
                .fill(LinearGradient(colors: [color.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
            }
        }
    }
}

struct RatingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "tennisball.fill").foregroundStyle(ball)
                Text("Öffne Pointcheck").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        let up = snapshot.change30d >= 0
        let color = up ? green : red
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Spielstärke").font(.caption2).widgetAccentable()
                    Text(Int(snapshot.rating.rounded()).formatted()).font(.system(.title3, design: .rounded).weight(.bold))
                    Text((up ? "+" : "−") + "\(Int(abs(snapshot.change30d).rounded())) · 30 T").font(.caption2)
                }
                Sparkline(values: snapshot.points.map(\.rating), color: .primary).frame(width: 60, height: 28)
            }
        case .systemMedium:
            HStack(spacing: 16) {
                small(snapshot, color: color)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("NÄCHSTES MATCH").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1).foregroundStyle(.secondary)
                    if let title = snapshot.nextGameTitle, let date = snapshot.nextGameDate {
                        Text(title).font(.headline).lineLimit(2)
                        Text(date, style: .relative).font(.caption).foregroundStyle(.secondary)
                        Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("Nichts geplant").font(.subheadline).foregroundStyle(.secondary)
                        Text("Stell ein Gesuch ein oder schlag eine Revanche vor.").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            small(snapshot, color: color)
        }
    }

    private func small(_ snapshot: WidgetSnapshot, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Spielstärke").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "tennisball.fill").font(.caption).foregroundStyle(ball)
            }
            Text(Int(snapshot.rating.rounded()).formatted())
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            HStack(spacing: 4) {
                Image(systemName: snapshot.change30d >= 0 ? "arrow.up.right" : "arrow.down.right").font(.caption2.weight(.bold))
                Text((snapshot.change30d >= 0 ? "+" : "−") + "\(Int(abs(snapshot.change30d).rounded()))").font(.caption.weight(.semibold).monospacedDigit())
                Text("30 Tage").font(.caption).foregroundStyle(.secondary)
            }
            .foregroundStyle(color)
            Sparkline(values: snapshot.points.map(\.rating), color: color)
                .frame(height: 34)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct RatingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PointcheckRating", provider: SnapshotProvider()) { entry in
            RatingWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Spielstärke")
        .description("Deine Spielstärke mit Verlauf – und dein nächstes geplantes Match.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

@main
struct PointcheckPhoneWidgetBundle: WidgetBundle {
    var body: some Widget {
        RatingWidget()
    }
}
