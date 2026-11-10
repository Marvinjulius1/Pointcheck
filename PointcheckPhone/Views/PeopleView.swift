import PadelStats
import SwiftData
import SwiftUI

/// Partner statistics and head-to-head records against opponents.
struct PeopleView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case partners = "Partner"
        case rivals = "Rivalen"
        var id: Self { self }
    }

    @Query(sort: \StoredMatch.startDate, order: .reverse) private var stored: [StoredMatch]
    @State private var mode: Mode

    init(initialMode: Mode = .partners) {
        _mode = State(initialValue: initialMode)
    }

    private var records: [PersonRecord] {
        let matches = stored.map(\.summary)
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
            }

            if records.isEmpty {
                ContentUnavailableView(
                    mode == .partners ? "Keine Partner eingetragen" : "Keine Gegner eingetragen",
                    systemImage: mode == .partners ? "person.fill.questionmark" : "person.2.slash",
                    description: Text("Trag Namen auf der Watch im Verlauf unter dem jeweiligen Match ein.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section(mode == .partners ? "Mit wem du gewinnst" : "Bilanz gegen") {
                    ForEach(records) { PersonRecordRow(record: $0) }
                }
            }
        }
        .navigationTitle(mode.rawValue)
    }
}

struct PersonRecordRow: View {
    let record: PersonRecord

    var body: some View {
        HStack(spacing: 12) {
            Text(String(record.name.prefix(1)).uppercased())
                .font(.headline)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.tint(Theme.me.opacity(0.3)), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name).font(.body.weight(.semibold))
                Text("\(record.wins) Siege · \(record.losses) Niederlagen")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.winRate.percentText)
                    .font(Theme.scoreFont(size: 17))
                    .foregroundStyle(record.winRate >= 0.5 ? Theme.me : Theme.opponent)
                Text("\(record.wins):\(record.losses)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
