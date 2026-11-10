import Charts
import PadelStats
import SwiftData
import SwiftUI

/// Overview card: current level, rating and the change of the last match.
struct RatingCard: View {
    let report: LocalRatingReport

    private var lastChange: Double? {
        guard report.history.count >= 2 else { return nil }
        return report.history[report.history.count - 1].rating - report.history[report.history.count - 2].rating
    }

    var body: some View {
        NavigationLink {
            RatingView()
        } label: {
            HStack(spacing: 16) {
                LevelBadge(level: report.me.level, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spielstärke")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(PadelLevel.name(for: report.me.level))
                        .font(.title3.weight(.bold))
                    HStack(spacing: 6) {
                        Text("\(Int(report.me.rating.rounded())) Punkte")
                            .monospacedDigit()
                        if let lastChange {
                            Text(lastChange >= 0 ? "▲ \(Int(lastChange.rounded()))" : "▼ \(Int((-lastChange).rounded()))")
                                .foregroundStyle(lastChange >= 0 ? Theme.me : Theme.opponent)
                                .monospacedDigit()
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
}

/// Round badge with the padel level (e.g. "3.6").
struct LevelBadge: View {
    let level: Double
    var size: CGFloat = 44

    var body: some View {
        Text(level.formatted(.number.precision(.fractionLength(1))))
            .font(Theme.scoreFont(size: size * 0.36))
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(Theme.me.opacity(0.45)), in: .circle)
    }
}

struct RatingView: View {
    @Query private var stored: [StoredMatch]
    @Environment(AccountService.self) private var account

    var body: some View {
        let report = PadelStats.localRatings(account.allMatches(local: stored.map(\.summary)))
        List {
            Section {
                VStack(spacing: 8) {
                    LevelBadge(level: report.me.level, size: 96)
                    Text(PadelLevel.name(for: report.me.level))
                        .font(.title2.weight(.bold))
                    Text("\(Int(report.me.rating.rounded())) Punkte · \(report.me.matches) gewertete Matches")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if report.me.isProvisional {
                        Label("Vorläufig – wird nach 10 Matches stabiler", systemImage: "hourglass")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            if report.history.count > 1 {
                Section("Verlauf") {
                    Chart(report.history) { point in
                        LineMark(x: .value("Datum", point.date), y: .value("Punkte", point.rating))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.me)
                        AreaMark(x: .value("Datum", point.date), y: .value("Punkte", point.rating))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(
                                colors: [Theme.me.opacity(0.3), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                    .padding(.vertical, 8)
                }
            }

            if report.players.count > 1 {
                Section {
                    ForEach(Array(report.players.enumerated()), id: \.element.id) { index, player in
                        HStack(spacing: 12) {
                            Text("\(index + 1).")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)
                            LevelBadge(level: player.level, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.name)
                                    .font(.body.weight(player.isMe ? .bold : .regular))
                                Text("\(player.matches) Matches\(player.isProvisional ? " · vorläufig" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(player.rating.rounded()))")
                                .font(Theme.scoreFont(size: 17))
                        }
                        .listRowBackground(player.isMe ? Theme.me.opacity(0.12) : nil)
                    }
                } header: {
                    Text("Dein Kreis")
                } footer: {
                    Text("Partner und Gegner werden nur anhand deiner Matches bewertet. Ein Gegnername steht dabei für das ganze gegnerische Team.")
                }
            }

            Section {
                Text("So funktioniert's")
                    .font(.headline)
                Text("Jeder startet mit 1500 Punkten (Level 3.5). Nach jedem Match gibt es Punkte – mehr bei einem Sieg gegen stärkere Gegner und bei deutlichen Ergebnissen, weniger bei einem erwarteten Sieg. In den ersten 10 Matches ändert sich der Wert schneller.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Vorschau: Sobald Konten dazukommen, fließen die echten Werte aller Mitspieler ein.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Spielstärke")
    }
}
