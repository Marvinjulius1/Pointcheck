import PadelStats
import SwiftData
import SwiftUI

struct MatchesView: View {
    @Query(sort: \StoredMatch.startDate, order: .reverse) private var stored: [StoredMatch]
    @Environment(WatchSync.self) private var sync
    @Environment(AccountService.self) private var account
    @Environment(PhoneMatchController.self) private var counter
    @State private var showsCounter = false
    @State private var showsManualEntry = false

    private struct MonthGroup: Identifiable {
        let month: Date
        let matches: [MatchSummary]
        var id: Date { month }
    }

    /// Watch matches and confirmed matches entered by co-players, grouped by month.
    private var monthGroups: [MonthGroup] {
        let all = account.allMatches(local: stored.map(\.summary)).sorted { $0.startDate > $1.startDate }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: all) {
            calendar.dateInterval(of: .month, for: $0.startDate)?.start ?? $0.startDate
        }
        return grouped.keys.sorted(by: >).map { MonthGroup(month: $0, matches: grouped[$0] ?? []) }
    }

    var body: some View {
        let groups = monthGroups
        ScrollView {
            if groups.isEmpty {
                NoMatchesView()
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                        let wins = group.matches.filter { $0.winner == .me }.count
                        let losses = group.matches.filter { $0.winner == .opponent }.count
                        HStack(alignment: .firstTextBaseline) {
                            Text(group.month.formatted(.dateTime.month(.wide).year()))
                                .font(.title3.weight(.bold))
                            Spacer()
                            HStack(spacing: 6) {
                                Text("\(wins)").foregroundStyle(Theme.lime)
                                Text("–").foregroundStyle(.tertiary)
                                Text("\(losses)").foregroundStyle(Theme.opponent)
                            }
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .accessibilityLabel("\(wins) Siege, \(losses) Niederlagen")
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, groupIndex == 0 ? 8 : 28)
                        .padding(.bottom, 8)
                        ForEach(Array(group.matches.enumerated()), id: \.element.id) { index, match in
                            NavigationLink {
                                MatchDetailView(match: match)
                            } label: {
                                MatchRow(match: match, isFromCoPlayer: account.foreignIDs.contains(match.id))
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.pressScale)
                            .revealOnAppear(delay: min(Double(index) * 0.04, 0.3))
                            if index < group.matches.count - 1 { RowDivider(inset: 72) }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Theme.background)
        .navigationTitle("Matches")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Live zählen", systemImage: "plus.forwardslash.minus") { showsCounter = true }
                    Button("Ergebnis eintragen", systemImage: "square.and.pencil") { showsManualEntry = true }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Match hinzufügen")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if counter.state.hasStarted && !counter.state.isFinished {
                Button { showsCounter = true } label: {
                    HStack(spacing: 12) {
                        Circle().fill(Theme.me).frame(width: 8, height: 8)
                        Text("Match läuft · \(counter.state.setsWon.me):\(counter.state.setsWon.opponent) Sätze, \(counter.state.games.me):\(counter.state.games.opponent) Spiele")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("Weiter").font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(Theme.surface, in: .capsule)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .buttonStyle(.pressScale)
            }
        }
        .fullScreenCover(isPresented: $showsCounter) { LiveCounterView() }
        .sheet(isPresented: $showsManualEntry) { ManualResultView() }
        .profileNavigation()
        .tennisBallRefresh {
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
    @Environment(AccountService.self) private var account
    @State private var showsComposer = false

    private var workout: WorkoutMetrics? { health.metrics[match.id] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                hero

                FormGroup(title: "Spieler") {
                    FormRow(symbol: "person.2.fill", tint: Theme.lime, title: "Partner") {
                        Text(match.partnerName.isEmpty ? "–" : match.partnerName).foregroundStyle(.secondary)
                    }
                    RowDivider()
                    FormRow(symbol: "person.fill.xmark", tint: Theme.opponent, title: "Gegner") {
                        Text(match.opponentName.isEmpty ? "–" : match.opponentName).foregroundStyle(.secondary)
                    }
                }

                if let workout {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Training")
                        Card {
                            HStack(spacing: 0) {
                                NumberTile(value: workout.duration / 60, label: "Minuten")
                                tileDivider
                                NumberTile(value: workout.activeEnergy ?? 0, label: "kcal", detail: "aktiv", delay: 0.08)
                                tileDivider
                                NumberTile(value: workout.averageHeartRate ?? 0, label: "bpm",
                                           detail: workout.maxHeartRate.map { "max. \(Int($0.rounded()))" }, delay: 0.16)
                            }
                            .padding(.vertical, 14)
                        }
                    }
                }

                FormGroup(title: "Details") {
                    FormRow(symbol: "calendar", title: "Datum") {
                        Text(match.startDate.formatted(date: .long, time: .shortened)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    if let duration = match.duration {
                        RowDivider()
                        FormRow(symbol: "stopwatch", title: "Dauer") {
                            Text(duration.durationText).foregroundStyle(.secondary)
                        }
                    }
                    RowDivider()
                    FormRow(symbol: "list.number", title: "Modus") {
                        Text(match.goldenPoint ? "\(match.modeText) · Golden Point" : match.modeText).foregroundStyle(.secondary)
                    }
                }

                OnlineMatchSection(match: match)

                HStack(spacing: 10) {
                    Button {
                        showsComposer = true
                    } label: {
                        Label("Als Beitrag", systemImage: "square.and.pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.accent, in: .capsule)
                    }
                    .buttonStyle(.pressScale)
                    ShareResultButton(match: match, workout: workout)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.surface, in: .capsule)
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                }
                FormNote(text: "Namen änderst du auf der Watch im Verlauf. Die Änderung erscheint dann automatisch hier.")
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .sheet(isPresented: $showsComposer) { PostComposer(match: match) }
        .navigationTitle(match.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Big result on top, each set as a line with the ball by the winner.
    private var hero: some View {
        let won = match.winner == .me
        let tint: Color = match.winner == nil ? .secondary : won ? Theme.lime : Theme.opponent
        return VStack(spacing: 18) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    CountUpText(value: Double(match.setsWon.me))
                        .foregroundStyle(won ? Theme.lime : .primary)
                    Text(":").foregroundStyle(.tertiary)
                    CountUpText(value: Double(match.setsWon.opponent), delay: 0.1)
                        .foregroundStyle(match.winner == .opponent ? Theme.opponent : .primary)
                }
                .font(Theme.scoreFont(size: 72))
                Text(match.result.title)
                    .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(match.winner == nil ? Color.secondary : Theme.onAccent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(match.winner == nil ? Theme.surfaceRaised : tint, in: .capsule)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            VStack(spacing: 0) {
                ForEach(Array(match.sets.enumerated()), id: \.offset) { index, set in
                    if index > 0 { RowDivider(inset: 16) }
                    HStack(spacing: 12) {
                        Image(systemName: "tennisball.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.lime)
                            .opacity(set.winner == .me ? 1 : 0)
                        Text(set.isSuperTiebreak ? "Match-Tiebreak" : "Satz \(index + 1)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let tiebreak = set.tiebreak, !set.isSuperTiebreak {
                            Text("(\(tiebreak.me):\(tiebreak.opponent))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        Text(set.resultText)
                            .font(Theme.scoreFont(size: 20))
                            .foregroundStyle(set.winner == .me ? Theme.lime : set.winner == .opponent ? Theme.opponent : .primary)
                        Image(systemName: "tennisball.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.opponent)
                            .opacity(set.winner == .opponent ? 1 : 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .revealOnAppear(delay: 0.1 + Double(index) * 0.06)
                }
            }
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    private var tileDivider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 36)
    }
}
