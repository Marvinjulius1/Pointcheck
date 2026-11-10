import AppIntents
import PadelScoring

// Siri / Shortcuts: "Punkt für uns in Pointcheck", "Punkt Gegner in Pointcheck",
// "Rückgängig in Pointcheck". Apple requires the app name in every phrase.

struct ScorePointForUsIntent: AppIntent {
    static let title: LocalizedStringResource = "Punkt für uns"
    static let description: IntentDescription? = IntentDescription("Zählt einen Punkt für dein Team.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let controller = AppEnvironment.controller
        controller.score(.me)
        return .result(dialog: "\(controller.scoreSummary)")
    }
}

struct ScorePointForOpponentIntent: AppIntent {
    static let title: LocalizedStringResource = "Punkt für Gegner"
    static let description: IntentDescription? = IntentDescription("Zählt einen Punkt für das gegnerische Team.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let controller = AppEnvironment.controller
        controller.score(.opponent)
        return .result(dialog: "\(controller.scoreSummary)")
    }
}

struct UndoPointIntent: AppIntent {
    static let title: LocalizedStringResource = "Letzten Punkt rückgängig"
    static let description: IntentDescription? = IntentDescription("Nimmt den zuletzt gezählten Punkt zurück.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let controller = AppEnvironment.controller
        controller.undo()
        return .result(dialog: "Rückgängig. \(controller.scoreSummary)")
    }
}

struct PointcheckShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScorePointForUsIntent(),
            phrases: [
                "Punkt für uns in \(.applicationName)",
                "\(.applicationName) Punkt für uns",
            ],
            shortTitle: "Punkt für uns",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: ScorePointForOpponentIntent(),
            phrases: [
                "Punkt Gegner in \(.applicationName)",
                "\(.applicationName) Punkt Gegner",
            ],
            shortTitle: "Punkt Gegner",
            systemImageName: "minus.circle.fill"
        )
        AppShortcut(
            intent: UndoPointIntent(),
            phrases: [
                "Rückgängig in \(.applicationName)",
                "\(.applicationName) rückgängig",
            ],
            shortTitle: "Rückgängig",
            systemImageName: "arrow.uturn.backward.circle.fill"
        )
    }
}
