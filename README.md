# Pointcheck – Padel-Zähler für die Apple Watch

Eigenständige watchOS-26-App (SwiftUI, Liquid Glass, SwiftData). Ein iPhone wird nicht benötigt.

## Projektstruktur

```
Pointcheck/
├── project.yml                     # XcodeGen-Definition → erzeugt Pointcheck.xcodeproj
├── docs/ROADMAP.md                 # Phasenplan (Watch → iPhone → Plattform → Hallen)
├── PointcheckWidget/               # Complication fürs Zifferblatt
├── Packages/PadelScoring/          # Zähllogik als Swift Package (ohne UI)
│   ├── Sources/PadelScoring/
│   │   ├── Team.swift              # Team (.me / .opponent), TeamScore
│   │   ├── MatchRules.swift        # Best of X, Einstand vs. Golden Point
│   │   ├── MatchState.swift        # Punkte → Spiele → Sätze → Match, Tiebreak
│   │   └── MatchScorer.swift       # State + Undo-Verlauf
│   └── Tests/PadelScoringTests/    # Tests (Swift Testing)
└── PointcheckWatch/                # Die Watch-App
    ├── App/PointcheckApp.swift     # Einstieg, SwiftData-Container
    ├── Controller/
    │   ├── MatchController.swift   # Steuert das laufende Match (Punkte, Undo, Neues Match)
    │   ├── WorkoutManager.swift    # HKWorkoutSession (Tennis) → Display bleibt aktiv
    │   └── Haptics.swift           # Haptik pro Punkt / Spiel / Satz / Match
    ├── Persistence/
    │   ├── MatchRecord.swift       # SwiftData-Modell für den Verlauf
    │   ├── MatchRepository.swift   # Speichern / Löschen
    │   ├── ActiveMatchStore.swift  # Laufendes Match überlebt App-Neustart
    │   └── AppSettings.swift       # Einstellungen (UserDefaults)
    ├── Views/
    │   ├── ScoreboardView.swift    # Hauptscreen (Krone + Wischen = Undo)
    │   ├── ScoreField.swift        # Rotes/grünes Liquid-Glass-Tippfeld
    │   ├── MatchStatusView.swift   # Mitte: Sätze „1:1“, darunter Spiele „4:3“
    │   ├── MenuView.swift          # Verlauf / Einstellungen
    │   ├── HistoryView.swift       # Liste, neueste zuerst, Wischen zum Löschen
    │   ├── MatchDetailView.swift   # Satzergebnisse, Gegnername bearbeiten
    │   └── SettingsView.swift      # Best of 1/3/5, Golden Point, Training
    ├── Assets.xcassets             # App-Icon, Akzentfarbe
    ├── Info.plist
    └── Pointcheck.entitlements     # HealthKit
```

## Bedienung

| Aktion | Geste |
|---|---|
| Punkt Gegner | Oberes, rotes Feld antippen |
| Punkt für uns | Unteres, grünes Feld antippen |
| Rückgängig | Digital Crown zurückdrehen (2 Rasten) **oder** horizontal über den Screen wischen |
| Neues Match | `+` rechts neben dem Spielstand → „Neues Match“ (das alte Match wird gespeichert) |
| Verlauf / Einstellungen | `≡` links neben dem Spielstand |
| Verlauf leeren | Verlauf → ganz nach unten scrollen → „Verlauf leeren“ (ein laufendes Match bleibt erhalten) |
| Aufschlag festlegen | Vor dem 1. Punkt den gelben Ball antippen – er wechselt zum anderen Team. Danach wandert er automatisch |
| Punkte per Siri | „Punkt für uns in Pointcheck“, „Punkt Gegner in Pointcheck“, „Rückgängig in Pointcheck“ |
| App vom Zifferblatt starten | Complication „Pointcheck“ beim Bearbeiten des Zifferblatts hinzufügen |

In der Mittelzeile erscheinen automatisch Hinweise: **Seitenwechsel** (mit Vibration), **Satzball** / **Matchball** in der Farbe des Teams,
**Einstand**, **Golden Point**, **Tiebreak** und **Match-Tiebreak** (in den Einstellungen statt Entscheidungssatz aktivierbar).

