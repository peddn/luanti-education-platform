# Luanti Education Platform (LEP)

Eine Lernplattform auf Basis von [Luanti](https://www.luanti.org/) für Schulen. Schülerinnen und Schüler lösen Lernaufgaben und werden dafür in einer Survival-Welt belohnt. Lehrkräfte steuern den Unterricht im Spiel und verwalten Gruppen, Aufgaben und Fortschritt in einer Web-Anwendung.

Geplante Lernmodule: Rechnen, Textfragen, Technisches Zeichnen, Logikrätsel.

**Status:** In Entwicklung. Die Mods für Orte, Lobby, Lernräume, Fortschritt, Belohnungen, Rechnen und das Lehrerpult laufen. Backend und Web-Anwendung laufen für eine Welt: Konten, Gruppen, Fortschritt, Protokolle, Belohnungen und Jahresabschluss. Der Agent für den Spielserver ist begonnen: Er meldet dem Backend seinen Zustand, trägt die Vorlage für Welten in sich und legt Welten auf Auftrag an. Starten und verwalten kann er sie noch nicht.

Dieses Projekt ist unabhängig und gehört nicht zum Luanti-Projekt. Es wird von dessen Entwicklern weder betrieben noch unterstützt.

## Dokumentation

- [Konzept](docs/konzept.md): Ziele, Entscheidungen, Aufbau, Reihenfolge der Umsetzung
- [Entwicklungsumgebung](docs/entwicklungsumgebung.md): Einrichtung unter Arch Linux
- [Betrieb](docs/betrieb.md): Backend und Agent als Dienste auf einem Debian-Server
- [CLAUDE.md](CLAUDE.md): Arbeitsregeln und Git-Vorgehensweise

## Aufbau des Repositorys

Verzeichnisse ohne Markierung entstehen erst mit dem jeweiligen Umsetzungsschritt.

```
luanti-education-platform/
├── README.md
├── CLAUDE.md                    Arbeitsregeln, Git-Vorgehensweise
├── LICENSE.md                   Übersicht: welche Lizenz gilt wo
├── LICENSES/                    Lizenztexte
├── docs/                        Konzept und Anleitungen
│
├── mods/                        Modpack mit allen eigenen Mods
│   ├── modpack.conf
│   ├── lep_core/                gemeinsame Hilfen
│   ├── lep_places/              Ortsverwaltung
│   ├── lep_lobby/
│   ├── lep_portals/
│   ├── lep_rooms/               Lernräume
│   ├── lep_progress/            Fortschritt, Niveau, Pensum
│   ├── lep_rewards/
│   ├── lep_trophies/
│   ├── lep_math/                Rechnen
│   ├── lep_quest_chest/         Aufgabentruhe
│   ├── lep_desk/                Lehrerpult mit Reiter „Web-Zugang“
│   ├── lep_attention/           Aufmerksamkeitsmodus
│   ├── lep_chat/
│   ├── lep_accounts/            Geschlossene Welt, Konten anlegen, Passwörter setzen, Wunschnamen
│   ├── lep_bridge/              Verbindung zum Backend
│   ├── lep_quiz/                Textfragen
│   ├── lep_tz/                  Technisches Zeichnen
│   └── lep_logic/               Logikrätsel
│
├── third_party/                 Spiel und fremde Mods als Listen mit festen Versionen
│
├── Cargo.toml                   Rust-Arbeitsbereich
├── crates/protocol/             gemeinsame Typen der Schnittstelle
├── backend/                     Web-Anwendung (Rust)
├── agent/                       Agent für Spielserver (Rust)
├── frontend/                    Oberfläche (Vue, Pinia, Router, Tailwind, JavaScript)
├── api/                         erzeugte OpenAPI-Beschreibung
│
├── deploy/                      Dienste und Vorlagen der Einstellungen für den Server
├── scripts/                     Hilfsskripte
└── .github/workflows/           automatische Prüfungen
```

Jeder Mod ist gleich aufgebaut:

```
lep_progress/
├── mod.conf          Name, Beschreibung, Abhängigkeiten
├── init.lua          lädt die übrigen Dateien
├── src/              Kern in reinem Lua, ohne Engine-Aufrufe
├── game/             Schicht zum Spiel: Fenster, Blöcke, Befehle
├── spec/             Busted-Tests für den Kern
├── locale/           Übersetzungen
└── textures/         Texturen
```

## Lizenz

Das Projekt steht unter Copyleft-Lizenzen. Welche Lizenz für welchen Teil gilt, steht in [LICENSE.md](LICENSE.md).
