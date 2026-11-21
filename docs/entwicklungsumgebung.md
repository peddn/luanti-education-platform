# Entwicklungsumgebung unter Arch Linux

Diese Anleitung beschreibt, wie die Testumgebung für die Luanti Education Platform auf Arch Linux mit KDE eingerichtet wird.

**Stand:** 15. November 2026. Die Befehle sind nach den Paketlisten von Arch zusammengestellt, aber noch nicht auf einem Arch-System ausprobiert. Wenn ein Schritt nicht funktioniert, bitte hier korrigieren.

Die Anleitung wächst mit dem Projekt. Abschnitte, die erst später gebraucht werden, sind entsprechend gekennzeichnet.

## Überblick

| Werkzeug | Wofür | Ab Schritt |
|---|---|---|
| Git | Quellcode | 1 |
| Luanti (Client und Server) | Spiel ausführen und testen | 1 |
| Minetest Game | Basisspiel | 1 |
| LuaJIT, Lua 5.1, LuaRocks | Lua-Tests außerhalb des Spiels | 1 |
| Busted, Luacheck | Testen und Prüfen der Lua-Mods | 1 |
| Rust | Backend und Agent | 6 |
| Node.js, npm | Oberfläche | 6 |
| SQLite | Datenbank des Backends | 6 |

Die Schrittnummern beziehen sich auf die Reihenfolge der Umsetzung im [Konzept](konzept.md), Abschnitt 15.

## 1. Systempakete

```sh
sudo pacman -Syu
sudo pacman -S --needed git base-devel luanti luanti-server luajit lua51 luarocks
```

- `luanti` ist der Client mit Oberfläche, `luanti-server` der Server ohne Oberfläche.
- Luanti führt Mods mit LuaJIT aus, das sich wie Lua 5.1 verhält. Die Tests laufen deshalb mit Lua 5.1.
- `base-devel` wird gebraucht, weil LuaRocks einige Pakete übersetzt.

Version prüfen:

```sh
luanti --version
```

Das Projekt setzt immer die neueste stabile Version von Luanti voraus, zurzeit 5.18. Arch lieferte zum Stand dieser Anleitung 5.17. Zum Testen geht das, solange ein Mod keine neuere Funktion nutzt. Funktioniert etwas nur mit der neueren Version, steht das im jeweiligen Pull Request.

## 2. Testwerkzeuge für Lua

Busted und Luacheck werden pro Benutzer über LuaRocks installiert, für Lua 5.1:

```sh
luarocks --lua-version 5.1 --local install busted
luarocks --lua-version 5.1 --local install luacheck
luarocks --lua-version 5.1 --local install dkjson
```

Damit die Programme gefunden werden, diese Zeile in `~/.bashrc` oder `~/.zshrc` eintragen:

```sh
eval "$(luarocks --lua-version 5.1 path --bin)"
```

Danach ein neues Terminal öffnen und prüfen:

```sh
busted --version
luacheck --version
```

## 3. Minetest Game

Minetest Game wird nicht mit Luanti ausgeliefert.

1. Luanti starten.
2. Reiter **Inhalte** öffnen, dann **Online-Inhalte durchsuchen**.
3. Nach „Minetest Game“ suchen und installieren.

Luanti legt das Spiel im Benutzerverzeichnis ab. Wo dieses Verzeichnis liegt, zeigt Luanti im Reiter **Über** mit dem Knopf **Benutzerdatenverzeichnis öffnen**. Üblich ist `~/.minetest`.

## 4. Repository

```sh
mkdir -p ~/projekte
cd ~/projekte
git clone https://github.com/peddn/luanti-education-platform.git
cd luanti-education-platform
```

Für das Prüfen von Pull Requests ist die GitHub-Kommandozeile praktisch, aber nicht nötig:

```sh
sudo pacman -S --needed github-cli
gh auth login
gh pr checkout <nummer>
```

## 5. Testwelt und Tests

Das Projekt nutzt ein eigenes Luanti-Benutzerverzeichnis im Repository: `.dev/`. Es wird nicht eingecheckt. Dein normales Luanti-Verzeichnis bleibt unberührt, und Schritt 3 ist für die Entwicklung nicht nötig, weil das Skript Minetest Game selbst lädt.

### Testwelt anlegen

```sh
scripts/dev-setup.sh
```

Das Skript

- lädt Minetest Game nach `.dev/games/`,
- verknüpft das Modpack `mods/` nach `.dev/mods/lep`, sodass Änderungen an den Mods ohne Kopieren wirken,
- legt die Testwelt `.dev/worlds/dev` an und schaltet darin alle LEP-Mods ein.

Beim ersten Lauf fragt das Skript nach dem Spielernamen des Admins und trägt ihn in `.dev/minetest.conf` ein. Dieser Spieler hat auf dem Testserver alle Privilegien, auch die für die Debug-Befehle. Der Name muss genau so geschrieben sein wie später bei der Anmeldung im Client. Ohne Rückfrage geht es so:

```sh
LEP_ADMIN_NAME=deinname scripts/dev-setup.sh
```

Das Skript kann beliebig oft laufen. Nach dem Anlegen eines neuen Mods muss es einmal laufen, damit der Mod in der Testwelt eingeschaltet wird.

### Testserver starten

```sh
scripts/dev-run.sh --server
```

Der Server lauscht auf Port 30000. Ob die Mods geladen wurden, zeigt die Ausgabe im Terminal, zum Beispiel `[lep_core] loaded`. Beendet wird der Server mit Strg+C. Nach einer Änderung an einem Mod oder an `.dev/minetest.conf` muss er neu gestartet werden.

### Mit dem Client verbinden

1. Luanti starten und den Reiter **Spiel beitreten** öffnen.
2. Adresse `127.0.0.1`, Port `30000`.
3. Als Admin beim ersten Mal **Registrieren** wählen, mit dem Namen aus der Einstellung `name` (in der Testumgebung `tester`) und einem Passwort. Luanti legt Konten nicht stillschweigend an.
4. Danach mit **Anmelden** verbinden.

**Die Welt ist geschlossen.** Nur der Admin kann sein Konto durch Registrieren anlegen. Jeder andere unbekannte Name wird abgewiesen: „Ein Konto mit diesem Namen gibt es nicht.“ Konten, die es in der Welt schon gibt, funktionieren weiter.

Weitere Konten entstehen über die Oberfläche (Abschnitt „Schülerkonten“). Für einen zweiten Spieler ohne Admin-Rechte dort ein Konto anlegen und mit Name und Passwort vom Zugangszettel anmelden. Eine Lehrkraft legt die Schulverwaltung an (Abschnitt „Lehrkräfte“). Ein Schülerkonto wird im Browser nie Lehrkraft, auch wenn ihm der Admin im Spiel Privilegien gibt.

### Ohne Server starten

```sh
scripts/dev-run.sh
```

Luanti startet direkt in der Testwelt, als Einzelspieler. Das geht schneller, bildet aber Rechte und mehrere Spieler nicht ab.

### Tests ausführen

```sh
scripts/test.sh
```

Das führt Luacheck und Busted für alle Mods aus, danach Formatprüfung, Clippy und Tests für die Rust-Pakete, zuletzt die Prüfungen der Oberfläche. Dieselben Prüfungen laufen bei jedem Pull Request automatisch auf GitHub. Mit `scripts/test.sh lua`, `scripts/test.sh rust` oder `scripts/test.sh frontend` läuft nur ein Teil.

