# Pointcheck – Supabase-Backend

Datenbank für Phase 3: Konten, Profile („öffentlich“ oder „nur Freunde“), Freundschaften,
Matches mit Bestätigung durch den Gegner und die Spielstärke-Berechnung auf dem Server.

## Was drin ist

| Tabelle / Funktion | Zweck |
|---|---|
| `profiles` | Name, Benutzername, Sichtbarkeit (`public` / `friends`, Standard: `friends`), Spielstärke |
| `friendships` | Freundschaftsanfragen und -bestätigungen |
| `matches`, `match_players` | Hochgeladene Matches; Slots 1–2 = eigenes Team, 3–4 = Gegner |
| `match_claims` | Geheimer Code für den QR-Code (nur Ersteller kann ihn abrufen) |
| `rating_history` | Spielstärke vor/nach jedem gewerteten Match |
| `leaderboard` | Rangliste – nur öffentliche Profile |
| `claim_and_confirm(match, code)` | Gegner scannt QR-Code → wird eingetragen und bestätigt |
| `confirm_match` / `dispute_match` | Bestätigen bzw. Ergebnis ablehnen |
| `find_profile(username)` | Spieler zum Hinzufügen als Freund finden |

**Sicherheitsregeln (Row Level Security):**
- Private Profile sehen nur Freunde.
- Ein Match sieht man als Teilnehmer, sonst nur, wenn es bestätigt ist **und** alle Spieler darin für einen sichtbar sind.
- Spielstärke und Bestätigungen lassen sich nicht direkt ändern, nur über die Server-Funktionen.
- Gewertet wird ein Match genau einmal, sobald ein Gegner bestätigt. Abgelehnte Matches werden nie gewertet.
- Per Name eintragen kann man nur Freunde. Alle anderen kommen über den QR-Code dazu.

## Einrichten (einmalig)

1. Supabase-Projekt anlegen, Region **Frankfurt (eu-central-1)**.
2. Im Supabase-Dashboard **SQL Editor** öffnen.
3. Den Inhalt von `migrations/20261110120000_initial_schema.sql` hineinkopieren und auf **Run** klicken.
4. Unter **Authentication → Providers → Email** die Anmeldung per E-Mail aktiv lassen.
   „Mit Apple anmelden“ kommt später mit dem Apple Developer Program dazu.

⚠️ `tests/local_supabase_stub.sql` **nicht** in Supabase ausführen. Die Datei ersetzt Supabase nur für lokale Tests.

## Tests (lokal, ohne Supabase)

Gegen ein lokales PostgreSQL 15+:
```bash
PGHOST=localhost PGUSER=postgres supabase/tests/run_local.sh
```
Der Lauf legt jedes Mal eine frische Testdatenbank an. Geprüft werden: Profil beim Registrieren,
Sichtbarkeit, gesperrte Spalten, Freunde-Regel, QR-Bestätigung, Spielstärke-Berechnung,
Schutz vor doppelter Wertung und Ablehnung.

## Schlüssel – was in die App darf
- **Project URL** und **anon / publishable key**: dürfen in die App und ins Repository.
- **service_role key** und **Datenbank-Passwort**: niemals in die App, ins Repository oder in einen Chat.
