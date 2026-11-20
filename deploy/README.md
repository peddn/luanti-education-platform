# deploy

Dateien für den Betrieb auf einem Server: Dienste für systemd und Vorlagen für die Einstellungen. Wie sie eingerichtet werden, steht in [`docs/betrieb.md`](../docs/betrieb.md).

| Datei | Ziel auf dem Server |
|---|---|
| `lep-backend.service` | `/etc/systemd/system/lep-backend.service` |
| `backend.env.example` | `/etc/lep/backend.env` |
| `lep-agent.service` | `/var/lib/lep/.config/systemd/user/lep-agent.service` |
| `agent.toml.example` | `/etc/lep/agent.toml` |

In den Vorlagen stehen keine echten Zugangsdaten. Die ausgefüllten Dateien gehören nicht ins Repository.

Lizenz: LGPL-3.0-or-later. Siehe [LICENSE.md](../LICENSE.md).
