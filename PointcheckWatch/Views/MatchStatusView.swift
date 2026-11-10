import PadelScoring
import SwiftUI

/// Centre strip: sets ("1:1") and below it the games of the current set ("4:3").
/// Our numbers are green, the opponent's red – same colours as the fields.
struct MatchStatusView: View {
    let state: MatchState
    let highlight: Highlight?

    var body: some View {
        VStack(spacing: 0) {
            if highlight?.kind == .undo {
                Label("Rückgängig", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
                HStack(spacing: 2) {
                    Text("\(state.setsWon.me)").foregroundStyle(Theme.me)
                    Text(":").foregroundStyle(.white.opacity(0.6))
                    Text("\(state.setsWon.opponent)").foregroundStyle(Theme.opponent)
                }
                .font(Theme.scoreFont(size: 20))
                .contentTransition(.numericText())

                HStack(spacing: 4) {
                    Text("\(state.games.me):\(state.games.opponent)")
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    if let situation = situationText {
                        Text(situation)
                            .foregroundStyle(.yellow)
                            .transition(.opacity)
                    }
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .animation(.smooth, value: state)
        .animation(.smooth, value: highlight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sätze \(state.setsWon.me) zu \(state.setsWon.opponent), Spiele \(state.games.me) zu \(state.games.opponent)")
    }

    private var situationText: String? {
        switch state.situation {
        case .tiebreak: "Tiebreak"
        case .goldenPoint: "Golden Point"
        case .deuce: "Einstand"
        case .advantage, .regular: nil
        }
    }
}