### Auf den neuesten Stand bringen

Nach dem Zusammenführen eines Pull Requests:

```sh
git checkout main
git pull
scripts/dev-setup.sh
```

Das Skript schaltet neue Mods in der Testwelt ein. Um einen offenen Pull Request zu testen, statt `main` dessen Zweig auschecken und danach ebenfalls `scripts/dev-setup.sh` ausführen.

### Debug-Hilfen

Das Skript trägt `lep_debug = true` in `.dev/minetest.conf` ein. Damit laden die Mods zusätzliche Befehle und Testorte, die es auf einem echten Server nicht gibt. Die Befehle brauchen das Privileg `lep_debug`. Der Admin des Testservers hat es automatisch, im Einzelspieler ebenfalls.

| Befehl | Wirkung |
|---|---|
| `/lep_place` | zeigt den aktuellen Ort |
| `/lep_place lep_places:debug_room` | versetzt in den Testort hoch über der Welt |
| `/lep_place lep_places:wilderness` | versetzt zurück in die Wildnis |
| `/lep_room enter` | bringt dich in deinen Testraum und baut ihn, falls nötig |
| `/lep_room leave` | zurück an den vorigen Ort, also Lobby oder Wildnis |
| `/lep_room info` | zeigt Raumtyp und Besitzer des Raums, in dem du stehst |
| `/lep_room clear` | leert den Innenraum |
| `/lep_room rebuild` | baut den Raum neu, in dem du stehst |
| `/lep_room rebuild <spieler> <raumtyp>` | baut einen bestimmten Raum neu |
| `/lep_room rebuild all [<raumtyp>]` | baut alle Räume neu |
| `/lep_lobby` | bringt dich in die Halle der Lobby |
| `/lep_lobby room [<spieler>]` | bringt dich vor deinen persönlichen Raum oder den eines anderen |
| `/lep_lobby leave` | von der Lobby in die Wildnis |
| `/lep_lobby rebuild` | baut Halle, Gänge und Räume neu |
| `/lep_math` und `/lep_math leave` | bringt dich in deinen Rechenraum und wieder hinaus. Kein Testbefehl, er gilt für alle Spieler |
| `/lep_trophy bronze \| gold \| daily <anzahl>` | gibt dir einen Testpokal oder erhöht deinen Zähler gelöster Tagesaufgaben |
| `/lep_rewards_reset [<spieler>]` | setzt das Tageslimit der Tagesaufgaben zurück, als hätte ein neuer Tag begonnen |
| `/lep_chests` | listet alle Aufgabentruhen mit Position und Restzeit |
| `/lep_chests spawn` | lässt sofort eine Aufgabentruhe in 30 bis 80 Blöcken Entfernung erscheinen und nennt Position und Richtung |
| `/lep_chests age <minuten>` | macht die erzeugten Truhen älter, als wären so viele Minuten vergangen. Damit lässt sich das Verschwinden prüfen, ohne zu warten |
| `/lep_report <aufgabe> [fail \| daily \| daily_low \| daily_high] [<niveau>]` | meldet eine Aufgabe des Testmoduls: gelöst als Niveauaufgabe, falsch, oder gelöst als Tagesaufgabe mit normalem, geringem oder hohem Aufwand. Niveau 2 ist eine Etappe, Niveau 4 schließt das Modul ab. Der Befehl meldet für das eigene Konto und braucht `lep_debug`. Aufgaben: `a1`, `a2` (Niveau 1), `b1`, `b2` (2), `c1` (3), `d1` (4) |

### Fenster im Spiel

Alle Fenster sehen gleich aus. Die Bausteine dafür liegen in der Hilfsschicht `lep_core.formspec`:

| Baustein | Wofür |
|---|---|
| `fs:title(text)` | Überschrift des Fensters: größer, fett, mit Linie darunter. Der Inhalt beginnt bei `formspec.CONTENT_TOP` |
| `fs:close(text)` | Knopf „Schließen“ unten rechts. Jedes Fenster hat einen |
| `fs:highlight(name, art)` | Hebt einen Knopf hervor. `formspec.ACTIVE` für die aktuelle Stellung eines Schalters, `formspec.OTHER` für eine andere Möglichkeit als die, um die es im Fenster geht |
| `fs:heading(x, y, text)` | Zwischenüberschrift in einem großen Fenster, fett |
| `fs:big_label(x, y, text)` | Große Schrift für die eine Sache, um die es geht, etwa die Aufgabe |
| `fs:separator(y)` | Linie, die einen Teil absetzt |
| `formspec.PADDING` | Abstand zum Rand |

Das Pult hat Reiter statt einer Überschrift. Seine Teile tragen Zwischenüberschriften.

Farben und Schriftgrößen stehen nur in der Hilfsschicht. Ein neues Fenster setzt keine eigenen.

### Wunschnamen

Ein Rechtsklick auf das Türschild des eigenen Raums in der Lobby öffnet das Fenster für den Wunschnamen. Fremde Schilder tun nichts. Der Name gilt sofort: über der Figur, im Chat, am Türschild und in der Liste des Pults. Protokolle und das Log des Servers nennen weiter den Kontonamen.

- Erlaubt sind 2 bis 16 Zeichen: Buchstaben, auch ä, ö, ü und ß, Ziffern, dazu einzelne Leerzeichen und Bindestriche in der Mitte.
- Vergeben ist ein Name, den es als Kontonamen oder als Wunschnamen schon gibt, ohne Rücksicht auf Groß- und Kleinschreibung.
- Ein neuer Name ist 30 Tage nach dem letzten möglich. Solange die Frist läuft oder das Wählen gesperrt ist, zeigt das Fenster kein Eingabefeld, nur den Grund.
- „Kontoname wiederherstellen“ geht immer, auch dann, und steht im Fenster abgesetzt unter einer Linie. Die Frist verkürzt es nicht.
- Wer das Pult öffnen darf und im Spiel ist, bekommt bei jeder Änderung eine Nachricht mit Konto und neuem Namen.
- Jede Änderung steht im Protokoll `lep_protocols/names.tsv` im Ordner der Welt.

Ist die Welt mit dem Backend verbunden, meldet sie den Stand jedes Kontos nach jeder Änderung. In der Web-Anwendung zeigt die Liste der Schüler dann den Wunschnamen mit dem Tag der Änderung:

- „Wunschname entfernen“ und „Wählen sperren“ oder „Wählen freigeben“ sind Aufträge an die Welt. Bis sie geantwortet hat, steht bei dem Konto „Änderung wartet auf die Welt“.
- „Verlauf“ zeigt, was mit den Namen eines Kontos geschah. Er kommt aus dem Protokoll `names`, das die Welt ans Backend weitergibt.
- Das Suchfeld über der Liste filtert nach Konto und Wunschname.
- Bei jedem neuen Wunschnamen eines Schülers schreibt das Backend den Lehrkräften der Gruppe eine Mail mit Konto und Namen. Ohne Mailserver steht sie im Terminal des Backends. Für Namen von Lehrkräften und für „Zurück zum Kontonamen“ gibt es keine Mail.

Ohne Browser, und zum Ausprobieren, gibt es drei Debug-Befehle:

| Befehl | Wirkung |
|---|---|
| `/lep_name_remove <konto>` | nimmt den Wunschnamen weg, das Konto darf sofort neu wählen |
| `/lep_name_lock <konto> on\|off` | sperrt das Wählen oder gibt es frei, der Name bleibt |
| `/lep_name_wait <konto>` | beendet die Frist von 30 Tagen |

