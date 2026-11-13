import AppIntents
import PadelStats

// Siri on the iPhone: "Punkt für uns in Pointcheck", "Punkt Gegner in Pointcheck",
// "Rückgängig in Pointcheck" – drives the iPhone counter.

struct PhonePointForUsIntent: AppIntent {
    static let title: LocalizedStringResource = "Punkt für uns"
    static let description: IntentDescription? = IntentDescription("Zählt einen Punkt für dein Team (iPhone-Zähler).")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let counter = PhoneEnvironment.counter
        counter.score(.me)
        return .result(dialog: "\(counter.scoreSummary)")
    }
}

struct PhonePointForOpponentIntent: AppIntent {
    static let title: LocalizedStringResource = "Punkt für Gegner"
    static let description: IntentDescription? = IntentDescription("Zählt einen Punkt für das gegnerische Team (iPhone-Zähler).")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let counter = PhoneEnvironment.counter
        counter.score(.opponent)
        return .result(dialog: "\(counter.scoreSummary)")
    }
}

struct PhoneUndoPointIntent: AppIntent {
    static let title: LocalizedStringResource = "Letzten Punkt rückgängig"
    static let description: IntentDescription? = IntentDescription("Nimmt den zuletzt gezählten Punkt zurück (iPhone-Zähler).")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let counter = PhoneEnvironment.counter
        counter.undo()
        return .result(dialog: "Rückgängig. \(counter.scoreSummary)")
    }
}

struct PhoneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PhonePointForUsIntent(),
            phrases: ["Punkt für uns in \(.applicationName)", "\(.applicationName) Punkt für uns"],
            shortTitle: "Punkt für uns",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: PhonePointForOpponentIntent(),
            phrases: ["Punkt Gegner in \(.applicationName)", "\(.applicationName) Punkt Gegner"],
            shortTitle: "Punkt Gegner",
            systemImageName: "minus.circle.fill"
        )
        AppShortcut(
            intent: PhoneUndoPointIntent(),
            phrases: ["Rückgängig in \(.applicationName)", "\(.applicationName) rückgängig"],
            shortTitle: "Rückgängig",
            systemImageName: "arrow.uturn.backward.circle.fill"
        )
    }
}
