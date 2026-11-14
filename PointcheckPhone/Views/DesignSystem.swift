import SwiftUI

// Calm, finance-app inspired building blocks: big numbers, quiet grouped cards,
// colour only where it carries meaning (up = green, down = red).

/// Grouped card like in Apple's Settings / Trade Republic lists.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}

/// Small uppercase label above a group ("SPIELSTÄRKE").
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(.secondary)
    }
}

/// Ball-based loading indicator (replaces spinners).
struct BallLoader: View {
    var size: CGFloat = 22
    var body: some View {
        BouncingBall(size: size).frame(height: size * 1.9)
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
    var fire: Int = 0

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, tint: tint, fire: fire)
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
    /// 0 = still, 1 = subtle flicker, 2 = flicker with glow (win streaks).
    var fire: Int = 0

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(tint == Theme.lime ? Theme.onAccent : Color.white)
            .frame(width: size, height: size)
            .background(tint, in: .rect(cornerRadius: size * 0.28, style: .continuous))
            .modifier(Flicker(level: fire, tint: tint))
    }
}

/// Subtle flicker (and glow) for the streak flame.
private struct Flicker: ViewModifier {
    let level: Int
    let tint: Color

    func body(content: Content) -> some View {
        if level == 0 {
            content
        } else {
            PhaseAnimator([0, 1, 2]) { phase in
                content
                    .scaleEffect(phase == 1 ? 1.06 : phase == 2 ? 0.97 : 1)
                    .opacity(phase == 2 ? 0.88 : 1)
                    .shadow(color: level >= 2 ? tint.opacity(phase == 1 ? 0.7 : 0.35) : .clear, radius: phase == 1 ? 12 : 6)
            } animation: { _ in .easeInOut(duration: 0.5) }
        }
    }
}

/// Hairline divider inset to the row text (after the icon tile).
struct RowDivider: View {
    var inset: CGFloat = 62

    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, inset)
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
        modifier(ProfileNavigation())
    }
}

/// Registers the profile destinations once per tab and provides the zoom namespace.
private struct ProfileNavigation: ViewModifier {
    @Namespace private var zoom

    func body(content: Content) -> some View {
        content
            .environment(\.zoomNamespace, zoom)
            .navigationDestination(for: UUID.self) { id in
                ProfileView(profileID: id)
                    .zoomDestination(id, in: zoom)
                    .environment(\.zoomNamespace, zoom)
            }
            .navigationDestination(for: PeopleListRoute.self) { PeopleListView(route: $0).environment(\.zoomNamespace, zoom) }
    }
}

extension View {
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
    @State private var errorText: String?

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            HStack(spacing: 6) {
                if isWorking {
                    ProgressView().controlSize(.mini)
                } else if relation == .following {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .transition(.scale.combined(with: .opacity))
                        .symbolEffect(.bounce, value: relation)
                }
                Text(relation.buttonTitle)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
            }
            .frame(minWidth: compact ? 0 : 110)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, 7)
            .background(background, in: .capsule)
            .foregroundStyle(relation == .none ? Theme.onAccent : Color.primary)
            .contentShape(.capsule)
        }
        .buttonStyle(.pressScale)
        .disabled(isWorking || relation == .self)
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: relation)
        .sensoryFeedback(.impact(weight: .light), trigger: relation)
        .alert("Das hat nicht geklappt", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private var background: AnyShapeStyle {
        relation == .none ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceRaised)
    }

    private func toggle() async {
        // The demo player lives only on this device.
        if profileID == DemoProfile.id {
            DemoProfile.isFollowed.toggle()
            relation = DemoProfile.isFollowed ? .following : .none
            return
        }
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
            errorText = "Prüf deine Internetverbindung und versuch es noch einmal."
        }
    }
}

/// One person in a list (followers, search, suggestions), with photo and optional button.
struct PersonListRow: View {
    let person: PersonRow
    var subtitle: String?
    var showsFollowButton = true
    @Environment(AccountService.self) private var account
    @Environment(\.zoomNamespace) private var zoomNamespace
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
                        .zoomSource(person.profileID, in: zoomNamespace)
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
            BouncingBall()
                .frame(height: 84)
            Text(title)
                .font(.title3.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.accent)
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
    var delay: Double = 0
    var format: (Double) -> String = { Int($0.rounded()).formatted() }
    @State private var shown: Double = 0

    var body: some View {
        Text(format(shown))
            .contentTransition(.numericText(value: shown))
            .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.9).delay(delay)) { shown = value } }
            .onChange(of: value) { _, new in withAnimation(.snappy) { shown = new } }
    }
}

// MARK: - Zoom transitions

