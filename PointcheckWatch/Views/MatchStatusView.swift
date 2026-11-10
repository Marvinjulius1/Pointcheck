import PadelScoring
import SwiftUI

/// Centre strip: sets ("1:1") and below it the games of the current set ("4:3").
/// Our numbers are green, the opponent's red – same colours as the fields.
struct MatchStatusView: View {
    let state: MatchState
    let highlight: Highlight?
    var showsSideChange = false

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

                if let highlight, let team = highlight.team {
                    // "SPIEL" / "SATZ" / "MATCH" in the winning team's colour, briefly
                    // replacing the games line.
                    Text(highlight.title.uppercased())
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.color(for: team))
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else if showsSideChange {
                    Label("Seitenwechsel", systemImage: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    gamesLine
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .animation(.smooth, value: state)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: highlight)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showsSideChange)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sätze \(state.setsWon.me) zu \(state.setsWon.opponent), Spiele \(state.games.me) zu \(state.games.opponent)")
    }

    private var gamesLine: some View {
        HStack(spacing: 4) {
            Text("\(state.games.me):\(state.games.opponent)")
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            if let situation {
                Text(situation.text)
                    .foregroundStyle(situation.color)
                    .transition(.opacity)
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
    }

    /// Extra hint next to the games, most important first.
    private var situation: (text: String, color: Color)? {
        if !state.hasStarted {
            return ("Aufschlag wählen", ScoreField.tennisBallYellow)
        }
        let mine = state.bigPoint(for: .me)
        let theirs = state.bigPoint(for: .opponent)
        if mine != nil || theirs != nil {
            let isMatch = mine == .matchPoint || theirs == .matchPoint
            let text = isMatch ? "Matchball" : "Satzball"
            switch (mine, theirs) {
            case (.some, nil): return (text, Theme.me)
            case (nil, .some): return (text, Theme.opponent)
            default: return (text, .yellow)
            }
        }
        switch state.situation {
        case .superTiebreak: return ("Match-Tiebreak", .yellow)
        case .tiebreak: return ("Tiebreak", .yellow)
        case .goldenPoint: return ("Golden Point", .yellow)
        case .deuce: return ("Einstand", .yellow)
        case .advantage, .regular: return nil
        }
    }
}
