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
- Der Nutzer testet auf einer VM mit Debian 13, eingerichtet nach [`docs/betrieb.md`](docs/betrieb.md). Die Anleitung nennt die Schritte, um die VM auf den Stand zu bringen (Zweig wechseln, bauen, Programme ablegen, Dienste neu starten), und die Prüfung dort.
- Der Luanti-Client des Nutzers läuft unter Arch Linux und verbindet sich mit der Adresse der VM. Er kann eine Version hinter der Zielversion liegen.
- Solange der Agent auf der VM keine Welten anlegt, gibt es dort keine Welt. Was nur im Spiel prüfbar ist, wird bis dahin als nicht vom Nutzer getestet benannt.
- Die Skripte der Testumgebung (`scripts/dev-setup.sh`, `scripts/dev-run.sh`) nutzt Claude weiter zum Bauen und Prüfen. Anleitungen für den Nutzer beziehen sich nicht darauf.
- Auf dem Server gelten Privilegien wie im echten Betrieb. Dazusagen, welche Schritte der Admin ausführt und welche ein Spieler ohne Admin-Rechte.

### Commits

- Englisch, kurz, im Imperativ: `Add reward chest inventory`.
- Ein Commit pro abgeschlossenem Gedanken.

### Qualität

- Kein Pull Request ohne Tests für Lua-Kerne und Backend.
- Automatische Prüfungen auf GitHub: Busted und Luacheck für Lua, Tests und Clippy für Rust, Lint, Typprüfung und Tests für die Oberfläche.
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
- Alle Fenster sehen gleich aus: Überschrift mit `title`, „Schließen“ mit `close`, hervorgehobene Knöpfe mit `highlight`, Zwischenüberschriften mit `heading`. Farben und Schriftgrößen stehen nur in der Hilfsschicht, kein Fenster setzt eigene. Braucht ein Fenster etwas Neues, kommt es als Baustein in die Hilfsschicht.
- Eingaben aus Fenstern nie trauen. Rechte beim Absenden erneut prüfen, Zustand pro Spieler auf dem Server halten.
- Sensible Block-Metadaten als privat markieren.
- HUD statt Fenster, wenn keine Eingabe nötig ist.
- Keine Spielerobjekte speichern, nur Namen.
- Privilegien beschreiben Handlungen, keine Rollen.
- Jeder Ortswechsel eines Spielers läuft über `lep_places`. Kein Mod teleportiert selbst.
- Schutz nur über Luantis Standardfunktion abfragen, nie direkt beim Schutz-Mod.
- Speicher-Backend vom restlichen Code trennen.

### Backend, Agent und Oberfläche

