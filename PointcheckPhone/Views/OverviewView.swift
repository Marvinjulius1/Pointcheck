import Charts
import PadelStats
import SwiftData
import SwiftUI

/// Home screen: playing strength like a portfolio value – big number, change, chart –
/// followed by calm grouped lists.
struct OverviewView: View {
    @Query(sort: \StoredMatch.startDate, order: .reverse) private var stored: [StoredMatch]
    @Environment(WatchSync.self) private var sync
    @Environment(HealthService.self) private var health
    @Environment(AccountService.self) private var account

    private var matches: [MatchSummary] { account.allMatches(local: stored.map(\.summary)) }

    var body: some View {
        let all = matches
        let overview = PadelStats.overview(all)
        Group {
            if overview.matchesPlayed == 0 {
                NoMatchesView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        RatingHero(matches: all)
                            .padding(.bottom, 8)
                        statistics(overview)
                        healthSection
                        activitySection(all)
                        peopleSection(title: "Beste Partner", records: PadelStats.partners(all), mode: .partners)
                        peopleSection(title: "Rivalen", records: PadelStats.rivals(all), mode: .rivals)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle("Übersicht")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            sync.requestAll()
            await account.refresh()
            await health.refresh(for: all)
        }
    }

    // MARK: Statistics

    private func statistics(_ overview: StatsOverview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Statistik")
            Card {
                MetricRow(
                    symbol: "percent", tint: Theme.me, title: "Siegquote",
                    subtitle: "\(overview.wins) Siege · \(overview.losses) Niederlagen",
                    value: overview.winRate?.percentText ?? "–"
                )
                RowDivider()
                MetricRow(
                    symbol: overview.currentStreak >= 0 ? "flame.fill" : "cloud.rain.fill",
                    tint: overview.currentStreak >= 0 ? .orange : .gray,
                    title: "Aktuelle Serie",
                    subtitle: "Rekord: \(overview.longestWinStreak) Siege in Folge",
                    value: streakText(overview.currentStreak),
                    valueTint: overview.currentStreak > 0 ? Theme.me : overview.currentStreak < 0 ? Theme.opponent : .primary
                )
                RowDivider()
                MetricRow(
                    symbol: "figure.tennis", tint: .blue, title: "Matches",
                    subtitle: overview.totalPlayTime > 0 ? "\(overview.totalPlayTime.durationText) gespielt" : nil,
                    value: "\(overview.matchesPlayed)"
                )
                RowDivider()
                MetricRow(
                    symbol: "square.stack.fill", tint: .indigo, title: "Sätze",
                    value: "\(overview.setsWon):\(overview.setsLost)"
                )
                RowDivider()
                MetricRow(
                    symbol: "scope", tint: .purple, title: "Tiebreaks",
                    subtitle: overview.tiebreakWinRate.map { "\($0.percentText) gewonnen" },
                    value: "\(overview.tiebreaksWon):\(overview.tiebreaksLost)"
                )
            }
        }
    }

    private func streakText(_ streak: Int) -> String {
        switch streak {
        case 0: "–"
        case 1: "1 Sieg"
        case 2...: "\(streak) Siege"
        case -1: "1 Niederlage"
        default: "\(-streak) Niederlagen"
        }
    }

    // MARK: Health

    @ViewBuilder
    private var healthSection: some View {
        if health.isAvailable, !health.hasRequestedAccess {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Training")
                Card {
                    HStack(alignment: .top, spacing: 14) {
                        IconTile(symbol: "heart.fill", tint: .pink)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Herzfrequenz und Kalorien zu jedem Match – aufgezeichnet von deiner Apple Watch.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Mit Health verbinden") {
                                Task { await health.requestAccess() }
                            }
                            .buttonStyle(.glassProminent)
                            .tint(.pink)
                        }
                    }
                    .padding(16)
                }
            }
        } else {
            let totals = PadelStats.healthTotals(health.metrics.values)
            if totals.matchesWithData > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Training")
                    Card {
                        MetricRow(
                            symbol: "flame.fill", tint: .orange, title: "Aktive Energie",
                            subtitle: "in \(totals.matchesWithData) Matches",
                            value: "\(Int(totals.activeEnergy.rounded()).formatted()) kcal"
                        )
                        RowDivider()
                        MetricRow(
                            symbol: "heart.fill", tint: .pink, title: "Ø Herzfrequenz",
                            subtitle: totals.maxHeartRate.map { "Maximum \(Int($0.rounded())) bpm" },
                            value: totals.averageHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "–"
                        )
                    }
                }
            }
        }
    }

    // MARK: Activity

    private func activitySection(_ matches: [MatchSummary]) -> some View {
        let weeks = PadelStats.matchesPerWeek(matches, weeks: 8)
        let total = weeks.map(\.total).reduce(0, +)
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Aktivität") {
                Text("\(total) Matches in 8 Wochen").foregroundStyle(.secondary)
            }
            Card {
                Chart(weeks) { week in
                    BarMark(x: .value("Woche", week.week, unit: .weekOfYear), y: .value("Matches", week.wins))
                        .foregroundStyle(by: .value("Ergebnis", "Siege"))
                        .cornerRadius(4)
                    BarMark(x: .value("Woche", week.week, unit: .weekOfYear), y: .value("Matches", week.losses))
                        .foregroundStyle(by: .value("Ergebnis", "Niederlagen"))
                        .cornerRadius(4)
                }
                .chartForegroundStyleScale(["Siege": Theme.me, "Niederlagen": Theme.opponent.opacity(0.75)])
                .chartLegend(position: .bottom, alignment: .leading)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) {
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 170)
                .padding(16)
            }
        }
    }

    // MARK: People

    @ViewBuilder
    private func peopleSection(title: String, records: [PersonRecord], mode: PeopleView.Mode) -> some View {
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title) {
                    NavigationLink("Alle") { PeopleView(initialMode: mode) }
                }
                Card {
                    ForEach(Array(records.prefix(3).enumerated()), id: \.element.id) { index, record in
                        if index > 0 { RowDivider(inset: 66) }
                        PersonRecordRow(record: record)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
    }
}

