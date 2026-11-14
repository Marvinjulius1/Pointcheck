import SwiftUI

// MARK: - "Spieler gesucht"

struct GamesWantedView: View {
    /// Limit to one club (club page), or nil for everything.
    var club: String?
    @Environment(AccountService.self) private var account
    @State private var games: [GameWanted] = []
    @State private var isLoading = true
    @State private var showsCreate = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isLoading && games.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in SkeletonRow(); FeedDivider() }
                } else if games.isEmpty {
                    EmptyState(symbol: "person.3", title: "Niemand sucht gerade",
                               message: "Stell selbst ein Gesuch ein – z. B. „Samstag 18 Uhr, Court 2, einer fehlt“.",
                               actionTitle: "Spieler suchen", action: { showsCreate = true })
                } else {
                    ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                        GameRow(game: game) { await reload() }
                            .revealOnAppear(delay: min(Double(index) * 0.04, 0.3))
                        FeedDivider()
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle(club ?? "Spieler gesucht")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Gesuch erstellen")
            }
        }
        .sheet(isPresented: $showsCreate, onDismiss: { Task { await reload() } }) {
            CreateGameSheet(club: club ?? account.profile?.homeClub ?? "")
        }
        .task { await reload() }
        .refreshable { await reload() }
        .profileNavigation()
    }

    private func reload() async {
        games = await account.openGames(club: club)
        isLoading = false
    }
}

struct GameRow: View {
    let game: GameWanted
    let onChange: () async -> Void
    @Environment(AccountService.self) private var account
    @State private var isWorking = false
    @State private var calendarMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                NavigationLink(value: game.hostID) {
                    ProfilePhoto(name: game.hostName, url: account.imageURL(game.hostAvatar, bucket: .avatars))
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.startsAt.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).hour().minute()))
                        .font(.body.weight(.semibold))
                    Text([game.club, game.court.map { "Court \($0)" }].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(game.isFull ? "Voll" : "\(game.openSpots) frei")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(game.isFull ? .secondary : Theme.me)
                    Text("\(game.joined)/\(game.playersNeeded)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let note = game.note, !note.isEmpty {
                Text(note).font(.subheadline)
            }
            HStack(spacing: 6) {
                Text("Von \(game.hostName)")
                if let names = game.joinedNames { Text("· dabei: \(names)") }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)

            HStack(spacing: 10) {
                if game.isHost {
                    Button("Gesuch löschen") { act { try await account.cancelGame(game) } }
                        .buttonStyle(.quiet)
                } else if game.iJoined {
                    Button("Absagen") { act { try await account.leaveGame(game) } }
                        .buttonStyle(.quiet)
                } else if !game.isFull {
                    Button("Ich bin dabei") { act { try await account.joinGame(game) } }
                        .buttonStyle(.accent)
                }
                if game.iJoined || game.isHost {
                    Button {
                        Task {
                            calendarMessage = await CalendarExport.add(
                                title: "Padel mit \(game.hostName)", start: game.startsAt, notes: game.note,
                                location: [game.club, game.court.map { "Court \($0)" }].compactMap { $0 }.joined(separator: ", ")
                            )
                        }
                    } label: {
                        Label(calendarMessage ?? "Kalender", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.quiet)
                }
            }
            .disabled(isWorking)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func act(_ work: @escaping () async throws -> Void) {
        Task {
            isWorking = true
            try? await work()
            await onChange()
            isWorking = false
        }
    }
}

struct CreateGameSheet: View {
    @State var club: String
    @Environment(AccountService.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? .now
    @State private var court = ""
    @State private var playersNeeded = 1
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Wann?", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    TextField("Halle", text: $club)
                    TextField("Court (optional)", text: $court)
                    Stepper("Es fehlen: \(playersNeeded)", value: $playersNeeded, in: 1...3)
                } header: {
                    Text("Spieler gesucht")
                }
                Section {
                    TextField("Hinweis, z. B. Level 3–4, lockeres Match", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(Theme.opponent) }
                }
            }
            .navigationTitle("Gesuch erstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Einstellen") { Task { await save() } }.disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await account.createGame(startsAt: date, club: club, court: court, playersNeeded: playersNeeded, note: note)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorText = "Das Gesuch konnte nicht gespeichert werden. Versuch es noch einmal."
        }
    }
}