- Backend und Agent in Rust, Oberfläche in Vue mit Pinia und Router, geschrieben in JavaScript ohne TypeScript-Syntax. Gestaltung mit Tailwind CSS.
- Die Oberfläche ist mehrsprachig (`vue-i18n`, Deutsch und Englisch). Kein Text steht direkt in einer Seite, alles kommt aus den Sprachdateien. Das Backend meldet Fehler mit einem festen Code, den die Oberfläche übersetzt.
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
- Lua 5.1, LuaJIT und LuaRocks kommen aus den Systempaketen (`lua5.1 liblua5.1-0-dev luajit luarocks`). Die Tests brauchen außer Busted und Luacheck das Paket `dkjson`.
- Luanti: Das Paket `minetest_5.18.0-ppa0~ubuntu24.04.1_amd64.deb` aus `ppa.launchpadcontent.net/minetestdevs/stable` direkt herunterladen und mit `apt-get install ./datei.deb` installieren. `add-apt-repository` funktioniert nicht.
- Den Luanti-Server, wie er auf dem Spielserver läuft, baut `scripts/luanti-build.sh` in gut zwei Minuten (Pakete `libluajit-5.1-dev libcurl4-openssl-dev libzstd-dev libgmp-dev libjsoncpp-dev`), abgelegt wird er mit `cmake --install target/luanti/build` als `/usr/local/bin/luantiserver`.
- Der Server braucht in dieser Umgebung `ipv6_server = false`, `enable_ipv6 = false` und `bind_address = 127.0.0.1` in der Konfiguration. Welten, die der Agent anlegt, bekommen die beiden ersten Zeilen von selbst, weil er das fehlende IPv6 erkennt.
- Screenshots aus dem Spiel sind möglich: `Xvfb` als virtueller Bildschirm, Client mit `LIBGL_ALWAYS_SOFTWARE=1` und `enable_sound = false`, Aufnahme mit `import -window root` (Pakete `xvfb xdotool libgl1-mesa-dri imagemagick`). Vorher die Tageszeit auf Mittag setzen, sonst ist das Bild nachts schwarz.
- Abläufe im Spiel lassen sich mit einem kleinen Hilfsmod in `.dev/mods/` prüfen, der nach dem Beitritt Schritte ausführt und ins Log schreibt. Er wird nicht eingecheckt. Vor jedem Lauf alte Luanti-Prozesse beenden, sonst startet der Server nicht.
- systemd läuft in dieser Umgebung nicht von selbst (Container, Ubuntu 24.04 mit systemd 255), lässt sich aber in einem abgetrennten Bereich hochfahren, um Dienste und Linger zu prüfen:
  - Vorher `systemctl mask docker.service docker.socket containerd.service postgresql.service redis-server.service`, sonst starten diese vorinstallierten Dienste mit.
  - Start: `setsid unshare --pid --fork --mount --mount-proc --uts sh -c 'mount --make-rshared /; mount -t tmpfs tmpfs /tmp; mount -t tmpfs tmpfs /run; exec env container=docker /lib/systemd/systemd --system --log-target=console --unit=multi-user.target' >/root/vm-console.log 2>&1 &`. Die eigenen `/tmp` und `/run` sind nötig: Ohne sie leert der Start das echte `/tmp`. `--make-rshared` gilt nur in dem abgetrennten Bereich und ist nötig, damit abgeschottete Dienste wie der Agent später eingehängte Ordner sehen, etwa `/run/user/<uid>`. Ohne es meldet der Agent nach einem Neustart alle Welten als gestoppt, was auf einer echten Maschine nicht geschieht.
  - Befehle darin: `nsenter -t <PID von systemd> -p -m <befehl>`, mit vollen Pfaden, weil das Arbeitsverzeichnis wechselt. Ende mit `systemctl poweroff`, erneuter Start prüft das Verhalten nach einem Neustart.
  - Für Benutzer ohne Root die Variable `SSL_CERT_FILE` entfernen (`env -u SSL_CERT_FILE`), sie zeigt hier auf eine Datei, die nur root lesen kann.
  - Der Agent läuft darin als Dienst des Systems, die Welten als Dienste des Benutzers `lep-agent` mit dem selbst gebauten `luantiserver`. Ein Client unter `Xvfb` erreicht sie von außerhalb des Bereichs unter `127.0.0.1` und ihrem Port, weil das Netz geteilt ist.
  - `journalctl -M` geht nicht, `systemctl --user -M <benutzer>@` schon. Der Ablauf in `docs/betrieb.md` ist so geprüft. Unterschiede zu Debian sind möglich, der Nutzer prüft auf einer Debian-VM.
- nginx vor dem Backend lässt sich hier prüfen: `apt-get update`, dann `apt-get install nginx`, ein Zertifikat mit `openssl` selbst ausstellen und `nginx` von Hand starten. In dieser Umgebung fehlt IPv6, die Zeilen mit `[::]` müssen aus der abgelegten Datei heraus. `curl` braucht `--noproxy <name> --resolve <name>:443:127.0.0.1 --cacert <Stelle>`, Chrome `--no-proxy-server --ignore-certificate-errors --host-resolver-rules="MAP <name> 127.0.0.1"`. `ufw` ist hier nur mit `--dry-run` geprüft: Eingeschaltet könnte es die Arbeitsumgebung vom Netz trennen.
- Rust (`cargo`) und Node (`node`, `npm`) sind vorhanden, crates.io und die npm-Registry sind erreichbar.
- Prüfungen vor jedem Pull Request: `scripts/test.sh` (Lua, Rust und Oberfläche; `scripts/test.sh lua`, `rust` oder `frontend` für einen Teil), dazu ein Start der Testwelt mit `scripts/dev-setup.sh` und `scripts/dev-run.sh --server`, um das Laden der Mods im Log zu prüfen.

## Lizenzen

Siehe [`LICENSE.md`](LICENSE.md). Neue Dateien gehören zu dem Teil, in dessen Verzeichnis sie liegen.
