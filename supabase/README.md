# Pointcheck – Supabase-Backend

Datenbank für Phase 3: Konten, Profile („öffentlich“ oder „nur Freunde“), Freundschaften,
Matches mit Bestätigung durch den Gegner und die Spielstärke-Berechnung auf dem Server.

## Was drin ist

| Tabelle / Funktion | Zweck |
|---|---|
| `profiles` | Name, Benutzername, Sichtbarkeit (`public` / `friends`, Standard: `friends`), Spielstärke |
| `friendships` | Freundschaftsanfragen und -bestätigungen |
| `matches`, `match_players` | Hochgeladene Matches; Slots 1–2 = eigenes Team, 3–4 = Gegner |
| `rating_history` | Spielstärke vor/nach jedem gewerteten Match |
| `leaderboard` | Rangliste – nur öffentliche Profile |
| `open_confirmations` | Ergebnisse, die ich als verlinkter Gegner noch bestätigen muss |
| `confirm_match` / `dispute_match` | Ergebnis in der App bestätigen bzw. ablehnen |
| `find_profile(username)` | Spieler finden, um ihn im Match zu verlinken oder als Freund hinzuzufügen |
| `my_friends()`, `request_friend`, `accept_friend`, `remove_friend` | Freundesliste mit Namen, Anfragen senden/annehmen/entfernen |
| `my_match_feed()` | Alle Matches, in denen ich spiele – aus meiner Sicht, mit Namen der Mitspieler |

**Sicherheitsregeln (Row Level Security):**
- Private Profile sehen nur Freunde.
- Ein Match sieht man als Teilnehmer, sonst nur, wenn es bestätigt ist **und** alle Spieler darin für einen sichtbar sind.
- Spielstärke und Bestätigungen lassen sich nicht direkt ändern, nur über die Server-Funktionen.
- Gewertet wird ein Match genau einmal, sobald ein Gegner bestätigt. Abgelehnte Matches werden nie gewertet.
- Der Ersteller verlinkt Partner und Gegner über ihren Benutzernamen. Der Gegner sieht das Ergebnis
  in seiner App unter „Offene Bestätigungen“ und bestätigt oder lehnt ab. Erst dann zählt es.

## Einrichten (einmalig)

1. Supabase-Projekt anlegen, Region **Frankfurt (eu-central-1)**.
2. Im Supabase-Dashboard **SQL Editor** öffnen.
3. **Nur falls schon ein früherer Stand eingespielt wurde** (Fehler wie `type "profile_visibility" already exists`):
   den Inhalt von `reset.sql` einfügen und auf **Run** klicken. ⚠️ Das löscht alle Pointcheck-Daten.
4. Alle Dateien aus `migrations/` **der Reihe nach** (nach Dateiname sortiert) einfügen und jeweils auf **Run** klicken.
   Später hinzukommende Migrationen werden genauso nachträglich ausgeführt – jede nur einmal.
5. Unter **Authentication → Providers → Email** die Anmeldung per E-Mail aktiv lassen.
   „Mit Apple anmelden“ kommt später mit dem Apple Developer Program dazu.
6. Die App meldet per **6-stelligem Code** an (kein Link). Dafür unter **Authentication → Emails** (Templates)
   in den Vorlagen **„Magic Link“** und **„Confirm signup“** den Text ersetzen, z. B.:

   ```html
   <h2>Dein Pointcheck-Code</h2>
   <p>Gib diesen Code in der App ein:</p>
   <p style="font-size:28px;font-weight:bold;letter-spacing:4px">{{ .Token }}</p>
   <p>Der Code ist eine Stunde gültig.</p>
   ```

7. Unter **Authentication → URL Configuration**:
   - **Site URL** auf `pointcheck://login` setzen,
   - bei **Redirect URLs** `pointcheck://login` hinzufügen.

   Dann öffnet auch ein Link in der E-Mail direkt die App (statt einer nicht erreichbaren Seite).

   Hinweis: Der eingebaute E-Mail-Versand von Supabase schickt nur wenige Mails pro Stunde – zum Testen reicht das.
   Für echte Nutzer später einen eigenen E-Mail-Dienst (SMTP) unter **Authentication → Emails → SMTP** eintragen.

⚠️ `tests/local_supabase_stub.sql` **nicht** in Supabase ausführen. Die Datei ersetzt Supabase nur für lokale Tests.

## Tests (lokal, ohne Supabase)

Gegen ein lokales PostgreSQL 15+:
```bash
PGHOST=localhost PGUSER=postgres supabase/tests/run_local.sh
```
Der Lauf legt jedes Mal eine frische Testdatenbank an. Geprüft werden: Profil beim Registrieren,
Sichtbarkeit, gesperrte Spalten, Verlinken, Bestätigung in der App, Spielstärke-Berechnung,
Schutz vor doppelter Wertung und Ablehnung.

## Schlüssel – was in die App darf
- **Project URL** und **anon / publishable key**: dürfen in die App und ins Repository.
- **service_role key** und **Datenbank-Passwort**: niemals in die App, ins Repository oder in einen Chat.
