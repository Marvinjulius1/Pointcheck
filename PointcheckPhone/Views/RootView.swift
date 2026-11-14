import PadelStats
import SwiftData
import SwiftUI

/// Black screen with the ball dropping in and the wordmark fading up – the moment between
/// launch image and first screen. Only shown while the session is being restored.
struct LoadingScreen: View {
    @State private var landed = false
    @State private var showsWordmark = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            // Faint court light behind the ball.
            Circle()
                .fill(Theme.lime.opacity(0.14))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .opacity(landed ? 1 : 0)
            VStack(spacing: 26) {
                if landed {
                    BouncingBall(size: 48)
                        .frame(height: 100)
                        .transition(.identity)
                } else {
                    Image(systemName: "tennisball.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(Theme.ball)
                        .frame(height: 100)
                        .offset(y: -320)
                        .transition(.identity)
                }
                VStack(spacing: 8) {
                    Text("Pointcheck")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Jeder Punkt zählt.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .opacity(showsWordmark ? 1 : 0)
                .offset(y: showsWordmark ? 0 : 12)
            }
        }
        .task {
            if reduceMotion {
                landed = true
                showsWordmark = true
                return
            }
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.interpolatingSpring(stiffness: 170, damping: 11)) { landed = true }
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { showsWordmark = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pointcheck wird geladen")
    }
}

/// The app is only usable with an account: welcome screen until signed in.
struct AppGate: View {
    @Environment(AccountService.self) private var account

    var body: some View {
        ZStack {
            switch account.state {
            case .loading:
                LoadingScreen()
                    .transition(.opacity)
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
