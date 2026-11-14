import SwiftUI

/// App settings: counting rules, goal, connections, notifications, account.
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

    private var autoUpload: Binding<Bool> {
        Binding(get: { account.autoUpload }, set: { account.autoUpload = $0 })
    }

    var body: some View {
        FormScreen(title: "Einstellungen", symbol: "slider.horizontal.3") {
            accountHeader

            FormGroup(title: "Zählen auf dem iPhone",
                      note: counter.state.hasStarted ? "Gilt ab dem nächsten Match. Die Watch hat ihre eigenen Regeln." : "Die Watch hat ihre eigenen Regeln.") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sätze").font(.body.weight(.medium))
                    PillPicker(selection: $bestOf, options: [(1, "1 Satz"), (3, "Best of 3"), (5, "Best of 5")])
                }
                .padding(16)
                RowDivider(inset: 16)
                ToggleRow(symbol: "scope", title: "Match-Tiebreak", subtitle: "Statt eines dritten Satzes bis 10", isOn: $superTiebreak)
                    .disabled(bestOf == 1)
                RowDivider()
                ToggleRow(symbol: "bolt.fill", title: "Golden Point", subtitle: "Bei 40:40 entscheidet ein Punkt", isOn: $goldenPoint)
            }
            .onChange(of: bestOf) { counter.applyRules() }
            .onChange(of: goldenPoint) { counter.applyRules() }
            .onChange(of: superTiebreak) { counter.applyRules() }

            FormGroup(title: "Wochenziel", note: "Der Ring auf der Startseite füllt sich mit jedem Match.") {
                VStack(spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(weeklyTarget)")
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                        Text(weeklyTarget == 1 ? "Match pro Woche" : "Matches pro Woche")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }
                    BallCounter(value: $weeklyTarget, range: 1...14)
                }
                .padding(16)
                .animation(.snappy, value: weeklyTarget)
            }

            FormGroup(title: "Matches & Daten",
                      note: "Neue Matches werden hochgeladen, sobald sie auf dem iPhone ankommen. Gegner verlinkst du danach im Match.") {
                ToggleRow(symbol: "icloud.and.arrow.up", title: "Automatisch eintragen", subtitle: "Neue Matches zählen sofort für deine Spielstärke", isOn: autoUpload)
                RowDivider()
                if health.isAvailable && !health.hasRequestedAccess {
                    ActionRow(symbol: "heart.fill", title: "Mit Health verbinden", subtitle: "Puls, Kalorien und Dauer pro Match") {
                        Task { await health.requestAccess() }
                    }
                } else {
                    FormRow(symbol: "heart.fill", title: "Health") {
                        StatusChip(text: health.isAvailable ? "Verbunden" : "Nicht verfügbar", on: health.isAvailable)
                    }
                }
                RowDivider()
                ActionRow(symbol: "applewatch", title: "Verlauf von der Watch laden",
                          subtitle: sync.isWatchAppInstalled ? nil : "Keine Watch-App gefunden",
                          trailingSymbol: "arrow.down.circle") { sync.requestAll() }
                    .disabled(!sync.isWatchAppInstalled)
                    .opacity(sync.isWatchAppInstalled ? 1 : 0.5)
            }

            FormGroup(title: "Mitteilungen",
                      note: "Bestätigungen, neue Follower, Applaus und Revanche-Anfragen. Außerhalb der App kommen sie erst mit TestFlight oder App Store an.") {
                ToggleRow(symbol: "bell.fill", title: "Mitteilungen", isOn: $pushEnabled)
                    .onChange(of: pushEnabled) { _, on in
                        if on { Task { await PushManager.shared.enable() } }
                    }
            }

            FormGroup(title: "Konto") {
                ActionRow(symbol: "key.fill", title: "Passwort ändern") { showsPasswordSheet = true }
                RowDivider()
                ActionRow(symbol: "rectangle.portrait.and.arrow.right", title: "Abmelden",
                          subtitle: "Deine Matches bleiben auf Watch und iPhone", trailingSymbol: nil) { confirmSignOut = true }
            }

            VStack(spacing: 6) {
                Button("Konto löschen") { confirmDelete = true }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.opponent)
                if let deleteError {
                    Text(deleteError).font(.caption).foregroundStyle(Theme.opponent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
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
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsPasswordSheet) { ChangePasswordSheet() }
        .confirmationDialog("Abmelden?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) {
                Task { await account.signOut(); dismiss() }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    /// Who is signed in: photo, name, e-mail.
    private var accountHeader: some View {
        HStack(spacing: 14) {
            ProfilePhoto(name: account.profile?.displayName ?? "",
                         url: account.imageURL(account.profile?.avatarPath, bucket: .avatars), size: 56)
                .overlay(Circle().stroke(Theme.lime, lineWidth: 2))
            VStack(alignment: .leading, spacing: 3) {
                Text(account.profile?.displayName ?? "Dein Konto")
                    .font(.headline)
                Text(account.client.auth.currentUser?.email ?? "–")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(16)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }
}
