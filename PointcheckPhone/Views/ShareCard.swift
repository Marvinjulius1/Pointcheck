import PadelStats
import SwiftUI

/// Shareable result image (4:5, Instagram-friendly).
struct ShareCardView: View {
    let match: MatchSummary

    private var won: Bool { match.winner == .me }
    private var accent: Color { won ? Theme.me : Theme.opponent }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.85), accent.opacity(0.25), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "tennisball.fill")
                        .foregroundStyle(Theme.ball)
                    Text("PADEL")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .tracking(3)
                    Spacer()
                    Text(match.startDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .opacity(0.8)
                }

                Spacer()

                Text(won ? "SIEG" : match.result == .lost ? "NIEDERLAGE" : "MATCH")
                    .font(.system(size: 46, weight: .black, design: .rounded))

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(match.sets.enumerated()), id: \.offset) { _, set in
                        Text(set.resultText)
                            .font(Theme.scoreFont(size: 54))
                            .foregroundStyle(set.winner == .me ? .white : .white.opacity(0.55))
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    if !match.partnerName.isEmpty {
                        Text("mit \(match.partnerName)")
                    }
                    if !match.opponentName.isEmpty {
                        Text("gegen \(match.opponentName)")
                            .opacity(0.8)
                    }
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))

                HStack {
                    if let duration = match.duration {
                        Label(duration.durationText, systemImage: "stopwatch")
                    }
                    Spacer()
                    Text("Pointcheck")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .opacity(0.8)
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(28)
        }
        .frame(width: 360, height: 450)
    }
}

/// Renders the card and opens the share sheet (Instagram, WhatsApp, Fotos …).
struct ShareResultButton: View {
    let match: MatchSummary
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
        let renderer = ImageRenderer(content: ShareCardView(match: match))
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
    ))
}