Andere Mods fragen `lep_accounts.get_display_name(name)` und speichern den Namen nie. Mit `lep_accounts.register_on_display_name_changed` erfahren sie von Änderungen.

### Lehrkräfte

Lehrkräfte legt die Schulverwaltung auf der Seite „Lehrkräfte“ an. Dort setzt sie auch Passwörter zurück und löscht Konten. Der Zugangszettel mit dem Startpasswort erscheint einmal. Die neue Lehrkraft meldet sich damit im Spiel an und richtet im Lehrerpult (`/pult`, Reiter „Web-Zugang“) ihre Mailadresse ein. Die Schnittstelle dahinter:

| Aufruf | Wirkung |
|---|---|
| `GET /api/web/v1/staff` | alle Lehrkräfte mit Stand, Web-Zugang und Gruppen |
| `POST /api/web/v1/staff` mit `{"name": "…"}` | legt das Konto in jeder Welt an und antwortet einmal mit dem Zugangszettel |
| `POST /api/web/v1/staff/{konto}/password` | neues Startpasswort in jeder Welt, Antwort ist der Zettel |
| `POST /api/web/v1/staff/{konto}/removal` mit `{"confirm": "<konto>"}` | löscht das Konto in jeder Welt |

- Der Name hat 2 bis 19 Zeichen aus Buchstaben, Ziffern, `_` und `-` und darf an der Schule weder vergeben noch gelöscht worden sein.
- Die Welt gibt dem neuen Konto die Privilegien des Bündels „Lehrkraft“: `lep_view_players`, `lep_send_players`, `lep_watch_players`, `lep_set_attention`, `lep_set_mode`, `lep_set_time`, `lep_mute_players`, `lep_place_quest_chest` und `lep_web_access`. Die Liste steht in `mods/lep_accounts/src/accounts.lua`. Einzelne Privilegien vergibt und nimmt weiter der Admin im Spiel.
- Geschützt sind der Admin aus der Einstellung `name` und jedes Konto mit `lep_manage_school`, `privs` oder `server`: Für sie nimmt die Welt von außen weder ein Passwort noch eine Löschung an (`staff`). Im Backend kommt dazu: Niemand ändert das eigene Konto.
- Die Welt schreibt Anlegen, neues Passwort und Löschen ins Protokoll des Pults (`web:create_teacher`, `web:reset_teacher_password`, `web:remove_teacher`), unter dem Konto der Schulverwaltung.
- Ein Konto aus einer Schülerliste erkennt das Backend nie als Lehrkraft oder Schulverwaltung an, was auch immer die Welt meldet.
- Wer in keiner Welt mehr `lep_web_access` hat, verliert seine Zuordnungen zu Gruppen.

### Konto löschen

Ein Konto lässt sich mit allem löschen, was die Welt darüber weiß (Konzept, Abschnitt 12). Ohne Browser gibt es dafür einen Debug-Befehl:

| Befehl | Wirkung |
|---|---|
| `/lep_account_remove <konto>` | löscht das Konto, wie es die Schulverwaltung darf |
| `/lep_account_remove <konto> unused` | löscht es nur, wenn sich noch nie jemand damit angemeldet hat, wie es die Lehrkraft darf |

- Wer gerade im Spiel ist, bekommt eine Meldung und wird getrennt. Danach kommt niemand mehr mit diesem Namen herein.
- Konten von Lehrkräften und des Admins werden abgelehnt (`staff`), unbekannte Namen auch (`unknown`). Mit `unused` wird ein benutztes Konto abgelehnt (`used`).
- Gelöscht werden: Zugang, Wunschname, Fortschritt, Trophäen, der Inhalt der Belohnungstruhe, gemerkte Orte und Inventar, das eigene Portal, die Zähler des Awards-Mods, das Bett als Wiedereinstiegspunkt und die Einträge des Kontos in allen Protokollen samt der privaten Nachrichten an das Konto.
- Das Zimmer in der Lobby wird leer zurückgebaut, das Schild ist blank. Das nächste neue Konto zieht dort ein. Lernräume werden geleert und nicht wieder vergeben.
- Nicht gelöscht wird, was in der Karte steht: Bauwerke, Schilder, Bücher und geschützte Bereiche in der Survival-Welt. Auch Luantis Logdatei bleibt. Der Awards-Mod kann einen Eintrag nur leeren: Der Kontoname bleibt dort ohne Daten stehen.

Mit Backend:

- Der Auftrag `remove_account` kommt vom Backend, wenn im Browser jemand ein Konto löscht (`POST /api/web/v1/groups/{id}/students/{konto}/removal` mit dem Kontonamen als Bestätigung). Eine Lehrkraft der Gruppe löscht nur nie benutzte Konten, die Schulverwaltung jedes Schülerkonto. Die Welt prüft das noch einmal selbst.
- Die Welt meldet jede Löschung mit dem Ereignis `account_removed`, auch eine mit dem Debug-Befehl. Erst dann löscht das Backend seine Kopien und schreibt den dauerhaften Vermerk (`GET /api/web/v1/removals`, nur Schulverwaltung).
- Bis dahin steht das Konto in der Liste mit „Löschung wartet“. Ein wartender Auftrag lässt sich zurücknehmen (`DELETE` auf dieselbe Adresse).
- Bei jeder Anmeldung meldet die Welt mit `account_used`, dass das Konto benutzt wird.
- Was über das Konto noch in der Warteschlange der Brücke liegt, wird bei der Löschung verworfen.
- Im Browser: In der Schülerliste steht bei jedem angelegten Konto „Konto löschen“, für Lehrkräfte nur bei Konten, mit denen sich noch nie jemand angemeldet hat. Ein Feld zeigt, was gelöscht wird und was nicht, bestätigt wird durch Eintippen des Kontonamens. Die Schulverwaltung sieht die Vermerke unter „Löschungen“.

Ein Mod, der etwas über Spieler speichert, meldet mit `lep_core.register_on_forget_account(function(konto) … end)` eine Funktion an, die es löscht. Wirft sie einen Fehler, bleibt das Konto bestehen und die Löschung lässt sich wiederholen. `lep_accounts.remove(name, { only_unused = …, by = … }, callback)` löst alles aus.

### Hinweise

- Die Skripte setzen `LUANTI_USER_PATH` und zusätzlich das ältere `MINETEST_USER_PATH`. Neuere Luanti-Versionen geben für das ältere eine Warnung aus, die sich ignorieren lässt.
- Die Verknüpfung des Modpacks ist mit Luanti 5.17 und 5.18 geprüft.
- Spieler sehen einander nur bis 160 Blöcke Entfernung. `lep_places` setzt dafür `player_transfer_distance = 10`, solange in `.dev/minetest.conf` kein eigener Wert steht. Ohne die Grenze stünden die Namensschilder aus Lobby und Lernräumen am Himmel über der Wildnis.
- Minetest Game steht mit festem Commit in `third_party/game.toml`. `scripts/dev-setup.sh` lädt genau diese Version nach `.dev/games/`.
- Fremde Mods stehen in `third_party/mods.toml`, jeder mit festem Commit. `scripts/dev-setup.sh` lädt sie nach `.dev/third_party/` und schaltet sie in der Testwelt ein. Dafür braucht das Skript Netzzugang. Ändert sich ein Commit in der Liste, holt der nächste Lauf die neue Version. Einstellungen eines fremden Mods stehen ebenfalls in der Liste (`settings.<name> = <wert>`). Das Skript schreibt sie in `.dev/minetest.conf` und ersetzt dort einen vorhandenen Wert.

