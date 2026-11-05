# ABC-Zug Kreis Heinsberg – Fahrzeug-Checklisten

Webanwendung zum Prüfen der Fahrzeugbeladung per Checkliste. Fehlende oder defekte Teile werden gespeichert und sind für berechtigte Personen als Bestellliste einsehbar. Dazu kommen Geräte mit Prüffristen und ein Lagerbestand.

Die Seite ist eine einzelne statische Datei (`index.html`) und nutzt **Supabase** als Backend (Datenbank, Anmeldung, Edge Function).

## Funktionen

- **Prüfen** – Fahrzeug wählen, Positionen mit *OK / Fehlt / Defekt* abhaken. Positionen können aufklappbare Inhalte haben (z. B. Verbandskasten → Pflaster, Schere …).
- **Fehlbestand** – zeigt, was bei der jeweils letzten Prüfung je Fahrzeug fehlte; Positionen lassen sich als „bestellt“ markieren, die Bestellliste kann kopiert oder gedruckt werden.
- **Historie** – wer wann welche Checkliste geprüft hat, mit Details zu Abweichungen.
- **Geräte** – Geräte mit Prüfintervall, letzter und nächster Prüfung; Übersicht über überfällige und bald fällige Prüfungen.
- **Lager** – Lagerbestand mit Mindestmengen und Plus/Minus-Bedienung.
- **Verwaltung** – Fahrzeuge und Checklisten pflegen, Benutzer verwalten.
- Zwei Einheiten (Heinsberg, Hückelhoven) mit getrennten Ansichten je nach Zuordnung.
- Für Handy und Tablet optimiert.

## Einheiten

Es gibt zwei Teileinheiten: **Heinsberg** und **Hückelhoven**. Fahrzeuge, Geräte und Lagerbestand gehören jeweils zu genau einer Einheit.

- **Nutzer** und **Gerätewart** werden einer Einheit zugeordnet und sehen und verwalten nur deren Fahrzeuge, Geräte, Lager, Fehlbestand und Historie. Ohne Zuordnung sehen sie nichts.
- **Einheitsführung** und **Admin** sehen beide Einheiten und können oben in der Seite zwischen „Alle Einheiten“, Heinsberg und Hückelhoven umschalten.

## Rollen

| Rolle | Rechte |
|---|---|
| Nutzer | Checklisten der eigenen Einheit abhaken |
| Gerätewart | zusätzlich: in der eigenen Einheit alles anlegen und ändern (Fahrzeuge, Checklisten, Geräte, Lager), Fehlbestand und Historie sehen |
| Einheitsführung | wie Gerätewart, aber für beide Einheiten; dazu Nutzer-Konten anlegen und verwalten (Einheit, Passwort, sperren, löschen) |
| Admin | alles, dazu Rollen vergeben |

Die Rechte werden in der Datenbank durchgesetzt (Row Level Security), nicht nur in der Oberfläche.

## Anmeldung

Benutzernamen haben das Format `Vorname.Nachname`. Intern wird daraus die E-Mail `vorname.nachname@abc-zug-heinsberg.de` (Domain in `index.html` als `USER_DOMAIN` und in der Edge Function). Es wird keine E-Mail verschickt. Eine Selbstregistrierung gibt es nicht; Benutzer legen Admin oder Einheitsführung in der Verwaltung an.

## Einrichtung

1. **Supabase-Projekt** anlegen.
2. Migrationen aus `supabase/migrations/` der Reihe nach ausführen (SQL-Editor oder `supabase db push`).
3. **Edge Function** `admin-users` aus `supabase/functions/admin-users/` bereitstellen (`supabase functions deploy admin-users`, JWT-Prüfung aktiv lassen).
4. In `index.html` die Werte `SUPABASE_URL` und `SUPABASE_KEY` (publishable key) auf das eigene Projekt setzen. Der publishable Key ist für den Einsatz im Browser gedacht; geschützt werden die Daten durch die Row-Level-Security-Regeln.
5. In Supabase unter *Authentication → Sign In / Providers* die öffentliche Registrierung ausschalten.
6. Ersten Benutzer im Supabase-Dashboard anlegen (*Authentication → Users*, E-Mail `vorname.nachname@abc-zug-heinsberg.de`, „Auto Confirm“) und ihm per SQL die Rolle Admin geben:

   ```sql
   update public.profiles set role = 'admin' where name = 'Vorname.Nachname';
   ```

7. `index.html` bei einem statischen Hoster veröffentlichen (z. B. Netlify, GitHub Pages).

## Projektstruktur

```
index.html                              die komplette Website
supabase/migrations/                    Datenbankschema in Reihenfolge
supabase/functions/admin-users/         Edge Function für die Benutzerverwaltung
```

## Hinweise

- Die Website funktioniert nur mit Internetverbindung (WLAN/Mobilfunk).
- Benutzer, die schon Prüfungen durchgeführt haben, können nicht gelöscht, sondern nur gesperrt werden – so bleibt die Historie erhalten.
