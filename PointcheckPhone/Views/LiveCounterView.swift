import PadelStats
import SwiftUI

/// Counting a match on the iPhone: red field = opponents, green field = us,
/// sets and games in between – like the watch, just bigger.
struct LiveCounterView: View {
    @Environment(PhoneMatchController.self) private var counter
    @Environment(\.dismiss) private var dismiss
    @State private var showsNewMatchDialog = false
    @State private var showsFinishSheet = false
    @State private var showsCloseDialog = false

    private var state: MatchState { counter.state }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let strip: CGFloat = 92
                let fieldHeight = max(0, (proxy.size.height - strip) / 2)
                VStack(spacing: 0) {
                    field(.opponent).frame(height: fieldHeight)
                    centreStrip.frame(height: strip)
                    field(.me).frame(height: fieldHeight)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .background(Color.black)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") {
                        if state.hasStarted && !state.isFinished { showsCloseDialog = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Live zählen").font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { counter.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!counter.scorer.canUndo)
                        .accessibilityLabel("Letzten Punkt zurücknehmen")
                }
            }
            .confirmationDialog("Match verwerfen?", isPresented: $showsCloseDialog, titleVisibility: .visible) {
                Button("Weiterzählen") { dismiss() }
                Button("Verwerfen", role: .destructive) { counter.discard(); dismiss() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("„Weiterzählen“ behält den Spielstand, du kannst später zurückkommen.")
            }
            .sheet(isPresented: $showsFinishSheet) {
                FinishMatchSheet { partner, opponent in
                    counter.finish(partner: partner, opponent: opponent)
                    dismiss()
                }
            }
            .onChange(of: state.isFinished) { _, finished in
                if finished {
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        showsFinishSheet = true
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: Fields

    private func field(_ team: Team) -> some View {
        let tint = team == .me ? Theme.me : Theme.opponent
        let highlighted = counter.highlight?.team == team
        return Button {
            counter.score(team)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(highlighted ? 0.95 : 0.75), tint.opacity(0.45)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(spacing: 6) {
                    HStack {
                        Text(team == .me ? "WIR" : "GEGNER")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        if state.server == team && !state.isFinished {
                            Button(action: { counter.toggleFirstServer() }) {
                                Image(systemName: "tennisball.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Theme.ball)
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                            .disabled(state.hasStarted)
                            .accessibilityLabel("Aufschlag")
                        }
                    }
                    Spacer()
                    Text(state.pointLabel(for: team))
                        .font(.system(size: 120, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                    Spacer()
                    if let highlight = counter.highlight, highlight.team == team {
                        Text(highlight.title.uppercased())
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .background(.white.opacity(0.22), in: .capsule)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Color.clear.frame(height: 24)
                    }
                }
                .padding(20)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(state.isFinished)
        .scaleEffect(highlighted ? 1.02 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: state.pointLabel(for: team))
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: highlighted)
        .padding(.vertical, 6)
        .accessibilityLabel("\(team == .me ? "Wir" : "Gegner"): \(state.pointLabel(for: team))")
        .accessibilityHint("Punkt für \(team == .me ? "uns" : "Gegner")")
    }

    // MARK: Centre strip

    private var centreStrip: some View {
        VStack(spacing: 4) {
            if counter.highlight?.kind == .undo {
                Label("Rückgängig", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            } else {
                HStack(spacing: 4) {
                    Text("\(state.setsWon.me)").foregroundStyle(Theme.me)
                    Text(":").foregroundStyle(.white.opacity(0.6))
                    Text("\(state.setsWon.opponent)").foregroundStyle(Theme.opponent)
                }
                .font(Theme.scoreFont(size: 30))
                .contentTransition(.numericText())
                HStack(spacing: 8) {
                    Text("\(state.games.me):\(state.games.opponent)")
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    if let hint = hintText {
                        Text(hint.text).foregroundStyle(hint.color)
                    }
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .animation(.smooth, value: state)
        .animation(.smooth, value: counter.highlight)
        .animation(.smooth, value: counter.showsSideChange)
    }

    private var hintText: (text: String, color: Color)? {
        if counter.showsSideChange { return ("Seitenwechsel", .white) }
        if !state.hasStarted { return ("Aufschlag wählen", Theme.ball) }
        let mine = state.bigPoint(for: .me), theirs = state.bigPoint(for: .opponent)
        if mine != nil || theirs != nil {
            let text = (mine == .matchPoint || theirs == .matchPoint) ? "Matchball" : "Satzball"
            switch (mine, theirs) {
            case (.some, nil): return (text, Theme.me)
            case (nil, .some): return (text, Theme.opponent)
            default: return (text, Theme.lime)
            }
        }
        switch state.situation {
        case .superTiebreak: return ("Match-Tiebreak", Theme.lime)
        case .tiebreak: return ("Tiebreak", Theme.lime)
        case .goldenPoint: return ("Golden Point", Theme.lime)
        case .deuce: return ("Einstand", Theme.lime)
        default: return nil
        }
    }
}

/// After the last point: names, then save.
struct FinishMatchSheet: View {
    @Environment(PhoneMatchController.self) private var counter
    @Environment(\.dismiss) private var dismiss
    @State private var partner = ""
    @State private var opponent = ""
    let onSave: (String, String) -> Void

    var body: some View {
        NavigationStack {
            FormScreen(title: counter.state.winner == .me ? "Gewonnen!" : "Verloren",
                       subtitle: "Wer stand mit dir auf dem Platz?",
                       symbol: counter.state.winner == .me ? "trophy.fill" : "tennisball.fill") {
                ScoreHero(sets: counter.state.completedSets, winner: counter.state.winner)
                FormGroup(title: "Mitspieler", note: "Optional. Gegner mit Konto verlinkst du danach im Match, damit das Ergebnis bestätigt wird.") {
                    InputRow(label: "Partner", placeholder: "Name", text: $partner, symbol: "person.2.fill")
                    RowDivider()
                    InputRow(label: "Gegner", placeholder: "Name", text: $opponent, symbol: "person.fill.xmark")
                }
            } footer: {
                FormActionBar(title: "Match speichern") { onSave(partner, opponent); dismiss() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
    }
}
