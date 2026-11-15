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

Das Projekt setzt die aktuelle stabile Version voraus. Arch lieferte zum Stand dieser Anleitung Luanti 5.16.

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

## 5. Mods in Luanti einbinden

**Kommt mit dem ersten Mod.** Sobald `lep_core` existiert, steht hier:

- wie die eigenen Mods aus dem Repository in eine Testwelt eingebunden werden,
- wie die fremden Mods aus `third_party/mods.toml` geladen werden,
- wie eine Testwelt angelegt und gestartet wird,
- wie die Tests laufen.

Der genaue Weg ist noch nicht festgelegt, weil Luanti Verknüpfungen aus dem Benutzerverzeichnis heraus nicht in jedem Fall folgt. Das wird mit dem ersten Mod ausprobiert.

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
