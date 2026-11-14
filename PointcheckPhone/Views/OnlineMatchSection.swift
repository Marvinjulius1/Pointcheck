import PadelStats
import SwiftUI

/// In the match details: upload the match and link partner/opponents for confirmation.
struct OnlineMatchSection: View {
    let match: MatchSummary
    @Environment(AccountService.self) private var account
    @State private var partner = ""
    @State private var opponent1 = ""
    @State private var opponent2 = ""
    @State private var isUploading = false
    @State private var errorText: String?

    private var status: RemoteMatchStatus? { account.uploads[match.id] }

    var body: some View {
        FormGroup(title: "Spielstärke", note: note) {
            if account.foreignIDs.contains(match.id) {
                FormRow(symbol: "checkmark.seal.fill", tint: Theme.lime, title: "Bestätigt",
                        subtitle: "Von einem Mitspieler eingetragen. Zählt für deine Spielstärke.") { EmptyView() }
            } else if !match.isDecided {
                FormRow(symbol: "hourglass", title: "Nicht entschieden",
                        subtitle: "Nur entschiedene Matches können eingetragen werden.") { EmptyView() }
            } else {
                if let status {
                    FormRow(symbol: status == .confirmed ? "checkmark.seal.fill" : status == .disputed ? "xmark.seal.fill" : "clock.fill",
                            tint: status == .confirmed ? Theme.lime : status == .disputed ? Theme.opponent : Theme.surfaceRaised,
                            title: "Status") {
                        StatusChip(text: status.title, on: status == .confirmed)
                    }
                }
                if status == nil || status == .pending {
                    if status != nil { RowDivider() }
                    InputRow(label: "Partner", placeholder: "@benutzername oder Name", text: $partner, symbol: "person.2.fill", lowercase: true)
                    RowDivider()
                    InputRow(label: "Gegner 1", placeholder: "@benutzername oder Name", text: $opponent1, symbol: "person.fill.xmark", lowercase: true)
                    RowDivider()
                    InputRow(label: "Gegner 2", placeholder: "@benutzername oder Name", text: $opponent2, symbol: "person.fill.xmark", lowercase: true)
                    if let errorText {
                        FormError(text: errorText).padding(.horizontal, 16).padding(.bottom, 8)
                    }
                    RowDivider(inset: 16)
                    Button {
                        Task { await upload() }
                    } label: {
                        HStack(spacing: 8) {
                            if isUploading { BallLoader(size: 12) }
                            Text(status == nil ? "Eintragen & bestätigen lassen" : "Spieler aktualisieren")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.pressScale)
                    .foregroundStyle(Theme.lime)
                    .disabled(isUploading)
                }
            }
        }
        .onAppear(perform: prefill)
    }

    private var note: String? {
        guard !account.foreignIDs.contains(match.id), match.isDecided, status == nil || status == .pending else { return nil }
        return "Mit @ verlinkst du ein Konto – dieser Gegner bestätigt das Ergebnis in seiner App. Namen ohne @ werden nur als Gast gespeichert."
    }

    private func prefill() {
        if partner.isEmpty { partner = match.partnerName }
        if opponent1.isEmpty { opponent1 = match.opponentName }
    }

    private func upload() async {
        isUploading = true
        errorText = nil
        defer { isUploading = false }
        do {
            try await account.upload(match, partner: partner, opponents: [opponent1, opponent2])
        } catch {
            errorText = error.localizedDescription
        }
    }
}
