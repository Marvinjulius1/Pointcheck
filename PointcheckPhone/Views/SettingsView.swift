import SwiftUI

/// App settings: upload, Health, account.
struct SettingsView: View {
    @Environment(AccountService.self) private var account
    @Environment(HealthService.self) private var health
    @Environment(WatchSync.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false
    @State private var showsPasswordSheet = false
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
