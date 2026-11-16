# CLAUDE.md

Anweisungen für die Zusammenarbeit an der Luanti Education Platform (LEP).

## Projekt

Eine Lernplattform auf Basis von Luanti für Schulen. Das verbindliche Konzept steht in [`docs/konzept.md`](docs/konzept.md). Es ist vor jeder Arbeit die erste Quelle. Die Verzeichnisstruktur steht in der [`README.md`](README.md).

## Arbeitsregeln

1. **Gebaut wird erst nach Rückfrage.** Vor jeder Aufgabe beschreiben, was gebaut werden soll und wie, und auf Zustimmung warten. Das gilt auch für Änderungen an der Dokumentation.
2. **Entscheidungen kritisieren**, wenn sie Doppelentwicklung oder große Verkomplizierung verursachen würden. Erst widersprechen und begründen, dann die Entscheidung des Nutzers umsetzen.
3. **Vorhandenes vor Eigenbau.** Für Bedarf im Survival-Teil zuerst bestehende Mods prüfen: Pflegezustand, Lizenz, Passung.
4. **Sprache:** Code, Bezeichner, Kommentare und Commit-Nachrichten auf Englisch. Texte im Spiel auf Deutsch über Luantis Übersetzungssystem. Dokumentation und Gespräch auf Deutsch.
5. **Das Konzept führt.** Weicht eine Entscheidung vom Konzept ab, wird zuerst das Konzept angepasst, dann der Code.

## Git-Vorgehensweise

### Zweige und Pull Requests

- Nie direkt auf `main` schreiben.
- Jede Aufgabe bekommt einen eigenen Zweig und einen Pull Request.
- Der Nutzer prüft und führt zusammen. Claude führt nie selbst zusammen.
- Pull Requests bleiben klein: eine Aufgabe, ein Thema.
- Kein Überschreiben der Historie auf geteilten Zweigen.
- Es gibt keine GitHub-Issues. Die Reihenfolge im Konzept und das Gespräch bestimmen die Aufgaben.

Zweignamen: `<bereich>/<kurze-beschreibung>`, zum Beispiel `setup/project-skeleton`, `mods/core-formspec-helpers`, `backend/accounts`.

### Ablauf einer Aufgabe

1. Vorhaben beschreiben und auf Zustimmung warten.
2. Auf dem Zweig bauen, mit Tests.
3. Pull Request öffnen mit: was, warum, wie getestet, was offen ist.
4. Dem Nutzer eine kurze Anleitung geben: wie er seine Testumgebung auf den Stand bringt und wie er die Änderung im Spiel prüft, Schritt für Schritt mit dem erwarteten Ergebnis.
5. Rückmeldung einarbeiten.

Für die Anleitung in Schritt 4 gilt:

- Zweige mit `git switch` wechseln, nicht mit `git checkout`.
- Immer den Start als Server angeben (`scripts/dev-run.sh --server`). Der Nutzer verbindet sich mit einem Luanti-Client auf `127.0.0.1`, Port `30000`.
- Der Nutzer testet unter Arch Linux mit dem dortigen Luanti-Paket. Es kann eine Version hinter der Zielversion liegen.
- Auf dem Server gelten Privilegien wie im echten Betrieb. Dazusagen, welche Schritte der Admin ausführt und welche ein Spieler ohne Admin-Rechte.

### Commits

- Englisch, kurz, im Imperativ: `Add reward chest inventory`.
- Ein Commit pro abgeschlossenem Gedanken.

### Qualität

- Kein Pull Request ohne Tests für Lua-Kerne und Backend.
- Automatische Prüfungen auf GitHub: Busted und Luacheck für Lua, Tests und Clippy für Rust, Typprüfung und Lint für die Oberfläche. Sie werden mit dem ersten Code eingerichtet.
- Ein Pull Request mit fehlgeschlagenen Prüfungen gilt als nicht fertig.
- Nicht getestete Teile im Pull Request ausdrücklich benennen, zum Beispiel alles, was nur im laufenden Spiel prüfbar ist.

### Was nie ins Repository gehört

- Zugangsdaten, Schlüssel, Passwörter.
- Schülerdaten, auch nicht als Testdaten. Testdaten sind erfunden.
- Kopien fremder Mods. Sie werden über `third_party/mods.toml` in fester Version geladen.

## Technische Leitlinien

### Lua-Mods

- Jeder Mod heißt `lep_<name>` und liegt unter `mods/`.
- Zwei Schichten pro Mod:
  - `src/`: Kern in reinem Lua, ohne `core.`-Aufrufe. Daten und Logik.
  - `game/`: Schicht zum Spiel. Fenster, Blöcke, Befehle, Rückruffunktionen.
