import PadelStats
import SwiftUI

enum GoalSettings {
    static let weeklyTargetKey = "goal.weeklyTarget"
    static var weeklyTarget: Int {
        let value = UserDefaults.standard.integer(forKey: weeklyTargetKey)
        return value == 0 ? 3 : value
    }
}

// MARK: - Weekly goal ring (Home)

struct WeeklyGoalCard: View {
    let matches: [MatchSummary]
    @AppStorage(GoalSettings.weeklyTargetKey) private var target = 3
    @State private var shownProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let goal = PadelStats.weeklyGoal(matches, target: target)
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Theme.surfaceRaised, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: shownProgress)
                    .stroke(Theme.lime, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(goal.playedThisWeek)")
                        .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("/ \(goal.target)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(goal.isMet ? "Wochenziel erreicht" : "Wochenziel")
                    .font(.headline)
                Text(goal.isMet
                     ? "Stark! \(goal.playedThisWeek) Matches diese Woche."
                     : "Noch \(goal.remaining) \(goal.remaining == 1 ? "Match" : "Matches") bis \(goal.target) pro Woche.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if goal.streakWeeks > 0 {
                    Label("\(goal.streakWeeks) \(goal.streakWeeks == 1 ? "Woche" : "Wochen") in Folge", systemImage: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.lime)
                }
            }
            Spacer()
        }
        .padding(Theme.Spacing.card)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 1.0, dampingFraction: 0.85).delay(0.2)) { shownProgress = goal.progress }
        }
        .onChange(of: goal.progress) { _, new in withAnimation(.snappy) { shownProgress = new } }
        .sensoryFeedback(.success, trigger: goal.isMet)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Month review (Home banner + share card)

struct MonthReviewCard: View {
    let review: MonthReview
    let onDismiss: () -> Void

    private var monthName: String { review.month.formatted(.dateTime.month(.wide)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DEIN \(monthName.uppercased())")
                        .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.5)
                        .foregroundStyle(.secondary)
                    Text("Monatsrückblick").font(.headline)
                }
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rückblick ausblenden")
            }
            HStack(spacing: 0) {
                stat("\(review.matches)", "Matches")
                stat(review.winRate?.percentText ?? "–", "Siegquote")
                stat("\(review.bestWinStreak)", "Beste Serie")
                stat(review.ratingChange.map { ($0 >= 0 ? "+" : "−") + "\(Int(abs($0).rounded()))" } ?? "–", "Punkte",
                     tint: (review.ratingChange ?? 0) >= 0 ? Theme.me : Theme.opponent)
            }
            if let partner = review.favouritePartner {
                Label("Lieblingspartner: \(partner) (\(review.favouritePartnerMatches)×)", systemImage: "person.2.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ShareCardButton(title: "Mein Padel-Monat") {
                MonthReviewShareCard(review: review)
            } label: {
                Label("Rückblick teilen", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: .capsule)
                    .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.card)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }

    private func stat(_ value: String, _ label: String, tint: Color = .primary) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MonthReviewShareCard: View {
    let review: MonthReview

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label("Pointcheck", systemImage: "tennisball.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ball)
                Spacer()
                Text(review.month.formatted(.dateTime.month(.wide).year()).uppercased())
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(2)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Text("Mein Padel-Monat")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            VStack(spacing: 14) {
                row("Matches", "\(review.matches)")
                row("Siege", "\(review.wins)")
                row("Siegquote", review.winRate?.percentText ?? "–")
                row("Beste Serie", "\(review.bestWinStreak)")
                if let partner = review.favouritePartner { row("Lieblingspartner", partner) }
                if let rival = review.toughestRival { row("Härtester Gegner", rival) }
                if review.playTime > 0 { row("Auf dem Platz", review.playTime.durationText) }
                if let change = review.ratingChange {
                    row("Spielstärke", (change >= 0 ? "+" : "−") + "\(Int(abs(change).rounded()))", tint: change >= 0 ? Theme.me : Theme.opponent)
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 20, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(width: 360, height: 450)
        .background(LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.16), .black], startPoint: .top, endPoint: .bottom))
    }

    private func row(_ label: String, _ value: String, tint: Color = .white) -> some View {
        HStack {
            Text(label).font(.system(size: 16, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(tint)
        }
    }
}

// MARK: - "Dein Kreis" ranking

struct CircleRankingView: View {
    @Environment(AccountService.self) private var account
    @State private var people: [PersonRow] = []
    @State private var loaded = false

    private var ranked: [PersonRow] {
        var all = people
        if let me = account.profile {
            all.append(PersonRow(profileID: me.id, displayName: me.displayName, username: me.username, avatarPath: me.avatarPath,
                                 homeClub: me.homeClub, rating: me.rating, relation: .self, reason: nil, requestedAt: nil, followedAt: nil))
        }
        return all.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
    }

    var body: some View {
        ScrollView {
            if loaded && people.isEmpty {
                EmptyState(symbol: "person.2", title: "Dein Kreis ist noch leer",
                           message: "Folge Spielern, dann siehst du hier, wer in deinem Kreis vorne liegt.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { index, person in
                        HStack(spacing: 12) {
                            Text("\(index + 1).")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(index < 3 ? Color.primary : .secondary)
                                .frame(width: 28, alignment: .trailing)
                            PersonListRow(person: person, subtitle: person.rating.map { "Level \(PadelLevel.level(for: $0).formatted(.number.precision(.fractionLength(1))))" },
                                          showsFollowButton: false)
                            Text(person.rating.map { "\(Int($0.rounded()))" } ?? "–")
                                .font(Theme.scoreFont(size: 17))
                                .padding(.trailing, 20)
                        }
                        .background(person.relation == .self ? Theme.surface : .clear)
                        .revealOnAppear(delay: min(Double(index) * 0.04, 0.3))
                        if index < ranked.count - 1 { RowDivider(inset: 100) }
                    }
                }
            }
        }
        .background(Theme.background)
        .navigationTitle("Dein Kreis")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let id = account.userID { people = await account.following(of: id) }
            loaded = true
        }
        .profileNavigation()
    }
}
