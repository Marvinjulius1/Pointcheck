import SwiftData
import SwiftUI

struct RootView: View {
    @Query private var stored: [StoredMatch]
    @Environment(HealthService.self) private var health
    @Environment(AccountService.self) private var account

    /// Reload training data when matches arrive or Health access was granted.
    private struct HealthRefreshKey: Hashable {
        let matchCount: Int
        let hasAccess: Bool
    }

    var body: some View {
        TabView {
            Tab("Übersicht", systemImage: "chart.bar.fill") {
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
        .task(id: HealthRefreshKey(matchCount: stored.count, hasAccess: health.hasRequestedAccess)) {
            await health.refresh(for: stored.map(\.summary))
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
