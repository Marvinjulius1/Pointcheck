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
    /// Diameter of the two round glass buttons beside the score in the centre strip.
    private let controlSize: CGFloat = 32

    private var state: MatchState { controller.state }

    var body: some View {
        // The outer reader measures the top safe area (system clock). The inner layout
        // ignores the safe area so the red field reaches the top edge; the clock floats
        // on its glass (third-party apps cannot hide it).
        GeometryReader { outer in
            let clockHeight = outer.safeAreaInsets.top
            GeometryReader { proxy in
                let fieldHeight = max(0, (proxy.size.height - statusHeight) / 2)
                let scoreSize = Self.scoreSize(fieldHeight: fieldHeight, clockHeight: clockHeight)
                VStack(spacing: 0) {
                    field(for: .opponent, scoreSize: scoreSize)
                        .frame(height: fieldHeight)
                    centerStrip
                        .frame(height: statusHeight)
                    field(for: .me, scoreSize: scoreSize)
                        .frame(height: fieldHeight)
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
        .toolbar {
            // watchOS only centres the system clock when both top-bar slots are filled
            // (Apple Developer Forums, thread 775912). The buttons live in the centre strip,
            // so invisible, non-interactive placeholders keep the clock in the middle.
            ToolbarItem(placement: .topBarLeading) { clockPlaceholder }
            ToolbarItem(placement: .topBarTrailing) { clockPlaceholder }
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

    private var clockPlaceholder: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Menu button at the left edge, sets/games in the middle, "new match" at the right edge.
    private var centerStrip: some View {
        HStack(spacing: 4) {
            NavigationLink {
                MenuView()
            } label: {
                controlIcon("list.bullet")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Verlauf und Einstellungen")

            MatchStatusView(state: state, highlight: controller.highlight)
                .frame(maxWidth: .infinity)

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

    /// Shared score size. The numbers sit at the centre-facing edge, so the red number
    /// may grow upwards until it reaches the clock band.
    static func scoreSize(fieldHeight: CGFloat, clockHeight: CGFloat) -> CGFloat {
        // A line of SF Pro Rounded digits: ~0.2 pt below the baseline + ~0.72 pt cap height per point.
        let glyphExtentRatio: CGFloat = 0.92
        let room = fieldHeight - ScoreField.edgePadding - clockHeight - 2
        return max(24, min(room / glyphExtentRatio, fieldHeight * 1.1, 96))
    }

    private func field(for team: Team, scoreSize: CGFloat) -> some View {
        ScoreField(
            team: team,
            label: state.pointLabel(for: team),
            isHighlighted: controller.highlight?.team == team,
            isEnabled: !state.isFinished,
            scoreFontSize: scoreSize
        ) {
            controller.score(team)
        }
        // Only a small gap towards the centre strip; the outer edges touch the display edge.
        .padding(team == .opponent ? .bottom : .top, 2)
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
