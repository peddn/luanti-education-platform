# Betrieb auf einem Server

Diese Anleitung richtet Backend und Agent als Dienste auf einem Server mit **Debian 13** ein. Beide laufen auf derselben Maschine. Die Regeln dahinter stehen im [Konzept](konzept.md), Abschnitt 11.3.

**Stand:** Backend und Agent laufen als Dienste, der Agent meldet dem Backend seinen Zustand, trägt die Vorlage für Welten in sich, legt Welten auf Auftrag an und startet und stoppt sie. Die Schulverwaltung legt Gruppen im Browser an, und Welten lassen sich dort starten und stoppen. Lehrkräfte in neuen Welten folgen mit den nächsten Teilen von Schritt 7. Diese Anleitung wächst mit.

**Noch nicht für den echten Betrieb mit Schülerdaten:** Die Anleitung endet ohne HTTPS. Ohne HTTPS reisen Anmeldung und Startpasswörter ungeschützt durch das Netz. Für einen Versuch auf einer eigenen VM reicht das, für eine Schule nicht.

Alle Befehle laufen als ein Benutzer mit `sudo`. Auf einem frisch installierten Debian fehlt `sudo` manchmal: dann als root `apt install sudo` und den eigenen Benutzer mit `adduser <name> sudo` in die Gruppe aufnehmen, danach neu anmelden.

## Übersicht

| Was | Wo |
|---|---|
| Programme | `/usr/local/bin/lep-backend`, `/usr/local/bin/lep-agent` |
| Befehle des Backends für den Server-Admin | `/usr/local/bin/lep-admin` |
| Luanti-Server | `/usr/local/bin/luantiserver`, dazu `/usr/local/share/luanti/` |
| Oberfläche | `/usr/local/share/lep/frontend/` |
| Einstellungen | `/etc/lep/backend.env`, `/etc/lep/agent.toml` |
| Datenbank des Backends | `/var/lib/lep-backend/lep.sqlite` |
| Ordner des Agenten, später mit den Welten | `/var/lib/lep/` |
| Vorlage für Welten, vom Agenten ausgepackt | `/var/lib/lep/templates/<Version>/` |
| Welten, vom Agenten angelegt | `/var/lib/lep/worlds/<Kennung>/` |
| Dienst des Backends | `lep-backend.service`, ein Dienst des Systems, Benutzer `lep-backend` |
| Dienst des Agenten | `lep-agent.service`, ein Dienst des Systems, Benutzer `lep-agent` |
| Dienst einer Welt | `lep-world@<Kennung>.service`, ein Dienst des Benutzers `lep-agent`. Die Vorlage dafür schreibt der Agent selbst |

Backend und Agent haben getrennte Benutzer ohne Admin-Rechte: `lep-backend` und `lep-agent`. Keiner kann die Dateien des anderen lesen. Unter `lep-agent` laufen auch die Welten. Nur deshalb darf der Agent sie starten und stoppen, ohne Rechte am System zu haben.

## 1. Werkzeuge zum Bauen

Die Programme, die Oberfläche und der Luanti-Server werden auf dem Server gebaut. Dafür braucht er Rust, Node 22 und die Pakete zum Bauen von Luanti.

```sh
sudo apt update
sudo apt install build-essential git curl ca-certificates
sudo apt install cmake libsqlite3-dev libluajit-5.1-dev libcurl4-openssl-dev zlib1g-dev libzstd-dev libgmp-dev libjsoncpp-dev
```

Die zweite Zeile ist für Luanti.

