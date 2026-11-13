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

/// Shown while no match has arrived from the watch yet.
struct NoMatchesView: View {
    @Environment(WatchSync.self) private var sync

    var body: some View {
        EmptyState(
            symbol: "applewatch",
            title: "Noch keine Matches",
            message: sync.isWatchAppInstalled
                ? "Spiel ein Match mit Pointcheck auf deiner Apple Watch. Danach erscheint es hier automatisch."
                : "Installiere Pointcheck auf deiner Apple Watch und zähle dort deine Matches.",
            actionTitle: sync.isWatchAppInstalled ? "Von der Watch laden" : nil,
            action: sync.isWatchAppInstalled ? { sync.requestAll() } : nil
        )
    }
}
