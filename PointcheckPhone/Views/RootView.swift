import SwiftData
import SwiftUI

/// The app is only usable with an account: welcome screen until signed in.
struct AppGate: View {
    @Environment(AccountService.self) private var account

    var body: some View {
        ZStack {
            switch account.state {
            case .loading:
                Theme.background.ignoresSafeArea()
                ProgressView()
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

    /// Reload training data / upload new matches when matches arrive or access changes.
    private struct RefreshKey: Hashable {
        let matchCount: Int
        let foreignCount: Int
        let hasHealthAccess: Bool
        let isSignedIn: Bool
    }

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                NavigationStack { HomeView() }
            }
            Tab("Matches", systemImage: "figure.tennis") {
                NavigationStack { MatchesView() }
            }
            Tab("Suche", systemImage: "magnifyingglass") {
                NavigationStack { SearchView() }
            }
            Tab("Profil", systemImage: "person.crop.circle.fill") {
                NavigationStack { MyProfileTab() }
            }
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
        }
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