- Tests mit Busted in `spec/`, für jeden Kern.
- Mods sprechen über Anmeldefunktionen miteinander (`register_on_...`), nicht über direkte Aufrufe in fremde Interna.
- Formspecs werden selbst geschrieben, ohne Fenster-Bibliothek. Jedes Fenster nutzt die Hilfsschicht aus `lep_core`.
- Eingaben aus Fenstern nie trauen. Rechte beim Absenden erneut prüfen, Zustand pro Spieler auf dem Server halten.
- Sensible Block-Metadaten als privat markieren.
- HUD statt Fenster, wenn keine Eingabe nötig ist.
- Keine Spielerobjekte speichern, nur Namen.
- Privilegien beschreiben Handlungen, keine Rollen.
- Jeder Ortswechsel eines Spielers läuft über `lep_places`. Kein Mod teleportiert selbst.
- Schutz nur über Luantis Standardfunktion abfragen, nie direkt beim Schutz-Mod.
- Speicher-Backend vom restlichen Code trennen.

### Backend, Agent und Oberfläche

- Backend und Agent in Rust, Oberfläche in Vue mit Pinia und Router, geschrieben in JavaScript ohne TypeScript-Syntax.
- Die Typen der Schnittstelle liegen einmal in `crates/protocol`. Daraus entsteht die OpenAPI-Beschreibung und daraus die Typen der Oberfläche. Die Oberfläche bindet sie über JSDoc-Kommentare ein, eine automatische Prüfung gleicht sie mit dem Code ab.
- Die Welt ruft das Backend an, nie umgekehrt: HTTPS, Long Polling, ein Schlüssel pro Welt.
- Jedes Ereignis hat eine eindeutige ID. Das Backend verwirft Doppelte.
- Das Spiel muss ohne Backend weiterlaufen.
- Der Agent kennt nur eine feste Liste von Aufträgen und führt keine beliebigen Befehle aus.

### Datenschutz

- Dauerhaft wird nur der Stand gespeichert, nicht der Verlauf.
- Protokolle speichern den Kontonamen, nicht den Wunschnamen.
- Details stehen im Konzept, Abschnitt 12.

## Arbeitsumgebung von Claude

Die Arbeitsumgebung ist pro Sitzung neu. Was hier steht, muss zu Beginn einer Sitzung bei Bedarf wieder eingerichtet werden.

- Erreichbar sind GitHub (nur per `git clone`), Codeberg, LuaRocks, ContentDB und die Luanti-Paketquelle.
- Archiv-Downloads von GitHub (`.../archive/...tar.gz`) sind gesperrt. Einige LuaRocks-Pakete laden so ihre Quellen. Abhilfe: das Repository klonen, in der Rockspec die `url` auf `git+https://...` setzen und `luarocks make` ausführen. Betroffen waren `lua-term` und `mediator_lua`, beides Abhängigkeiten von Busted.
- Lua 5.1, LuaJIT und LuaRocks kommen aus den Systempaketen (`lua5.1 liblua5.1-0-dev luajit luarocks`).
- Luanti: Das Paket `minetest_5.18.0-ppa0~ubuntu24.04.1_amd64.deb` aus `ppa.launchpadcontent.net/minetestdevs/stable` direkt herunterladen und mit `apt-get install ./datei.deb` installieren. `add-apt-repository` funktioniert nicht.
- Der Server braucht in dieser Umgebung `ipv6_server = false`, `enable_ipv6 = false` und `bind_address = 127.0.0.1` in der Konfiguration.
- Screenshots aus dem Spiel sind möglich: `Xvfb` als virtueller Bildschirm, Client mit `LIBGL_ALWAYS_SOFTWARE=1` und `enable_sound = false`, Aufnahme mit `import -window root` (Pakete `xvfb xdotool libgl1-mesa-dri imagemagick`). Vorher die Tageszeit auf Mittag setzen, sonst ist das Bild nachts schwarz.
- Abläufe im Spiel lassen sich mit einem kleinen Hilfsmod in `.dev/mods/` prüfen, der nach dem Beitritt Schritte ausführt und ins Log schreibt. Er wird nicht eingecheckt. Vor jedem Lauf alte Luanti-Prozesse beenden, sonst startet der Server nicht.
- Rust (`cargo`) und Node (`node`, `npm`) sind vorhanden, crates.io und die npm-Registry sind erreichbar.
- Prüfungen vor jedem Pull Request: `scripts/test.sh` (Lua und Rust; `scripts/test.sh lua` oder `rust` für einen Teil), dazu ein Start der Testwelt mit `scripts/dev-setup.sh` und `scripts/dev-run.sh --server`, um das Laden der Mods im Log zu prüfen.

## Lizenzen

Siehe [`LICENSE.md`](LICENSE.md). Neue Dateien gehören zu dem Teil, in dessen Verzeichnis sie liegen.
