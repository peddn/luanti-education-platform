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
3. Beim ersten Mal **Registrieren** wählen, Name und Passwort eingeben. Luanti legt Konten nicht stillschweigend an.
4. Danach mit **Anmelden** verbinden.

Für Tests mit einem zweiten Spieler ohne Admin-Rechte einfach ein weiteres Konto registrieren. Einzelne Privilegien vergibt der Admin im Spiel mit `/grant <name> <privileg>`.

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
| `/lep_report <aufgabe> [fail \| daily \| daily_low \| daily_high] [<niveau>]` | meldet eine Aufgabe des Testmoduls: gelöst als Niveauaufgabe, falsch, oder gelöst als Tagesaufgabe mit normalem, geringem oder hohem Aufwand. Niveau 2 und 4 sind Etappen. Aufgaben: `a1`, `a2` (Niveau 1), `b1`, `b2` (2), `c1` (3), `d1` (4) |

### Hinweise

- Die Skripte setzen `LUANTI_USER_PATH` und zusätzlich das ältere `MINETEST_USER_PATH`. Neuere Luanti-Versionen geben für das ältere eine Warnung aus, die sich ignorieren lässt.
- Die Verknüpfung des Modpacks ist mit Luanti 5.17 und 5.18 geprüft.
- Spieler sehen einander nur bis 160 Blöcke Entfernung. `lep_places` setzt dafür `player_transfer_distance = 10`, solange in `.dev/minetest.conf` kein eigener Wert steht. Ohne die Grenze stünden die Namensschilder aus Lobby und Lernräumen am Himmel über der Wildnis.
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

Erwartete Antwort: `{"status":"ok","version":"0.1.0","database":true}`. Die Beschreibung der Schnittstelle liefert `http://127.0.0.1:8080/api/openapi.json`.

### Einstellungen

Das Backend liest seine Einstellungen aus Umgebungsvariablen.

| Variable | Bedeutung | Voreinstellung |
|---|---|---|
| `LEP_BIND` | Adresse und Port | `127.0.0.1:8080` |
| `LEP_DATABASE` | Pfad der SQLite-Datei | `.dev/backend/lep.sqlite` |
| `LEP_FRONTEND` | Ordner mit der gebauten Oberfläche | `frontend/dist` |
| `LEP_PUBLIC_URL` | Adresse der Web-Anwendung, wie Browser sie erreichen. Damit beginnen die Links in Mails. | `http://127.0.0.1:8080` |
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
| `scripts/backend-run.sh world add <name>` | legt eine Welt an und zeigt ihren Schlüssel, nur dieses eine Mal |
| `scripts/backend-run.sh world rekey <name>` | gibt einer Welt einen neuen Schlüssel, der alte gilt nicht mehr |
| `scripts/backend-run.sh world list` | listet die Welten mit letztem Kontakt |
| `scripts/backend-run.sh world ping <name>` | stellt einen Ping-Auftrag ein, um den Weg zur Welt und zurück zu prüfen |
| `scripts/backend-run.sh world state <name>` | zeigt, was das Backend von einer Welt weiß: Module, Fortschritt, Trophäen, Protokolle |
| `scripts/backend-run.sh world sync <name>` | bittet die Welt, ihren ganzen Stand noch einmal zu senden |
| `scripts/backend-run.sh teacher list` | listet die Lehrkräfte: Adresse, ob sie bestätigt ist, und in wie vielen Welten das Privileg gilt |
| `scripts/update-openapi.sh` | schreibt `api/openapi.json` und die Typen der Oberfläche neu, nach Änderungen an der Schnittstelle |

Die Befehle arbeiten direkt auf der Datenbank und brauchen keinen laufenden Server. Ein Ping, der so eingestellt wird, erreicht eine verbundene Welt innerhalb von 25 Sekunden.

### Web-Zugang einer Lehrkraft

Eine Lehrkraft richtet ihren Web-Zugang im Lehrerpult ein, Reiter „Web-Zugang“. Den Reiter sieht, wer das Privileg `lep_web_access` hat. Der Admin vergibt es im Spiel:

```
/grant <name> lep_web_access
```

Voraussetzung: Die Testwelt ist mit dem Backend verbunden (`scripts/dev-bridge.sh`), und die Oberfläche ist gebaut (`scripts/frontend-run.sh build`), denn der Link aus der Mail öffnet eine Seite der Oberfläche.

**Mails stehen im Terminal.** Der Mailversand ist noch nicht eingerichtet. Das Backend schreibt jede Mail in sein Terminal, zwischen zwei Linien aus Strichen. Den Link darin im Browser öffnen und dort „Adresse bestätigen“ klicken. Ein Link gilt 15 Minuten und einmal.

Die Welt meldet dem Backend, welche Konten das Privileg haben, beim Start und bei jeder Änderung. Nur für diese Konten nimmt das Backend Meldungen zum Web-Zugang an. `scripts/backend-run.sh teacher list` zeigt, was das Backend weiß.

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