## 6. Backend und Oberfläche

Das Backend ist ein Rust-Programm im Ordner `backend/`. Die Typen seiner Schnittstelle liegen in `crates/protocol/`. Die Oberfläche ist eine Vue-Anwendung im Ordner `frontend/`.

```sh
sudo pacman -S --needed rustup nodejs npm sqlite
rustup default stable
```

Prüfen:

```sh
cargo --version
node --version
npm --version
sqlite3 --version
```

### Backend starten

```sh
scripts/backend-run.sh
```

Der erste Lauf lädt und übersetzt die Bibliotheken, das dauert einige Minuten. Danach meldet das Terminal `listening on http://127.0.0.1:8080`. Beendet wird mit Strg+C.

Prüfen, in einem zweiten Terminal:

```sh
curl http://127.0.0.1:8080/api/health
```

Erwartete Antwort: `{"status":"ok"}`. Mehr sagt dieser Weg nicht, weil ihn jeder aufrufen kann. Version und Einzelheiten zeigt die Seite „Zustand“ nach der Anmeldung. Die Beschreibung der Schnittstelle liefert `http://127.0.0.1:8080/api/openapi.json`.

### Einstellungen

Das Backend liest seine Einstellungen aus Umgebungsvariablen.

| Variable | Bedeutung | Voreinstellung |
|---|---|---|
| `LEP_BIND` | Adresse und Port | `127.0.0.1:8080` |
| `LEP_DATABASE` | Pfad der SQLite-Datei | `.dev/backend/lep.sqlite` |
| `LEP_FRONTEND` | Ordner mit der gebauten Oberfläche | `frontend/dist` |
| `LEP_PUBLIC_URL` | Adresse der Web-Anwendung, wie Browser sie erreichen. Damit beginnen die Links in Mails. | `http://127.0.0.1:8080` |
| `LEP_SMTP_HOST` | Name des Mailservers. Ohne ihn stehen Mails nur im Terminal. | nicht gesetzt |
| `LEP_SMTP_SECURITY` | Schutz der Verbindung: `starttls`, `tls` oder `none` | `starttls` |
| `LEP_SMTP_PORT` | Port des Mailservers | 587 bei `starttls`, 465 bei `tls`, 25 bei `none` |
| `LEP_SMTP_USER`, `LEP_SMTP_PASSWORD` | Anmeldung am Mailserver, beide oder keine | nicht gesetzt |
| `LEP_MAIL_FROM` | Absender, etwa `LEP <lep@schule.example>`. Pflicht, sobald ein Mailserver gesetzt ist. | nicht gesetzt |

Einstellungen, die nicht in der Befehlszeile stehen sollen, gehören in die Datei `.dev/backend.env`, eine Zeile `NAME=wert` je Einstellung. `scripts/backend-run.sh` liest sie bei jedem Start. Der Ordner `.dev/` wird nie eingecheckt.
| `RUST_LOG` | Ausführlichkeit der Meldungen | `info` |

Die Datenbank der Testumgebung liegt in `.dev/` und wird nicht eingecheckt. Wer sie löscht, bekommt beim nächsten Start eine leere. Tabellen entstehen und ändern sich über Migrationen in `backend/migrations/`, das Backend spielt sie beim Start von selbst ein.

### Testwelt mit dem Backend verbinden

Der Mod `lep_bridge` verbindet eine Welt mit dem Backend. Dafür braucht die Welt die Adresse des Backends, ihren Schlüssel und die Erlaubnis für Netzzugriff. Für die Testwelt erledigt das ein Skript:

```sh
scripts/dev-bridge.sh
```

Es legt im lokalen Backend die Welt `dev` an und trägt drei Zeilen in `.dev/minetest.conf` ein: `secure.http_mods`, `lep_bridge_url` und `lep_bridge_key`. Ein erneuter Lauf vergibt einen neuen Schlüssel. Danach beide starten, jedes in seinem Terminal:

```sh
scripts/backend-run.sh
scripts/dev-run.sh --server
```

Im Terminal der Welt steht `[lep_bridge] connecting to http://127.0.0.1:8080`. Ob die Verbindung steht, zeigen im Spiel `/lep_bridge` (braucht das Privileg `server`) und im Terminal:

```sh
scripts/backend-run.sh world list
```

Ohne laufendes Backend spielt die Welt normal weiter. Luanti schreibt dann für jeden vergeblichen Versuch eine Zeile `HTTPFetch ... failed` ins Terminal, die Brücke selbst meldet den Ausfall einmal und versucht es in wachsenden Abständen erneut, höchstens jede Minute.

### Reihenfolge beim Aktualisieren

Nach einem Wechsel des Zweigs oder einem `git pull` immer **zuerst das Backend** neu starten, **dann die Welt**. Ein laufendes Backend bleibt auf seinem alten Stand, bis es beendet und neu gestartet wird.

Kennt das Backend ein Ereignis der Welt nicht, antwortet es mit „unbekannt“, und die Welt verwirft das Ereignis. Für Fortschritt und Trophäen ist das harmlos, `scripts/backend-run.sh world sync dev` holt den Stand nach. Protokolleinträge aus dieser Zeit fehlen dem Backend aber dauerhaft, sie stehen dann nur in den Dateien der Welt.

Die Welt meldet den Fall einmal deutlich im Terminal (`THE BACKEND DOES NOT KNOW EVENTS OF THIS WORLD`), und `/lep_bridge` zeigt, wie viele Ereignisse verworfen wurden.

### Befehle des Backends

| Befehl | Wirkung |
|---|---|
| `scripts/backend-run.sh` | startet den Server |
| `scripts/backend-run.sh world add <name>` | legt eine Welt an, die von Hand eingerichtet wird, und zeigt ihren Schlüssel, nur dieses eine Mal |
| `scripts/backend-run.sh world create <name>` | legt eine Welt an und beauftragt den Agenten, sie auf dem Spielserver einzurichten und zu starten. Den Schlüssel sieht niemand |
| `scripts/backend-run.sh world start <name>`, `stop`, `restart` | beauftragt den Agenten, eine seiner Welten zu starten, zu stoppen oder neu zu starten |
| `scripts/backend-run.sh world rekey <name>` | gibt einer Welt einen neuen Schlüssel, der alte gilt nicht mehr |
| `scripts/backend-run.sh world list` | listet die Welten mit letztem Kontakt |
| `scripts/backend-run.sh world ping <name>` | stellt einen Ping-Auftrag ein, um den Weg zur Welt und zurück zu prüfen |
| `scripts/backend-run.sh world state <name>` | zeigt, was das Backend von einer Welt weiß: Module, Fortschritt, Trophäen, Protokolle |
| `scripts/backend-run.sh world sync <name>` | bittet die Welt, ihren ganzen Stand noch einmal zu senden |
| `scripts/backend-run.sh mail test <adresse>` | schickt eine Probemail über den eingestellten Mailserver |
| `scripts/backend-run.sh agent key` | gibt dem Agenten einen Schlüssel und zeigt ihn, nur dieses eine Mal. Ein älterer Schlüssel gilt nicht mehr |
| `scripts/backend-run.sh agent show` | zeigt, was der Agent zuletzt über den Spielserver gemeldet hat |
| `scripts/backend-run.sh teacher list` | listet die Lehrkräfte: Adresse, ob sie bestätigt ist, und in wie vielen Welten das Privileg gilt |
| `scripts/update-openapi.sh` | schreibt `api/openapi.json` und die Typen der Oberfläche neu, nach Änderungen an der Schnittstelle |

