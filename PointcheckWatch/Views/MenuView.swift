import SwiftData
import SwiftUI

struct MenuView: View {
    @Query private var matches: [MatchRecord]

    var body: some View {
        List {
            NavigationLink {
                HistoryView()
            } label: {
                Label {
                    HStack {
                        Text("Verlauf")
                        Spacer()
                        Text("\(matches.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Theme.me)
                }
            }

            NavigationLink {
                SettingsView()
            } label: {
                Label {
                    Text("Einstellungen")
                } icon: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.gray)
                }
            }
        }
        .navigationTitle("Pointcheck")
    }
}
