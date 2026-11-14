import PadelStats
import SwiftData
import SwiftUI

/// Start screen: the wordmark POINT · CHECK with the red/green score pill from the app icon.
/// The pill counts up to 15:40 while the session is restored; a small ball bounces below.
struct LoadingScreen: View {
    /// Called once the intro has played (about 2.5 seconds).
    var onFinished: () -> Void = {}
    @State private var top = 0
    @State private var bottom = 0
    @State private var shown = false
    @State private var showsBall = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let red = LinearGradient(colors: [Color(red: 0.93, green: 0.33, blue: 0.30), Color(red: 0.72, green: 0.14, blue: 0.14)],
                                     startPoint: .top, endPoint: .bottom)
    private let green = LinearGradient(colors: [Color(red: 0.30, green: 0.78, blue: 0.40), Color(red: 0.10, green: 0.52, blue: 0.24)],
                                       startPoint: .top, endPoint: .bottom)

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 36) {
                HStack(spacing: 10) {
                    Text("POINT")
                    pill
                    Text("CHECK")
                }
                .font(.system(size: 40, weight: .heavy, design: .default))
                .foregroundStyle(.white)
                .scaleEffect(shown ? 1 : 0.92)
                .opacity(shown ? 1 : 0)

                BallLoader(size: 16)
                    .opacity(showsBall ? 1 : 0)
            }
        }
        .task { await play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pointcheck wird geladen")
    }

    /// Two stacked capsules: red 15 on top, green 40 below, like the app icon.
    private var pill: some View {
        VStack(spacing: 3) {
            score(top, fill: red)
            score(bottom, fill: green)
        }
    }

    private func score(_ value: Int, fill: LinearGradient) -> some View {
        Text("\(value)")
            .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .contentTransition(.numericText(value: Double(value)))
            .frame(width: 60, height: 26)
            .background(fill, in: .capsule)
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
    }

    private func play() async {
        if reduceMotion {
            top = 15; bottom = 40; shown = true; showsBall = true
            try? await Task.sleep(for: .seconds(1.2))
            onFinished()
            return
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { shown = true }
        try? await Task.sleep(for: .milliseconds(600))
        // Tennis points, like a rally: 15 · 15 · 30 · 40
        for (a, b) in [(15, 0), (15, 15), (15, 30), (15, 40)] {
            withAnimation(.snappy(duration: 0.3)) { top = a; bottom = b }
            try? await Task.sleep(for: .milliseconds(380))
        }
        withAnimation(.easeOut(duration: 0.4)) { showsBall = true }
        try? await Task.sleep(for: .milliseconds(700))
        onFinished()
    }
}

/// The app is only usable with an account: welcome screen until signed in.
struct AppGate: View {
    @Environment(AccountService.self) private var account
    /// The intro stays on screen until its animation has played, even if the session is restored faster.
    @State private var introDone = false

    private var showsIntro: Bool { account.state == .loading || !introDone }

    var body: some View {
        ZStack {
            if showsIntro {
                LoadingScreen { introDone = true }
                    .transition(.opacity)
                    .zIndex(1)
            } else {
                switch account.state {
                case .loading:
                    EmptyView()
                case .signedOut:
                    WelcomeView()
                        .transition(.opacity)
                case .resettingPassword:
                    NewPasswordView()
                        .transition(.opacity)
                case .signedIn:
                    RootView()
                        .transition(.opacity)
                }
            }
        }
        .animation(.smooth(duration: 0.5), value: showsIntro)
        .animation(.smooth(duration: 0.4), value: account.state == .signedIn)
    }
}

struct RootView: View {
    @Query private var stored: [StoredMatch]
    @Environment(HealthService.self) private var health
    @Environment(AccountService.self) private var account
    @Environment(BadgeTracker.self) private var badges
    @State private var selection: AppTab = .home

    enum AppTab: Hashable { case home, matches, search, profile }

