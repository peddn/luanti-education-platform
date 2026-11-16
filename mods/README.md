# Mods

Modpack mit allen eigenen Mods der Luanti Education Platform. Die Liste der Mods steht im [Konzept](../docs/konzept.md), Abschnitt 14.2.

Bisher vorhanden:

- `lep_core`: Lader für die Dateien eines Mods, Ereignisverteiler, Hilfsschicht für Fenster und Protokolle.
- `lep_places`: Ortsverwaltung. Versetzt Spieler zwischen Orten und hält Position, Inventar und Rechte stimmig.
- `lep_rooms`: Lernräume. Baut persönliche Räume hoch über der Welt, teilt sie zu und schützt sie.
- `lep_progress`: Fortschritt. Nimmt Ergebnisse der Lernmodule an, führt Niveau und Pensum pro Schüler und verteilt Ereignisse an andere Mods. Vermittelt außerdem kurze Aufgaben der Module an andere Mods.
- `lep_rewards`: Belohnungen. Zahlt für gelöste Aufgaben und abgeschlossene Niveaus in die Belohnungskiste im Raum, bei Tagesaufgaben in der Survival-Welt direkt ins Inventar. Mit Tageslimit und Protokoll.
- `lep_trophies`: Trophäen. Vergibt sie für Meilensteine und zeigt sie auf den Sockeln im Raum. Jeder Mod kann Trophäen anmelden.
- `lep_math`: Kopfrechnen. Erzeugte Aufgaben in zwölf Niveaus, im Rechenraum mit Anzeige und Tastenfeld aus Blöcken.
- `lep_quest_chest`: Aufgabentruhen. Sie erscheinen in der Wildnis in der Nähe der Spieler, stellen eine kurze Aufgabe und verschwinden wieder. Lehrkräfte stellen dauerhafte Truhen auf.
- `lep_desk`: Lehrerpult. Ein Fenster mit den Schülern, ihrem Ort und den Aktionen der Lehrkraft, geöffnet mit `/pult`. Jeder Mod kann Aktionen anmelden.
- `lep_chat`: Chat. Schreibt Chat, Privatnachrichten und Schildtexte mit und lässt Lehrkräfte einzelne Schüler am Pult stummschalten.
- `lep_attention`: Aufmerksamkeitsmodus. Versetzt Schüler in eine dunkle Zelle, zeigt den Text der Lehrkraft und sperrt den Chat.
- `lep_survival`: Regeln der Survival-Welt. Entfernt Rezepte aus Minetest Game, die ein fremder Mod ersetzt, und macht Erfolge des Awards-Mods zu Trophäen.
- `lep_portals`: Portale. Das feste Paar zwischen Halle und Wildnis und das persönliche Paar zwischen Raum und Grundstück. Dazu die Lernhalle, in der jedes Lernmodul sein Portal anmeldet.
- `lep_lobby`: Lobby. Baut die Glashalle, in der neue Spieler ankommen, und regelt Erscheinen, Tod und Schutz.

## Ebenen der Raumtypen

Jeder Raumtyp belegt eine Ebene. Die Nummer darf nie geändert werden, weil sie die Höhe aller vorhandenen Räume bestimmt. Neue Raumtypen tragen sich hier ein.

| Ebene | Raumtyp | Mod |
|---|---|---|
| 1 | `lep_math:room` | `lep_math` |
| 2 | `lep_attention:cell` | `lep_attention` |
| 38 | `lep_rooms:debug` (nur mit `lep_debug`) | `lep_rooms` |

Tests und Testwelt: siehe [Entwicklungsumgebung](../docs/entwicklungsumgebung.md), Abschnitt 5.

Lizenz: LGPL-3.0-or-later für Code, CC BY-SA 4.0 für Texturen und Texte. Siehe [LICENSE.md](../LICENSE.md).
