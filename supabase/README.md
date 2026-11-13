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
| Storage `avatars`, `posts` | Profilfotos und Beitragsbilder; nur der eigene Ordner ist beschreibbar |
| `my_match_feed()` | Alle Matches, in denen ich spiele – aus meiner Sicht, mit Namen der Mitspieler |
| `halls`, `search_halls(text, lat, lon)` | Padel-Hallen mit Koordinaten; Suche nach Name, Stadt, PLZ oder „in der Nähe“ |
| `profiles.home_hall_id` | Heimat-Halle; `home_club` zeigt dann automatisch den Hallennamen |
| `hall_campaigns`, `feed_ads(lat, lon)` | Bezahlte Hallen-Anzeigen im Feed – nur für Spieler im Umkreis der Halle |
| `ad_events`, `log_ad_event`, `campaign_stats`, `campaign_report` | Einblendungen und Klicks; Auswertung pro Kampagne |
| Storage `halls` | Hallen-Logos und Anzeigenbilder (nur das Pointcheck-Team lädt hoch) |

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

## Hallen & Anzeigen verwalten

Hallen und Kampagnen legst du im **SQL Editor** an (dort hast du Admin-Rechte; die App kann sie nur lesen).
Bilder lädst du unter **Storage → halls** hoch und trägst den Dateinamen als `logo_path` / `image_path` ein.
Koordinaten: in Google Maps Rechtsklick auf die Halle → die erste Zahl ist `latitude`, die zweite `longitude`.

```sql
-- 1. Halle anlegen
insert into public.halls (name, street, postal_code, city, latitude, longitude, logo_path, booking_url)
values ('Padel Club Beispiel', 'Musterstraße 1', '50667', 'Köln', 50.9375, 6.9603,
        'padel-club-beispiel/logo.png', 'https://example.com/buchen')
returning id;

-- 2. Kampagne anlegen (id der Halle von oben einsetzen)
insert into public.hall_campaigns
    (hall_id, headline, body, image_path, cta_label, cta_url, radius_km, starts_at, ends_at,
     max_impressions, daily_cap_per_player, price_cents)
values ('<hall-id>', 'Happy Hour: −30 % auf Plätze',
        'Mo–Do 14–17 Uhr. Einfach online buchen.', 'padel-club-beispiel/happy-hour.jpg',
        'Platz buchen', 'https://example.com/buchen', 25,
        '2026-12-01', '2027-01-01', null, 3, 7900);

-- 3. Pausieren / fortsetzen
update public.hall_campaigns set is_paused = true where id = '<campaign-id>';

-- 4. Auswertung pro Tag (für den Monatsbericht an die Halle)
select * from public.campaign_stats where hall = 'Padel Club Beispiel' order by day;

-- 5. Optional: Konto der Halle verknüpfen – dann kann es campaign_report('<campaign-id>') abrufen
insert into public.hall_managers (hall_id, profile_id) values ('<hall-id>', '<profil-id>');
```

**Regeln, die die Datenbank durchsetzt:**
- Eine Anzeige sieht nur, wer im Umkreis `radius_km` der Halle ist – gemessen am ungefähren Standort
  (auf ~1 km gerundet, nicht gespeichert) oder, ohne Standortfreigabe, an der eigenen Heimat-Halle.
- Pro Spieler höchstens `daily_cap_per_player` Einblendungen am Tag; bei mehreren Hallen kommen zuerst die,
  die der Spieler heute noch nicht gesehen hat.
- Mit `max_impressions` endet eine Kampagne automatisch, sobald das bezahlte Volumen erreicht ist.
- Wiederholte Einblendungen desselben Spielers innerhalb von 30 Minuten zählen einmal.
- Spieler können weder Kampagnen noch Einblendungen direkt lesen oder schreiben.
- Die App kennzeichnet jede Anzeige als **„Gesponsert“**, nennt die Halle als Auftraggeber und erklärt unter
  „Warum sehe ich das?“, warum sie angezeigt wird (Kennzeichnungspflicht, EU Digital Services Act).
  Vor dem Start mit echten Hallen: Datenschutzerklärung um Standort und Anzeigen ergänzen.

## Tests (lokal)

```bash
PGHOST=... PGPORT=... PGUSER=postgres supabase/tests/run_local.sh
```

Läuft alle `supabase/tests/*_test.sql` gegen eine frische lokale Datenbank.

## Schlüssel – was in die App darf
- **Project URL** und **anon / publishable key**: dürfen in die App und ins Repository.
- **service_role key** und **Datenbank-Passwort**: niemals in die App, ins Repository oder in einen Chat.