    /// Reload training data / upload new matches when matches arrive or access changes.
    private struct RefreshKey: Hashable {
        let matchCount: Int
        let foreignCount: Int
        let hasHealthAccess: Bool
        let isSignedIn: Bool
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                NavigationStack { HomeView() }.tabSettle(selection)
            }
            Tab("Matches", systemImage: "figure.tennis", value: .matches) {
                NavigationStack { MatchesView() }.tabSettle(selection)
            }
            Tab("Suche", systemImage: "magnifyingglass", value: .search) {
                NavigationStack { SearchView() }.tabSettle(selection)
            }
            Tab("Profil", systemImage: "person.crop.circle.fill", value: .profile) {
                NavigationStack { MyProfileTab() }.tabSettle(selection)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .overlay(alignment: .bottom) {
            if let badge = badges.celebrating {
                BadgeCelebration(badge: badge) { badges.dismissCelebration() }
                    .padding(.bottom, 70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: badges.celebrating)
        .onChange(of: stored.count + account.foreignMatches.count, initial: true) { _, _ in
            badges.check(account.allMatches(local: stored.map(\.summary)))
        }
        .task(id: RefreshKey(
            matchCount: stored.count,
            foreignCount: account.foreignMatches.count,
            hasHealthAccess: health.hasRequestedAccess,
            isSignedIn: account.state == .signedIn
        )) {
            let local = stored.map(\.summary)
            await account.uploadNewMatches(local)
            await health.refresh(for: account.allMatches(local: local))
            WidgetBridge.update(account: account, matches: account.allMatches(local: local))
        }
    }
}

/// The tab content settles from 0.98 to 1 when its tab is selected.
private struct TabSettle: ViewModifier {
    let selection: RootView.AppTab
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: selection) { _, _ in
                scale = 0.98
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { scale = 1 }
            }
    }
}

private extension View {
    func tabSettle(_ selection: RootView.AppTab) -> some View { modifier(TabSettle(selection: selection)) }
}

/// Card that rises from the bottom, flips once (icon → text) and leaves after two seconds.
struct BadgeCelebration: View {
    let badge: Badge
    let onDone: () -> Void
    @State private var flipped = false

    var body: some View {
        ZStack {
            front.opacity(flipped ? 0 : 1)
                .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            back.opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(width: 280, height: 110)
        .background(Theme.surface, in: .rect(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .onTapGesture(perform: onDone)
        .task {
            try? await Task.sleep(for: .seconds(1.1))
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { flipped = true }
            try? await Task.sleep(for: .seconds(2.2))
            onDone()
        }
        .sensoryFeedback(.success, trigger: badge.id)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Erfolg freigeschaltet: \(badge.title). \(badge.detail)")
    }

    private var front: some View {
        HStack(spacing: 16) {
            Image(systemName: badge.symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 60, height: 60)
                .background(Theme.accent, in: .circle)
                .symbolEffect(.bounce, value: badge.id)
            VStack(alignment: .leading, spacing: 4) {
                Text("ERFOLG FREIGESCHALTET")
                    .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(badge.title).font(.headline)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var back: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(badge.title).font(.headline)
            Text(badge.detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

/// Profile tab: my own profile.
private struct MyProfileTab: View {
    @Environment(AccountService.self) private var account

    var body: some View {
        Group {
            if let id = account.userID {
                ProfileView(profileID: id)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Profil")
        .profileNavigation()
    }
}

/// Shown while there are no matches yet – with every way to add one.
struct NoMatchesView: View {
    @Environment(WatchSync.self) private var sync
    @Environment(PhoneMatchController.self) private var counter
    @State private var showsCounter = false
    @State private var showsManualEntry = false

    var body: some View {
        VStack(spacing: 8) {
            EmptyState(
                symbol: "figure.tennis",
                title: "Noch keine Matches",
                message: sync.isWatchAppInstalled
                    ? "Zähl auf der Apple Watch – oder direkt hier auf dem iPhone."
                    : "Du brauchst keine Apple Watch: Zähl live auf dem iPhone oder trag ein Ergebnis nachträglich ein."
            )
            VStack(spacing: 10) {
                Button { showsCounter = true } label: {
                    Label("Live zählen", systemImage: "plus.forwardslash.minus")
                        .font(.headline)
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.accent, in: .rect(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressScale)
                Button { showsManualEntry = true } label: {
                    Label("Ergebnis eintragen", systemImage: "square.and.pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.surface, in: .rect(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressScale)
                if sync.isWatchAppInstalled {
                    Button("Von der Watch laden") { sync.requestAll() }
                        .font(.subheadline.weight(.medium))
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 32)
        }
        .fullScreenCover(isPresented: $showsCounter) { LiveCounterView() }
        .sheet(isPresented: $showsManualEntry) { ManualResultView() }
    }
}
