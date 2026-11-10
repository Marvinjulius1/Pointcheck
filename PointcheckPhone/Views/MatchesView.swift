import PadelStats
import SwiftData
import SwiftUI

struct MatchesView: View {
    @Query(sort: \StoredMatch.startDate, order: .reverse) private var stored: [StoredMatch]
    @Environment(WatchSync.self) private var sync
    @Environment(AccountService.self) private var account

    /// Watch matches and confirmed matches entered by co-players, grouped by month.
    private var months: [(month: Date, matches: [MatchSummary])] {
        let all = account.allMatches(local: stored.map(\.summary)).sorted { $0.startDate > $1.startDate }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: all) {
            calendar.dateInterval(of: .month, for: $0.startDate)?.start ?? $0.startDate
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        let months = months
        Group {
            if months.isEmpty {
                NoMatchesView()
            } else {
                List {
                    ForEach(months, id: \.month) { group in
                        Section(group.month.formatted(.dateTime.month(.wide).year())) {
                            ForEach(group.matches) { match in
                                NavigationLink {
                                    MatchDetailView(match: match)
                                } label: {
                                    MatchRow(match: match, isFromCoPlayer: account.foreignIDs.contains(match.id))
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Matches")
        .refreshable {
            sync.requestAll()
            await account.refresh()
        }
    }
}

struct MatchRow: View {
    let match: MatchSummary
    var isFromCoPlayer = false

    private var subtitle: String {
        var parts = [match.startDate.formatted(.dateTime.day().month(.abbreviated).hour().minute())]
        if !match.partnerName.isEmpty { parts.append("mit \(match.partnerName)") }
        if isFromCoPlayer { parts.append("von Mitspieler") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            ResultIcon(result: match.result)
            VStack(alignment: .leading, spacing: 3) {
                Text(match.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(match.resultText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(match.setsWon.me):\(match.setsWon.opponent)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(match.result.color)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Circle with a check (won) or cross (lost), like transaction icons in a banking app.
struct ResultIcon: View {
    let result: MatchSummary.Result

    private var symbol: String {
        switch result {
        case .won: "checkmark"
        case .lost: "xmark"
        case .abandoned: "minus"
        case .live: "ellipsis"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(result.color)
            .frame(width: 40, height: 40)
            .background(result.color.opacity(0.14), in: .circle)
            .accessibilityLabel(result.title)
    }
}

struct MatchDetailView: View {
    let match: MatchSummary
    @Environment(HealthService.self) private var health

    private var workout: WorkoutMetrics? { health.metrics[match.id] }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Text("\(match.setsWon.me)").foregroundStyle(Theme.me)
                        Text(":").foregroundStyle(.secondary)
                        Text("\(match.setsWon.opponent)").foregroundStyle(Theme.opponent)
                    }
                    .font(Theme.scoreFont(size: 56))
                    ResultBadge(result: match.result)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Sätze") {
                ForEach(Array(match.sets.enumerated()), id: \.offset) { index, set in
                    HStack {
                        Text(set.isSuperTiebreak ? "Match-Tiebreak" : "Satz \(index + 1)")
                        Spacer()
                        Text(set.resultText)
                            .font(Theme.scoreFont(size: 17))
                            .foregroundStyle(set.winner == .me ? Theme.me : set.winner == .opponent ? Theme.opponent : .primary)
                        if let tiebreak = set.tiebreak, !set.isSuperTiebreak {
                            Text("(\(tiebreak.me):\(tiebreak.opponent))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Spieler") {
                LabeledContent("Gegner", value: match.opponentName.isEmpty ? "–" : match.opponentName)
                LabeledContent("Partner", value: match.partnerName.isEmpty ? "–" : match.partnerName)
            }

            if let workout {
                Section("Training") {
                    LabeledContent("Trainingsdauer", value: workout.duration.durationText)
                    if let energy = workout.activeEnergy {
                        LabeledContent("Aktive Energie", value: "\(Int(energy.rounded())) kcal")
                    }
                    if let average = workout.averageHeartRate {
                        LabeledContent("Ø Herzfrequenz", value: "\(Int(average.rounded())) bpm")
                    }
                    if let max = workout.maxHeartRate {
                        LabeledContent("Max. Herzfrequenz", value: "\(Int(max.rounded())) bpm")
                    }
                }
            }

            Section("Details") {
                LabeledContent("Datum", value: match.startDate.formatted(date: .long, time: .shortened))
                if let duration = match.duration {
                    LabeledContent("Dauer", value: duration.durationText)
                }
                LabeledContent("Modus", value: match.modeText)
                LabeledContent("40:40", value: match.goldenPoint ? "Golden Point" : "Vorteil")
            }

            OnlineMatchSection(match: match)

            Section {
                ShareResultButton(match: match, workout: workout)
            } footer: {
                Text("Namen änderst du auf der Watch im Verlauf. Die Änderung erscheint dann automatisch hier.")
            }
        }
        .navigationTitle(match.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
