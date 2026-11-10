import SwiftUI

struct SettingsView: View {
    @Environment(MatchController.self) private var controller

    @AppStorage(AppSettings.bestOfKey) private var bestOf = 3
    @AppStorage(AppSettings.goldenPointKey) private var goldenPoint = false
    @AppStorage(AppSettings.recordWorkoutKey) private var recordWorkout = true
    @AppStorage(AppSettings.superTiebreakKey) private var superTiebreak = false

    var body: some View {
        List {
            Section {
                Picker("Sätze", selection: $bestOf) {
                    Text("1 Satz").tag(1)
                    Text("Best of 3").tag(3)
                    Text("Best of 5").tag(5)
                }
            } footer: {
                Text("Satz bei 6 Spielen mit 2 Vorsprung, bei 6:6 Tiebreak bis 7.")
            }

            Section {
                Toggle("Match-Tiebreak", isOn: $superTiebreak)
                    .disabled(bestOf == 1)
            } footer: {
                Text(bestOf == 1
                     ? "Nur bei mehreren Sätzen verfügbar."
                     : "Bei Satzgleichstand entscheidet ein Tiebreak bis 10 statt eines weiteren Satzes.")
            }

            Section {
                Toggle("Golden Point", isOn: $goldenPoint)
            } footer: {
                Text(goldenPoint
                     ? "Bei 40:40 entscheidet der nächste Punkt das Spiel."
                     : "Bei 40:40 wird mit Einstand und Vorteil gespielt.")
            }

            Section {
                Toggle("Training aufzeichnen", isOn: $recordWorkout)
            } footer: {
                Text("Zeichnet jedes Match als Tennis-Training in Health auf und hält die App während des Spiels im Vordergrund.")
            }

            if controller.settingsDifferFromCurrentMatch {
                Section {
                    Label("Regeln gelten ab dem nächsten Match.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Einstellungen")
        .onChange(of: bestOf) { controller.settingsDidChange() }
        .onChange(of: goldenPoint) { controller.settingsDidChange() }
        .onChange(of: superTiebreak) { controller.settingsDidChange() }
    }
}
