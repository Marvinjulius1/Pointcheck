import PadelStats
import SwiftData
import SwiftUI

/// Friends, partner statistics and head-to-head records.
struct PeopleView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case friends = "Freunde"
        case partners = "Partner"
        case rivals = "Rivalen"
        var id: Self { self }
    }

    @Query(sort: \StoredMatch.startDate, order: .reverse) private var stored: [StoredMatch]
    @Environment(AccountService.self) private var account
    @State private var mode: Mode

    init(initialMode: Mode = .friends) {
        _mode = State(initialValue: initialMode)
    }

    private var records: [PersonRecord] {
        let matches = account.allMatches(local: stored.map(\.summary))
        return mode == .partners ? PadelStats.partners(matches) : PadelStats.rivals(matches)
    }

    var body: some View {
        List {
            Section {
                Picker("Ansicht", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            switch mode {
            case .friends:
                FriendsSections()
            case .partners, .rivals:
                recordSections
            }
        }
        .navigationTitle("Personen")
        .refreshable { await account.refresh() }
    }

    @ViewBuilder
    private var recordSections: some View {
        if records.isEmpty {
            ContentUnavailableView(
                mode == .partners ? "Keine Partner eingetragen" : "Keine Gegner eingetragen",
                systemImage: mode == .partners ? "person.fill.questionmark" : "person.2.slash",
                description: Text("Trag Namen auf der Watch im Verlauf unter dem jeweiligen Match ein.")
            )
            .listRowBackground(Color.clear)
        } else {
            Section(mode == .partners ? "Mit wem du gewinnst" : "Deine Bilanz gegen") {
                ForEach(records) { PersonRecordRow(record: $0) }
            }
        }
    }
}

// MARK: - Friends

private struct FriendsSections: View {
    @Environment(AccountService.self) private var account
    @State private var username = ""
    @State private var isAdding = false
    @State private var message: (text: String, isError: Bool)?

    private var incoming: [Friend] { account.friends.filter { $0.status == .pending && $0.incoming } }
    private var outgoing: [Friend] { account.friends.filter { $0.status == .pending && !$0.incoming } }
    private var accepted: [Friend] {
        account.friends.filter { $0.status == .accepted }.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
    }

    var body: some View {
        if account.state != .signedIn {
            ContentUnavailableView(
                "Freunde mit Konto",
                systemImage: "person.2.badge.plus",
                description: Text("Melde dich im Tab „Konto“ an, um Freunde hinzuzufügen und ihre Spielstärke zu sehen.")
            )
            .listRowBackground(Color.clear)
        } else {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "at")
                        .foregroundStyle(.secondary)
                    TextField("benutzername", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .onSubmit { Task { await add() } }
                    if isAdding {
                        ProgressView()
                    } else {
                        Button("Hinzufügen") { Task { await add() } }
                            .buttonStyle(.borderless)
                            .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } header: {
                Text("Freund hinzufügen")
            } footer: {
                if let message {
                    Text(message.text).foregroundStyle(message.isError ? Theme.opponent : Theme.me)
                } else {
                    Text("Freunde sehen dein Profil auch, wenn es auf „Nur Freunde“ steht.")
                }
            }

            if !incoming.isEmpty {
                Section("Anfragen") {
                    ForEach(incoming) { friend in
                        HStack(spacing: 12) {
                            Avatar(name: friend.displayName)
                            NameStack(friend: friend)
                            Spacer()
                            Button("Annehmen") { act { try await account.acceptFriend(friend) } }
                                .buttonStyle(.glassProminent)
                                .tint(Theme.me)
                            Button {
                                act { try await account.removeFriend(friend) }
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.glass)
                            .accessibilityLabel("Ablehnen")
                        }
                    }
                }
            }

            Section {
                if accepted.isEmpty {
                    Text("Noch keine Freunde")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accepted) { friend in
                        HStack(spacing: 12) {
                            if let level = friend.level {
                                LevelBadge(level: level, size: 40)
                            } else {
                                Avatar(name: friend.displayName)
                            }
                            NameStack(friend: friend)
                            Spacer()
                            if let rating = friend.rating {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(Int(rating.rounded()))")
                                        .font(.body.weight(.semibold).monospacedDigit())
                                    Text("\(friend.ratedMatches ?? 0) Matches")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button("Entfernen", role: .destructive) {
                                act { try await account.removeFriend(friend) }
                            }
                        }
                    }
                }
            } header: {
                Text("Freunde")
            }

            if !outgoing.isEmpty {
                Section("Gesendet") {
                    ForEach(outgoing) { friend in
                        HStack(spacing: 12) {
                            Avatar(name: friend.displayName)
                            NameStack(friend: friend)
                            Spacer()
                            Text("Wartet")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Zurückziehen", role: .destructive) {
                                act { try await account.removeFriend(friend) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func add() async {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !isAdding else { return }
        isAdding = true
        defer { isAdding = false }
        do {
            let isFriend = try await account.addFriend(username: name)
            message = (isFriend ? "Ihr seid jetzt befreundet." : "Anfrage gesendet.", false)
            username = ""
        } catch {
            message = (error.localizedDescription, true)
        }
    }

    private func act(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { message = ("Das hat nicht geklappt. Versuch es noch einmal.", true) }
        }
    }
}

private struct NameStack: View {
    let friend: Friend

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(friend.displayName)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            if let username = friend.username {
                Text("@\(username)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Circle with the first letter of a name.
struct Avatar: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor.gradient, in: .circle)
    }
}

// MARK: - Partner / rival row

struct PersonRecordRow: View {
    let record: PersonRecord

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: record.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name).font(.body.weight(.semibold))
                Text("\(record.wins) Siege · \(record.losses) Niederlagen")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.winRate.percentText)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(record.winRate >= 0.5 ? Theme.me : Theme.opponent)
                Text("\(record.wins):\(record.losses)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