Die Befehle arbeiten direkt auf der Datenbank und brauchen keinen laufenden Server. Ein Ping, der so eingestellt wird, erreicht eine verbundene Welt innerhalb von 25 Sekunden.

### Agent

Der Agent ist ein eigenes Rust-Programm im Ordner `agent/`. Im Betrieb läuft er auf dem Spielserver (Konzept, Abschnitt 11.3). Er meldet dem Backend alle 30 Sekunden seine Version, den freien Speicherplatz, die Version seiner Vorlage und seine Welten. Er holt Aufträge beim Backend ab: Welt anlegen, starten, stoppen, neu starten. Welten laufen als Dienste von systemd, auch in der Testumgebung, dort als Dienste des eigenen Benutzers. Ohne systemd lehnt der Agent das Starten ab und sagt warum.

In der Testumgebung läuft er neben dem Backend, in einem dritten Terminal:

```sh
scripts/agent-run.sh
```

Beim ersten Start lässt das Skript das Backend einen Schlüssel erzeugen und schreibt die Einstellungen nach `.dev/agent.toml`. Die Datei ist nur für dich lesbar und wird nie eingecheckt. Der Ordner des Agenten ist `.dev/agent/`.

| Befehl | Wirkung |
|---|---|
| `scripts/agent-run.sh` | startet den Agenten, Ende mit Strg+C |
| `scripts/agent-run.sh check` | liest die Einstellungen, schickt eine einzelne Meldung und sagt, ob das Backend sie angenommen hat |
| `scripts/agent-run.sh --new-key` | erzeugt vorher einen neuen Schlüssel, etwa nach dem Löschen der Datenbank des Backends |

Der Agent trägt die Vorlage für Welten in sich: Minetest Game, die eigenen und die fremden Mods. In der Testumgebung baut sie ein eigenes Skript:

```sh
scripts/template-build.sh
```

Es lädt Spiel und fremde Mods in den festen Versionen aus `third_party/game.toml` und `third_party/mods.toml` und legt das Archiv nach `target/lep-template/`. `scripts/agent-run.sh` bettet es beim nächsten Start ein, und der Agent packt es nach `.dev/agent/templates/<Version>/` aus. Die Version ist der Anfang einer Prüfsumme über den Inhalt: Ändert sich ein Mod, entsteht nach erneutem `scripts/template-build.sh` eine neue Version neben der alten. Ohne das Skript läuft der Agent ohne Vorlage und sagt das beim Start.

Ein einfaches `cargo build` oder `cargo test` bettet keine Vorlage ein und braucht kein Netz. Für einen Server baut `scripts/agent-build.sh` Vorlage und Agent in einem Schritt.

Was der Agent meldet, zeigt die Web-Anwendung auf der Seite „Zustand“ im Kasten „Spielserver“, und im Terminal `scripts/backend-run.sh agent show`. Nach 90 Sekunden ohne Meldung gilt der Spielserver als nicht erreichbar.

Die Einstellungen sind eine kleine Datei:

```toml
backend = "https://lep.schule.example"
key = "lepa_…"
data_dir = "/var/lib/lep-agent"
```

- `backend`: Adresse des Backends. Sie muss mit `https://` beginnen, weil der Schlüssel mit jeder Anfrage mitreist. Nur ein Backend auf derselben Maschine darf mit `http://` erreicht werden.
- `key`: der Schlüssel aus `agent key`.
- `data_dir`: Ordner für alles, was der Agent anfasst. Ohne Angabe `/var/lib/lep-agent`.
- `admin`: Kontoname des Server-Admins, den der Agent in jede neue Welt einträgt. Ohne Angabe legt er keine Welten an. `scripts/agent-run.sh` übernimmt beim ersten Start den Namen aus `.dev/minetest.conf`.
- `ports`: Bereich der Ports für die Welten, ohne Angabe `30000-30099`.
- `luanti`: Pfad des Luanti-Servers für die Welten, ohne Angabe `/usr/local/bin/luantiserver`.
- `host`: Name oder Adresse des Spielservers für die Spieler, ohne Port. Daraus und aus dem Port bildet das Backend die Adresse jeder Welt des Agenten. Ohne Angabe wird die Adresse von Hand eingetragen.

Der Agent liest die Datei aus `/etc/lep/agent.toml` oder von dem Pfad hinter `--config`. Ist das Backend nicht erreichbar oder lehnt es den Schlüssel ab, läuft der Agent weiter und versucht es alle 30 Sekunden erneut. Im Terminal steht nur, wenn sich etwas ändert.

Löschst du die Datenbank des Backends (`.dev/backend/`), kennt es den Schlüssel nicht mehr. Der Agent meldet dann „the backend refuses the key“. `scripts/agent-run.sh --new-key` behebt das.

### Web-Zugang einer Lehrkraft

Eine Lehrkraft richtet ihren Web-Zugang im Lehrerpult ein, Reiter „Web-Zugang“. Den Reiter sieht, wer das Privileg `lep_web_access` hat. Der Admin vergibt es im Spiel:

```
/grant <name> lep_web_access
```

Voraussetzung: Die Testwelt ist mit dem Backend verbunden (`scripts/dev-bridge.sh`), und die Oberfläche ist gebaut (`scripts/frontend-run.sh build`), denn der Link aus der Mail öffnet eine Seite der Oberfläche.

**Mails stehen im Terminal**, solange kein Mailserver eingestellt ist (siehe „Mailversand“). Das Backend schreibt dann jede Mail in sein Terminal, zwischen zwei Linien aus Strichen. Den Link darin im Browser öffnen und dort „Adresse bestätigen“ klicken. Ein Link gilt 15 Minuten und einmal.

Die Welt meldet dem Backend, welche Konten das Privileg haben, beim Start und bei jeder Änderung. Nur für diese Konten nimmt das Backend Meldungen zum Web-Zugang an. `scripts/backend-run.sh teacher list` zeigt, was das Backend weiß.

### Anmelden im Browser

Ohne Anmeldung zeigt die Oberfläche nur die Seiten „Anmelden“ und „Adresse bestätigen“. Anmelden kann sich, wer eine bestätigte Adresse hat und in mindestens einer Welt das Privileg `lep_web_access`.

1. `http://127.0.0.1:8080/` öffnen und die bestätigte Adresse eintragen.
2. Die Mail mit dem Link steht im Terminal des Backends. Die Seite antwortet immer gleich, auch bei unbekannter Adresse; dann steht keine Mail im Terminal.
3. Den Link im selben Browser öffnen und „Anmelden“ klicken.

Ein Link gilt 15 Minuten und einmal, eine neue Mail gibt es frühestens nach einer Minute. Die Anmeldung gilt 12 Stunden und verlängert sich nicht. Entzieht der Admin das Privileg (`/revoke <name> lep_web_access`), ist die Anmeldung beim nächsten Klick beendet.

Die Sitzung ist ein Cookie für `/api/web`. Über den Entwicklungsserver auf Port 5173 funktioniert sie ebenso, dort gilt sie aber getrennt von Port 8080. Für Links, die auf den Entwicklungsserver zeigen sollen, das Backend mit `LEP_PUBLIC_URL=http://127.0.0.1:5173` starten.

