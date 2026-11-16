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

Das führt Luacheck und Busted für alle Mods aus. Dieselben Prüfungen laufen bei jedem Pull Request automatisch auf GitHub.

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
| `/lep_trophy bronze \| gold \| daily <anzahl>` | gibt dir einen Testpokal oder erhöht deinen Zähler gelöster Tagesaufgaben |
| `/lep_rewards_reset [<spieler>]` | setzt das Tageslimit der Tagesaufgaben zurück, als hätte ein neuer Tag begonnen |
| `/lep_report <aufgabe> [fail \| daily \| daily_low \| daily_high] [<niveau>]` | meldet eine Aufgabe des Testmoduls: gelöst als Niveauaufgabe, falsch, oder gelöst als Tagesaufgabe mit normalem, geringem oder hohem Aufwand. Niveau 2 und 4 sind Etappen. Aufgaben: `a1`, `a2` (Niveau 1), `b1`, `b2` (2), `c1` (3), `d1` (4) |

### Hinweise

- Die Skripte setzen `LUANTI_USER_PATH` und zusätzlich das ältere `MINETEST_USER_PATH`. Neuere Luanti-Versionen geben für das ältere eine Warnung aus, die sich ignorieren lässt.
- Die Verknüpfung des Modpacks ist mit Luanti 5.17 und 5.18 geprüft.
- Fremde Mods stehen in `third_party/mods.toml`, jeder mit festem Commit. `scripts/dev-setup.sh` lädt sie nach `.dev/third_party/` und schaltet sie in der Testwelt ein. Dafür braucht das Skript Netzzugang. Ändert sich ein Commit in der Liste, holt der nächste Lauf die neue Version. Einstellungen eines fremden Mods stehen ebenfalls in der Liste (`settings.<name> = <wert>`). Das Skript schreibt sie in `.dev/minetest.conf` und ersetzt dort einen vorhandenen Wert.

## 6. Backend und Oberfläche

**Wird erst ab Schritt 6 gebraucht.**

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

Wie Backend und Oberfläche gebaut und gestartet werden, wird ergänzt, sobald sie existieren.

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
