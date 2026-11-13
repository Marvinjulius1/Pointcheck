import Charts
import PadelStats
import SwiftUI

/// Sign-in flow (e-mail code) and the public leaderboard.

/// Shown in the profile tab while signed out / entering the code.
struct AccountGate<Content: View>: View {
    @Environment(AccountService.self) private var account
    @ViewBuilder var content: Content

    var body: some View {
        switch account.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .signedOut:
            SignInView()
        case .awaitingCode(let email):
            CodeEntryView(email: email)
        case .signedIn:
            content
        }
    }
}

struct SignInView: View {
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

struct CodeEntryView: View {
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