Der Weg `/api/health` bleibt ohne Anmeldung erreichbar, für Prüfungen von außen. Er sagt nur, ob das Backend arbeiten kann. Die Seite „Zustand“ in der Oberfläche braucht die Anmeldung und zeigt dazu die Version und wie Mails rausgehen.

### Gruppen

Eine Gruppe ist eine Welt, eins zu eins. Mit einem Agenten legt die Schulverwaltung sie auf der Seite „Gruppen“ an (`POST /api/web/v1/groups`), der Agent richtet die Welt ein. Die Seite zeigt den Zustand der Welt: von Hand eingerichtet, wird eingerichtet, läuft, gestoppt oder abgelehnt. Eine abgelehnte Gruppe lässt sich erneut einrichten (`POST /api/web/v1/groups/{id}/setup`) oder verwerfen (`DELETE /api/web/v1/groups/{id}`), beides nur durch die Schulverwaltung und nur, solange die Welt nie entstanden ist. Die Welt einer Gruppe lässt sich starten, stoppen und neu starten (`POST /api/web/v1/groups/{id}/world` mit `step`), durch die Lehrkräfte der Gruppe und die Schulverwaltung. Ohne Agenten legt der Server-Admin die Gruppe mit `scripts/backend-run.sh world add <name>` an, für die Testwelt erledigt das `scripts/dev-bridge.sh`.

| Rolle | Privileg im Spiel | Sieht | Darf |
|---|---|---|---|
| Lehrkraft | `lep_web_access` | die Gruppen, denen sie zugeordnet ist | ansehen |
| Schulverwaltung | zusätzlich `lep_manage_school` | alle Gruppen | umbenennen, Lehrkräfte zuordnen |

Der Admin vergibt die Schulverwaltung im Spiel:

```
/grant <name> lep_manage_school
```

Die Welt meldet beide Privilegien ans Backend, beim Start und bei jeder Änderung. Wird eines entzogen, gilt das im Browser beim nächsten Klick.

Zum Ausprobieren mit zwei Rollen braucht es zwei Konten mit bestätigter Adresse, also zwei Adressen. Ohne Mailserver in `.dev/backend.env` stehen die Mails im Terminal, dann genügen erfundene Adressen wie `leitung@schule.example`.

Der Name einer Gruppe ist zugleich der Name, den die Befehle des Backends erwarten (`world ping`, `world state`). Nach dem Umbenennen der Testwelt in der Oberfläche `scripts/dev-bridge.sh` nicht erneut ausführen: Es würde eine zweite Welt namens `dev` anlegen. Stattdessen `scripts/backend-run.sh world rekey <neuer name>`, falls ein neuer Schlüssel nötig ist.

### Schülerkonten

Auf der Seite einer Gruppe führt „Schülerkonten“ zur Liste der Konten. Zugang haben die Lehrkräfte der Gruppe und die Schulverwaltung.

1. Anzahl eintragen und „Namen würfeln“. Die Namen sind zuerst ein Entwurf und lassen sich einzeln neu würfeln oder entfernen.
2. „Konten anlegen“ beauftragt die Welt und zeigt die Zugangszettel mit den Startpasswörtern. Sie stehen nur jetzt dort: Das Backend bewahrt sie nicht auf.
3. Die Welt legt die Konten an, sobald sie verbunden ist. Der Stand wechselt von „wird in der Welt angelegt“ zu „angelegt“. Danach baut sie im Hintergrund für jedes neue Konto den Raum in der Lobby, den Rechenraum und die Zelle für den Aufmerksamkeitsmodus. Im Log steht am Ende `rooms for … new account(s) built in … s`. Für 25 Konten dauert das etwa eine halbe Minute.

Auf jedem Zettel gibt es ein Feld für den Namen des Kindes. Die Namen bleiben im Browser und stehen nur auf dem Ausdruck, leere Felder werden nicht gedruckt.

Die Adresse auf den Zetteln trägt die Schulverwaltung auf der Seite der Gruppe ein. Für die Testumgebung ist das `127.0.0.1, Port 30000`.

Gibt es einen gewürfelten Namen in der Welt schon, etwa aus der Zeit, als man sich noch selbst registrieren konnte, lehnt die Welt ihn ab und fasst das vorhandene Konto nicht an. Der Name steht dann als „von der Welt abgelehnt“ in der Liste.

**Passwort zurücksetzen.** Bei einem angelegten Konto steht „Passwort zurücksetzen“. Nach der Rückfrage zeigt die Seite einen Zettel mit dem neuen Startpasswort, nur einmal. Das alte gilt, bis die Welt das neue übernommen hat. Solange steht beim Konto „neues Passwort wartet auf die Welt“.

Die Welt setzt ein Passwort nur für ein gewöhnliches Konto. Hat das Konto mehr als die Privilegien eines neuen Spielers, lehnt sie ab. Privilegien, die ein Ort vergibt, zählen nicht mit: `lep_places.get_granted_privileges(name)` nennt sie, auch für Spieler, die nicht da sind. In der Liste steht dann „neues Passwort von der Welt abgelehnt“, im Log der Welt `password for … not set: staff`. Das Passwort einer Lehrkraft setzt der Admin im Spiel.

### Seiten, die sich selbst aktualisieren

Die Seiten einer Gruppe („Gruppe“, „Schüler“, „Fortschritt“) halten eine Verbindung zum Backend offen: `GET /api/web/v1/groups/{id}/changes`, Server-Sent Events. Das Backend schickt darüber nur ein Signal, welcher Teil sich geändert hat (`group`, `students` oder `progress`), nie die Daten. Die Seite lädt den Teil dann über die üblichen Wege neu.

- Ein Signal gibt es, wenn die Welt etwas meldet, wenn sie einen Auftrag beantwortet und wenn jemand im Browser etwas an der Gruppe ändert.
- Mehrere Signale kurz hintereinander werden zu einem Laden.
- Aufgeklappte Teile und Eingaben bleiben beim Laden erhalten. Solange Zugangszettel gezeigt werden, lädt die Seite nichts.
- Ist die Verbindung weg, steht das in einer Zeile auf der Seite. Der Browser verbindet sich von selbst wieder, danach lädt die Seite einmal alles.
- Die Verbindung endet mit der Sitzung und wenn das Backend beendet wird.

Zum Zusehen: `curl -N -b cookies.txt http://127.0.0.1:8080/api/web/v1/groups/<id>/changes` zeigt die Signale im Terminal.

Das Backend endet bei Strg+C jetzt sofort. Vorher wartete es bis zu 25 Sekunden auf die Anfrage einer verbundenen Welt.

### Protokolle

Auf der Seite einer Gruppe führt „Protokolle“ zu dem, was die Welt mitgeschrieben hat: Chat, Schilder, Belohnungen, Wunschnamen und Lehrerpult. Dazu kommt die Liste der Exporte. Aus der Liste der Schüler führt „Protokolle“ direkt zu den Einträgen eines Kontos.

