# Pointcheck – Roadmap

Grundprinzip: **Die Watch zählt, das iPhone zeigt.**
Die Watch-App bleibt ein reines Spieltracking-Werkzeug (schnell, wenig Text, große Flächen).
Statistiken, Ranglisten, Profile und alles Soziale kommen in eine eigene iPhone-App.
Hallen und Clubs bekommen später eine Web-Ansicht.

---

## Phase 1 – Watch-App: besser im echten Match
*Kein Server, kein Konto, funktioniert mit kostenlosem Apple-Account.*

| Funktion | Status |
|---|---|
| Aufschlag-Anzeige (gelber Ball beim aufschlagenden Team, wechselt automatisch; vor dem 1. Punkt antippbar) | ✅ |
| Seitenwechsel-Hinweis nach ungeraden Spielen, im Tiebreak alle 6 Punkte (Haptik + Text) | ✅ |
| Satzball- / Matchball-Anzeige in der Mittelzeile | ✅ |
| Super-Tiebreak (Match-Tiebreak bis 10) statt Entscheidungssatz, in den Einstellungen | ✅ |
| Punkte per Siri: „Punkt für uns in Pointcheck“, „Punkt Gegner in Pointcheck“, „Rückgängig in Pointcheck“ | ✅ |
| Complication fürs Zifferblatt (Tipp öffnet direkt den Zähler) | ✅ |

## Phase 2 – iPhone-App: persönliche Statistik
*Ohne Server und ohne bezahltes Developer-Programm: Daten kommen per Watch ↔ iPhone-Verbindung (WatchConnectivity).*

| Funktion | Status |
|---|---|
| iPhone-App als Begleiter (Watch-App bleibt eigenständig nutzbar) | ✅ |
| Übertragung beendeter Matches, Namensänderungen und Löschungen von der Watch | ✅ |
| Gesamten Verlauf von der Watch laden (erster Start, Pull-to-Refresh) | ✅ |
| Partner auf der Watch eintragen (mit Namensvorschlägen) | ✅ |
| Übersicht: Siegquote, Matches, Serien, Tiebreak-Bilanz, Sätze, Spielzeit, 8-Wochen-Diagramm | ✅ |
| **Partner-Statistik** und **Rivalen-Bilanz** | ✅ |
| **Abzeichen & Serien** (11 Erfolge mit Fortschritt) | ✅ |
| **Teilbare Ergebnis-Karte** (Bild für Instagram/WhatsApp) | ✅ |
| Trainingsdaten aus Health (Herzfrequenz, Kalorien) pro Match, Gesamtwerte, Kalorien auf der Teilen-Karte | ✅ |
| iCloud-Sync (braucht das bezahlte Developer-Programm) | offen → Phase 3 |

## Phase 3 – Plattform: Konten & Spielstärke
*Braucht einen Server (CloudKit oder eigener Backend-Dienst) und das bezahlte Apple Developer Program.*

- Konten, Spielerprofile, Sichtbarkeit (öffentlich / nur Freunde) – ✅ Anmeldung per E-Mail-Code, Profil mit Benutzername und Sichtbarkeit in der iPhone-App; „Mit Apple anmelden“ folgt mit dem Developer-Programm
- Ergebnis-Bestätigung durch den Gegner: Ersteller verlinkt das Profil des Gegners, der Gegner bestätigt oder lehnt in seiner App ab – ✅ Datenbank und iPhone-App („Offene Bestätigungen“)
- **Spielstärke-Wert** (Elo-ähnlich, für Doppel) – ✅ Rechenlogik fertig und getestet; ✅ lokale Vorschau in der iPhone-App (Level 1.0–7.0, Verlauf, „Dein Kreis“). Fehlt: echte Werte aller Mitspieler über Konten
- ✅ Öffentliche Rangliste in der iPhone-App
- ✅ Freunde: per @benutzername hinzufügen, Anfragen annehmen/ablehnen, Freundesliste mit Spielstärke
- ✅ Von Mitspielern eingetragene, bestätigte Matches zählen in allen Statistiken
- ✅ Neue Watch-Matches werden nach der Anmeldung automatisch hochgeladen (abschaltbar)
- ✅ Übersicht im Finanz-App-Stil: Spielstärke wie ein Depotwert mit Verlauf (1W–Max)
- **Gegner suchen** (ähnliche Spielstärke, in der Nähe)

### Redesign & Social (13.11.)
- ✅ Neue Tab-Leiste: **Home** (Spielstärke + Feed), **Matches**, **Suche**, **Aktivität**, **Profil**
- ✅ Folgen statt Freunde (einseitig, wie Instagram); private Profile bestätigen Anfragen
- ✅ Profilseite mit Foto, Bio, Heimat-Halle, Zählern (Beiträge · Follower · Folge ich), Level, Siegquote, Serie; Tabs Ergebnisse / Beiträge / Erfolge
- ✅ Beiträge mit Text, Foto und angehängtem Ergebnis; Feed mit Pagination
- ✅ Suche per Name oder @benutzername, Vorschläge; Aktivität mit Folge-Anfragen, neuen Followern und offenen Bestätigungen
- ✅ Einheitliche Bausteine (Karten, Avatare, Folgen-Button, leere Zustände) statt Einstellungs-Listen
- Offen: Push-Mitteilungen (Developer-Programm), Beiträge liken/kommentieren

### Ohne Apple Watch spielbar (13.11.)
- ✅ **Live zählen auf dem iPhone**: gleiche Rot/Grün-Felder und Zähllogik wie auf der Watch, Rückgängig, Aufschlag, Seitenwechsel, Satzball/Matchball; laufendes Match überlebt App-Neustart
- ✅ **Ergebnis nachträglich eintragen**: Sätze, Match-Tiebreak, Partner, Gegner, Datum
- ✅ **Siri auf dem iPhone**: „Punkt für uns in Pointcheck“, „Punkt Gegner in Pointcheck“, „Rückgängig in Pointcheck“
- ✅ Eigene Regeln fürs iPhone in den Einstellungen; iPhone-Matches zählen wie Watch-Matches (Statistik, Upload, Bestätigung)

## Phase 4 – Hallen & Clubs (Business)
*Web-Dashboard für Betreiber, Abo-Modell.*

- **Hallen-Rangliste** für den Bildschirm im Eingangsbereich
- **Ligen & Turniere** mit automatischem Spielplan und Tabelle
- **Monats-Challenges** mit Preisen der Halle
- **Anbindung an Platzbuchungen** (abhängig von den Schnittstellen der Buchungsanbieter)
