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
*Noch ohne Server: Daten kommen per Watch ↔ iPhone-Verbindung.*

- iPhone-App als Begleiter (Watch-App bleibt eigenständig nutzbar)
- Übertragung der Matches von der Watch aufs iPhone (WatchConnectivity)
- Statistik-Übersicht: Siegquote, Matches pro Woche, Tiebreak-Bilanz, Trainingsdaten aus Health
- **Partner-Statistik** (mit wem gewinnst du am häufigsten) → dafür auf der Watch optional „Partner“ eintragen
- **Rivalen-Bilanz** („Du gegen Max: 7:4“)
- **Abzeichen & Serien**
- **Teilbare Ergebnis-Karte** (Bild für Instagram/WhatsApp)

## Phase 3 – Plattform: Konten & Spielstärke
*Braucht einen Server (CloudKit oder eigener Backend-Dienst) und das bezahlte Apple Developer Program.*

- Konten („Mit Apple anmelden“), Spielerprofile, Datenschutz-Einstellungen (öffentlich / nur Freunde)
- Ergebnis-Bestätigung durch den Gegner (QR-Code auf der Watch → Gegner bestätigt am iPhone)
- **Spielstärke-Wert** (Elo-ähnlich, für Doppel)
- **Gegner suchen** (ähnliche Spielstärke, in der Nähe)

## Phase 4 – Hallen & Clubs (Business)
*Web-Dashboard für Betreiber, Abo-Modell.*

- **Hallen-Rangliste** für den Bildschirm im Eingangsbereich
- **Ligen & Turniere** mit automatischem Spielplan und Tabelle
- **Monats-Challenges** mit Preisen der Halle
- **Anbindung an Platzbuchungen** (abhängig von den Schnittstellen der Buchungsanbieter)
