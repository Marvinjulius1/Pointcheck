import PadelStats
import SwiftData
import SwiftUI

struct MatchesView: View {
    @Query(sort: \StoredMatch.startDate, order: .reverse) private var stored: [StoredMatch]
    @Environment(WatchSync.self) private var sync

    var body: some View {
        Group {
            if stored.isEmpty {
                NoMatchesView()
            } else {
                List(stored) { match in
                    let summary = match.summary
                    NavigationLink {
                        MatchDetailView(match: summary)
                    } label: {
                        MatchRow(match: summary)
                    }
                }
            }
        }
        .navigationTitle("Matches")
        .refreshable { sync.requestAll() }
    }
}

struct MatchRow: View {
    let match: MatchSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(match.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                ResultBadge(result: match.result)
            }
            Text(match.resultText)
                .font(Theme.scoreFont(size: 20))
            HStack(spacing: 4) {
                Text(match.startDate.formatted(date: .abbreviated, time: .shortened))
                if !match.partnerName.isEmpty {
                    Text("· mit \(match.partnerName)")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct MatchDetailView: View {
    let match: MatchSummary

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

            Section("Details") {
                LabeledContent("Datum", value: match.startDate.formatted(date: .long, time: .shortened))
                if let duration = match.duration {
                    LabeledContent("Dauer", value: duration.durationText)
                }
                LabeledContent("Modus", value: match.modeText)
                LabeledContent("40:40", value: match.goldenPoint ? "Golden Point" : "Vorteil")
            }

            Section {
                ShareResultButton(match: match)
            } footer: {
                Text("Namen änderst du auf der Watch im Verlauf. Die Änderung erscheint dann automatisch hier.")
            }
        }
        .navigationTitle(match.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
