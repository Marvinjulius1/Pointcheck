import Charts
import PadelStats
import SwiftData
import SwiftUI

/// Statistics: calm grouped lists for stats, training, activity, partners and rivals.
struct StatsView: View {
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
                            .revealOnAppear()
                        statistics(overview)
                            .revealOnAppear(delay: 0.05)
                        healthSection
                        activitySection(all)
                        peopleSection(title: "Beste Partner", records: PadelStats.partners(all), mode: .partners)
                        peopleSection(title: "Rivalen", records: PadelStats.rivals(all), mode: .rivals)
                        Text("Partner und Gegner stammen aus den Namen, die du auf der Watch eingetragen hast.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .background(Theme.background)
            }
        }
        .navigationTitle("Statistik")
        .refreshable {
            sync.requestAll()
            await account.refresh()
            await health.refresh(for: all)
        }
    }

    // MARK: Statistics

    /// Win rate as a ring, form as a row of balls, the rest as quiet count-up numbers.
    private func statistics(_ overview: StatsOverview) -> some View {
        let decided = matches.filter(\.isDecided).sorted { $0.startDate > $1.startDate }
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Bilanz")
            HStack(spacing: 10) {
                Card {
                    WinRateRing(rate: overview.winRate ?? 0, wins: overview.wins, losses: overview.losses)
                        .padding(16)
                }
                Card {
                    FormBalls(results: decided.prefix(10).map { $0.winner == .me }, streak: overview.currentStreak,
                              record: overview.longestWinStreak)
                        .padding(16)
                }
            }
            Card {
                HStack(spacing: 0) {
                    NumberTile(value: Double(overview.matchesPlayed), label: "Matches",
                               detail: overview.totalPlayTime > 0 ? overview.totalPlayTime.durationText : nil)
                    tileDivider
                    NumberTile(value: Double(overview.setsWon), label: "Sätze", detail: "\(overview.setsLost) verloren",
                               delay: 0.08)
                    tileDivider
                    NumberTile(value: Double(overview.tiebreaksWon), label: "Tiebreaks",
                               detail: overview.tiebreakWinRate.map { "\($0.percentText) gewonnen" } ?? "\(overview.tiebreaksLost) verloren",
                               delay: 0.16)
                }
                .padding(.vertical, 14)
            }
        }
    }

    private var tileDivider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 36)
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
                        IconTile(symbol: "heart.fill", tint: Theme.opponent)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Herzfrequenz und Kalorien zu jedem Match – aufgezeichnet von deiner Apple Watch.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Mit Health verbinden") {
                                Task { await health.requestAccess() }
                            }
                            .buttonStyle(.accent)
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
                            symbol: "flame.fill", tint: Theme.lime, title: "Aktive Energie",
                            subtitle: "in \(totals.matchesWithData) Matches",
                            value: "\(Int(totals.activeEnergy.rounded()).formatted()) kcal"
                        )
                        RowDivider()
                        MetricRow(
                            symbol: "heart.fill", tint: Theme.opponent, title: "Ø Herzfrequenz",
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
    private func peopleSection(title: String, records: [PersonRecord], mode: PartnersRivalsView.Mode) -> some View {
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title) {
                    NavigationLink("Alle") { PartnersRivalsView(initialMode: mode) }
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
struct RatingHero: View {
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
            .drawOnAppear()
            .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: selected?.date)
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

// MARK: - Partners & rivals

struct PartnersRivalsView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case partners = "Partner"
        case rivals = "Rivalen"
        var id: Self { self }
    }

    @Query(sort: \StoredMatch.startDate, order: .reverse) private var stored: [StoredMatch]
    @Environment(AccountService.self) private var account
    @State private var mode: Mode

    init(initialMode: Mode = .partners) {
        _mode = State(initialValue: initialMode)
    }

    private var records: [PersonRecord] {
        let matches = account.allMatches(local: stored.map(\.summary))
        return mode == .partners ? PadelStats.partners(matches) : PadelStats.rivals(matches)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Ansicht", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if records.isEmpty {
                    EmptyState(symbol: mode == .partners ? "person.2" : "flag.2.crossed",
                               title: mode == .partners ? "Keine Partner eingetragen" : "Keine Gegner eingetragen",
                               message: "Trag Namen auf der Watch im Verlauf unter dem jeweiligen Match ein.")
                } else {
                    Card {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            if index > 0 { RowDivider(inset: 66) }
                            PersonRecordRow(record: record)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(mode.rawValue)
    }
}

struct PersonRecordRow: View {
    let record: PersonRecord

    var body: some View {
        HStack(spacing: 12) {
            ProfilePhoto(name: record.name, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name).font(.body.weight(.semibold))
                Text("\(record.wins) Siege · \(record.losses) Niederlagen")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.winRate.percentText)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(record.winRate >= 0.5 ? Theme.me : Theme.opponent)
                Text("\(record.wins):\(record.losses)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}


// MARK: - Visual tiles

/// Animated ring that draws to the win rate, number counting up inside.
struct WinRateRing: View {
    let rate: Double
    let wins: Int
    let losses: Int
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.surfaceRaised, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(Theme.lime, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: shown, to: 1)
                    .stroke(Theme.opponent.opacity(0.55), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(shown > 0 ? 1 : 0)
                VStack(spacing: 0) {
                    CountUpText(value: rate * 100, format: { "\(Int($0.rounded()))" })
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    Text("%").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 92)
            VStack(spacing: 2) {
                Text("Siegquote").font(.footnote.weight(.semibold))
                HStack(spacing: 4) {
                    Text("\(wins)").foregroundStyle(Theme.lime)
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(losses)").foregroundStyle(Theme.opponent)
                }
                .font(.caption.weight(.bold).monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 1.1, dampingFraction: 0.85).delay(0.1)) { shown = rate }
        }
        .onChange(of: rate) { _, new in withAnimation(.snappy) { shown = new } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Siegquote \(Int((rate * 100).rounded())) Prozent, \(wins) Siege, \(losses) Niederlagen")
    }
}

/// The last ten results as balls: lime = won, red = lost. Newest on the right, dropping in one by one.
struct FormBalls: View {
    let results: [Bool]
    let streak: Int
    let record: Int
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { column in
                            let index = row * 5 + column
                            let ordered = Array(results.reversed())
                            Image(systemName: "tennisball.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(index < ordered.count ? (ordered[index] ? Theme.lime : Theme.opponent) : Theme.surfaceRaised)
                                .scaleEffect(appeared ? 1 : 0.2)
                                .opacity(appeared ? 1 : 0)
                                .animation(.spring(response: 0.45, dampingFraction: 0.6).delay(Double(index) * 0.04), value: appeared)
                        }
                    }
                }
            }
            .frame(height: 92 - 46, alignment: .center)
            .frame(height: 92)
            VStack(spacing: 2) {
                Text(streakTitle).font(.footnote.weight(.semibold))
                    .foregroundStyle(streak > 0 ? Theme.lime : streak < 0 ? Theme.opponent : .primary)
                Text("Rekord \(record) in Folge").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { appeared = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Letzte \(results.count) Matches: \(results.filter { $0 }.count) Siege. \(streakTitle).")
    }

    private var streakTitle: String {
        switch streak {
        case 0: "Keine Serie"
        case 1: "1 Sieg in Folge"
        case 2...: "\(streak) Siege in Folge"
        case -1: "1 Niederlage"
        default: "\(-streak) Niederlagen in Folge"
        }
    }
}

/// Count-up number with a label, for a row of three.
struct NumberTile: View {
    let value: Double
    let label: String
    var detail: String?
    var delay: Double = 0

    var body: some View {
        VStack(spacing: 3) {
            CountUpText(value: value, delay: delay)
                .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
            Text(label).font(.footnote.weight(.semibold))
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
