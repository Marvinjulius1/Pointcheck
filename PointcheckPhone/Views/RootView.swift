import SwiftData
import SwiftUI

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
            Tab("Aktivität", systemImage: "bell.fill") {
                NavigationStack { ActivityView() }
            }
            .badge(account.activityCount)
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

/// Profile tab: sign-in while signed out, otherwise my own profile.
private struct MyProfileTab: View {
    @Environment(AccountService.self) private var account

    var body: some View {
        AccountGate {
            if let id = account.userID {
                ProfileView(profileID: id)
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
