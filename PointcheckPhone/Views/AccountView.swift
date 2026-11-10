import Charts
import PadelStats
import SwiftUI

/// "Konto" tab: sign-in, profile with visibility, open confirmations, leaderboard.
struct AccountView: View {
    @Environment(AccountService.self) private var account

    var body: some View {
        Group {
            switch account.state {
            case .loading:
                ProgressView()
            case .signedOut:
                SignInView()
            case .awaitingCode(let email):
                CodeEntryView(email: email)
            case .signedIn:
                ProfileView()
            }
        }
        .navigationTitle("Konto")
    }
}

// MARK: - Sign in

private struct SignInView: View {
    @Environment(AccountService.self) private var account
    @State private var email = ""
    @State private var name = ""
    @State private var isSending = false
    @State private var errorText: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.me)
                    Text("Mit Konto spielst du um eine echte Spielstärke: Gegner bestätigen deine Ergebnisse, und du erscheinst – wenn du willst – in Ranglisten.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Name (z. B. Marvin J.)", text: $name)
                    .textContentType(.name)
                TextField("E-Mail-Adresse", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("Du bekommst einen 6-stelligen Code per E-Mail. Ein Passwort brauchst du nicht.")
            }

            if let errorText {
                Section { Text(errorText).foregroundStyle(Theme.opponent) }
            }

            Section {
                Button {
                    Task { await send() }
                } label: {
                    HStack {
                        Text("Code senden")
                        if isSending { Spacer(); ProgressView() }
                    }
                }
                .disabled(isSending || !email.contains("@"))
            }
        }
    }

    private func send() async {
        isSending = true
        errorText = nil
        defer { isSending = false }
        do {
            try await account.sendCode(email: email, displayName: name)
        } catch {
            errorText = "Der Code konnte nicht gesendet werden. Prüf die E-Mail-Adresse und versuch es in ein paar Minuten noch einmal."
        }
    }
}

private struct CodeEntryView: View {
    @Environment(AccountService.self) private var account
    let email: String
    @State private var code = ""
    @State private var isChecking = false
    @State private var errorText: String?

    var body: some View {
        Form {
            Section {
                TextField("123456", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .font(Theme.scoreFont(size: 28))
            } header: {
                Text("Code eingeben")
            } footer: {
                Text("Wir haben dir eine E-Mail an \(email) geschickt. Gib den Code hier ein oder tippe in der E-Mail auf den Link – beides funktioniert. Schau auch im Spam-Ordner nach.")
            }

            if let errorText {
                Section { Text(errorText).foregroundStyle(Theme.opponent) }
            }

            Section {
                Button("Anmelden") { Task { await check() } }
                    .disabled(isChecking || code.filter(\.isNumber).count < 6)
                Button("Andere E-Mail-Adresse", role: .cancel) { account.cancelCode() }
            }
        }
    }

    private func check() async {
        isChecking = true
        errorText = nil
        defer { isChecking = false }
        do {
            try await account.verify(code: code)
        } catch {
            errorText = "Der Code stimmt nicht oder ist abgelaufen. Fordere bei Bedarf einen neuen an."
        }
    }
}

// MARK: - Profile

private struct ProfileView: View {
    @Environment(AccountService.self) private var account
    @State private var editing = false