// MARK: - Hero

/// Big rating number with change and an interactive line chart (drag to see past values).
private struct RatingHero: View {
    let matches: [MatchSummary]
    @Environment(AccountService.self) private var account
    @State private var range: RatingRange = .threeMonths
    @State private var selectedDate: Date?

    enum RatingRange: String, CaseIterable, Identifiable {
        case week = "1W", month = "1M", threeMonths = "3M", year = "1J", max = "Max"
        var id: Self { self }

        var days: Double? {
            switch self {
            case .week: 7
            case .month: 30
            case .threeMonths: 91
            case .year: 365
            case .max: nil
            }
        }

        var description: String {
            switch self {
            case .week: "1 Woche"
            case .month: "1 Monat"
            case .threeMonths: "3 Monate"
            case .year: "1 Jahr"
            case .max: "insgesamt"
            }
        }
    }

    /// Server values once signed in with rated matches, otherwise the local preview.
    private var source: (points: [RatingPoint], current: Double, isServer: Bool) {
        if let profile = account.profile, let first = account.ratingHistory.first {
            let start = RatingPoint(date: first.createdAt.addingTimeInterval(-1), rating: first.ratingBefore)
            let points = [start] + account.ratingHistory.map { RatingPoint(date: $0.createdAt, rating: $0.ratingAfter) }
            return (points, profile.rating, true)
        }
        let report = PadelStats.localRatings(matches)
        return (report.history.map { RatingPoint(date: $0.date, rating: $0.rating) }, report.me.rating, false)
    }

    var body: some View {
        let data = source
        let now = Date.now
        let window = RatingSeries.window(
            data.points,
            current: data.current,
            since: range.days.map { now.addingTimeInterval(-$0 * 86_400) },
            now: now
        )
        let change = RatingSeries.change(window)
        let selected = selectedDate.flatMap { date in
            window.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        let shown = selected?.rating ?? data.current
        let isUp = change.delta >= 0
        let lineColor = isUp ? Theme.me : Theme.opponent

        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                RatingView()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Spielstärke")
                        Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                    Text(Int(shown.rounded()).formatted())
                        .font(.system(size: 46, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(value: shown))
                        .animation(.snappy, value: shown)

                    if let selected {
                        Text(selected.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    } else {
                        ChangeLabel(change: change.delta, base: change.base, suffix: range.description)
                    }

                    Text("Level \(PadelLevel.level(for: shown).formatted(.number.precision(.fractionLength(1)))) · \(PadelLevel.name(for: PadelLevel.level(for: shown)))\(data.isServer ? "" : " · Vorschau")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Chart {
                ForEach(window) { point in
                    AreaMark(x: .value("Datum", point.date), y: .value("Punkte", point.rating))
                        .foregroundStyle(LinearGradient(
                            colors: [lineColor.opacity(0.25), lineColor.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Datum", point.date), y: .value("Punkte", point.rating))
                        .foregroundStyle(lineColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let selected {
                    RuleMark(x: .value("Datum", selected.date))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    PointMark(x: .value("Datum", selected.date), y: .value("Punkte", selected.rating))
                        .foregroundStyle(lineColor)
                        .symbolSize(80)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: yDomain(window))
            .chartXSelection(value: $selectedDate)
            .frame(height: 190)
            .sensoryFeedback(.selection, trigger: selected?.date)
            .animation(.smooth, value: range)

            RangePicker(values: RatingRange.allCases, selection: $range, title: \.rawValue, tint: lineColor)
        }
        .padding(.top, 8)
    }

    /// Keeps a flat line in the middle and gives small changes some room.
    private func yDomain(_ window: [RatingPoint]) -> ClosedRange<Double> {
        let values = window.map(\.rating)
        let low = values.min() ?? 1500
        let high = values.max() ?? 1500
        let padding = max((high - low) * 0.25, 10)
        return (low - padding)...(high + padding)
    }
}
