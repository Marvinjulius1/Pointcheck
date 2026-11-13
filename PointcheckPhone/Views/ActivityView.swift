import PadelStats
import SwiftUI

/// Follow requests, results to confirm and new followers.
struct ActivityView: View {
    @Environment(AccountService.self) private var account

    private var isEmpty: Bool {
        account.followRequests.isEmpty && account.openConfirmations.isEmpty && account.recentFollowers.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isEmpty {
                    EmptyState(symbol: "bell", title: "Alles erledigt",
                               message: "Hier erscheinen Folge-Anfragen, neue Follower und Ergebnisse, die du bestätigen sollst.")
                } else {
                    if !account.openConfirmations.isEmpty {
                        SectionTitle("Ergebnisse bestätigen")
                        ForEach(account.openConfirmations) { ConfirmationCard(item: $0) }
                    }
                    if !account.followRequests.isEmpty {
                        SectionTitle("Folge-Anfragen")
                        ForEach(Array(account.followRequests.enumerated()), id: \.element.id) { index, person in
                            if index > 0 { RowDivider(inset: 72) }
                            RequestRow(person: person)
                        }
                    }
                    if !account.recentFollowers.isEmpty {
                        SectionTitle("Neue Follower")
                        ForEach(Array(account.recentFollowers.enumerated()), id: \.element.id) { index, person in
                            if index > 0 { RowDivider(inset: 72) }
                            PersonListRow(person: person, subtitle: person.followedAt.map { "Folgt dir seit \($0.relativeShort)" })
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Aktivität")
        .refreshable { await account.refresh() }
        .profileNavigation()
    }
}

private struct RequestRow: View {
    let person: PersonRow
    @Environment(AccountService.self) private var account
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: person.profileID) {
                HStack(spacing: 12) {
                    ProfilePhoto(name: person.displayName, url: account.imageURL(person.avatarPath, bucket: .avatars))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.displayName).font(.body.weight(.semibold)).foregroundStyle(.primary)
                        Text("möchte dir folgen").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button("Annehmen") { act { try await account.acceptFollow(person) } }
                .buttonStyle(.accent)
                .controlSize(.small)
            Button {
                act { try await account.removeFollower(person) }
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityLabel("Ablehnen")
        }
        .disabled(isWorking)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func act(_ work: @escaping () async throws -> Void) {
        Task {
            isWorking = true
            try? await work()
            isWorking = false
        }
    }
}

/// A result someone entered with me as opponent – confirm or reject.
struct ConfirmationCard: View {
    let item: OpenConfirmation
    @Environment(AccountService.self) private var account
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Eingetragen von \(item.creatorName)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(item.startedAt.relativeShort)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.iWon ? "Sieg" : "Niederlage")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(item.iWon ? Theme.me : Theme.opponent)
                    ResultLine(text: item.myResultText, won: item.iWon)
                }
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.opponent)
                }
                HStack(spacing: 10) {
                    Button { act { try await account.confirm(item) } } label: {
                        Text("Stimmt").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.accent)
                    Button(role: .destructive) { act { try await account.reject(item) } } label: {
                        Text("Falsch").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                .disabled(isWorking)
            }
            .padding(16)
        }
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
