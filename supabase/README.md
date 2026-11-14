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
| `follows` | Folgen wie bei Instagram: `follow`, `unfollow`, `accept_follow`, `remove_follower`, `followers_of`, `following_of`, `follow_requests` |
| `profile_page(id)` | Alles für die Profilseite: Foto, Bio, Heimat-Halle, Zähler, Spielstärke, Serie |
| `search_profiles(text)`, `suggested_profiles()` | Spielersuche und Vorschläge („Hat mit dir gespielt“, „Aus deiner Halle“) |
| `posts`, `home_feed`, `profile_posts`, `profile_results` | Beiträge (Text, Bild, Match) und der Feed der Leute, denen ich folge |
| `reactions`, `comments` | 👏 und Kommentare zu Beiträgen bzw. bestätigten Matches |
| `rematch_requests`, `games_wanted`, `game_joins` | Revanche-Vorschläge und „Spieler gesucht“ |
| `club_ranking`, `club_activity`, `head_to_head` | Hallen-Seite und gemeinsame Matches |
| `device_tokens`, `delete_my_account` | Push-Vorbereitung und Konto-Löschung |
| Storage `avatars`, `posts` | Profilfotos und Beitragsbilder; nur der eigene Ordner ist beschreibbar |
| `my_match_feed()` | Alle Matches, in denen ich spiele – aus meiner Sicht, mit Namen der Mitspieler |

**Sicherheitsregeln (Row Level Security):**
- Profile sind „Öffentlich“ oder „Privat“ (nur bestätigte Follower). Folgen eines öffentlichen Profils gilt sofort, bei privaten muss die Anfrage angenommen werden.
- Ein Match sieht man als Teilnehmer, sonst nur, wenn es bestätigt ist **und** alle Spieler darin für einen sichtbar sind.
- Spielstärke und Bestätigungen lassen sich nicht direkt ändern, nur über die Server-Funktionen.
- Gewertet wird ein Match genau einmal, sobald ein Gegner bestätigt. Abgelehnte Matches werden nie gewertet.
- Alte Freundschaften wurden in gegenseitiges Folgen übernommen.
- Der Ersteller verlinkt Partner und Gegner über ihren Benutzernamen. Der Gegner sieht das Ergebnis
  in seiner App unter „Offene Bestätigungen“ und bestätigt oder lehnt ab. Erst dann zählt es.

## Einrichten (einmalig)

1. Supabase-Projekt anlegen, Region **Frankfurt (eu-central-1)**.
2. Im Supabase-Dashboard **SQL Editor** öffnen.
3. **Nur falls schon ein früherer Stand eingespielt wurde** (Fehler wie `type "profile_visibility" already exists`):
   den Inhalt von `reset.sql` einfügen und auf **Run** klicken. ⚠️ Das löscht alle Pointcheck-Daten.
4. Alle Dateien aus `migrations/` **der Reihe nach** (nach Dateiname sortiert) einfügen und jeweils auf **Run** klicken.
   Alle Migrationen ab dem 11.11. sind so geschrieben, dass ein versehentlicher zweiter Lauf nichts kaputtmacht.
   Die Datei `…_storage.sql` legt die Bild-Buckets an; sie läuft nur in Supabase (nicht lokal).
5. **Anmeldung mit Passwort** (so funktioniert die App):
   - **Authentication → Providers → Email**: „Enable Email provider“ an.
   - Dort **„Confirm email“ ausschalten**, damit neue Konten sofort nutzbar sind. Sonst schickt Supabase erst eine
     Bestätigungs-Mail, und die App meldet „Bitte bestätige zuerst deine E-Mail-Adresse“.
   - **Authentication → URL Configuration**: **Site URL** `pointcheck://login`; bei **Redirect URLs** sowohl
     `pointcheck://login` als auch `pointcheck://reset-password` eintragen. Über die zweite Adresse öffnet der Link
     aus der „Passwort vergessen“-Mail die App direkt im Bildschirm „Neues Passwort“.
   - Die E-Mail-Vorlage **„Reset Password“** kann bleiben wie sie ist (sie enthält den Link).
   - Der eingebaute E-Mail-Versand schickt nur wenige Mails pro Stunde. Für echte Nutzer später einen eigenen
     E-Mail-Dienst (SMTP) unter **Authentication → Emails → SMTP** eintragen.
   - „Mit Apple anmelden“ kommt später mit dem Apple Developer Program dazu.

## Schlüssel – was in die App darf
- **Project URL** und **anon / publishable key**: dürfen in die App und ins Repository.
- **service_role key** und **Datenbank-Passwort**: niemals in die App, ins Repository oder in einen Chat.