Jedes Match wird beim ersten Punkt automatisch im Verlauf angelegt und nach jedem Punkt aktualisiert.
Ist ein Match entschieden, ist es fertig gespeichert. Mit „Neues Match“ wird ein laufendes Match als „Abgebrochen“ abgelegt.

Beim ersten Punkt startet ein Tennis-Training (HealthKit kennt keinen eigenen Padel-Typ). Dadurch bleibt die App beim Handgelenk-Heben im Vordergrund.
Das Training endet mit dem Matchgewinn oder mit „Neues Match“. Abschalten kannst du das in den Einstellungen.

## Tests der Zähllogik

```bash
cd Packages/PadelScoring
swift test
```

Alternativ `Packages/PadelScoring/Package.swift` in Xcode öffnen und **⌘U** drücken.

## App in Xcode auf die Apple Watch bringen

### Voraussetzungen
- Mac mit **Xcode 26** (enthält das watchOS-26-SDK)
- Apple Watch mit **watchOS 26**, gekoppelt mit deinem iPhone
- Apple-ID. Ein kostenloser Account reicht, dann läuft die App allerdings nur 7 Tage und muss danach neu installiert werden.
  Mit dem bezahlten Developer Program (99 €/Jahr) gilt das nicht.

### 1. Projekt erzeugen
```bash
brew install xcodegen
```
```bash
cd Pointcheck
xcodegen
```
```bash
open Pointcheck.xcodeproj
```

### 2. Signieren
1. In Xcode links das Projekt **Pointcheck** → Target **Pointcheck** → Tab **Signing & Capabilities**.
2. **Team** auswählen. Falls nötig, vorher unter *Xcode → Settings → Accounts* deine Apple-ID hinzufügen.
3. Bundle Identifier eindeutig machen, z. B. `com.<deinname>.pointcheck.watchkitapp`.
   Alternativ vor `xcodegen` in `project.yml` `com.yourname` ersetzen.
4. Prüfen, dass **HealthKit** und **Background Modes → Workout processing** als Capabilities aktiv sind (kommen aus der project.yml).

### 3. Watch vorbereiten
1. **iPhone:** Einstellungen → Datenschutz & Sicherheit → **Entwicklermodus** einschalten (Neustart).
2. iPhone per Kabel an den Mac, entsperren, „Vertrauen“ bestätigen.
3. **Watch:** Einstellungen → Datenschutz & Sicherheit → **Entwicklermodus** einschalten (Neustart).
4. In Xcode unter *Window → Devices and Simulators* warten, bis die Watch erscheint. Watch entsperrt und nah am Mac/iPhone lassen. Die erste Verbindung kann ein paar Minuten dauern.

### 4. Starten
1. Oben in der Xcode-Leiste Schema **Pointcheck** und als Ziel deine **Apple Watch** wählen.
2. **⌘R** drücken. Xcode baut und installiert die App auf der Watch.
3. Beim ersten Start der App auf der Watch den Health-Zugriff erlauben.
4. Nur bei kostenlosem Account: Falls die Watch „Nicht vertrauenswürdiger Entwickler“ meldet, auf dem iPhone unter
   *Einstellungen → Allgemein → VPN & Geräteverwaltung* dein Entwicklerprofil bestätigen.

Ausprobieren ohne Watch: Als Ziel einen **Apple Watch Simulator** wählen und ⌘R drücken. Die Krone simulierst du mit dem Scrollrad bzw. Trackpad.

### Ohne XcodeGen (manuell)
1. Xcode → *File → New → Project → watchOS → App* → „Watch-only App“, Name `Pointcheck`, Interface SwiftUI, Storage None.
2. Die generierten Swift-Dateien und `Assets.xcassets` löschen. Danach den Ordnerinhalt von `PointcheckWatch/` ins Projekt ziehen.
3. *File → Add Package Dependencies… → Add Local…* → `Packages/PadelScoring` wählen und dem Watch-Target hinzufügen.
4. Unter *Signing & Capabilities*: **+ HealthKit** und **+ Background Modes → Workout processing** hinzufügen.
5. Unter *Build Settings*: `Info.plist File` = `PointcheckWatch/Info.plist` (oder die zwei `NSHealth…`-Texte im Info-Tab eintragen), Deployment Target watchOS 26.0.