/// Namespace for zoom transitions (avatar → profile, tile → detail), shared per tab.
struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Marks this view as the source of a zoom transition for `id` (no-op without a namespace).
    @ViewBuilder
    func zoomSource(_ id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Lets this destination grow out of its `zoomSource` (no-op without a namespace).
    @ViewBuilder
    func zoomDestination(_ id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

// MARK: - Skeleton loading

/// Grey placeholder with a moving shimmer.
struct SkeletonBlock: View {
    var height: CGFloat = 16
    var width: CGFloat? = nil
    var radius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.surface)
            .frame(width: width, height: height)
            .overlay {
                PhaseAnimator([false, true]) { phase in
                    LinearGradient(colors: [.clear, Color.primary.opacity(0.07), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 160)
                        .offset(x: phase ? 320 : -320)
                } animation: { _ in .linear(duration: 1.3) }
            }
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Placeholder for a feed entry or a list row.
struct SkeletonRow: View {
    var showsImage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SkeletonBlock(height: 40, width: 40, radius: 20)
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBlock(height: 12, width: 140)
                    SkeletonBlock(height: 10, width: 80)
                }
            }
            if showsImage {
                SkeletonBlock(height: 90, radius: 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Bouncing ball (empty states)

/// A tennis ball that slowly bounces in place.
struct BouncingBall: View {
    var size: CGFloat = 44

    var body: some View {
        PhaseAnimator([0, 1]) { phase in
            VStack(spacing: 6) {
                Image(systemName: "tennisball.fill")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(Theme.ball)
                    .scaleEffect(x: phase == 1 ? 1.06 : 1, y: phase == 1 ? 0.94 : 1)
                    .offset(y: phase == 1 ? 10 : -10)
                Ellipse()
                    .fill(Color.primary.opacity(phase == 1 ? 0.14 : 0.06))
                    .frame(width: phase == 1 ? size * 1.0 : size * 0.7, height: 8)
            }
        } animation: { phase in
            phase == 1 ? .easeIn(duration: 0.55) : .easeOut(duration: 0.55)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Pull to refresh with a tennis ball

/// Replaces the system spinner: a ball spins while pulling and bounces when data arrived.
struct TennisBallRefresh: ViewModifier {
    let action: () async -> Void
    @State private var pull: CGFloat = 0
    @State private var isRefreshing = false
    @State private var bounce = 0
    private let threshold: CGFloat = 80

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                -(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, offset in
                if !isRefreshing { pull = max(0, offset) }
            }
            .onScrollPhaseChange { old, new in
                guard old == .interacting, new != .interacting, pull > threshold, !isRefreshing else { return }
                Task { await refresh() }
            }
            .overlay(alignment: .top) {
                let progress = min(pull / threshold, 1)
                Image(systemName: "tennisball.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.ball)
                    .rotationEffect(.degrees(Double(pull) * 3))
                    .scaleEffect(isRefreshing ? 1 : 0.5 + progress * 0.5)
                    .opacity(isRefreshing ? 1 : Double(progress))
                    .keyframeAnimator(initialValue: 0.0, trigger: bounce) { view, y in
                        view.offset(y: y)
                    } keyframes: { _ in
                        SpringKeyframe(-18, duration: 0.18)
                        SpringKeyframe(0, duration: 0.3, spring: .bouncy)
                    }
                    .padding(.top, 6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .safeAreaPadding(.top, isRefreshing ? 44 : 0)
            .animation(.snappy, value: isRefreshing)
            .sensoryFeedback(.impact(weight: .light), trigger: isRefreshing)
    }

    private func refresh() async {
        isRefreshing = true
        await action()
        bounce += 1
        try? await Task.sleep(for: .seconds(0.5))
        isRefreshing = false
        pull = 0
    }
}

extension View {
    func tennisBallRefresh(_ action: @escaping () async -> Void) -> some View {
        modifier(TennisBallRefresh(action: action))
    }
}


/// Fades and slides a view in on first appearance, optionally staggered.
struct RevealOnAppear: ViewModifier {
    var delay: Double = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle().frame(width: proxy.size.width * (reduceMotion ? 1 : progress))
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

/// Filled capsule in the neutral accent with guaranteed readable text
/// (black on white in dark mode, white on black in light mode).
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let small = controlSize == .small || controlSize == .mini
        configuration.label
            .font((small ? Font.subheadline : .body).weight(.semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, small ? 14 : 20)
            .padding(.vertical, small ? 7 : 12)
            .background(Theme.accent, in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AccentButtonStyle {
    static var accent: AccentButtonStyle { AccentButtonStyle() }
}

/// Quiet secondary button on a surface (always-readable primary label).
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.surfaceRaised, in: .capsule)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

/// Thin full-width separator between feed items.
struct FeedDivider: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
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


// MARK: - Ball as a brand moment

/// A ball drops from above, bounces once on the content and rolls out – shown briefly after
/// something succeeded (match saved, post published). Nothing else in the app uses this motion.
struct BallDrop: ViewModifier {
    let trigger: Int
    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if phase > 0 {
                    GeometryReader { proxy in
                        Image(systemName: "tennisball.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Theme.lime)
                            .shadow(color: Theme.lime.opacity(0.5), radius: 12)
                            .scaleEffect(x: phase == 2 ? 1.15 : 1, y: phase == 2 ? 0.85 : 1)
                            .position(x: proxy.size.width / 2 + (phase == 3 ? proxy.size.width : 0),
                                      y: phase == 1 ? -40 : proxy.size.height * 0.42)
                            .rotationEffect(.degrees(phase == 3 ? 540 : 0))
                            .opacity(phase == 3 ? 0 : 1)
                    }
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: trigger) { _, _ in
                guard !reduceMotion else { return }
                Task { @MainActor in
                    phase = 1
                    try? await Task.sleep(for: .milliseconds(20))
                    withAnimation(.easeIn(duration: 0.32)) { phase = 2 }
                    try? await Task.sleep(for: .milliseconds(340))
                    withAnimation(.easeOut(duration: 0.5)) { phase = 3 }
                    try? await Task.sleep(for: .milliseconds(520))
                    phase = 0
                }
            }
            .sensoryFeedback(.success, trigger: trigger)
    }
}

extension View {
    /// Plays the ball drop whenever `trigger` changes.
    func ballDrop(trigger: Int) -> some View { modifier(BallDrop(trigger: trigger)) }
}
