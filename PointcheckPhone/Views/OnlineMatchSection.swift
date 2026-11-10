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
        Section {
            if account.foreignIDs.contains(match.id) {
                Label("Von einem Mitspieler eingetragen und bestätigt. Es zählt für deine Spielstärke.",
                      systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.me)
            } else if account.state != .signedIn {
                Label("Melde dich im Tab „Konto“ an, um das Match bestätigen zu lassen.", systemImage: "person.crop.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !match.isDecided {
                Text("Nur entschiedene Matches können eingetragen werden.")
                    .foregroundStyle(.secondary)
            } else if let status, status != .pending {
                LabeledContent("Status", value: status.title)
            } else {
                if let status {
                    LabeledContent("Status", value: status.title)
                }
                TextField("Partner: @benutzername oder Name", text: $partner)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Gegner 1: @benutzername oder Name", text: $opponent1)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Gegner 2: @benutzername oder Name", text: $opponent2)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.opponent)
                }
                Button {
                    Task { await upload() }
                } label: {
                    HStack {
                        Text(status == nil ? "Eintragen & bestätigen lassen" : "Spieler aktualisieren")
                        if isUploading { Spacer(); ProgressView() }
                    }
                }
                .disabled(isUploading)
            }
        } header: {
            Text("Spielstärke")
        } footer: {
            if account.state == .signedIn, !account.foreignIDs.contains(match.id), status == nil || status == .pending {
                Text("Mit @ verlinkst du ein Konto – dieser Gegner bestätigt das Ergebnis in seiner App. Namen ohne @ werden nur als Gast gespeichert.")
            }
        }
        .onAppear(perform: prefill)
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
