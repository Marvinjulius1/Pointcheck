import PadelStats
import SwiftUI

/// Shareable result image (4:5, Instagram-friendly).
struct ShareCardView: View {
    let match: MatchSummary
    var workout: WorkoutMetrics?

    private var won: Bool { match.winner == .me }
    private var accent: Color { won ? Theme.me : Theme.opponent }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
            // Lime glow in the corner, like a court light; red if lost.
            Circle()
                .fill(accent.opacity(0.35))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: 120, y: -140)
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "tennisball.fill").foregroundStyle(Theme.lime)
                        Text("Pointcheck")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Text(match.startDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .opacity(0.7)
                }

                Spacer()

                Text(won ? "SIEG" : match.result == .lost ? "NIEDERLAGE" : "MATCH")
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(3)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(accent, in: .capsule)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(match.setsWon.me)").foregroundStyle(accent)
                    Text(":").opacity(0.4)
                    Text("\(match.setsWon.opponent)").opacity(won ? 0.6 : 1)
                }
                .font(Theme.scoreFont(size: 96))

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(match.sets.enumerated()), id: \.offset) { _, set in
                        HStack(spacing: 10) {
                            Circle().fill(set.winner == .me ? Theme.lime : Theme.opponent).frame(width: 8, height: 8)
                            Text(set.resultText)
                                .font(Theme.scoreFont(size: 26))
                                .foregroundStyle(set.winner == .me ? .white : .white.opacity(0.6))
                        }
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    if !match.partnerName.isEmpty {
                        Text("mit \(match.partnerName)")
                    }
                    if !match.opponentName.isEmpty {
                        Text("gegen \(match.opponentName)")
                            .opacity(0.7)
                    }
                }
                .font(.system(size: 17, weight: .semibold, design: .rounded))

                HStack(spacing: 14) {
                    if let duration = match.duration {
                        Label(duration.durationText, systemImage: "stopwatch")
                    }
                    if let energy = workout?.activeEnergy {
                        Label("\(Int(energy.rounded())) kcal", systemImage: "flame.fill")
                    }
                    Spacer()
                    Text("PADEL")
                        .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(3)
                        .opacity(0.5)
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(28)
        }
        .frame(width: 360, height: 450)
        .clipped()
    }
}

/// Renders the card and opens the share sheet (Instagram, WhatsApp, Fotos …).
struct ShareResultButton: View {
    let match: MatchSummary
    var workout: WorkoutMetrics?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let image = renderImage() {
            ShareLink(
                item: image,
                preview: SharePreview("Padel-Ergebnis", image: image)
            ) {
                Label("Ergebnis teilen", systemImage: "square.and.arrow.up")
            }
        }
    }

    @MainActor
    private func renderImage() -> Image? {
        let renderer = ImageRenderer(content: ShareCardView(match: match, workout: workout))
        renderer.scale = max(displayScale, 3)
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}

#Preview {
    ShareCardView(match: MatchSummary(
        startDate: .now,
        endDate: .now.addingTimeInterval(5400),
        opponentName: "Max & Lena",
        partnerName: "Tom",
        sets: [
            SetScore(games: TeamScore(me: 6, opponent: 4)),
            SetScore(games: TeamScore(me: 3, opponent: 6)),
            SetScore(games: TeamScore(me: 1, opponent: 0), tiebreak: TeamScore(me: 10, opponent: 8), isSuperTiebreak: true),
        ],
        winner: .me
    ), workout: WorkoutMetrics(start: .now, end: .now.addingTimeInterval(5400), activeEnergy: 712))
}
