import SwiftUI

// Calm, finance-app inspired building blocks: big numbers, quiet grouped cards,
// colour only where it carries meaning (up = green, down = red).

/// Grouped card like in Apple's Settings / Trade Republic lists.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.surface, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

/// Bold section title with an optional trailing link.
struct SectionTitle<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
            Spacer()
            trailing
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 4)
        .padding(.top, 12)
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// Row with a tinted icon tile, title, optional subtitle and a trailing value.
struct MetricRow: View {
    let symbol: String
    var tint: Color = .accentColor
    let title: String
    var subtitle: String?
    let value: String
    var valueTint: Color = .primary

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(valueTint)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Rounded square with an SF Symbol, like the icons in Apple's Settings.
struct IconTile: View {
    let symbol: String
    var tint: Color = .accentColor
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: size, height: size)
            .background(tint, in: .rect(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Hairline divider inset to the row text (after the icon tile).
struct RowDivider: View {
    var inset: CGFloat = 62

    var body: some View {
        Divider().padding(.leading, inset)
    }
}

/// "▲ 34 (2,3 %)" in green or red.
struct ChangeLabel: View {
    let change: Double
    let base: Double
    var suffix: String?

    private var isUp: Bool { change >= 0 }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.footnote.weight(.bold))
            Text(changeText)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
            if let suffix {
                Text(suffix)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(isUp ? Theme.me : Theme.opponent)
    }

    private var changeText: String {
        let points = Int(change.rounded())
        let percent = base > 0 ? abs(change) / base : 0
        let sign = points >= 0 ? "+" : "−"
        return "\(sign)\(abs(points)) (\(percent.formatted(.percent.precision(.fractionLength(1)))))"
    }
}

/// Row of capsule buttons to pick a time range ("1W 1M 3M 1J Max").
struct RangePicker<Value: Hashable & Identifiable>: View {
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 4) {
            ForEach(values) { value in
                let selected = value == selection
                Button {
                    withAnimation(.snappy) { selection = value }
                } label: {
                    Text(title(value))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Color(.systemBackground) : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                Capsule().fill(tint)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Navigation

/// Follower / following list of a profile.
struct PeopleListRoute: Hashable {
    enum Kind: Hashable {
        case followers, following

        var title: String {
            switch self {
            case .followers: "Follower"
            case .following: "Folge ich"
            }
        }
    }

    let kind: Kind
    let profileID: UUID
}

extension View {
    /// Registers the profile-related destinations. Apply once at the root of each tab's
    /// NavigationStack (nested registrations would be ignored with a warning).
    func profileNavigation() -> some View {
        self
            .navigationDestination(for: UUID.self) { ProfileView(profileID: $0) }
            .navigationDestination(for: PeopleListRoute.self) { PeopleListView(route: $0) }
    }
}

// MARK: - Social building blocks

/// Profile photo with initial fallback.
struct ProfilePhoto: View {
    let name: String
    var url: URL?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(Theme.surface)
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

/// "Folgen" / "Folge ich" / "Angefragt" – the relation decides look and action.
struct FollowButton: View {
    let profileID: UUID
    @Binding var relation: FollowRelation
    var compact = false
    @Environment(AccountService.self) private var account
    @State private var isWorking = false

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            HStack(spacing: 6) {
                if isWorking {
                    ProgressView().controlSize(.mini)
                } else if relation == .following {
                    Image(systemName: "checkmark").font(.caption.weight(.bold))
                }
                Text(relation.buttonTitle)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(minWidth: compact ? 0 : 110)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, 7)
            .background(background, in: .capsule)
            .foregroundStyle(relation == .none ? Theme.onAccent : Color.primary)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(isWorking || relation == .self)
        .animation(.snappy, value: relation)
        .sensoryFeedback(.success, trigger: relation == .following)
    }

    private var background: AnyShapeStyle {
        relation == .none ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(.tertiarySystemFill))
    }

    private func toggle() async {
        isWorking = true
        defer { isWorking = false }
        do {
            switch relation {
            case .none:
                relation = try await account.follow(profileID)
            case .following, .pending:
                try await account.unfollow(profileID)
                relation = .none
            case .self:
                break
            }
        } catch {
            // keep the old state
        }
    }
}

/// One person in a list (followers, search, suggestions), with photo and optional button.
struct PersonListRow: View {
    let person: PersonRow
    var subtitle: String?
    var showsFollowButton = true
    @Environment(AccountService.self) private var account
    @State private var relation: FollowRelation

    init(person: PersonRow, subtitle: String? = nil, showsFollowButton: Bool = true) {
        self.person = person
        self.subtitle = subtitle
        self.showsFollowButton = showsFollowButton
        _relation = State(initialValue: person.relation ?? .none)
    }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: person.profileID) {
                HStack(spacing: 12) {
                    ProfilePhoto(name: person.displayName, url: account.imageURL(person.avatarPath, bucket: .avatars))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let line = subtitle ?? person.username.map({ "@\($0)" }) {
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if showsFollowButton, relation != .self {
                FollowButton(profileID: person.profileID, relation: $relation, compact: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// Big empty-state block with icon, title, text and an optional action.
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 72, height: 72)
                .background(Theme.surface, in: .circle)
            Text(title)
                .font(.title3.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 44)
    }
}

/// Result line "6:4  3:6  [10:8]" with a won/lost dot, used in feed and profile cards.
struct ResultLine: View {
    let text: String
    let won: Bool
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(won ? Theme.me : Theme.opponent)
                .frame(width: 10, height: 10)
            Text(text)
                .font(Theme.scoreFont(size: size))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

extension Date {
    /// "vor 5 Min.", "gestern", "3. Nov."
    var relativeShort: String {
        let seconds = Date.now.timeIntervalSince(self)
        if seconds < 60 { return "gerade eben" }
        if seconds < 3600 { return "vor \(Int(seconds / 60)) Min." }
        if seconds < 86_400 { return "vor \(Int(seconds / 3600)) Std." }
        if Calendar.current.isDateInYesterday(self) { return "gestern" }
        if seconds < 7 * 86_400 { return "vor \(Int(seconds / 86_400)) Tagen" }
        return formatted(.dateTime.day().month(.abbreviated))
    }
}

// MARK: - Motion (Trade-Republic-style)

/// Counts a number up on appear and whenever it changes.
struct CountUpText: View {
    let value: Double
    var format: (Double) -> String = { Int($0.rounded()).formatted() }
    @State private var shown: Double = 0

    var body: some View {
        Text(format(shown))
            .contentTransition(.numericText(value: shown))
            .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.9)) { shown = value } }
            .onChange(of: value) { _, new in withAnimation(.snappy) { shown = new } }
    }
}

/// Fades and slides a view in on first appearance, optionally staggered.
struct RevealOnAppear: ViewModifier {
    var delay: Double = 0
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func revealOnAppear(delay: Double = 0) -> some View { modifier(RevealOnAppear(delay: delay)) }

    /// Draws a chart (or anything) from left to right on appear.
    func drawOnAppear(duration: Double = 0.9) -> some View { modifier(DrawOnAppear(duration: duration)) }
}

struct DrawOnAppear: ViewModifier {
    let duration: Double
    @State private var progress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle().frame(width: proxy.size.width * progress)
                }
            }
            .onAppear { withAnimation(.easeOut(duration: duration)) { progress = 1 } }
    }
}

/// Buttons shrink slightly while pressed.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressScaleStyle {
    static var pressScale: PressScaleStyle { PressScaleStyle() }
}

/// Thin full-width separator between feed items.
struct FeedDivider: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5)
    }
}

/// Instagram-style avatar bubble for the row at the top of the feed.
struct AvatarBubble: View {
    let name: String
    var url: URL?
    var caption: String?
    var highlighted = false

    var body: some View {
        VStack(spacing: 6) {
            ProfilePhoto(name: name, url: url, size: 64)
                .padding(3)
                .overlay(
                    Circle().stroke(highlighted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.hairline), lineWidth: highlighted ? 2 : 1)
                )
            Text(caption ?? name)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 72)
        }
    }
}
