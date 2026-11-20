# Betrieb auf einem Server

Diese Anleitung richtet Backend und Agent als Dienste auf einem Server mit **Debian 13** ein. Beide laufen auf derselben Maschine. Die Regeln dahinter stehen im [Konzept](konzept.md), Abschnitt 11.3.

**Stand:** Backend und Agent laufen als Dienste, der Agent meldet dem Backend seinen Zustand. Welten legt der Agent noch nicht an, das folgt mit den nächsten Teilen von Schritt 7. Diese Anleitung wächst mit.

**Noch nicht für den echten Betrieb mit Schülerdaten:** Die Anleitung endet ohne HTTPS. Ohne HTTPS reisen Anmeldung und Startpasswörter ungeschützt durch das Netz. Für einen Versuch auf einer eigenen VM reicht das, für eine Schule nicht.

Alle Befehle laufen als ein Benutzer mit `sudo`. Auf einem frisch installierten Debian fehlt `sudo` manchmal: dann als root `apt install sudo` und den eigenen Benutzer mit `adduser <name> sudo` in die Gruppe aufnehmen, danach neu anmelden.

## Übersicht

| Was | Wo |
|---|---|
| Programme | `/usr/local/bin/lep-backend`, `/usr/local/bin/lep-agent` |
| Oberfläche | `/usr/local/share/lep/frontend/` |
| Einstellungen | `/etc/lep/backend.env`, `/etc/lep/agent.toml` |
| Datenbank des Backends | `/var/lib/lep-backend/lep.sqlite` |
| Ordner des Agenten, später mit den Welten | `/var/lib/lep/` |
| Dienst des Backends | `lep-backend.service`, ein Dienst des Systems, Benutzer `lep-backend` |
| Dienst des Agenten | `lep-agent.service`, ein Dienst des Benutzers `lep` |

Backend und Agent haben getrennte Benutzer ohne Admin-Rechte. Keiner kann die Dateien des anderen lesen.

## 1. Werkzeuge zum Bauen

Die Programme und die Oberfläche werden auf dem Server aus dem Repository gebaut. Dafür braucht er Rust und Node 22.

```sh
sudo apt update
sudo apt install build-essential git curl ca-certificates
```

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
cargo build --release --package lep-backend --package lep-agent
scripts/frontend-run.sh build
```

Der erste Bau dauert einige Minuten.

## 3. Programme und Oberfläche ablegen

```sh
sudo install -m 755 target/release/lep-backend target/release/lep-agent /usr/local/bin/
sudo mkdir -p /usr/local/share/lep
sudo rm -rf /usr/local/share/lep/frontend
sudo cp -r frontend/dist /usr/local/share/lep/frontend
```

## 4. Benutzer anlegen

```sh
sudo adduser --system --group --home /var/lib/lep-backend --no-create-home lep-backend
sudo adduser --system --group --home /var/lib/lep lep
sudo mkdir -p /etc/lep
```

Beide Benutzer haben kein Passwort und keine Anmeldung.

## 5. Backend einrichten

```sh
sudo install -m 640 -o root -g lep-backend deploy/backend.env.example /etc/lep/backend.env
sudo nano /etc/lep/backend.env
```

Für einen Versuch im eigenen Netz ohne Zertifikat, mit der Adresse des Servers statt `192.0.2.10`:

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

Schlüssel erzeugen. Er wird nur dieses eine Mal gezeigt:

```sh
sudo -u lep-backend env LEP_DATABASE=/var/lib/lep-backend/lep.sqlite lep-backend agent key
```

Einstellungen anlegen und den Schlüssel bei `key` eintragen:

```sh
sudo install -m 600 -o lep -g lep deploy/agent.toml.example /etc/lep/agent.toml
sudo nano /etc/lep/agent.toml
```

Die Datei gehört dem Benutzer `lep` und ist für niemanden sonst lesbar. Probe, ob der Agent das Backend erreicht:

```sh
sudo -u lep lep-agent check
```

Erwartet: `The backend took the report.`

Die Dienste des Benutzers `lep` sollen ohne Anmeldung laufen und beim Hochfahren starten (Linger). Das wird einmal eingeschaltet:

```sh
sudo loginctl enable-linger lep
```

Dienst einrichten und starten:

```sh
sudo install -d -o lep -g lep /var/lib/lep/.config /var/lib/lep/.config/systemd /var/lib/lep/.config/systemd/user
sudo install -m 644 -o lep -g lep deploy/lep-agent.service /var/lib/lep/.config/systemd/user/
sudo systemctl --user -M lep@ daemon-reload
sudo systemctl --user -M lep@ enable --now lep-agent
```

`--user -M lep@` heißt: die Dienstverwaltung des Benutzers `lep`, nicht die des Systems.

## 7. Prüfen

```sh
sudo systemctl --user -M lep@ is-active lep-agent
sudo -u lep-backend env LEP_DATABASE=/var/lib/lep-backend/lep.sqlite lep-backend agent show
```

Erwartet: `active` und `Game server: connected` mit Version und freiem Speicherplatz.

Nach einem Neustart der Maschine (`sudo reboot`) müssen beide Befehle ohne weiteres Zutun dasselbe zeigen.

Die Web-Anwendung zeigt den Spielserver auf der Seite „Zustand“. Anmelden kann sich dort aber erst eine Lehrkraft mit Web-Zugang, und die entsteht in einer Welt. Solange der Agent keine Welten anlegt, bleibt zur Prüfung der Befehl `agent show`.

## Im Alltag

| Zweck | Befehl |
|---|---|
| Zustand des Backends | `systemctl status lep-backend` |
| Log des Backends | `sudo journalctl -u lep-backend` |
| Backend neu starten | `sudo systemctl restart lep-backend` |
| Zustand des Agenten | `sudo systemctl --user -M lep@ status lep-agent` |
| Log des Agenten | `sudo journalctl _SYSTEMD_USER_UNIT=lep-agent.service` |
| Agent neu starten | `sudo systemctl --user -M lep@ restart lep-agent` |
| Befehle des Backends | `sudo -u lep-backend env LEP_DATABASE=/var/lib/lep-backend/lep.sqlite lep-backend <befehl>` |

Stürzt ein Programm ab, startet systemd es neu. Ist das Backend nicht erreichbar, läuft der Agent weiter und versucht es alle 30 Sekunden erneut.

## Aktualisieren

```sh
cd luanti-education-platform
git pull
cargo build --release --package lep-backend --package lep-agent
scripts/frontend-run.sh build
sudo install -m 755 target/release/lep-backend target/release/lep-agent /usr/local/bin/
sudo rm -rf /usr/local/share/lep/frontend
sudo cp -r frontend/dist /usr/local/share/lep/frontend
sudo systemctl restart lep-backend
sudo systemctl --user -M lep@ restart lep-agent
```

Erst das Backend, dann der Agent. Haben sich die Dienstdateien in `deploy/` geändert, werden sie wie in Abschnitt 5 und 6 neu abgelegt, gefolgt von `daemon-reload`.

## Was noch fehlt

- **HTTPS:** ein Webserver mit Zertifikat vor dem Backend. Dann lauscht das Backend nur auf `127.0.0.1`.
- **Welten:** Luanti, die Vorlage und der Dienst `lep-world@<Kennung>.service`, mit den Ports in der Firewall.
- **Sicherung** der Datenbank des Backends.
