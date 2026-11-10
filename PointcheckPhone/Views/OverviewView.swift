import Charts
import PadelStats
import SwiftData
import SwiftUI

struct OverviewView: View {
    @Query(sort: \StoredMatch.startDate, order: .reverse) private var stored: [StoredMatch]
    @Environment(WatchSync.self) private var sync
    @Environment(HealthService.self) private var health

    private var matches: [MatchSummary] { stored.map(\.summary) }

    var body: some View {
        let overview = PadelStats.overview(matches)
        Group {
            if overview.matchesPlayed == 0 {
                NoMatchesView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        RatingCard(report: PadelStats.localRatings(matches))
                        tiles(overview)
                        healthSection
                        weeklyChart
                        peopleSection(title: "Beste Partner", records: PadelStats.partners(matches), mode: .partners)
                        peopleSection(title: "Rivalen", records: PadelStats.rivals(matches), mode: .rivals)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Übersicht")
        .refreshable {
            sync.requestAll()
            await health.refresh(for: matches)
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        if health.isAvailable, !health.hasRequestedAccess {
            VStack(alignment: .leading, spacing: 10) {
                Label("Trainingsdaten", systemImage: "heart.fill")
                    .font(.headline)
                    .foregroundStyle(.pink)
                Text("Zeig Herzfrequenz und Kalorien zu jedem Match – aufgezeichnet von deiner Apple Watch.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Mit Health verbinden") {
                    Task { await health.requestAccess() }
                }
                .buttonStyle(.glassProminent)
                .tint(.pink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
        } else {
            let totals = PadelStats.healthTotals(health.metrics.values)
            if totals.matchesWithData > 0 {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatTile(
                        title: "Kalorien",
                        value: totals.activeEnergy.formatted(.number.precision(.fractionLength(0))),
                        detail: "kcal in \(totals.matchesWithData) Matches",
                        symbol: "flame.fill",
                        tint: .orange
                    )
                    StatTile(
                        title: "Ø Puls",
                        value: totals.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "–",
                        detail: totals.maxHeartRate.map { "max. \(Int($0.rounded())) bpm" },
                        symbol: "heart.fill",
                        tint: .pink
                    )
                }
            }
        }
    }

    private func tiles(_ overview: StatsOverview) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(
                title: "Siegquote",
                value: overview.winRate?.percentText ?? "–",
                detail: "\(overview.wins) Siege · \(overview.losses) Niederlagen",
                symbol: "percent",
                tint: Theme.me
            )
            StatTile(
                title: "Matches",
                value: "\(overview.matchesPlayed)",
                detail: overview.totalPlayTime > 0 ? overview.totalPlayTime.durationText : nil,
                symbol: "figure.tennis"
            )
            StatTile(
                title: "Serie",
                value: streakValue(overview.currentStreak),
                detail: "Rekord: \(overview.longestWinStreak) Siege",
                symbol: overview.currentStreak >= 0 ? "flame.fill" : "cloud.rain.fill",
                tint: overview.currentStreak >= 0 ? .orange : Theme.opponent
            )
            StatTile(
                title: "Tiebreaks",
                value: "\(overview.tiebreaksWon):\(overview.tiebreaksLost)",
                detail: overview.tiebreakWinRate.map { "\($0.percentText) gewonnen" } ?? "Noch keine",
                symbol: "scope"
            )
            StatTile(
                title: "Sätze",
                value: "\(overview.setsWon):\(overview.setsLost)",
                symbol: "square.stack.fill"
            )
        }
    }

    private func streakValue(_ streak: Int) -> String {
        switch streak {
        case 0: "–"
        case 1...: "\(streak) S"
        default: "\(-streak) N"
        }
    }

    private var weeklyChart: some View {
        let weeks = PadelStats.matchesPerWeek(matches, weeks: 8)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Letzte 8 Wochen")
                .font(.headline)
            Chart(weeks) { week in
                BarMark(x: .value("Woche", week.week, unit: .weekOfYear), y: .value("Siege", week.wins))
                    .foregroundStyle(by: .value("Ergebnis", "Siege"))
                BarMark(x: .value("Woche", week.week, unit: .weekOfYear), y: .value("Niederlagen", week.losses))
                    .foregroundStyle(by: .value("Ergebnis", "Niederlagen"))
            }
            .chartForegroundStyleScale(["Siege": Theme.me, "Niederlagen": Theme.opponent])
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) {
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 180)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    @ViewBuilder
    private func peopleSection(title: String, records: [PersonRecord], mode: PeopleView.Mode) -> some View {
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    NavigationLink("Alle") { PeopleView(initialMode: mode) }
                        .font(.subheadline)
                }
                ForEach(records.prefix(3)) { record in
                    PersonRecordRow(record: record)
                }
            }
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
    }
}
