import PadelScoring
import SwiftUI

/// Main screen: opponent field on top, our field at the bottom, sets/games in between.
///
/// Undo: turn the Digital Crown backwards, or swipe horizontally across the screen.
struct ScoreboardView: View {
    @Environment(MatchController.self) private var controller

    @State private var showsNewMatchDialog = false
    @State private var crownValue = 0.0
    @State private var crownAnchor = 0.0
    @FocusState private var hasCrownFocus: Bool

    /// Crown detents needed (backwards) for one undo – protects against accidental touches.
    private let crownUndoThreshold = 2.0
    private let statusHeight: CGFloat = 38

    private var state: MatchState { controller.state }

    var body: some View {
        GeometryReader { proxy in
            let fieldHeight = max(0, (proxy.size.height - statusHeight) / 2)
            VStack(spacing: 0) {
                field(for: .opponent).frame(height: fieldHeight)
                MatchStatusView(state: state, highlight: controller.highlight)
                    .frame(height: statusHeight)
                field(for: .me).frame(height: fieldHeight)
            }
        }
        .padding(.horizontal, 2)
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay {
            if state.isFinished, controller.highlight?.kind != .match {
                MatchResultOverlay(state: state) {
                    controller.startNewMatch()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.smooth(duration: 0.35), value: state.isFinished)
        .animation(.smooth(duration: 0.35), value: controller.highlight)
        .containerBackground(.black, for: .navigation)
        .simultaneousGesture(swipeToUndo)
        .focusable()
        .focused($hasCrownFocus)
        .onAppear { hasCrownFocus = true }
        .digitalCrownRotation(
            $crownValue,
            from: -100_000,
            through: 100_000,
            by: 1,
            sensitivity: .low,
            isContinuous: true,
            isHapticFeedbackEnabled: true
        )
        .digitalCrownAccessory(.hidden)
        .onChange(of: crownValue) { _, newValue in
            handleCrown(newValue)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    MenuView()
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Verlauf und Einstellungen")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsNewMatchDialog = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!state.hasStarted)
                .accessibilityLabel("Neues Match")
            }
        }
        .confirmationDialog("Neues Match starten?", isPresented: $showsNewMatchDialog, titleVisibility: .visible) {
            Button("Neues Match") {
                controller.startNewMatch()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Das aktuelle Match wird im Verlauf gespeichert.")
        }
        .task {
            await controller.workout.requestAuthorization()
        }
    }

    private func field(for team: Team) -> some View {
        ScoreField(
            team: team,
            label: state.pointLabel(for: team),
            banner: banner(for: team),
            isEnabled: !state.isFinished
        ) {
            controller.score(team)
        }
        .padding(.vertical, 2)
    }

    private func banner(for team: Team) -> String? {
        guard let highlight = controller.highlight, highlight.team == team else { return nil }
        return highlight.title
    }

    // MARK: - Undo gestures

    private var swipeToUndo: some Gesture {
        DragGesture(minimumDistance: 25)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if abs(dx) > 40, abs(dx) > abs(dy) * 1.5 {
                    controller.undo()
                }
            }
    }

    private func handleCrown(_ value: Double) {
        if value > crownAnchor {
            // Turning forward just moves the reference point.
            crownAnchor = value
        } else if crownAnchor - value >= crownUndoThreshold {
            crownAnchor = value
            controller.undo()
        }
    }
}

/// Shown once a match is decided.
private struct MatchResultOverlay: View {
    let state: MatchState
    let onNewMatch: () -> Void

    private var didWin: Bool { state.winner == .me }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: didWin ? "trophy.fill" : "flag.checkered")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(didWin ? .yellow : .white)
                .symbolEffect(.bounce, value: state.winner)

            Text(didWin ? "Gewonnen!" : "Verloren")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text(state.completedSets.map(\.gamesText).joined(separator: "  "))
                .font(Theme.scoreFont(size: 15))
                .foregroundStyle(.secondary)

            Button("Neues Match", action: onNewMatch)
                .buttonStyle(.glassProminent)
                .tint(didWin ? Theme.me : Theme.opponent)
                .padding(.top, 4)

            Text("Krone zurückdrehen zum Korrigieren")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .background(.black.opacity(0.4))
    }
}
