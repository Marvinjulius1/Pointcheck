import SwiftUI

/// App settings: upload, Health, account.
struct SettingsView: View {
    @Environment(AccountService.self) private var account
    @Environment(HealthService.self) private var health
    @Environment(WatchSync.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false
    @State private var showsPasswordSheet = false
    @State private var confirmDelete = false
    @State private var deleteError: String?
    @AppStorage(GoalSettings.weeklyTargetKey) private var weeklyTarget = 3
    @AppStorage(PushManager.enabledKey) private var pushEnabled = false
    @Environment(PhoneMatchController.self) private var counter
    @AppStorage(PhoneRules.bestOfKey) private var bestOf = 3
    @AppStorage(PhoneRules.goldenPointKey) private var goldenPoint = false
    @AppStorage(PhoneRules.superTiebreakKey) private var superTiebreak = false

    var body: some View {
        List {
            Section {
                Toggle("Neue Matches automatisch eintragen", isOn: Binding(
                    get: { account.autoUpload },
                    set: { account.autoUpload = $0 }
                ))
            } header: {
                Text("Matches")
            } footer: {
                Text("Neue Matches von deiner Watch werden hochgeladen, sobald sie auf dem iPhone ankommen. Gegner verlinkst du danach im Match unter „Spielstärke“.")
            }

            Section {
                Picker("Sätze", selection: $bestOf) {
                    Text("1 Satz").tag(1)
                    Text("Best of 3").tag(3)
                    Text("Best of 5").tag(5)
                }
                Toggle("Match-Tiebreak statt 3. Satz", isOn: $superTiebreak)
                    .disabled(bestOf == 1)
                Toggle("Golden Point bei 40:40", isOn: $goldenPoint)
            } header: {
                Text("Zählen auf dem iPhone")
            } footer: {
                Text(counter.state.hasStarted ? "Gilt ab dem nächsten Match." : "Die Watch hat ihre eigenen Einstellungen.")
            }
            .onChange(of: bestOf) { counter.applyRules() }
            .onChange(of: goldenPoint) { counter.applyRules() }
            .onChange(of: superTiebreak) { counter.applyRules() }

            Section {
                if health.isAvailable && !health.hasRequestedAccess {
                    Button("Mit Health verbinden") { Task { await health.requestAccess() } }
                } else {
                    LabeledContent("Health", value: health.isAvailable ? "Verbunden" : "Nicht verfügbar")
                }
                Button("Verlauf von der Watch laden") { sync.requestAll() }
                    .disabled(!sync.isWatchAppInstalled)
            } header: {
                Text("Daten")
            }

            Section {
                Stepper("Wochenziel: \(weeklyTarget) \(weeklyTarget == 1 ? "Match" : "Matches")", value: $weeklyTarget, in: 1...14)
            } header: {
                Text("Motivation")
            } footer: {
                Text("Der Ring auf der Startseite füllt sich mit jedem gespielten Match.")
            }

            Section {
                Toggle("Mitteilungen", isOn: $pushEnabled)
                    .onChange(of: pushEnabled) { _, on in
                        if on { Task { await PushManager.shared.enable() } }
                    }
            } header: {
                Text("Mitteilungen")
            } footer: {
                Text("Bestätigungen, neue Follower, Applaus und Revanche-Anfragen. Mitteilungen außerhalb der App kommen erst, sobald die App über TestFlight oder den App Store verteilt wird.")
            }

            Section {
                LabeledContent("E-Mail", value: account.client.auth.currentUser?.email ?? "–")
                Button("Passwort ändern") { showsPasswordSheet = true }
            } header: {
                Text("Konto")
            }

            Section {
                Button("Abmelden", role: .destructive) { confirmSignOut = true }
            } footer: {
                Text("Deine Matches bleiben auf Watch und iPhone erhalten.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button("Konto löschen", role: .destructive) { confirmDelete = true }
                    .font(.footnote)
                if let deleteError {
                    Text(deleteError).font(.caption).foregroundStyle(Theme.opponent)
                }
            }
            .padding(.vertical, 10)
        }
        .confirmationDialog("Konto endgültig löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Konto und alle Daten löschen", role: .destructive) {
                Task {
                    do { try await account.deleteAccount(); dismiss() }
                    catch { deleteError = "Löschen hat nicht geklappt. Prüf die Verbindung und versuch es erneut." }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Profil, Follower, Beiträge, Kommentare und hochgeladene Matches werden vom Server gelöscht. Die Matches auf Watch und iPhone bleiben. Das lässt sich nicht rückgängig machen.")
        }
        .navigationTitle("Einstellungen")
        .sheet(isPresented: $showsPasswordSheet) { ChangePasswordSheet() }
        .confirmationDialog("Abmelden?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) {
                Task { await account.signOut(); dismiss() }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}
