import PadelScoring
import SwiftUI

/// One big tappable Liquid Glass field (red = opponent, green = us).
struct ScoreField: View {
    let team: Team
    let label: String
    /// Glows briefly after this team won a game, set or match.
    let isHighlighted: Bool
    let isEnabled: Bool
    /// Shared by both fields so the red and green numbers are always the same size.
    let scoreFontSize: CGFloat
    let action: () -> Void

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var tapCount = 0

    private var tint: Color { Theme.color(for: team) }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.fieldCornerRadius, style: .continuous)
    }
    /// Gap between the number and the edge facing the centre strip.
    static let edgePadding: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            // The number sits on the edge facing the centre strip: bottom of the red field,
            // top of the green field – close to the sets/games and away from the clock.
            Text(label)
                .font(Theme.scoreFont(size: scoreFontSize))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .padding(team == .opponent ? .bottom : .top, ScoreField.edgePadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: team == .opponent ? .bottom : .top)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .glassEffect(.regular.tint(tint.opacity(isHighlighted ? 0.75 : 0.5)).interactive(), in: shape)
            .background {
                // Colour underneath the glass gives the soft gradient glow.
                shape.fill(
                    LinearGradient(
                        colors: [tint.opacity(isLuminanceReduced ? 0.25 : 0.65), tint.opacity(isLuminanceReduced ? 0.1 : 0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .shadow(color: tint.opacity(isHighlighted ? 0.7 : 0), radius: 10)
            .scaleEffect(isHighlighted ? 1.03 : 1)
            .keyframeAnimator(initialValue: 1.0, trigger: tapCount) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(0.96, duration: 0.08)
                SpringKeyframe(1.0, duration: 0.25)
            }
            .contentShape(shape)
            .onTapGesture {
                guard isEnabled else { return }
                tapCount += 1
                action()
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: label)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isHighlighted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Theme.title(for: team)): \(label)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Punkt für \(Theme.title(for: team))")
        .accessibilityAction { if isEnabled { action() } }
    }
}
