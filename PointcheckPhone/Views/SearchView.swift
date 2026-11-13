import SwiftUI

/// Find players by name or @username; suggestions while the field is empty.
struct SearchView: View {
    @Environment(AccountService.self) private var account
    @State private var query = ""
    @State private var results: [PersonRow] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if account.state != .signedIn {
                    EmptyState(symbol: "person.crop.circle.badge.questionmark", title: "Spieler finden",
                               message: "Melde dich im Tab „Profil“ an, um Spieler zu suchen und ihnen zu folgen.")
                } else if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                    if isSearching && results.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if results.isEmpty {
                        EmptyState(symbol: "magnifyingglass", title: "Niemand gefunden",
                                   message: "Prüf die Schreibweise oder frag nach dem @benutzernamen.")
                    } else {
                        peopleCard(results, subtitle: { $0.homeClub })
                    }
                } else {
                    if !account.suggestions.isEmpty {
                        SectionTitle("Vorschläge für dich")
                        peopleCard(account.suggestions, subtitle: { $0.reason })
                    } else {
                        EmptyState(symbol: "person.2", title: "Spieler entdecken",
                                   message: "Gib einen Namen oder @benutzernamen ein. Vorschläge erscheinen, sobald du Matches mit anderen gespielt hast.")
                    }
                    SectionTitle("Rangliste")
                    Card {
                        NavigationLink { LeaderboardView() } label: {
                            MetricRow(symbol: "trophy.fill", tint: .orange, title: "Öffentliche Rangliste",
                                      subtitle: "Die stärksten Spieler", value: "")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Suche")
        .searchable(text: $query, prompt: "Name oder @benutzername")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onChange(of: query) { _, newValue in search(newValue) }
        .task { await account.loadSuggestions() }
        .refreshable { await account.loadSuggestions() }
        .profileNavigation()
    }

    private func peopleCard(_ people: [PersonRow], subtitle: @escaping (PersonRow) -> String?) -> some View {
        Card {
            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                if index > 0 { RowDivider(inset: 72) }
                PersonListRow(person: person, subtitle: subtitle(person) ?? person.username.map { "@\($0)" })
            }
        }
    }

    private func search(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { results = []; return }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let found = await account.search(trimmed)
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }
}