Rust kommt über `rustup`:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
. "$HOME/.cargo/env"
```

Node 22 kommt aus der Paketquelle von NodeSource. Debian 13 selbst bringt nur Node 20 mit, und die Werkzeuge der Oberfläche verlangen Node 22:

```sh
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
sudo apt install nodejs
```

`npm` ist in diesem Paket enthalten. Ist schon das Node aus Debian installiert, vorher `sudo apt remove nodejs npm` ausführen. Updates für Node kommen danach mit dem normalen `sudo apt upgrade`.

Prüfen:

```sh
cargo --version
node --version
```

Erwartet: bei Node eine Version, die mit `v22` beginnt.

## 2. Bauen

```sh
git clone https://github.com/peddn/luanti-education-platform.git
cd luanti-education-platform
cargo build --release --package lep-backend
scripts/agent-build.sh
scripts/frontend-run.sh build
```

Der erste Bau dauert einige Minuten.

`scripts/agent-build.sh` baut den Agenten mit der Vorlage für Welten. Dafür lädt es Minetest Game und die fremden Mods in den festen Versionen aus `third_party/`, packt sie mit den eigenen Mods und den Lizenztexten zusammen und bettet das Archiv in das Programm ein. Am Ende steht `Built target/release/lep-agent with the template inside.` Der laufende Agent braucht danach keinen Zugriff auf fremde Quellen.

### Luanti

Debian 13 liefert Luanti 5.10. Die Welten brauchen die Version, mit der entwickelt wird, zurzeit 5.18. Deshalb wird der Server selbst gebaut, ohne Grafik und Ton:

```sh
scripts/luanti-build.sh
```

Das Skript holt den Quelltext in der festen Version aus `third_party/luanti.toml` und baut einige Minuten lang. Am Ende steht `Built: Luanti 5.18.0 (Linux)`. Schlägt es fehl, zeigt es die letzten Zeilen der Ausgabe, meist fehlt dann eines der Pakete aus Abschnitt 1.

## 3. Programme und Oberfläche ablegen

```sh
sudo install -m 755 target/release/lep-backend target/release/lep-agent deploy/lep-admin /usr/local/bin/
sudo mkdir -p /usr/local/share/lep
sudo rm -rf /usr/local/share/lep/frontend
sudo cp -r frontend/dist /usr/local/share/lep/frontend
sudo cmake --install target/luanti/build
```

Die letzte Zeile legt Luanti ab. Prüfen:

```sh
luantiserver --version
```

Erwartet: `Luanti 5.18.0 (Linux)`, darunter `Using LuaJIT`.

## 4. Benutzer anlegen

```sh
sudo adduser --system --group --home /var/lib/lep-backend --no-create-home lep-backend
sudo adduser --system --group --home /var/lib/lep lep-agent
sudo mkdir -p /etc/lep
```

Beide Benutzer haben kein Passwort und keine Anmeldung.

## 5. Backend einrichten

```sh
sudo install -m 640 -o root -g lep-backend deploy/backend.env.example /etc/lep/backend.env
sudo nano /etc/lep/backend.env
```

Die Datei enthält schon alle Zeilen. Für einen Versuch im eigenen Netz ohne Zertifikat änderst du nur diese beiden, mit der Adresse des Servers statt `192.0.2.10`:

```
LEP_BIND=0.0.0.0:8080
LEP_PUBLIC_URL=http://192.0.2.10:8080
```

Die Angaben zum Mailserver sind dieselben wie in der [Entwicklungsumgebung](entwicklungsumgebung.md). Ohne Mailserver stehen die Mails im Log des Dienstes.

Dienst einrichten und starten:

```sh
sudo install -m 644 deploy/lep-backend.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now lep-backend
```

Prüfen:

```sh
systemctl is-active lep-backend
curl http://127.0.0.1:8080/api/health
```

Erwartet: `active` und `{"status":"ok"}`.

## 6. Agent einrichten

Die Befehle des Backends ruft der Server-Admin über `lep-admin` auf, zum Beispiel `lep-admin world list`. Das kleine Skript führt sie als Benutzer des Backends aus, mit denselben Einstellungen wie der Dienst, und fragt dafür nach dem Passwort für `sudo`. `lep-admin --help` zeigt alle Befehle.

Schlüssel erzeugen. Er wird nur dieses eine Mal gezeigt:

```sh
lep-admin agent key
```

Einstellungen anlegen und den Schlüssel bei `key` eintragen:

```sh
sudo install -m 600 -o lep-agent -g lep-agent deploy/agent.toml.example /etc/lep/agent.toml
sudo nano /etc/lep/agent.toml
```

In derselben Datei stehen zwei Angaben für die Welten:

- `admin`: dein Kontoname als Server-Admin. Der Agent trägt ihn in jede neue Welt ein, damit sie einen ersten Zugang hat. Erlaubt sind 1 bis 19 Zeichen: Buchstaben, Ziffern, `-` und `_`. Ohne diese Angabe legt der Agent keine Welt an.
- `ports`: der Bereich der Ports für die Welten, voreingestellt `30000-30099`. Läuft auf dem Server eine Firewall, muss sie UDP für diesen Bereich durchlassen.
- `host`: der Name oder die Adresse, unter der Spieler den Server erreichen, ohne Port, zum Beispiel `spiel.schule.example` oder die IP der Maschine. Zusammen mit dem Port einer Welt wird daraus ihre Adresse auf den Zugangszetteln, etwa „spiel.schule.example, Port 30000“. Ohne diese Angabe trägt die Schulverwaltung die Adresse jeder Welt von Hand ein.
- `luanti`: der Pfad des Luanti-Servers, voreingestellt `/usr/local/bin/luantiserver`. Dorthin legt ihn Abschnitt 3.

Die Datei gehört dem Benutzer `lep-agent` und ist für niemanden sonst lesbar. Probe, ob der Agent das Backend erreicht:

```sh
sudo -u lep-agent lep-agent check
```

Erwartet: `The backend took the report.` Darüber stehen die Vorlage, der Admin, der Bereich der Ports, der Name des Servers und der Pfad von Luanti.

Die Welten sind Dienste des Benutzers `lep-agent`. Sie sollen ohne Anmeldung laufen und beim Hochfahren starten (Linger). Das wird einmal eingeschaltet:

```sh
sudo loginctl enable-linger lep-agent
```

Der Agent selbst ist ein Dienst des Systems, wie das Backend. Einrichten und starten:

```sh
sudo install -m 644 deploy/lep-agent.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now lep-agent
```

Die Dienstdatei erlaubt dem Agenten, nur in `/var/lib/lep` zu schreiben. Steht in der `agent.toml` ein anderes `data_dir`, gehört dieser Ordner auch in die Zeile `ReadWritePaths` der Dienstdatei.

## 7. Prüfen

```sh
systemctl is-active lep-agent
lep-admin agent show
```

Erwartet: `active` und `Game server: connected` mit Version, freiem Speicherplatz und der Version der Vorlage in der Zeile `template for worlds`. Die Vorlage liegt ausgepackt unter `/var/lib/lep/templates/`:

```sh
sudo ls /var/lib/lep/templates/
```

Steht in der Zeile `none`, wurde der Agent ohne Vorlage gebaut, also mit `cargo build` statt mit `scripts/agent-build.sh`.

Nach einem Neustart der Maschine (`sudo reboot`) müssen beide Befehle ohne weiteres Zutun dasselbe zeigen.

Die Web-Anwendung zeigt den Spielserver auf der Seite „Zustand“. Anmelden kann sich dort aber erst eine Lehrkraft mit Web-Zugang, und die entsteht in einer Welt. Solange der Agent keine Welten anlegt, bleibt zur Prüfung der Befehl `agent show`.

## 8. Die erste Welt anlegen

Eine Welt gehört zu einer Gruppe. Gruppen legt die Schulverwaltung im Browser an (Abschnitt 10). Im Browser anmelden kann sich aber nur, wer in einer Welt Web-Zugang bekommen hat. Die allererste Welt legt deshalb der Server-Admin mit einem Befehl an:

```sh
lep-admin world create "Klasse 7b"
```

Das Backend merkt sich die Welt und stellt dem Agenten einen Auftrag hin. Der Agent holt ihn innerhalb einer halben Minute ab, legt den Ordner der Welt an, vergibt einen Port, trägt den Schlüssel ein, mit dem sich die Welt beim Backend meldet, und startet die Welt. Diesen Schlüssel bekommt kein Mensch zu sehen.

Wie es ging:

```sh
lep-admin world list
sudo ls -la /var/lib/lep/worlds/
```

Erwartet: erst `waiting for the agent`, kurz darauf `running, port 30000, template …`, und ein Ordner mit der Kennung der Welt. Wenig später steht statt `never seen` ein `last seen … s ago` mit der Luanti-Version: Die Welt hat sich selbst beim Backend gemeldet. Lehnt der Agent ab, steht der Grund in der Liste, etwa `the agent refused: the settings of the agent name no admin for the worlds`.

Mit einem Luanti-Client erreichst du die Welt unter der Adresse des Servers und dem Port aus der Liste. Der erste, der sich mit dem Namen aus `admin` anmeldet, legt dabei das Passwort dieses Kontos fest. Das solltest du selbst sein, gleich nach dem Anlegen.

## 9. Welten starten und stoppen

```sh
lep-admin world stop "Klasse 7b"
lep-admin world start "Klasse 7b"
lep-admin world restart "Klasse 7b"
```

| Befehl | Wirkung |
|---|---|
| `world stop` | stoppt die Welt. Sie bleibt gestoppt, auch nach einem Neustart der Maschine. Wer gerade spielt, wird getrennt |
| `world start` | startet die Welt, jetzt und nach jedem Neustart der Maschine |
| `world restart` | startet eine laufende Welt neu. Eine gestoppte bleibt gestoppt |

Jeder Befehl stellt dem Agenten einen Auftrag hin, den er innerhalb einer halben Minute abholt. `world list` zeigt danach `running` oder `stopped`.

Welche Welten laufen sollen, merkt sich systemd. Stürzt eine Welt ab, startet systemd sie nach zehn Sekunden neu. Kann eine Welt gar nicht starten, lehnt der Agent den Auftrag ab und nennt den Befehl, der den Grund zeigt.

## 10. Der erste Web-Zugang und Gruppen im Browser

Der Server-Admin hat in jeder Welt das Privileg für den Web-Zugang. Das Privileg der Schulverwaltung hat er nicht von selbst: Wer den Server betreibt, sieht nicht automatisch alle Gruppen und Schülerlisten. Mit der ersten Welt macht er sich oder jemand anderen zur Schulverwaltung und richtet den Zugang zur Web-Anwendung ein:

1. Im Spiel in der ersten Welt anmelden und das Privileg der Schulverwaltung vergeben, an das eigene Konto oder an das einer Lehrkraft: `/grant <name> lep_manage_school`. Wer es in einer Welt hat, ist für das Backend Schulverwaltung aller Gruppen.
2. Mit `/pult` das Lehrerpult öffnen, Reiter „Web-Zugang“, und die eigene Mailadresse eintragen.
3. Den Link aus der Mail im Browser öffnen und die Adresse bestätigen. Ohne Mailserver steht die Mail im Log des Backends. Dieser Befehl zeigt den neuesten Link vollständig:

   ```sh
   sudo journalctl -u lep-backend --no-pager -o cat | grep -o 'http[^ ]*' | tail -n 1
   ```

   Ohne `--no-pager` schneidet `journalctl` lange Zeilen am Rand des Terminals ab, und ein abgeschnittener Link gilt nicht. Ein Link gilt 15 Minuten und einmal, und jede neue Anforderung macht ältere ungültig.
4. In der Web-Anwendung unter der Adresse aus `LEP_PUBLIC_URL` mit dieser Mailadresse anmelden. Auch dieser Link kommt per Mail oder steht im Log.

Danach legt die Schulverwaltung weitere Gruppen auf der Seite „Gruppen“ an: Name eintragen, „Gruppe anlegen“. Der Agent richtet die Welt ein und startet sie, die Seite zeigt den Zustand von selbst: „wird eingerichtet …“, dann „läuft“.

Lehnt der Agent ab, steht bei der Gruppe „abgelehnt“. Auf ihrer Seite steht der Grund im Wortlaut des Agenten, mit zwei Knöpfen: „Erneut versuchen“, nachdem die Ursache behoben ist, und „Gruppe verwerfen“. Verwerfen gibt es nur für Gruppen, deren Welt nie entstanden ist.

Auf der Seite einer Gruppe lässt sich ihre Welt auch starten, stoppen und neu starten, mit derselben Wirkung wie die Befehle aus Abschnitt 9. Das dürfen die Lehrkräfte der Gruppe und die Schulverwaltung. Stoppen fragt nach, weil es trennt, wer gerade spielt. Führt der Agent etwas nicht aus, steht sein Grund auf der Seite.

Eine im Browser angelegte Welt kennt zunächst nur den Server-Admin. Dass die Lehrkräfte dort ankommen, folgt mit dem nächsten Teil.

`world add` gibt es weiter. Es legt eine Welt nur im Backend an und zeigt ihren Schlüssel, für eine Welt, die von Hand eingerichtet wird.

## Im Alltag

| Zweck | Befehl |
|---|---|
| Zustand des Backends | `systemctl status lep-backend` |
| Log des Backends | `sudo journalctl -u lep-backend` |
| Backend neu starten | `sudo systemctl restart lep-backend` |
| Zustand des Agenten | `systemctl status lep-agent` |
| Log des Agenten | `sudo journalctl -u lep-agent` |
| Agent neu starten | `sudo systemctl restart lep-agent` |
| Zustand einer Welt | `sudo systemctl --user -M lep-agent@ status 'lep-world@<Kennung>'` |
| Fehler einer Welt beim Start | `sudo journalctl _SYSTEMD_USER_UNIT=lep-world@<Kennung>.service` |
| Logdatei einer Welt | `/var/lib/lep/worlds/<Kennung>/debug.txt` |
| Befehle des Backends | `lep-admin <befehl>` |

Die Kennung einer Welt zeigt `world list` in der zweiten Spalte. Im Journal einer Welt stehen nur Fehler. Was im Spiel geschieht, auch Chatnachrichten, steht allein in ihrer Logdatei.

Stürzt ein Programm ab, startet systemd es neu. Ist das Backend nicht erreichbar, läuft der Agent weiter und versucht es alle 30 Sekunden erneut.

## Aktualisieren

```sh
cd luanti-education-platform
git pull
cargo build --release --package lep-backend
scripts/agent-build.sh
scripts/frontend-run.sh build
sudo install -m 755 target/release/lep-backend target/release/lep-agent deploy/lep-admin /usr/local/bin/
sudo rm -rf /usr/local/share/lep/frontend
sudo cp -r frontend/dist /usr/local/share/lep/frontend
sudo systemctl restart lep-backend lep-agent
```

Nennt `third_party/luanti.toml` nach dem `git pull` eine neue Version, kommen `scripts/luanti-build.sh` und `sudo cmake --install target/luanti/build` dazu. Laufende Welten nutzen das neue Luanti nach ihrem nächsten Neustart.

Erst das Backend, dann der Agent. Haben sich Spiel oder Mods geändert, hat die Vorlage eine neue Version, und der Agent packt sie beim Start neben die alte. Haben sich die Dienstdateien in `deploy/` geändert, werden sie wie in Abschnitt 5 und 6 neu abgelegt, gefolgt von `daemon-reload`.

## Umzug von einer älteren Einrichtung

Bis Fassung 75 des Konzepts hieß der Benutzer des Agenten `lep`, und der Agent war ein Dienst dieses Benutzers. Eine Maschine, die so eingerichtet wurde, zieht einmal um. Welten, Vorlagen, Einstellungen und Passwörter bleiben dabei, wie sie sind. Die Welten stehen für die Dauer des Umzugs still.

Zuerst wie unter „Aktualisieren“ bauen und die Programme ablegen, dann:

```sh
sudo systemctl --user -M lep@ disable --now lep-agent
sudo rm -f /var/lib/lep/.config/systemd/user/lep-agent.service
sudo loginctl disable-linger lep
sudo systemctl stop "user@$(id -u lep).service"
sudo usermod -l lep-agent lep
sudo groupmod -n lep-agent lep
sudo loginctl enable-linger lep-agent
sudo install -m 644 deploy/lep-agent.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now lep-agent
```

Die ersten vier Zeilen halten den alten Agenten und alle Welten an, denn ein Benutzer lässt sich nur umbenennen, wenn nichts mehr unter ihm läuft. Die beiden Zeilen danach benennen Benutzer und Gruppe um. Dateien werden dabei nicht bewegt. Mit `enable-linger` starten die Welten wieder, die vorher eingeschaltet waren, und die letzten drei Zeilen richten den Agenten als Dienst des Systems ein.

Prüfen wie in Abschnitt 7. `lep-admin world list` zeigt nach einer halben Minute wieder, welche Welten laufen.

## Was noch fehlt

- **HTTPS:** ein Webserver mit Zertifikat vor dem Backend. Dann lauscht das Backend nur auf `127.0.0.1`.
- **Lehrkräfte in neuen Welten:** Eine frische Welt kennt nur den Server-Admin.
- **Sicherung** der Datenbank des Backends.