    var body: some View {
        List {
            if let profile = account.profile {
                Section {
                    HStack(spacing: 16) {
                        LevelBadge(level: profile.level, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.displayName).font(.title3.weight(.bold))
                            Text(profile.username.map { "@\($0)" } ?? "Noch kein Benutzername")
                                .foregroundStyle(.secondary)
                            Text("\(Int(profile.rating.rounded())) Punkte · \(profile.ratedMatches) gewertete Matches")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                if profile.username == nil {
                    Section {
                        Label("Leg einen Benutzernamen fest, damit andere dich als Gegner oder Partner eintragen können.",
                              systemImage: "at")
                            .font(.subheadline)
                        Button("Profil bearbeiten") { editing = true }
                    }
                }

                Section("Sichtbarkeit") {
                    LabeledContent("Profil", value: profile.visibility.title)
                    Text(profile.visibility.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if account.openConfirmations.isEmpty {
                    Text("Keine offenen Ergebnisse")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(account.openConfirmations) { item in
                        ConfirmationRow(item: item)
                    }
                }
            } header: {
                Text("Offene Bestätigungen")
            } footer: {
                Text("Ergebnisse, bei denen dich jemand als Gegner eingetragen hat. Erst nach deiner Bestätigung zählen sie für die Spielstärke.")
            }

            if account.ratingHistory.count > 1 {
                Section("Spielstärke-Verlauf") {
                    Chart(account.ratingHistory) { row in
                        LineMark(x: .value("Datum", row.createdAt), y: .value("Punkte", row.ratingAfter))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.me)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 160)
                }
            }

            Section {
                Toggle("Neue Matches automatisch eintragen", isOn: Binding(
                    get: { account.autoUpload },
                    set: { account.autoUpload = $0 }
                ))
            } footer: {
                Text("Neue Matches von deiner Watch werden hochgeladen, sobald sie auf dem iPhone ankommen. Gegner verlinkst du danach im Match unter „Spielstärke“. Ältere Matches bleiben privat, bis du sie selbst einträgst.")
            }

            Section {
                NavigationLink("Öffentliche Rangliste") { LeaderboardView() }
                Button("Profil bearbeiten") { editing = true }
                Button("Abmelden", role: .destructive) { Task { await account.signOut() } }
            }
        }
        .refreshable { await account.refresh() }
        .sheet(isPresented: $editing) {
            if let profile = account.profile {
                ProfileEditor(profile: profile)
            }
        }
    }
}

private struct ConfirmationRow: View {
    @Environment(AccountService.self) private var account
    let item: OpenConfirmation
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.iWon ? "Sieg" : "Niederlage")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.iWon ? Theme.me : Theme.opponent)
                Spacer()
                Text(item.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(item.myResultText)
                .font(Theme.scoreFont(size: 22))
            Text("Eingetragen von \(item.creatorName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(Theme.opponent)
            }
            HStack {
                Button("Bestätigen") { act { try await account.confirm(item) } }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.me)
                Button("Ablehnen", role: .destructive) { act { try await account.reject(item) } }
                    .buttonStyle(.glass)
            }
            .disabled(isWorking)
        }
        .padding(.vertical, 4)
    }

    private func act(_ work: @escaping () async throws -> Void) {
        Task {
            isWorking = true
            errorText = nil
            do { try await work() } catch { errorText = "Das hat nicht geklappt. Versuch es noch einmal." }
            isWorking = false
        }
    }
}

private struct ProfileEditor: View {
    @Environment(AccountService.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var username: String
    @State private var visibility: ProfileVisibility
    @State private var errorText: String?
    @State private var isSaving = false

    init(profile: RemoteProfile) {
        _displayName = State(initialValue: profile.displayName)
        _username = State(initialValue: profile.username ?? "")
        _visibility = State(initialValue: profile.visibility)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Anzeigename", text: $displayName)
                }
                Section {
                    TextField("benutzername", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Benutzername")
                } footer: {
                    Text("Damit tragen dich andere als @\(username.isEmpty ? "benutzername" : username.lowercased()) in Matches ein.")
                }
                Section {
                    Picker("Sichtbarkeit", selection: $visibility) {
                        ForEach(ProfileVisibility.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Wer darf dein Profil sehen?")
                } footer: {
                    Text(visibility.explanation)
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(Theme.opponent) }
                }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }
                        .disabled(isSaving || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        do {
            try await account.updateProfile(displayName: displayName, username: username, visibility: visibility)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Leaderboard

struct LeaderboardView: View {
    @Environment(AccountService.self) private var account
    @State private var rows: [LeaderboardRow] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && rows.isEmpty {
                ContentUnavailableView(
                    "Noch keine Rangliste",
                    systemImage: "trophy",
                    description: Text("Hier erscheinen öffentliche Profile mit mindestens einem bestätigten Match.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 12) {
                    Text("\(index + 1).")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                    LevelBadge(level: row.level, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.displayName).font(.body.weight(row.id == account.userID ? .bold : .regular))
                        Text("\(row.ratedMatches) Matches").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(row.rating.rounded()))").font(Theme.scoreFont(size: 17))
                }
                .listRowBackground(row.id == account.userID ? Theme.me.opacity(0.12) : nil)
            }
        }
        .navigationTitle("Rangliste")
        .task {
            rows = await account.leaderboard()
            loaded = true
        }
        .refreshable { rows = await account.leaderboard() }
    }
}
