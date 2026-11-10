import PadelScoring
import SwiftUI

/// One big tappable Liquid Glass field (red = opponent, green = us).
struct ScoreField: View {
    let team: Team
    let label: String
    /// "Spiel" / "Satz" / "Match" while this team just won something.
    let banner: String?
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var tapCount = 0

    private var tint: Color { Theme.color(for: team) }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.fieldCornerRadius, style: .continuous)
    }
    private var isHighlighted: Bool { banner != nil }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Text(label)
                    .font(Theme.scoreFont(size: min(proxy.size.height * 0.62, 64)))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)

                VStack {
                    HStack {
                        Text(Theme.title(for: team).uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                    }
                    Spacer()
                    if let banner {
                        Text(banner.uppercased())
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.22), in: .capsule)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
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
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: banner)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Theme.title(for: team)): \(label)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Punkt für \(Theme.title(for: team))")
        .accessibilityAction { if isEnabled { action() } }
    }
}