- Gezeigt wird, was die Welt seit ihrer Verbindung mit dem Backend gemeldet hat, neueste Einträge zuerst, 100 je Seite.
- Filter: Konto und Zeitraum. Die Protokolle nennen den Kontonamen, darunter steht der Wunschname von heute.
- Das Protokoll des Pults sieht nur, wer in einer Welt `lep_manage_school` hat. Für alle anderen fehlt der Reiter, und das Backend antwortet mit `forbidden`.
- Kommen neue Einträge, während die Seite offen ist, bleibt die Tabelle stehen. Ein Knopf darüber sagt, wie viele warten, und zeigt sie auf Klick.
- „Als CSV herunterladen“ liefert die gefilterten Einträge als Datei: älteste zuerst, Zeiten in UTC, Zellen mit Semikolon getrennt. Texte, die eine Tabellenkalkulation für eine Formel halten würde, bekommen ein Hochkomma vorangestellt. 
- Jeder Download wird festgehalten: wer, wann, welches Protokoll, mit welchen Filtern und wie viele Einträge. Das steht im Reiter „Exporte“, den wie das Lehrerpult nur die Schulverwaltung sieht. Auch der Download dieser Liste wird eingetragen. Das Backend führt sie selbst, die Welt weiß nichts davon.

### Jahresabschluss

Die Seite „Jahresabschluss“ steht nur der Schulverwaltung in der Navigation, also einem Konto mit `lep_manage_school`. Sie zeigt je Gruppe, wie viele Einträge in Protokollen und Exportliste gelöscht würden.

- Zum Auslösen tippt man das Wort „LÖSCHEN“ ein. Das Backend löscht dann seine Kopien aller Protokolle und die Liste der Exporte und schickt jeder Welt den Auftrag `clear_protocols`.
- Die Welt löscht alle Dateien in `lep_protocols/`. Im Log steht `[lep_bridge] <konto> closed the year: deleting all protocols` und `[lep_core] deleted n protocol file(s)`.
- Läuft eine Welt nicht, wartet der Auftrag. Die Seite zeigt bei der Gruppe „hat ihre Protokolle noch nicht gelöscht“ und fragt alle paar Sekunden nach.
- Konten, Fortschritt, Trophäen und Wunschnamen bleiben.
- Dass und wann abgeschlossen wurde, bleibt unten auf der Seite stehen: wer, wann, wie viel.
- Einträge, die eine Welt vor dem Abschluss geschrieben hat und erst danach meldet, nimmt das Backend an und verwirft sie.

Mods, die Jahresdaten an anderer Stelle halten, melden sich mit `lep_core.protocols.register_on_clear` an. Archive und Sicherungen von Welten kommen mit dem Agenten dazu.

### Belohnungen

Jede Welt hat eine Belohnungstabelle: je Anlass ein Gegenstand mit Anzahl, dazu das Tageslimit der Tagesaufgaben.

| Anlass | Vorgabe |
|---|---|
| `task`: Niveauaufgabe gelöst | 1 Stahlbarren |
| `daily`: Tagesaufgabe gelöst | 1 Goldbarren |
| `level`: Niveau abgeschlossen | 1 Goldbarren |
| `stage`: Etappe abgeschlossen | 1 Diamant |
| `module`: Modul abgeschlossen | 3 Diamanten |

- Der Aufwand vervielfacht die Anzahl: gering einfach, normal doppelt, hoch dreifach. Ein Modul nennt seinen Aufwand beim Anmelden (`effort`, ohne Angabe gering), eine Tagesaufgabe beim Melden (ohne Angabe normal). Die Aufgabentruhe in der Wildnis ist eine Tagesaufgabe mit normalem Aufwand und bringt deshalb das Doppelte der Zeile „Tagesaufgabe“.
- Für einen Abschluss gibt es genau eine Belohnung. Das letzte Niveau eines Moduls ist nie eine Etappe: Es bringt die Belohnung für das Modul und die goldene Trophäe „… abgeschlossen“.
- `lep_rewards.get_table()`, `lep_rewards.set_table(tabelle)` und `lep_rewards.reset_table()` lesen und ändern die Tabelle zur Laufzeit. Sie wird nur als Ganzes angenommen. Eine Änderung gilt ab der nächsten Belohnung.
- Im Spiel zeigt `/lep_rewards`, was es wofür gibt.
- Die Gegenstände, aus denen eine Lehrkraft wählen kann, legt der Admin mit der Einstellung `lep_rewards_choices` fest (Namen mit Komma getrennt). Ohne Einstellung gilt eine Liste aus Barren, Kohle, Diamant, Mesekristall, Apfel, Brot, Fackel und Buch. Was die Welt nicht kennt, fällt heraus.
- Im Browser: Auf der Seite einer Gruppe führt „Belohnungen“ zur Tabelle. Dort wählt die Lehrkraft je Anlass Gegenstand und Anzahl, stellt das Tageslimit ein und kann die Vorgabe wiederherstellen. Bis die Welt geantwortet hat, steht dort „Änderung wartet auf die Welt“.
- Mit Backend: Die Welt meldet Tabelle und Auswahlliste mit dem Ereignis `rewards`, bei jedem Start und nach jeder Änderung. `GET /api/web/v1/groups/{id}/rewards` zeigt beides, `PUT` auf dieselbe Adresse bestellt eine neue Tabelle (`{"table": …}`) oder die Vorgabe (`{}`). Die Welt prüft noch einmal und schreibt `web:set_rewards` oder `web:reset_rewards` ins Protokoll des Pults. Ändern dürfen die Lehrkräfte der Gruppe und die Schulverwaltung.
- Die früheren Einstellungen `lep_rewards_small`, `lep_rewards_medium`, `lep_rewards_large` und `lep_rewards_daily_limit` gibt es nicht mehr.
- Im Protokoll der Belohnungen steht statt der Größe jetzt der Aufwand. Ältere Einträge zeigen in dieser Spalte nichts.

### Fortschritt

Auf der Seite einer Gruppe führt „Fortschritt“ zur Tabelle der Schüler und Module. Sie zeigt, was die Welt zuletzt gemeldet hat, und aktualisiert sich von selbst.

Ein Klick auf ein Feld klappt die Aufgaben des Niveaus auf. Dort lässt sich ein Niveau setzen und der Aufstieg sperren oder freigeben. Beides ist ein Auftrag an die Welt:

- Im Log der Welt steht `[lep_desk] <lehrkraft> used web:set_level <modul> <niveau> on <schüler>` und `job set_level …: done set`.
- Im Protokoll des Pults (`lep_protocols/desk.tsv` im Ordner der Welt) steht dieselbe Zeile unter dem Konto der Lehrkraft.
- Bis die Welt geantwortet hat, steht im Feld „Änderung wartet auf die Welt“. Läuft die Welt nicht, bleibt das so, bis sie sich wieder meldet.
- Lehnt die Welt ab, steht im Feld „Änderung von der Welt abgelehnt“ und im Log `failed unknown` (kein solches Konto), `failed module` oder `failed level`.

Steht ein Kind auf einem Niveau, dessen Pensum voll ist, etwa mit gesperrtem Aufstieg oder auf dem letzten Niveau, bietet das Feld „Niveau wiederholen“ an. Das bestellt dasselbe Niveau noch einmal, und die Welt leert dessen Pensum.

In der Testwelt gibt es neben „Kopfrechnen“ das „Testmodul“ aus den Debug-Hilfen.

Das **Startniveau** eines Moduls gilt für jedes Konto, über das die Welt in diesem Modul noch nichts gespeichert hat: keine gelöste Aufgabe, kein gesetztes Niveau, keine Sperre. Wer schon etwas getan hat, bleibt, wo er ist. Die übersprungenen Niveaus gelten nicht als abgeschlossen, es gibt für sie weder Belohnung noch Trophäe.

