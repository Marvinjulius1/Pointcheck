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
            Tab("Übersicht", systemImage: "chart.line.uptrend.xyaxis") {
                NavigationStack { OverviewView() }
            }
            Tab("Matches", systemImage: "list.bullet") {
                NavigationStack { MatchesView() }
            }
            Tab("Personen", systemImage: "person.2.fill") {
                NavigationStack { PeopleView() }
            }
            Tab("Erfolge", systemImage: "trophy.fill") {
                NavigationStack { BadgesView() }
            }
            Tab("Konto", systemImage: "person.crop.circle") {
                NavigationStack { AccountView() }
            }
            .badge(account.openConfirmations.count)
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

/// Shown while no match has arrived from the watch yet.
struct NoMatchesView: View {
    @Environment(WatchSync.self) private var sync

    var body: some View {
        ContentUnavailableView {
            Label("Noch keine Matches", systemImage: "applewatch")
        } description: {
            Text(sync.isWatchAppInstalled
                 ? "Spiel ein Match mit Pointcheck auf deiner Apple Watch. Danach erscheint es hier automatisch."
                 : "Installiere Pointcheck auf deiner Apple Watch und zähle dort deine Matches.")
        } actions: {
            if sync.isWatchAppInstalled {
                Button("Von der Watch laden") { sync.requestAll() }
                    .buttonStyle(.glassProminent)
            }
        }
    }
}
