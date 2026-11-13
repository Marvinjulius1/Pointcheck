import SwiftUI

/// Choose the home hall: search by name, city or postal code, or list the halls nearby.
struct HallPicker: View {
    @Binding var selection: Hall?
    @Environment(AccountService.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var halls: [Hall] = []
    @State private var isLoading = false
    @State private var loaded = false
    @State private var location = CoarseLocation.shared

    var body: some View {
        List {
            if query.isEmpty {
                Section {
                    Button {
                        Task { await load(askForLocation: true) }
                    } label: {
                        Label("Hallen in meiner Nähe", systemImage: "location.fill")
                    }
                    .disabled(location.isDenied)
                } footer: {
                    Text(location.isDenied
                         ? "Standort ist ausgeschaltet. Du kannst ihn in den iPhone-Einstellungen erlauben – oder oben nach Name, Stadt oder PLZ suchen."
                         : "Pointcheck nutzt nur deinen ungefähren Standort und speichert ihn nicht.")
                }
            }

            if !halls.isEmpty {
                Section(query.isEmpty ? "In der Nähe" : "Treffer") {
                    ForEach(halls) { hall in
                        Button {
                            selection = hall
                            dismiss()
                        } label: {
                            HallRow(hall: hall, isSelected: hall.id == selection?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if loaded && !query.isEmpty && !isLoading {
                Section {
                    Text("Keine Halle gefunden. Deine Halle ist noch nicht dabei? Lass das Feld leer und trag stattdessen deine Stadt ein.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if selection != nil {
                Section {
                    Button("Keine Heimat-Halle", role: .destructive) {
                        selection = nil
                        dismiss()
                    }
                }
            }
        }
        .overlay {
            if isLoading && halls.isEmpty { ProgressView() }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, Stadt oder PLZ")
        .navigationTitle("Heimat-Halle")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: query) {
            // Short pause so not every keystroke is a request.
            if !query.isEmpty {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
            await load(askForLocation: false)
        }
    }

    private func load(askForLocation: Bool) async {
        isLoading = true
        defer { isLoading = false; loaded = true }
        halls = await account.searchHalls(query, askForLocation: askForLocation)
    }
}

/// One hall: logo, name, city, distance and how many Pointcheck players call it home.
struct HallRow: View {
    let hall: Hall
    var isSelected = false
    @Environment(AccountService.self) private var account

    var body: some View {
        HStack(spacing: 12) {
            HallLogo(name: hall.name, url: account.imageURL(hall.logoPath, bucket: .halls), size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(hall.name).font(.body.weight(.semibold))
                Text(details).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").font(.body.weight(.semibold))
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var details: String {
        var parts = [hall.city]
        if let km = hall.distanceKm { parts.append(km.distanceText) }
        if let players = hall.players, players > 0 { parts.append(players == 1 ? "1 Spieler" : "\(players) Spieler") }
        return parts.joined(separator: " · ")
    }
}

/// Rounded-square hall logo with the initial as fallback (halls are not people, so no circle).
struct HallLogo: View {
    let name: String
    var url: URL?
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(Theme.surface)
            Image(systemName: "sportscourt.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.secondary)
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }
}

extension Double {
    /// "800 m", "3,2 km", "25 km".
    var distanceText: String {
        if self < 0.95 { return "\(max(Int((self * 10).rounded()), 1) * 100) m" }
        if self < 10 { return formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "de_DE"))) + " km" }
        return "\(Int(rounded())) km"
    }
}