- Eingestellt wird es auf der Seite „Fortschritt“ im Kasten „Startniveau“, auch bevor es Schüler gibt. Dahinter steht `POST /api/web/v1/groups/{id}/progress/start/{modul}` mit `{"level": n}`. Die Welt speichert es (`lep_progress.set_start_level`), schreibt `web:set_start_level <modul> <niveau>` ins Protokoll des Pults und meldet es mit ihren Modulen.
- Im Log der Welt steht `[lep_progress] start level of <modul> is now <niveau>`.
- Andere Mods fragen `lep_progress.get_start_level(modul)` und erfahren von Änderungen mit `lep_progress.register_on_start_level_changed`.

„Als CSV herunterladen“ liefert den Stand der Gruppe als Datei `fortschritt-<gruppe>.csv`: eine Zeile je Schüler und Modul, Zellen mit Semikolon getrennt.

| Spalte | Inhalt |
|---|---|
| `account` | Kontoname |
| `display_name` | Wunschname, leer ohne |
| `module` | Titel des Moduls |
| `level`, `levels` | aktuelles Niveau und Zahl der Niveaus |
| `percent` | Anteil des Pensums im aktuellen Niveau |
| `completed`, `locked` | `yes` oder `no`: Modul abgeschlossen, Aufstieg gesperrt |

Die Spaltennamen sind englisch wie beim Export der Protokolle, das Backend kennt keine Sprache. Jeder Download steht im Exportprotokoll der Gruppe als „Fortschritt“, mit Konto und Zahl der Zeilen. Das Exportprotokoll sieht nur die Schulverwaltung.

### Mailversand

Ohne Mailserver schreibt das Backend jede Mail in sein Terminal. Für echten Versand die Einstellungen in `.dev/backend.env` eintragen, zum Beispiel:

```sh
LEP_SMTP_HOST=mail.schule.example
LEP_SMTP_USER=lep@schule.example
LEP_SMTP_PASSWORD=...
LEP_MAIL_FROM=LEP <lep@schule.example>
```

Das Passwort steht nur in dieser Datei, nie im Repository und nie in einem Gespräch.

Prüfen, ob es klappt:

```sh
scripts/backend-run.sh mail test <deine-adresse>
```

Der Befehl meldet sich am Mailserver an, schickt eine Probemail und sagt, ob der Mailserver sie angenommen hat. Ob sie ankommt, zeigt das Postfach. Schlägt etwas fehl, nennt die Meldung den Grund, etwa einen falschen Port oder ein abgelehntes Passwort.

Beim Start meldet das Backend dann `mails are sent through ...`. Einstellungen, die nicht zusammenpassen, beenden es sofort mit einer Meldung, zum Beispiel ein Mailserver ohne Absender oder ein Name ohne Passwort.

- Mails gehen im Hintergrund raus. Wer einen Link anfordert, bekommt die Antwort sofort, egal ob eine Mail rausgeht.
- Scheitert der Versand, steht das im Protokoll des Backends mit dem Kontonamen, ohne Adresse und ohne Link. Die Lehrkraft fordert die Mail neu an.
- `none` als Schutz ist mit Passwort nur für einen Mailserver auf demselben Rechner erlaubt.
- Das Backend prüft das Zertifikat des Mailservers gegen die üblichen öffentlichen Stellen. Ein selbst ausgestelltes Zertifikat lehnt es ab.

### Oberfläche

Die Oberfläche lässt sich auf zwei Arten starten.

**Gebaut, vom Backend ausgeliefert.** So läuft sie später im Betrieb, und so reicht es zum Ausprobieren:

```sh
scripts/frontend-run.sh build
scripts/backend-run.sh
```

Der erste Befehl lädt beim ersten Lauf die npm-Pakete nach `frontend/node_modules/` und baut die Oberfläche nach `frontend/dist/`. Das Backend meldet beim Start `serving the frontend` und liefert sie unter `http://127.0.0.1:8080/` aus. Fehlt der Ordner, meldet es `no built frontend found` und bedient nur die Schnittstelle. Nach einem Wechsel des Zweigs neu bauen, das Backend muss dafür nicht neu starten.

**Entwicklungsserver.** Zum Arbeiten an der Oberfläche, jede Änderung erscheint sofort im Browser:

```sh
scripts/backend-run.sh      # erstes Terminal
scripts/frontend-run.sh     # zweites Terminal
```

Die Oberfläche steht dann unter `http://127.0.0.1:5173/`. Anfragen an `/api` reicht der Entwicklungsserver an das Backend auf Port 8080 weiter, `LEP_DEV_URL` ändert das Ziel.

Aufbau in `frontend/src/`:

| Ort | Inhalt |
|---|---|
| `api/client.js` | die eine Stelle, die mit dem Backend spricht |
| `api/schema.d.ts` | Typen der Schnittstelle, erzeugt aus `api/openapi.json`, nie von Hand ändern |
| `stores/` | Zustand mit Pinia |
| `pages/`, `components/` | Seiten und Bausteine |
| `locales/de.json`, `locales/en.json` | alle Texte, in beiden Sprachen mit denselben Schlüsseln |
| `router.js`, `i18n.js` | Adressen der Seiten, Wahl der Sprache |

Regeln, die die Prüfungen durchsetzen:

- **Kein Text in einer Seite.** Jeder Text steht in beiden Sprachdateien und wird über `$t('schlüssel')` geholt. ESLint lehnt Text direkt in einer Vorlage ab, ebenso unbekannte und ungenutzte Schlüssel. Ein Test vergleicht die Schlüssel beider Sprachen.
- **Fehler haben einen festen Code.** Das Backend antwortet bei einem Fehler mit `{"code": "...", "message": "..."}`. Die Oberfläche zeigt den Text zu `errors.<code>` aus den Sprachdateien, die englische `message` ist nur für Protokolle da. Ein neuer Code in `crates/protocol` braucht einen Eintrag in beiden Sprachdateien, ein Test prüft das.
- **Typen kommen aus der Schnittstelle.** Der Code ist JavaScript, die Typen stehen in JSDoc-Kommentaren und verweisen auf `schema.d.ts`. Die Typprüfung (`npm run typecheck`) findet damit Tippfehler in Feldnamen, auch in den Vorlagen. Nach einer Änderung an der Schnittstelle `scripts/update-openapi.sh` ausführen, sonst schlägt die Prüfung auf veraltete Typen fehl.

Die Sprache richtet sich nach dem Browser, Deutsch ist die Rückfallsprache. Die Auswahl oben rechts gilt für diesen Browser und bleibt gespeichert.

## 7. Empfohlene Werkzeuge

Nicht nötig, aber hilfreich:

- Ein Editor mit Unterstützung für Lua und Rust, zum Beispiel Kate (bei KDE dabei) oder VS Code.
- `lua-language-server` für Hinweise beim Schreiben von Lua:

  ```sh
  sudo pacman -S --needed lua-language-server
  ```

## Fehlersuche

**`busted: command not found`**
Die Zeile aus Abschnitt 2 fehlt in der Shell-Konfiguration, oder das Terminal wurde danach nicht neu geöffnet.

**LuaRocks installiert für die falsche Lua-Version**
Immer `--lua-version 5.1` angeben. Ohne die Angabe nimmt LuaRocks die neueste installierte Lua-Version.

**Minetest Game erscheint nicht in der Spielauswahl**
Im Reiter **Über** das Benutzerdatenverzeichnis öffnen und prüfen, ob dort `games/minetest_game` liegt.
