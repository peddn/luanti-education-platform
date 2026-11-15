# Mods

Modpack mit allen eigenen Mods der Luanti Education Platform. Die Liste der Mods steht im [Konzept](../docs/konzept.md), Abschnitt 14.2.

Bisher vorhanden:

- `lep_core`: Lader für die Dateien eines Mods und Ereignisverteiler.
- `lep_places`: Ortsverwaltung. Versetzt Spieler zwischen Orten und hält Position, Inventar und Rechte stimmig.
- `lep_rooms`: Lernräume. Baut persönliche Räume hoch über der Welt, teilt sie zu und schützt sie.
- `lep_survival`: Regeln der Survival-Welt. Entfernt Rezepte aus Minetest Game, die ein fremder Mod ersetzt.
- `lep_portals`: Portale. Das feste Paar zwischen Halle und Wildnis und das persönliche Paar zwischen Raum und Grundstück.
- `lep_lobby`: Lobby. Baut die Glashalle, in der neue Spieler ankommen, und regelt Erscheinen, Tod und Schutz.

## Ebenen der Raumtypen

Jeder Raumtyp belegt eine Ebene. Die Nummer darf nie geändert werden, weil sie die Höhe aller vorhandenen Räume bestimmt. Neue Raumtypen tragen sich hier ein.

| Ebene | Raumtyp | Mod |
|---|---|---|
| 38 | `lep_rooms:debug` (nur mit `lep_debug`) | `lep_rooms` |

Tests und Testwelt: siehe [Entwicklungsumgebung](../docs/entwicklungsumgebung.md), Abschnitt 5.

Lizenz: LGPL-3.0-or-later für Code, CC BY-SA 4.0 für Texturen und Texte. Siehe [LICENSE.md](../LICENSE.md).
