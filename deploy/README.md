# deploy

Dateien für den Betrieb auf einem Server: Dienste für systemd, Vorlagen für die Einstellungen und der kurze Befehl `lep-admin` für den Server-Admin. Wie sie eingerichtet werden, steht in [`docs/betrieb.md`](../docs/betrieb.md).

| Datei | Ziel auf dem Server |
|---|---|
| `lep-backend.service` | `/etc/systemd/system/lep-backend.service` |
| `backend.env.example` | `/etc/lep/backend.env` |
| `lep-agent.service` | `/etc/systemd/system/lep-agent.service` |
| `agent.toml.example` | `/etc/lep/agent.toml` |
| `lep-admin` | `/usr/local/bin/lep-admin` |
| `nginx-lep.conf.example` | `/etc/nginx/sites-available/lep` |

In den Vorlagen stehen keine echten Zugangsdaten. Die ausgefüllten Dateien gehören nicht ins Repository.

Lizenz: LGPL-3.0-or-later. Siehe [LICENSE.md](../LICENSE.md).
