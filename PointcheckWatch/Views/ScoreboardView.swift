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
    /// Diameter of the two round glass buttons at the bottom.
    private let controlSize: CGFloat = 32
    private let controlBottomPadding: CGFloat = 6
    private var controlsInset: CGFloat { controlSize + controlBottomPadding + 4 }

    private var state: MatchState { controller.state }

    var body: some View {
        // The outer reader only measures the top safe area (system clock).
        // The inner layout ignores the safe area so the red field reaches the top edge;
        // the clock floats on its glass (third-party apps cannot hide it).
        GeometryReader { outer in
            let topInset = outer.safeAreaInsets.top
            GeometryReader { proxy in
                let fieldHeight = max(0, (proxy.size.height - statusHeight) / 2)
                // Same score size in both fields: based on the smaller visible area.
                let visibleHeight = fieldHeight - max(topInset, controlsInset)
                let scoreSize = min(max(visibleHeight, 0) * 0.62, 64)
                VStack(spacing: 0) {
                    field(for: .opponent, scoreSize: scoreSize, topInset: topInset, bottomInset: 0)
                        .frame(height: fieldHeight)
                    MatchStatusView(state: state, highlight: controller.highlight)
                        .frame(height: statusHeight)
                    field(for: .me, scoreSize: scoreSize, topInset: 0, bottomInset: controlsInset)
                        .frame(height: fieldHeight)
                }
                .overlay(alignment: .bottom) {
                    bottomControls
                        .padding(.bottom, controlBottomPadding)
                }
            }
            .padding(.horizontal, 2)
            .ignoresSafeArea()
        }
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

    /// Menu (history/settings) and "new match", centred at the bottom edge.
    private var bottomControls: some View {
        HStack(spacing: 14) {
            NavigationLink {
                MenuView()
            } label: {
                controlIcon("list.bullet")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Verlauf und Einstellungen")

            Button {
                showsNewMatchDialog = true
            } label: {
                controlIcon("plus")
            }
            .buttonStyle(.plain)
            .disabled(!state.hasStarted)
            .opacity(state.hasStarted ? 1 : 0.4)
            .accessibilityLabel("Neues Match")
        }
    }

    private func controlIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: controlSize, height: controlSize)
            .glassEffect(.regular.interactive(), in: .circle)
            .contentShape(.circle)
    }

    private func field(for team: Team, scoreSize: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        ScoreField(
            team: team,
            label: state.pointLabel(for: team),
            banner: banner(for: team),
            isEnabled: !state.isFinished,
            scoreFontSize: scoreSize,
            contentTopInset: topInset,
            contentBottomInset: bottomInset
        ) {
            controller.score(team)
        }
        // Only a small gap towards the centre strip; the outer edges touch the display edge.
        .padding(team == .opponent ? .bottom : .top, 2)
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
