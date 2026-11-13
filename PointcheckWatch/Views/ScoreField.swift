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
    /// This team serves the next point (yellow ball next to the score).
    var isServing = false
    /// Set before the first point: tapping the ball hands the serve to the other team.
    var onServeTap: (() -> Void)?
    let action: () -> Void

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var tapCount = 0

    private var tint: Color { Theme.color(for: team) }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.fieldCornerRadius, style: .continuous)
    }
    /// Gap between the number and the edge facing the centre strip.
    static let edgePadding: CGFloat = 2
    static let serveSlotWidth: CGFloat = 30
    static let tennisBallYellow = Color(red: 0.86, green: 1.0, blue: 0.31)

    @ViewBuilder
    private var serveSlot: some View {
        let ball = Image(systemName: "tennisball.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Self.tennisBallYellow)
            .shadow(color: Self.tennisBallYellow.opacity(0.6), radius: 4)
            .frame(width: Self.serveSlotWidth, height: Self.serveSlotWidth)
            .contentShape(.circle)

        Group {
            if isServing {
                if let onServeTap {
                    Button(action: onServeTap) {
                        ball.symbolEffect(.pulse, options: .repeating)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Aufschlag \(Theme.title(for: team)). Antippen zum Wechseln")
                } else {
                    ball.accessibilityLabel("Aufschlag \(Theme.title(for: team))")
                }
            } else {
                Color.clear
            }
        }
        .frame(width: Self.serveSlotWidth, height: Self.serveSlotWidth)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isServing)
    }

    var body: some View {
        GeometryReader { proxy in
            // The number sits on the edge facing the centre strip: bottom of the red field,
            // top of the green field – close to the sets/games and away from the clock.
            HStack(spacing: 0) {
                serveSlot
                Spacer(minLength: 0)
                Text(label)
                    .font(Theme.scoreFont(size: scoreFontSize))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                Spacer(minLength: 0)
                // Mirrors the serve slot so the number stays centred.
                Color.clear.frame(width: Self.serveSlotWidth, height: 1)
            }
            .padding(team == .opponent ? .bottom : .top, ScoreField.edgePadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: team == .opponent ? .bottom : .top)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .modifier(TintedGlass(tint: tint.opacity(isHighlighted ? 0.75 : 0.5), shape: shape))
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
        .accessibilityLabel("\(Theme.title(for: team)): \(label)\(isServing ? ", Aufschlag" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Punkt für \(Theme.title(for: team))")
        .accessibilityAction { if isEnabled { action() } }
        .accessibilityAction(named: "Aufschlag wechseln") { onServeTap?() }
    }
}


/// Tinted Liquid Glass on watchOS 26+, a flat tinted fill on older watches.
private struct TintedGlass<S: Shape>: ViewModifier {
    let tint: Color
    let shape: S

    func body(content: Content) -> some View {
        if #available(watchOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            content.background(shape.fill(tint.opacity(0.6)))
        }
    }
}
