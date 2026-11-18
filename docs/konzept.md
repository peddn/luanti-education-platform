# Luanti Education Platform (LEP): Konzept

Fassung 52 · 18. November 2026 · Status: Schritte 1 bis 5 umgesetzt, Schritt 6 begonnen

## 1. Ziel

Eine Lernplattform auf Basis von Luanti für Förderschule, Mittelschule (Technik) und Realschule (Werken) in Bayern. Schülerinnen und Schüler lösen Lernaufgaben und werden dafür in einer Survival-Welt belohnt. Lehrkräfte steuern den Unterricht im Spiel und verwalten Gruppen, Aufgaben und Fortschritt in einer Web-Anwendung.

Lernmodule: Rechnen, Textfragen, Technisches Zeichnen (TZ), Logikrätsel.

Es gibt derzeit keinen konkreten Unterricht, an dem sich die Planung ausrichten muss. Die Plattform wird deshalb von Grund auf aufbauend entwickelt, die Lernmodule kommen nach dem Fundament.

## 2. Arbeitsregeln

Die verbindliche Fassung steht in der `CLAUDE.md` im Wurzelverzeichnis, zusammen mit der Git-Vorgehensweise. Die Grundregeln:

1. **Gebaut wird erst nach Rückfrage.**
2. **Entscheidungen werden kritisiert**, wenn sie Doppelentwicklung oder große Verkomplizierung verursachen würden.
3. **Vorhandenes vor Eigenbau.** Für Bedarf im Survival-Teil werden zuerst bestehende Mods geprüft.
4. **Code und Kommentare auf Englisch**, Texte im Spiel auf Deutsch über Luantis Übersetzungssystem.

## 3. Entscheidungen im Überblick

### Projekt

| Thema | Entscheidung |
|---|---|
| Name | Luanti Education Platform, Mod-Präfix `lep_` |
| Offenheit | Offenes Projekt mit Copyleft |
| Lizenz | AGPL-3.0-or-later für Backend und Agent, LGPL-3.0-or-later für die Mods, CC BY-SA 4.0 für Texturen und Texte |
| Basis | Minetest Game, darauf eigene und ausgewählte fremde Mods |
| Luanti-Version | Immer die neueste stabile Version, zurzeit 5.18 |
| Fenster im Spiel | Formspecs werden selbst geschrieben, keine Fenster-Bibliothek |

### Betrieb

| Thema | Entscheidung |
|---|---|
| Umfang | Ein Setup pro Schule |
| Spielserver | Auf Servern der Schule oder auf Cloud-Servern |
| Web-Anwendung | Immer auf einem Cloud-Server (Hetzner) |
| Mailversand | Über ein Postfach aus einem Webhosting-Paket, kein eigener Mailserver |
| Welten | Eine Welt (ein Serverprozess) pro Gruppe |
| Welten anlegen | Zunächst von Hand durch den Server-Admin, ab Schritt 7 durch den Agenten (Abschnitt 11.3) |

### Gruppen und Konten

| Thema | Entscheidung |
|---|---|
| Gruppe | Klasse, Kurs oder freie Gruppe, technisch dasselbe. Meist eine Klasse |
| Zugehörigkeit | Ein Schüler gehört zu genau einer Gruppe |
| Gruppen anlegen | Die Schulverwaltung entscheidet. Solange Welten von Hand entstehen, legt der Server-Admin Gruppe und Welt zusammen an (Abschnitt 5) |
| Quelle für Konten | Das Backend. Welten legen Konten auf Auftrag an |
| Kontoname | Zufällige Kombination aus Adjektiv und Nomen, z. B. `lustiger_loewe` |
| Wunschname | Vom Schüler selbst gesetzt, ohne Freigabe. Jede Änderung wird protokolliert, die Lehrkraft kann entfernen und sperren. Nur Anzeige |
| Lebensdauer | Das Konto wächst mit dem Schüler mit |
| Bleibt erhalten | Lernniveau, Meilensteine, Trophäen, Wunschname |
| Jährlich gelöscht | Chatprotokolle, Belohnungsprotokoll, einzelne Aufgabenversuche, Pult-Protokolle, Protokoll der Wunschnamen |
| Schulaustritt | Konto und alle Daten werden gelöscht |
| Passwort | Schüler dürfen es ändern, die zuständige Lehrkraft setzt es zurück |
| Konten der Lehrkräfte | Die Schulverwaltung legt sie beim Ernennen im Pult an, der Name ist frei wählbar |

### Spielablauf

| Thema | Entscheidung |
|---|---|
| Wildnis | Von Anfang an offen |
| Erste Anmeldung | Lobby |
| Weitere Anmeldungen | Ort des Ausloggens |
| Tod | Lobby, außer man hat ein Bett |
| Feste Portale | Ein Paar: Lobby und Wildnis, miteinander verbunden |
| Persönliches Portal | Im eigenen Lobby-Raum, verbunden mit dem selbst gebauten Portal |
| Lobby-Raum | Pro Schüler: Portal, Belohnungskiste, Trophäen |
| PvP | Aus, pro Welt einstellbar |
| Monster | Später, pro Welt zuschaltbar |
| Grundstücke | Schüler schützen eigene Grundstücke |
| Chat | Frei, ohne Filter, wird protokolliert. Das Protokoll bleibt bis zum Jahresabschluss |
| Besitz | Schüler dürfen mit ihrem Besitz tun, was sie wollen |

### Belohnung

| Thema | Entscheidung |
|---|---|
| Art | Naturalien (Barren, Diamanten u. Ä.) |
| Auszahlung | In die Belohnungskiste im eigenen Lobby-Raum. Tagesaufgaben in der Survival-Welt zahlen direkt ins Inventar |
| Niveau | Beliebig viele Niveaus pro Modul, von der Lehrkraft pro Schüler gesetzt |
| Aufstieg | Automatisch beim Abschluss eines Niveaus, von der Lehrkraft sperrbar |
| Belohnt wird | Nur für Aufgaben auf dem eigenen Niveau und darüber |
| Größen | Klein (Niveauaufgabe), mittel (Tagesaufgabe, Niveau abgeschlossen), groß (Etappe abgeschlossen) |
| Begrenzung | Niveauaufgaben bringen nur Lohn, solange sie fürs Pensum zählen. Tagesaufgaben: 5 pro Tag |
| Textfragen | Belohnung nur beim ersten Lösen |
| Multiple Choice | Volle Belohnung nur im ersten Versuch |
| Aufgabentruhen | Von der Welt erzeugt und von Lehrkräften aufgestellt |
| Trophäen | Für Meilensteine, nicht übertragbar, im Lobby-Raum ausgestellt |

### Lehrkraft

| Thema | Entscheidung |
|---|---|
| Im Spiel | Mit Spielfigur eingeloggt, eigenes Lehrerpult |
| Steuern | Alle Eingeloggten der aktuellen Welt |
| Verwalten | Nur eigene Gruppen und deren Belohnungen |
| Unterrichtsmodi | Unterricht, Freiarbeit, Freizeit |
| Tageszeit | Am Pult: Zeit setzen, dazu Zeit läuft, dauernd Tag oder dauernd Nacht |
| Aufmerksamkeitsmodus | Blind, taub, bewegungsunfähig |
| Web-Anwendung | Nur Verwaltung, kein Live-Eingriff |
| Web-Anmeldung | E-Mail-Link ohne Passwort, Registrierung nur im Pult |
| Lehrkräfte ernennen | Nur die Schulverwaltung |

### TZ-Modul

| Thema | Entscheidung |
|---|---|
| Zeitpunkt | Nach den Textfragen |
| Begriff | Nicht durchgehende Veränderungen heißen „Ausklinkung“ |
| Farben | Vorder- und Rückseite rot, Seiten blau, Drauf- und Untersicht gelb |
| Größe | Höchstens 20 × 20 × 20 Blöcke |
| Veränderungen | Höchstens 4 pro Körper |
| Werkzeug | Einfaches Schnellabbau-Werkzeug, kein Bereichswerkzeug |
| Bau-Stationen | Ein Ankerblock markiert die Startecke |
| Untersicht | Körper schwebt, Flugrecht im Bauraum |
| Gemeinschaftsraum | Ja, zusammen mit dem TZ-Modul |

## 4. Systemüberblick

```
                Browser der Lehrkraft
                         |
                         | HTTPS
                         v
   +-------------------------------------------+
   |  Web-Anwendung (Cloud-Server)             |
   |  Rust-Backend, liefert die Vue-Oberfläche |
   |  SQLite                                   |
   +-------------------------------------------+
        ^              ^               ^      |
        | HTTPS, die Welt ruft an      |      | SMTP
        | (Long Polling)               |      v
   +----------+   +----------+   +----------+   Postfach
   | Welt 7b  |   | Welt 8a  |   | Welt T9  |   (Webhosting)
   | Luanti   |   | Luanti   |   | Luanti   |
   | + Brücke |   | + Brücke |   | + Brücke |
   +----------+   +----------+   +----------+
        Spielserver der Schule (oder Cloud)
        später: ein Agent pro Maschine
```

In jeder Welt gibt es drei Orte: **Wildnis**, **Lobby** und **Lernräume**.

## 5. Gruppen und Welten

- **Gruppe = Welt, eins zu eins.** Die Welt hat eine feste interne Kennung, der Name der Gruppe ist frei änderbar.
- Ein Schüler existiert nur in der Welt seiner Gruppe.
- Lehrkräfte werden mit ihren Privilegien in alle Welten verteilt.
- Jede Welt hat eigene Einstellungen (PvP, Monster, Chat).
- Lobby und Lernräume erzeugt der Mod in jeder Welt.
- Im Spiel gibt es keinen Wechsel zwischen Welten. Lehrkräfte verbinden sich mit der Adresse der jeweiligen Welt.

**Anlegen einer Gruppe:** Eine Gruppe braucht ihren Eintrag im Backend und ihre Luanti-Welt, verbunden über den Schlüssel der Welt.

- Vorerst legt der Server-Admin beides an: den Eintrag mit einem Befehl des Backends, die Welt von Hand. So bleibt der Schlüssel bei dem, der ihn braucht.
- Die Schulverwaltung benennt Gruppen in der Web-Anwendung um und ordnet ihnen Lehrkräfte zu.
- Das Anlegen im Browser kommt mit dem Agenten, der die Welt auf Knopfdruck einrichtet. Dann muss auch niemand mehr den Schlüssel sehen.

**Gruppenwechsel eines Schülers:** Das Konto wandert in die neue Welt. Lernniveau und Trophäen gehen mit, der übrige Besitz bleibt in der alten Welt. Die Web-Anwendung weist beim Verschieben darauf hin.

**Schuljahreswechsel:** Pro Gruppe weiterführen (bei Bedarf umbenennen) oder archivieren. Eine Gruppe lässt sich nicht einzeln löschen: Endgültig gelöscht wird einmal im Jahr, mit dem Jahresabschluss (Abschnitt 12). Bis dahin lässt sich eine archivierte Gruppe wiederherstellen.

## 6. Konten und Namen

### 6.1 Kontoname

Das Backend würfelt aus zwei gepflegten Wortlisten eine Kombination aus Adjektiv und Nomen und prüft, ob sie an der Schule frei ist.

- Form: das Adjektiv klein, das Nomen groß, ohne Trennzeichen, etwa `klugeEule` oder `mutigerDachs`.
- Nur Buchstaben ohne Umlaute.
- Höchstens 19 Zeichen. Luanti 5.18 nimmt 20 an, ein Zeichen bleibt als Reserve.
- Jedes Nomen trägt sein Geschlecht, damit die Endung des Adjektivs stimmt.
- Nur freundliche Wörter, bei denen keine Kombination spöttisch klingt.
- Ein Name ist an der ganzen Schule einmalig, unabhängig von Groß- und Kleinschreibung, und gleicht keinem Konto einer Lehrkraft.
- Die Lehrkraft kann einzelne Namen neu würfeln, solange das Konto nicht angelegt ist. Der neue Name steht an derselben Stelle der Liste.

Der Kontoname bleibt für immer der Anmeldename. Konto, Besitz und Grundstücke hängen an ihm.

**Anlegen**

1. Die Lehrkraft der Gruppe lässt in der Web-Anwendung Namen würfeln. Sie sind zuerst ein Entwurf.
2. Mit „Konten anlegen“ erzeugt das Backend für jeden Entwurf ein Startpasswort und beauftragt die Welt.
3. Die Welt legt die Konten an und meldet, welche es gibt und welche Namen sie abgelehnt hat. Ein Konto, das es in der Welt schon gibt, fasst sie nie an.
4. Die Web-Anwendung zeigt die Zugangszettel zum Drucken: Adresse der Welt, Kontoname, Startpasswort.

**Startpasswort**

- Zwei Wörter und zwei Ziffern, etwa `wolke-apfel-47`. Kinder müssen es abtippen, deshalb ist es leicht statt stark. Sie können es im Spiel ändern. Erzwingen lässt sich das in Luanti nicht.
- Das Backend zeigt es genau einmal, auf den Zugangszetteln, und bewahrt es nicht auf. Im Auftrag an die Welt steht es, bis die Welt geantwortet hat, dann wird es dort gelöscht. Die Welt speichert nur den Hash.
- Geht ein Zettel verloren, setzt die Lehrkraft das Passwort in der Web-Anwendung zurück. Sie bekommt einen neuen Zettel mit einem neuen Startpasswort, wieder nur einmal angezeigt. Das alte gilt, bis die Welt das neue übernommen hat. Ein Kind, das gerade spielt, bleibt angemeldet.
- Die Welt setzt ein Passwort nur für ein gewöhnliches Konto: eines, das nichts hat außer den Privilegien, die jeder neue Spieler bekommt. Für das Konto einer Lehrkraft oder des Admins lehnt sie ab, was auch immer der Auftrag sagt. Was ein Schüler nur wegen seines Orts hat, etwa Fliegen in einem Raum, der es erlaubt, zählt dabei nicht. Die Welt weiß von jedem Konto, welche Privilegien vom Ort kommen, auch wenn der Spieler gerade nicht da ist. Das Backend steht im Netz. Wer es übernimmt, soll damit nicht die Lehrer- und Admin-Konten der Welten bekommen.

**Geschlossene Welt**

- Eine Welt lässt nur Namen hinein, für die es ein Konto gibt. Wer mit einem unbekannten Namen kommt, wird abgewiesen. Konten entstehen auf Auftrag, nicht durch Hereinkommen.
- Die Ausnahme ist der Admin aus der Einstellung `name`: Er darf sein Konto durch das erste Anmelden anlegen, sonst käme in eine neue Welt niemand hinein.
- Das gilt für jede Welt, auch für die Testumgebung. Eine Einstellung zum Offenhalten gibt es nicht.
- Ein Konto ist ein Konto. Ob jemand Schüler oder Lehrkraft ist, sagen allein die Privilegien. Bis die Schulverwaltung Lehrerkonten anlegen kann (Schritt 7), entsteht eine Lehrkraft, indem der Admin einem angelegten Konto die Privilegien gibt.
- Fremde Zusatzmods für Namenslisten werden nicht eingesetzt: Sie führten eine zweite Liste neben den Konten, die mit ihnen im Gleichschritt bleiben müsste.

**Echte Namen**

- Das Backend erfährt nie, welches Kind hinter einem Konto steht. Es kennt nur die Anzahl.
- Auf jedem Zugangszettel kann die Lehrkraft im Browser den Namen des Kindes eintragen. Er steht dann auf dem Ausdruck. Die Namen verlassen den Browser nicht und werden nicht gespeichert.
- Die Zuordnung von Kontoname zu Kind führt die Lehrkraft selbst, zum Beispiel mit dem Ausdruck.

**Adresse der Welt**

- Auf dem Zettel steht, wie die Kinder die Welt erreichen. Bis der Agent das meldet, trägt die Schulverwaltung die Adresse bei der Gruppe ein.

### 6.2 Wunschname

Der Grundsatz: Schüler bekommen die Möglichkeit, sich richtig zu verhalten. Niemand prüft vorab. Dafür ist alles nachvollziehbar, und die Schule kann eingreifen.

1. Der Schüler setzt im Spiel seinen Wunschnamen, am Türschild seines Lobby-Raums.
2. Die Welt prüft die Regeln unten. Passt der Name, gilt er sofort, auch wenn das Backend gerade nicht erreichbar ist.
3. Die Welt schreibt die Änderung in ein Protokoll und sagt sie allen, die gerade im Spiel sind und das Pult benutzen dürfen.
4. Die Welt meldet den Namen über die Brücke ans Backend. Die Web-Anwendung zeigt ihn bei dem Schüler und markiert Namen, die neu sind.
5. Das Backend schreibt den Lehrkräften der Gruppe eine E-Mail, dass es neue Wunschnamen gibt. So erfahren sie es auch in den Ferien, wenn lange keine Lehrkraft im Spiel ist.
6. Die Lehrkraft der Gruppe kann einen Namen in der Web-Anwendung entfernen und dem Schüler das Ändern sperren. Beides ist ein Auftrag an die Welt.

Regeln:

- Der Wunschname ist nur eine Anzeige.
- Eindeutig pro Welt, mit einer einfachen Regel: Ein Name ist vergeben, wenn es ihn schon als Kontonamen oder als Wunschnamen gibt. Groß- und Kleinschreibung macht dabei keinen Unterschied. Ähnlichkeit wird nicht geprüft.
- Für alle Konten gilt dasselbe. Auch Lehrkräfte setzen einen Wunschnamen, mit denselben Regeln und derselben Frist. Entfernt oder gesperrt werden nur die Namen von Schülern: Lehrkräften wird vertraut. Ob die Schulverwaltung den Wunschnamen einer Lehrkraft löschen können soll, wird mit Schritt 7 entschieden.
- 2 bis 16 Zeichen: Buchstaben, auch Umlaute und ß, Ziffern, dazu einzelne Leerzeichen und Bindestriche in der Mitte.
- Ein Schüler kann seinen Namen einmal im Monat ändern. Zum Kontonamen zurück kann er jederzeit.
- Hat die Lehrkraft einen Namen entfernt, darf der Schüler sofort einen neuen setzen, wenn er nicht gesperrt ist.
- Eine Sperre gilt, bis die Lehrkraft sie aufhebt. Sie entfernt den Namen nicht von selbst.
- Das Protokoll hält fest, wer wann welchen Namen gesetzt hat und welche Lehrkraft einen Namen entfernt oder gesperrt hat. Es gehört zu den Protokollen der Welt und wird mit ihnen gelöscht.
- Entfernen und Sperren gibt es zunächst nur in der Web-Anwendung. Das Pult im Spiel kann es später bekommen.
- Der Wunschname liegt in der Welt und bleibt mit dem Konto erhalten. Beim Jahresabschluss wird nur das Protokoll der Wunschnamen gelöscht.
- Die E-Mail nennt die Gruppe, das Konto und den neuen Wunschnamen. Lehrkräfte nutzen die Plattform mit ihrer dienstlichen Adresse.
- Je Gruppe geht höchstens eine solche E-Mail am Tag hinaus, an die Lehrkräfte der Gruppe mit bestätigter Adresse. Sie nennt alle Änderungen seit der letzten.
- Genau eine Funktion „Anzeigename dieses Spielers“ bedient alle Stellen: Name über der Figur, Chat, Türschild, Pult.
- Im Spiel steht überall nur der Wunschname, für Schüler wie für Lehrkräfte. Welches Konto dahintersteht, zeigt die Web-Anwendung: Die Liste der Schüler lässt sich nach Wunschname und Kontoname durchsuchen.
- Eine Ausnahme ist die Nachricht über eine Änderung an die Lehrkräfte im Spiel. Sie nennt Konto und neuen Namen.
- Private Nachrichten (`/msg`) werden weiter an den Kontonamen geschickt und nennen den Kontonamen des Absenders.

### 6.3 Zwei Arten von Daten

| | Bleibt mit dem Konto | Wird jährlich gelöscht |
|---|---|---|
| Was | Lernniveau pro Modul, Meilensteine, Trophäen, Wunschname | Chatprotokolle, Belohnungsprotokoll, einzelne Aufgabenversuche, Pult-Protokolle, Protokoll der Wunschnamen |
| Löschen | beim Schulaustritt, oder vorher auf Verlangen (Abschnitt 12) | per Jahresabschluss |

Das Backend bewahrt dauerhaft nur den Stand auf, nicht den Verlauf dahin.

## 7. Orte

### 7.1 Überblick

| Ort | Zweck | Inventar | Besonderheiten |
|---|---|---|---|
| Wildnis | freies Survival | Survival-Inventar | Grundstücksschutz |
| Lobby | Portale, persönliche Räume | Survival-Inventar | Schutzzone: kein Schaden, kein Bauen, kein PvP |
| Lernräume | Aufgaben mit eigenem Raum (TZ, Logikrätsel) | Lern-Inventar | z. B. Flugrecht |

Die Lernräume und die Lobby liegen weit oben im Himmel der jeweiligen Welt, wo der Kartengenerator nur Luft erzeugt.

### 7.2 Lernräume

Der Mod `lep_rooms` baut und verwaltet die Lernräume. Er kennt keine Aufgaben, die kommen von den Lernmodulen.

- **Raumtypen.** Ein Lernmodul meldet seinen Raumtyp an: Innenmaße, geltende Rechte und eine Funktion, die den Raum nach dem Bau einrichtet.
- **Ein fester Raum pro Schüler und Raumtyp.** Die Zuteilung wird gespeichert. Angefangene Arbeit bleibt stehen, wenn jemand den Raum verlässt.
- **Lage.** Jeder Raumtyp hat eine eigene Ebene ab Höhe 10 000. Die Räume stehen in der Mitte von Feldern mit 512 Blöcken Kantenlänge, die Ebenen liegen 512 Blöcke übereinander. So liegen Schüler in Nachbarräumen außerhalb der Reichweite, in der der Server Spieler, Namen, Geräusche und Kartenteile überträgt. Dieses Raster ist fest und darf nie geändert werden, weil es die Lage aller vorhandenen Räume bestimmt.
- **Ebenen.** Jede Ebene gehört genau einem Raumtyp. Die Nummer wird einmal vergeben und nie geändert. Ebene 38 gehört dem Test-Raumtyp.
- **Hülle.** Boden, Wände und Decke sind unzerstörbar. Die Blöcke sind eigene Blöcke von `lep_rooms`, nutzen aber Texturen aus Minetest Game: dunkles Holz für den Boden, Silbersandstein für Wände und Decke. Die Fugen ergeben ein Raster von einem Block.
- **Licht.** Der Innenraum ist mit unsichtbarer, leuchtender Luft gefüllt (`lep_rooms:air`). Damit ist jede Stelle gleich hell, auch die Unterseite eines Körpers in der Raummitte. Lernmodule müssen diesen Block wie Luft behandeln.
- **Schutz.** Im Innenraum darf nur der Besitzer bauen und abbauen. Hüllen und der Raum zwischen den Räumen sind für alle gesperrt.
- **Bau.** Ein Raum entsteht spätestens beim ersten Betreten. Legt die Welt Konten an, baut sie für jedes neue Konto gleich den Raum in der Lobby und die Räume aller Raumtypen, einen nach dem anderen im Hintergrund. So muss nichts gebaut werden, wenn sich am ersten Tag eine ganze Klasse gleichzeitig anmeldet. Ein Raumtyp kann sich davon ausnehmen, wenn ihn nicht jeder Schüler braucht.
- **Neubau.** Ein Raum lässt sich von Grund auf neu bauen: neue Hülle, leerer Innenraum, neu eingerichtet. Was darin gebaut war, geht verloren. Das Lernmodul erfährt es über ein Ereignis. Jeder Raumtyp hat eine Versionsnummer. Erhöht ein Modul sie, werden alte Räume beim nächsten Betreten von selbst neu gebaut.
- **Verlassen.** Führt vorerst in die Wildnis. Mit der Lobby führt es dorthin zurück, woher der Schüler kam.

### 7.3 Erscheinen

- **Erste Anmeldung:** Lobby.
- **Weitere Anmeldungen:** Ort des Ausloggens, auch im Lernraum. Wer eingefroren ausloggt, bleibt eingefroren.
- **Tod:** Lobby, außer man hat ein Bett. Der Besitz bleibt wie in Minetest Game am Todesort.

### 7.4 Portale

**Aussehen und Benutzung**

- Ein Portal steht senkrecht. Der Rahmen ist außen 3 breit und 4 hoch, innen ist eine Fläche von 1 × 2 frei. Die vier Ecken des Rahmens dürfen fehlen.
- Die Fläche leuchtet, beim festen und beim persönlichen Paar violett. Über den Portalen in Halle und Lernhalle hängt ein Schild mit dem Ziel, bei den beiden frei stehenden Portalen der Halle vorn und hinten. Wer etwa eine Sekunde in der Fläche steht, wird versetzt und kommt einen Schritt vor dem Zielportal an.
- Jeder Ortswechsel durch ein Portal läuft über die Ortsverwaltung.

**Festes Paar**

- Ein Portal steht in der Mitte der Halle, links neben dem Portal zur Lernhalle. Das Gegenstück steht in der Wildnis am Startpunkt der Welt auf einer kleinen Plattform.
- Beide sind unzerstörbar, die Plattform ist geschützt.

**Persönliches Paar**

- Im eigenen Lobby-Raum steht ein fertiger Rahmen an der Rückwand. Das Gegenstück baut der Schüler selbst auf seinem Grundstück.
- **Bauen:** Rahmen aus Obsidian mauern (6 Blöcke, mit Ecken 10) und mit einem Mese-Kristall in der Hand auf den Rahmen rechtsklicken. Der Kristall wird verbraucht.
- **Bedingungen:** Die Form stimmt, das Innere ist frei, der Schüler ist in der Wildnis, und der Rahmen steht in einem geschützten Bereich, in dem er bauen darf. Sonst sagt eine Meldung, was fehlt, und der Kristall bleibt erhalten.
- Geprüft wird der Schutz nur beim Zünden und nur über Luantis Standardfunktion. Wer auf einem fremden Grundstück als Mitglied eingetragen ist, kann sein Portal deshalb auch dort zünden.
- Jeder Schüler hat höchstens ein gebautes Portal. Ein neues lässt das alte erlöschen, dessen Rahmen bleibt stehen.
- Wird ein Block des Rahmens abgebaut, erlischt das Portal. Der Kristall ist verloren.
- Ohne gebautes Portal ist die Fläche im Raum grau. Wer hineingeht, bekommt einen Hinweis, wie man ein Portal baut.
- Das Portal im Raum funktioniert nur für den Besitzer. Besucher bekommen einen Hinweis.
- Betritt ein fremder Schüler ein gebautes Portal, landet er in der Halle. Zurück kommt er nur über sein eigenes oder das feste Portal.

**Lernhalle**

- Rechts neben dem Portal zur Wildnis steht in der Halle das Portal „Lernen“ mit grüner Fläche. Es führt in die Lernhalle.
- Die Lernhalle ist ein gerader, geschlossener Gang hoch über der Lobby, außer Sichtweite. Sie gehört zum Ort Lobby: kein Bauen, kein Schaden.
- An ihrem Anfang steht das Portal zurück in die Halle. An den Seitenwänden stehen die Portale der Lernmodule, abwechselnd links und rechts, jedes mit einem Schild und einer Fläche in der Farbe des Moduls. Rechnen ist orange.
- Der Gang wächst mit der Zahl der Module, in Schritten von zwei Portalen. So ist Platz für beliebig viele.
- Ein Lernmodul meldet sein Portal bei `lep_portals` an: Name, Farbe, Zielort und was beim Betreten passiert. Es weiß nicht, wo das Portal steht. Sein Platz wird einmal vergeben und bleibt.
- Wer durch ein Modulportal in einen Lernraum geht und ihn wieder verlässt, steht vor diesem Portal.
- Die Unterrichtsmodi gelten: Im Modus „Unterricht“ weist ein Modulportal Schüler ab.

Portale werden selbst gebaut. Vorhandene Portal-Mods bilden frei verknüpfbare Reisenetze oder verknüpfen Orte statt Spieler und passen nicht zu diesen Regeln. Geprüft wurde auch die Portal-Schnittstelle des Nether-Mods.

### 7.5 Lobby

**Halle.** Der gemeinsame Bereich ist eine Halle hoch über der Welt, unterhalb der Lernräume.

- **Form:** ein Zylinder mit einer Kuppel darüber. Innenradius 15 Blöcke, 4 Blöcke senkrechte Wand, in der Mitte 19 Blöcke hoch.
- **Material:** Wand und Kuppel aus Glas. Der Boden ist fast schwarz (Obsidian), mit einer kreisrunden Glasscheibe von 11 Blöcken Durchmesser in der Mitte. Durch sie sieht man den Himmel, nicht die Landschaft.
- **Licht:** zwei Leuchtringe im Boden, einer lückenlos unter der Glaswand und einer um die Glasscheibe, dazu das leuchtende Portal in der Mitte. Nachts ist es dadurch nirgends dunkel.
- **Tiere:** Unter der Kuppel schweben Glühwürmchen, weiter unten Schmetterlinge. Sie sind Schmuck an festen Plätzen und lassen sich nicht fangen.
- **Musik:** In der Halle läuft leise eine eigene Hintergrundmusik in Schleife. Sie beginnt beim Betreten und blendet beim Verlassen aus. Einen Schalter dafür gibt es nicht, wer keine Musik möchte, stellt sie am eigenen Client ab.
- **Inhalt:** in der Mitte auf der Glasscheibe zwei Portale nebeneinander, links zur Wildnis und rechts zur Lernhalle mit den freiwilligen Aufgaben (Abschnitt 7.4), dazu die Anzeigetafel.
- **Gänge:** Vier Gänge verlassen die Halle, einer in jede Himmelsrichtung. Sie führen zu den persönlichen Räumen.
- **Schutz:** Niemand kann in der Lobby bauen oder abbauen, niemand nimmt Schaden. Alle Blöcke sind unzerstörbar.

Die Halle wird aus Code erzeugt. Eine von Hand gebaute Halle kann sie später ersetzen. Der Rest des Mods fragt die Halle nur nach vier Dingen: dem Startpunkt für ankommende Spieler, dem Platz für das Portal, Anfang und Richtung der vier Gänge und dem geschützten Bereich. Das Einbinden eines Bauplans wird erst gebaut, wenn es eine solche Halle gibt.

**Persönliche Räume** an den vier Gängen, einer pro Schüler:

- Die Räume liegen auf beiden Seiten jedes Gangs. Neue Räume werden reihum auf die vier Gänge verteilt, damit kein Gang viel länger wird als die anderen. Bei 30 Schülern ist kein Raum weiter als 30 Blöcke von der Halle entfernt.
- Ein Raum ist innen 5 Blöcke breit, 7 tief und 4 hoch. Die Tiefe kostet keinen Laufweg im Gang. Vorn stehen die Sockel, die beiden hinteren Reihen bleiben frei für Portal und Kiste. Wände und Decke sind aus Silbersandstein, von außen sieht man nicht hinein. Licht geben je eine Lampe in Boden und Decke.
- **Tür:** Jeder Raum hat eine Tür, die dem Besitzer gehorcht. Er öffnet und schließt sie mit einem Klick. Offen heißt Besuch willkommen, geschlossen heißt gesperrt. Andere können eine geschlossene Tür von außen nicht öffnen und eine offene nicht schließen. Wer im Raum steht, kann eine geschlossene Tür immer von innen öffnen, damit niemand eingesperrt wird. Schließen kann sie nur der Besitzer. Lehrkräfte kommen immer hinein. Die Tür ist zu Beginn offen und lässt sich nicht abbauen.
- Gänge und Räume gehören zum Ort Lobby. Schutz und Musik gelten dort wie in der Halle.

- Persönliches Portal.
- Belohnungskiste: Nur der Besitzer öffnet sie, und er kann nur entnehmen.
- Sechs Sockel für Trophäen, drei an jeder Seitenwand (Abschnitt 8.4).
- Türschild über dem Eingang mit dem Anzeigenamen in lesbarer Schrift, dort setzt der Besitzer auch seinen Wunschnamen. Kontonamen stehen in zwei Zeilen, getrennt am Unterstrich. Umlaute brauchen eine zweite Schrift von signs_lib, sie wird mit den Wunschnamen eingeschaltet.
- Andere dürfen den Raum betreten und schauen, solange die Tür offen ist. Portal, Kiste und Trophäen funktionieren nur für den Besitzer.
- Wände, Portal, Kiste und Sockel sind unveränderlich.
- Im Raum stehen nur Trophäen, keine normalen Gegenstände.
- Ein Gang wächst um einen Raum, sobald die Welt ein neues Konto anlegt. Solange es das Backend nicht gibt, zählt dafür die erste Anmeldung. Die Zuteilung bleibt dauerhaft.

Ein eigenes sicheres Lager gibt es in der Lobby nicht. Abschließbare Kisten bauen sich die Schüler selbst auf ihrem Grundstück.

### 7.6 Ortsverwaltung

Jeder Ortswechsel läuft über eine einzige Funktion in einem eigenen Mod, egal ob Portal, Lehrkraft, Tod oder Anmeldung. Sie kümmert sich um:

- Position merken,
- Inventar tauschen,
- Rechte setzen,
- den vorigen Ort merken.

Bei jeder Anmeldung werden Rechte und Zustand passend zum aktuellen Ort neu gesetzt. So bleibt nach einem Absturz kein Flugrecht in der Wildnis hängen.

**Ortstypen.** Andere Mods melden Ortstypen bei `lep_places` an, mit dem dort geltenden Inventar, den dort geltenden Rechten und einem Namen für die Übersicht im Pult. Die Wildnis ist von Anfang an angemeldet.

**Inventar.** Gespeichert wird nur das Survival-Inventar: Hauptinventar und Handwerksfeld. Beim Betreten eines Lernraums wird es gesichert und geleert, der Lernraum gibt dem Spieler seine Gegenstände neu. Beim Verlassen werden die Lern-Gegenstände verworfen und das Survival-Inventar zurückgegeben. Lebenspunkte bleiben unverändert.

**Zurück.** `lep_places` merkt sich pro Spieler, ob er zuletzt in der Lobby oder in der Wildnis war. Wer einen Lernraum verlässt, kommt dorthin zurück. Lernräume selbst zählen dabei nicht.

**Rechte.** `lep_places` vergibt die Rechte eines Ortes selbst und merkt sich pro Spieler, welche es vergeben hat. Entzogen werden nur diese. Wer ein Recht ohnehin hat, etwa eine Lehrkraft das Flugrecht, behält es.

Lern-Gegenstände lassen sich außerhalb der Lernräume nicht verwenden.

**Eigene Wege.** Portale, Ausgänge und Befehle, mit denen ein Spieler sich selbst bewegt, fragen vorher bei `lep_places` nach, ob er dorthin darf. Andere Mods melden dafür Regeln an. So sperrt der Unterrichtsmodus die Wildnis, ohne dass die Portale ihn kennen.

**Sichtweite.** Luanti zeigt in der Voreinstellung jeden Spieler jedem Client, egal wie weit entfernt. Dann stehen die Namensschilder von Leuten in der Lobby oder im Lernraum am Himmel über der Wildnis. `lep_places` begrenzt die Sichtweite deshalb auf 160 Blöcke (`player_transfer_distance = 10`), solange der Server nichts anderes einstellt. Wer in seiner `minetest.conf` selbst einen Wert setzt, behält ihn.

## 8. Lernen

### 8.1 Fortschritt

Die Lernmodule melden nur, was passiert ist: wer, Modul und Thema, Niveau, gelöst ja/nein, Versuche, benutzte Hilfen, Dauer. Sie entscheiden nichts.

Der Fortschritts-Mod verteilt diese Ereignisse nach dem Beobachter-Muster. Belohnung, Trophäen, Brücke und die Übersicht im Pult melden sich dort an. Ein Lernmodul weiß nichts von Diamanten.

Ein Modul fragt umgekehrt nur ab: „Auf welchem Niveau steht dieser Schüler bei mir?“ und „Welche Aufgabensets sind ihm zugewiesen?“

Module, die kurze Aufgaben im Dialogfenster stellen können (Rechnen, Textfragen), melden diese Fähigkeit bei `lep_progress` an. Die Aufgabentruhe nutzt sie und weiß nicht, aus welchem Modul eine Aufgabe stammt. Eine kurze Aufgabe besteht aus einer Zeile Text, dem Aufgabentyp, dem Niveau und einer Prüffunktion. Die Lösung bleibt in der Prüffunktion auf dem Server.

### 8.2 Niveau und Pensum

**Niveau**

- Jedes Modul hat beliebig viele Niveaus, also Schwierigkeitsgrade. Das Modul legt fest, wie viele es sind. Kopfrechnen braucht deutlich mehr als drei.
- Die Lehrkraft setzt das Niveau pro Schüler und Modul. Ein Schüler kann in verschiedenen Modulen auf verschiedenen Niveaus stehen.
- Für neue Schüler gilt ein Startniveau, das die Lehrkraft pro Gruppe und Modul festlegt.
- Es gibt keinen Auf- oder Abstieg nach Leistung.

**Pensum**

Erzeugte Aufgaben gibt es unbegrenzt. Damit ein Prozentwert und ein Abschluss möglich sind, hat jedes Niveau ein festes Pensum:

- Jedes Niveau eines Moduls besteht aus einer festen Liste von Aufgabentypen, z. B. „Addition bis 20“.
- Ein Aufgabentyp gilt als geschafft, wenn der Schüler ihn eine bestimmte Anzahl von Malen richtig gelöst hat. Voreingestellt ist fünfmal, ein Modul kann das pro Aufgabentyp ändern.
- Falsche Antworten ziehen nichts ab, sie zählen nur nicht.
- Gezählt werden nur Aufgaben auf dem aktuellen Niveau. Aufgaben eines höheren Niveaus, etwa aus einer Aufgabentruhe, werden gemeldet und können belohnt werden, zählen aber nicht für das Pensum.
- Setzt die Lehrkraft das Niveau um, bleibt der Stand der anderen Niveaus erhalten.
- Der Prozentwert ist der Anteil der richtig gelösten Aufgaben an den verlangten, über alle Aufgabentypen des Niveaus. Vier von zweimal fünf sind 40 %. So zeigt jede gezählte Aufgabe Wirkung, nicht erst ein voller Aufgabentyp.
- Bei 100 % ist das Niveau abgeschlossen.
- Bei Textfragen ordnet die Lehrkraft ein Fragenset einem Niveau zu. Der Prozentwert ist der Anteil richtig gelöster Fragen.

**Abschluss und Aufstieg**

- Nach dem Abschluss eines Niveaus steigt der Schüler automatisch ins nächste auf.
- Der automatische Aufstieg ist voreingestellt an. Die Lehrkraft kann ihn pro Schüler sperren.
- Die Lehrkraft kann das Niveau jederzeit von Hand ändern.
- Setzt die Lehrkraft einen Schüler auf ein Niveau, das er schon abgeschlossen hat, wird dessen Pensum geleert: Er wiederholt das Niveau. Ist das Pensum wieder voll, steigt er von selbst auf, wenn der Aufstieg nicht gesperrt ist.
- Ein Niveau wird nur einmal abgeschlossen. Beim Wiederholen gibt es die Belohnung für den Abschluss und die Trophäe nicht noch einmal. Die einzelnen Aufgaben zählen und werden belohnt wie beim ersten Mal.
- Nach dem letzten Niveau ist das Modul abgeschlossen. Belohnungen gibt es danach weiter über die Tagesaufgaben.

**Begriffe**

Ein Niveau ist ein Schwierigkeitsgrad, gezählt ab 1. Die Abfolge von Aufgaben oder Räumen innerhalb eines Niveaus heißt Station, nicht Level.

**Wo das Niveau gesetzt wird**

In der Web-Anwendung. Bis sie existiert, genügt ein einfacher Chatbefehl für Lehrkräfte. Ein eigener Reiter im Pult wäre doppelte Arbeit.

### 8.3 Belohnungen

**Zwei Arten von Aufgaben**

- **Niveauaufgaben** gehören zum Pensum eines Niveaus und sind nicht wiederholbar: Eine Aufgabe bringt nur so lange Lohn, wie sie fürs Pensum zählt. Ist ein Aufgabentyp geschafft, gibt es dafür nichts mehr. Üben kann der Schüler weiter, nur ohne Belohnung.
- **Tagesaufgaben** sind wiederholbar und bringen jeden Tag aufs Neue Lohn, bis zum Tageslimit. Dazu gehören die Aufgabentruhen in der Welt und die freiwilligen Aufgaben in der Lobby. Sie zählen nicht fürs Pensum.

So lohnt es sich nicht, leichte Aufgaben endlos zu wiederholen, und das Üben lohnt sich trotzdem auch nach einem abgeschlossenen Modul.

**Größen und Anlässe**

- Naturalien.
- Drei Größen, die die zuständige Lehrkraft pro Gruppe in der Web-Anwendung mit Gegenständen füllt. Bis es sie gibt, kommen sie aus den Einstellungen des Servers.

| Anlass | Größe | Voreinstellung |
|---|---|---|
| Niveauaufgabe gelöst, die fürs Pensum zählt | klein | 1 Eisenbarren |
| Tagesaufgabe gelöst | mittel | 1 Goldbarren |
| Niveau abgeschlossen | mittel | 1 Goldbarren |
| Etappe abgeschlossen | groß | 1 Diamant |

- Tagesaufgaben können unterschiedlich belohnt werden. Wer die Aufgabe stellt, gibt ihren Aufwand an: gering, normal oder hoch. Daraus wird klein, mittel oder groß. Ohne Angabe gilt normal.

**Etappen**

- Ein Modul kennzeichnet einzelne Niveaus als Etappe. Das letzte Niveau ist immer eine.
- Nur der Abschluss einer Etappe bringt die große Belohnung. So bleibt sie auch bei Modulen mit vielen Niveaus etwas Besonderes.
- Dieselben Etappen gelten für die Trophäen.

**Regeln**

- Niveauaufgaben haben kein Tageslimit. Das Pensum ist endlich und begrenzt den Lohn von selbst: Ein Niveau mit drei Aufgabentypen zu je fünf Lösungen bringt genau 15 kleine Belohnungen und eine mittlere.
- Tagesaufgaben: 5 belohnte pro Tag. Der Tag wechselt um Mitternacht nach der Uhr des Servers, nicht nach der Spielzeit.
- Ist das Limit erreicht, kann der Schüler weiter Tagesaufgaben lösen, sie bringen aber nichts mehr.
- Faustregel: Eine Aufgabe bringt etwas mehr, als man in derselben Zeit abbauen könnte.
- Keine Zufallsbelohnungen. Die Belohnung steht vorher fest und ist sichtbar.
- Belohnung nur auf dem eigenen Niveau und darüber. Weil die Lehrkraft das Niveau passend setzt, ist das für alle fair.
- Textfragen belohnen nur beim ersten Lösen, Multiple Choice voll nur im ersten Versuch.

**Auszahlung**

- Die Belohnung einer Tagesaufgabe geht direkt ins Inventar, wenn der Schüler in diesem Moment sein Survival-Inventar trägt, also etwa an einer Aufgabentruhe in der Wildnis.
- Alles andere geht in die Belohnungskiste: Tagesaufgaben in einem Lernraum, wo das Survival-Inventar weggelegt ist, Niveauaufgaben und abgeschlossene Niveaus und Etappen.
- Was nicht ins Inventar passt, geht ebenfalls in die Kiste.
- Die Chatnachricht sagt, wo die Belohnung liegt.
- Was im Inventar liegt, kann wie jeder andere Besitz beim Tod verloren gehen. Das ist so gewollt.

**Belohnungskiste**

- Sie steht im persönlichen Raum. Nur der Besitzer kann sie öffnen, und er kann nur herausnehmen.
- Der Inhalt gehört zum Konto, nicht zum Block. Belohnungen kommen auch an, wenn der Schüler abgemeldet ist.
- Ist die Kiste voll, wartet der Rest und rückt nach, sobald Platz ist.

**Protokoll**

- Jede Belohnung wird protokolliert: Zeitpunkt, Kontoname, Größe, Anlass, Modul, Niveau, Aufgabentyp, Inhalt.
- Das Protokoll hilft bei Streitfällen. Schüler sehen ihr eigenes, Lehrkräfte das ihrer Schüler.
- Verwaltung und Löschung wie bei allen Protokollen, siehe Abschnitt 12.

### 8.4 Trophäen

**Verdienen**

- Ein eigener Mod vergibt Trophäen für Meilensteine. Eine Trophäe wird einmal verdient und gehört dann dem Konto.
- Jeder Mod kann Trophäen anmelden und vergeben, nicht nur die Lernmodule.
- Meilensteine aus dem Lernen:

| Meilenstein | Trophäe |
|---|---|
| Etappe eines Moduls abgeschlossen (Etappen siehe Abschnitt 8.3) | Silber, die letzte Etappe Gold |
| 10, 50, 100 gelöste Niveauaufgaben in einem Modul | Bronze, Silber, Gold |
| 10, 50 gelöste Tagesaufgaben insgesamt | Bronze, Silber |
| Fragenset zu mindestens 80 % richtig abgeschlossen | kommt mit dem Modul Textfragen |

- Für die Zähler gilt jede gelöste Aufgabe, auch eine, die keine Belohnung mehr bringt. Üben ist eine Trophäe wert.
- Trophäen aus dem Survival-Teil kommen über den Awards-Mod (rubenwardy, MIT). Er zählt Leistungen wie abgebaute Blöcke und meldet freigeschaltete Erfolge. Eine Brücke in `lep_survival` macht daraus Trophäen. Sie erscheinen auf dem Sockel als Plakette mit dem Symbol des Erfolgs. Abgeschaltet ist nur der Erfolg für hundertfaches Sterben. Die Zähler von Awards bleiben in der Welt, die Trophäen gehören dem Konto. Awards zeigt beim Freischalten eine eigene Einblendung und hat mit `/awards` eine eigene Übersicht.

**Ausstellen**

- Im eigenen Lobby-Raum stehen sechs feste Sockel, drei an jeder Seitenwand. Die Trophäe steht als Block auf dem Sockel.
- Der Besitzer klickt einen Sockel an, sieht die Liste seiner verdienten Trophäen und wählt eine aus oder leert den Sockel.
- Jede Trophäe steht nur auf einem Sockel. Wird sie woanders gewählt, zieht sie um.
- Besucher sehen die Auswahl und beim Zeigen auf eine Trophäe, wofür sie steht. Ändern können sie nichts.
- Voreingestellt sind Pokale in Bronze, Silber und Gold. Ein Mod kann für seine Trophäen ein eigenes Aussehen angeben.
- Trophäen sind nicht übertragbar. Sie sind kein Gegenstand im Inventar.

**Daten**

- Verdiente Trophäen, Zähler und die Belegung der Sockel sind Daten des Kontos, später im Backend. Der Raum zeigt sie nur an. Nach einem Gruppenwechsel baut die neue Welt den Raum mit denselben Trophäen wieder auf.

### 8.5 Aufgabentruhe

Eine Truhe in der Wildnis, die statt eines Inhalts eine kurze Aufgabe stellt. Sie ist eine Tagesaufgabe mit normalem Aufwand und bringt die mittlere Belohnung.

**Regeln**

- Schüler können sie nicht herstellen und nicht abbauen.
- Herkunft: von der Welt erzeugt oder von der Lehrkraft aufgestellt.
- Jeder Schüler kann jede Truhe einmal lösen und bekommt seine eigene Belohnung.
- Die Aufgabe richtet sich nach dem Niveau des Öffnenden, die Belohnung ist gleich. Welches Modul die Aufgabe stellt, entscheidet der Zufall unter den Modulen mit kurzen Aufgaben (Abschnitt 8.1).
- Das Fenster zeigt die Frage als Text, ein Eingabefeld und die Belohnung. Die Eingabetaste prüft die Antwort.
- Nach einem Fehlversuch: 30 Sekunden Wartezeit, dann eine neue Aufgabe. Die Lösung wird nie gezeigt.
- Aufgabe und Lösung merkt sich der Server pro Spieler. Im Block selbst steht nichts, was ein Client auslesen könnte. Beim Absenden prüft der Server erneut, ob der Spieler an der Truhe steht.

**Erzeugte Truhen**

- Alle paar Minuten prüft der Server für jeden Schüler in der Wildnis, ob eine Truhe in seiner Nähe steht. Wenn nicht, erscheint eine in 30 bis 80 Blöcken Entfernung, und der Schüler bekommt einen Hinweis im Chat.
- Sie steht auf festem, natürlichem Boden: nicht im Wasser, nicht in Höhlen, nicht in Gebäuden und nicht auf geschützten Grundstücken. Im Wald steht sie am Boden unter den Bäumen, nie in der Krone.
- Eine Truhe, die niemand löst, verschwindet nach 30 Minuten.
- Nach dem ersten Lösen bleibt sie noch 10 Minuten stehen, damit Begleiter sie auch lösen können. Dann verschwindet sie.
- Höchstens 20 erzeugte Truhen pro Welt.

**Truhen der Lehrkraft**

- Wer das Privileg `lep_place_quest_chest` hat, bekommt mit `/lep_quest_chest` eine Truhe ins Inventar und stellt sie auf wie einen Block.
- Diese Truhen laufen nicht ab. Entfernt werden sie über einen Knopf im Fenster, den nur sieht, wer das Privileg hat.
- Vorerst stellen sie dieselben Aufgaben wie die erzeugten Truhen. Eigene Fragen der Lehrkraft kommen mit den Textfragen (Abschnitt 8.7).

### 8.6 Rechnen

**Aufgaben**

- Aufgaben werden erzeugt. Jeder Aufgabentyp ist eine Regel, etwa „Addition bis 20 mit Zehnerübergang“.
- „3,5“ und „3.5“ gelten beide.
- Zeitdruck nur optional.
- Ein Aufgabentyp ist nach zehn richtigen Lösungen geschafft, die gemischten Aufgaben nach fünf.
- Der Schüler wählt den Aufgabentyp nicht selbst. Gestellt werden bevorzugt die Typen, die ihm noch fehlen.

**Zwölf Niveaus**

| Niveau | Aufgabentypen | Etappe |
|---|---|---|
| 1 | Addition bis 10, Subtraktion bis 10 | |
| 2 | Addition und Subtraktion bis 20, ohne Zehnerübergang | |
| 3 | Addition und Subtraktion bis 20, mit Zehnerübergang | ja |
| 4 | Addition und Subtraktion bis 100, ohne Übergang | |
| 5 | Addition und Subtraktion bis 100, mit Übergang | |
| 6 | Einmaleins mit 2, 5 und 10, dazu die Division | ja |
| 7 | Einmaleins mit 3, 4 und 6, dazu die Division | |
| 8 | Einmaleins mit 7, 8 und 9, dazu die Division | |
| 9 | Gemischte Aufgaben mit Punkt vor Strich | ja |
| 10 | Addition und Subtraktion bis 1000 | |
| 11 | Zehnerzahl mal Einer, Division mit Zehnerzahlen | |
| 12 | Dezimalzahlen mit einer Nachkommastelle, plus und minus | ja |

**Der Rechenraum**

Gerechnet wird in der Welt, nicht in einem Fenster.

- **Bündig:** Anzeige, Tastenfeld und Ausgang sind in die Wände eingelassen und ragen nicht in den Raum.
- **Anzeige:** In der Stirnwand sitzt eine Anzeige im Stil einer 7-Segment-Anzeige, neun Zeichen breit und zwei Reihen hoch. Oben steht die Aufgabe, darunter hinter einem Gleichheitszeichen die Eingabe.
- **Tastenfeld:** In der rechten Wand sitzt senkrecht ein Tastenfeld aus Blöcken, angeordnet wie beim Telefon: 7 8 9 oben, darunter 4 5 6 und 1 2 3, unten Löschen, 0 und die Eingabetaste. Die unterste Reihe liegt auf Bodenhöhe. Das Komma erscheint als weitere Taste, sobald eine Aufgabe es braucht. Getippt wird durch Anklicken.
- **Rückmeldung:** Bei einer richtigen Antwort leuchtet die Eingabe grün, dazu ein Ton, dann kommt die nächste Aufgabe. Bei einer falschen leuchtet sie rot, und der Schüler darf es noch einmal versuchen. Nach dem zweiten Fehler zeigt die Anzeige die richtige Lösung, die Aufgabe gilt als nicht gelöst, und es folgt eine neue.
- **Stand:** Unten in der Bildschirmmitte, über Herzen und Schnellleiste, stehen Modul, Niveau, Aufgabentyp und Stand, darunter die Belohnung für diese Aufgabe. Der obere Rand bleibt dem Chat.
- **Verlassen:** über einen Ausgangsblock neben der Stelle, an der man erscheint.
- **Hinkommen:** vorerst über einen Befehl. Später führen das Lehrerpult und ein Portal in der Halle dorthin.

Die Aufgabentruhe stellt dieselben Aufgaben in einem Fenster. Beide nutzen denselben Kern: Aufgabe erzeugen, Antwort prüfen, Versuche zählen.

Die Töne für richtig und falsch gehören dem Fortschritts-Mod und klingen in allen Lernmodulen gleich. Das Modul bestimmt nur den Moment. Dasselbe gilt für die Töne beim Abschluss eines Niveaus und einer Etappe.

Das Rechenmodul kennt keine Belohnungen. Die Zeile mit der Belohnung liefert der Belohnungs-Mod über eine neutrale Anfrage beim Fortschritts-Mod.

### 8.7 Textfragen

- Fragensets kommen von den Lehrkräften, hochgeladen in der Web-Anwendung und dort einem Niveau zugeordnet.
- Import im GIFT-Format, das Moodle (und damit die ByCS-Lernplattform) exportieren kann.
- Multiple Choice und kurze Freitexte mit einer Liste erlaubter Antworten.
- Lange Antworten gehen zur Durchsicht an die Lehrkraft und halten den Schüler nicht auf.

### 8.8 Technisches Zeichnen

**Grundlagen**

- Maßangaben folgen immer dem Schema Breite × Höhe × Tiefe.
- Achsen: Breite = x, Höhe = y, Tiefe = z. Die Vorderansicht ist die −Z-Seite.
- Sechs Ansichten: Vorderansicht, Rückansicht, Draufsicht, Untersicht, Seitenansicht von links und von rechts.
- Vorgehen wie im ISB-Material: erst der vollständige Quader, dann werden die Formveränderungen entfernt.
- Sprache des Monitors: Grundmaße, Formmaße, Lagemaße.
- Der didaktische Kern ist das eigene Bearbeiten des Körpers in der 3D-Welt.

**Baustein**

Ein Block mit sechs Texturen, der sich beim Setzen nicht dreht. Jede freigelegte Fläche zeigt automatisch die Farbe ihrer Richtung. Ein dünner dunkler Rahmen macht die Blöcke zählbar. Die Farben sind einstellbar.

**Datenmodell**

Jede Veränderung ist ein achsenparalleler Quader, der vom Grundkörper abgezogen wird. Pro Achse: **D** = durchgehend, **R** = Rand (berührt eine Seite), **I** = innen.

| Muster | Veränderung |
|---|---|
| D R R | Stufe |
| D R I | Nut |
| D I I | Durchbruch |
| R R R | Ausklinkung (Stufe, nicht durchgehend) |
| R R I | Ausklinkung (Nut, nicht durchgehend) |
| R I I | Ausklinkung (Durchbruch, nicht durchgehend) |
| D D x | ungültig: Körper wird kürzer oder zerfällt |
| I I I | ungültig: unsichtbarer Hohlraum |

Der Typ ergibt sich aus der Geometrie und wird nicht gespeichert.

**Generator**

Grundkörper erzeugen, bis zu 4 Veränderungen wählen und abwechselnd um je einen Block wachsen lassen.

1. Das Muster bleibt beim Wachsen erhalten.
2. Berühren ist eine Kollision. Zwischen zwei Veränderungen liegt mindestens 1 Block Material.
3. Jede Veränderung hat eine Zielgröße als Abbruchkriterium.
4. Pro Aufgabe sind höchstens 150 Blöcke abzubauen. Der Wert ist einstellbar. Es gibt dafür kein Bereichswerkzeug.

Eine Prüffunktion gilt für jeden Generator: Muster gültig, Mindestabstand, Mindestwandstärke, Körper zusammenhängend.

**Beschreibung**

- Der Text wird aus dem Modell erzeugt.
- Maße beziehen sich immer auf den Körper.
- Stufe und Eck-Ausklinkung: Ecke plus Formmaße. Nut und Durchbruch brauchen zusätzlich Lagemaße.
- Lage anfangs auf den Körper bezogen, später aus Sicht einer Ansicht.
- Bei Ausklinkungen nennt der Monitor die Grundform.

**Raum**

- Pro Schüler ein Raum mit Decke. Der Körper schwebt etwa 3 Blöcke über dem Boden.
- Flugrecht nur im Raum, kein Noclip.
- Unendlich Bausteine und ein Schnellabbau-Werkzeug, das nur TZ-Bausteine abbaut.
- Rückmeldung in Ansichten: „Vorderansicht ✓, Draufsicht ✗“.
- Ist der Körper richtig, öffnet sich die Tür zur nächsten Station.
- Bau-Stationen: Ein neutraler Ankerblock markiert die Startecke und wird bei der Prüfung ignoriert.
- Gemeinschaftsraum, in dem die Lehrkraft allen einen Körper zeigt.

**Stationen**

Die folgenden Schritte werden bei der Umsetzung auf die Niveaus verteilt.

1. Grundkörper nach B × H × T bauen.
2. Eine Stufe, Lage auf den Körper bezogen.
3. Nut und Durchbruch mit Lagemaßen.
4. Ausklinkungen.
5. Mehrere Veränderungen, Beschreibung aus gespiegelten Ansichten.
6. Umkehrung: Körper steht fertig da, die Schüler bestimmen seine Veränderungen.
7. Endstufe: Dreitafelprojektion statt Text.

**Differenzierung**

- Begriffe einstellbar („Formänderung“ an der Mittelschule, „Formveränderung“ an der Realschule).
- Schwierigkeit pro Gruppe oder Schüler einstellbar.
- Wenig Text für die Förderschule: Symbole, kurze Sätze, gleiche Satzmuster.
- Hilfe-Stufen statt Scheitern.

### 8.9 Logikrätsel

- Eigener Raum mit Mesecons.
- Prüfung über die Wahrheitstabelle, mit sichtbarem Prüflauf.
- Nur Schalter, Leitung, UND, ODER, NICHT, Lampe. Programmierbare Bausteine bleiben abgeschaltet.
- Rätsel lassen sich erzeugen: zufällige Logikfunktion mit 2 bis 3 Eingängen.

## 9. Survival-Welt

- **Grundstücksschutz:** Protector. Schüler stellen einen Schutzblock her und setzen ihn. Der Schutzbereich reicht 8 Blöcke in jede Richtung.
- **PvP:** aus, pro Welt einstellbar.
- **Monster:** zunächst keine, später pro Welt zuschaltbar über Mobs Redo.
- **Chat:** frei und ohne Filter. Jede Nachricht wird protokolliert, auch Privatnachrichten und `/me`: Zeitpunkt, Kontoname, Art, Empfänger, Text. Bei der Anmeldung liest jeder Spieler den Hinweis, dass mitgeschrieben wird. Pro Welt abschaltbar.
- **Stummschalten:** Lehrkräfte schalten einzelne Schüler am Pult stumm (Privileg `lep_mute_players`). Der Schüler verliert dabei Luantis Privileg `shout` und kann weder im Chat schreiben noch Privatnachrichten senden. Die Übersicht im Pult zeigt, wer stumm ist. Ist keine Lehrkraft mehr angemeldet, wird jede Stummschaltung aufgehoben, ebenso bei einem Neustart des Servers. So bleibt kein vergessener Schüler tagelang stumm.
- **Einsicht:** Wer das Privileg `lep_view_chat` hat, sieht die letzten Einträge mit einem Chatbefehl. Die eigentliche Einsicht kommt in der Web-Anwendung.
- **Schilder:** Schüler dürfen Schilder aufstellen und beschriften. Der Text ist für alle lesbar. Schildtexte werden wie Chatnachrichten protokolliert, mit Kontoname und Ort. Das Protokoll entsteht zusammen mit dem Chatprotokoll.
- **Abschließbare Türen, Falltüren und Kisten:** von Protector. Sie folgen dem Schutzbereich: Wer dort als Mitglied eingetragen ist, kann sie benutzen. Die entsprechenden Rezepte aus Minetest Game (Stahltür, Stahlfalltür, abschließbare Kiste) sind entfernt, damit es nicht zwei Sorten gibt. Das erledigt `lep_survival`.
- **Betten, Knochen, einfache Türen und Kisten:** aus Minetest Game.

Eigene Mods fragen den Schutz nur über Luantis Standardfunktion ab, nie direkt bei Protector. So bleibt der Schutz-Mod austauschbar.

## 10. Lehrkraft im Spiel

### 10.1 Lehrerpult

Ein eigener Mod mit selbst geschriebenem Fenster. Links die Zielauswahl (alle, einzelne Schüler), rechts die Aktionen. Aktionen sind registrierbare Bausteine, damit Lernmodule eigene Knöpfe ergänzen können.

- **Öffnen:** mit dem Chatbefehl `/pult`. Er funktioniert an jedem Ort, auch im Lernraum, wo das Inventar getauscht ist. Ein Pult-Block in der Halle kann später dasselbe Fenster öffnen.
- **Schüler:** In der Liste stehen alle angemeldeten Spieler, die das Pult selbst nicht öffnen dürfen. Gruppen kommen mit dem Backend.
- **Zielauswahl:** Die Liste ist eine Tabelle mit Kästchen, Name, Ort und Niveaus. Ein Klick auf das Kästchen markiert einen Schüler oder nimmt ihn heraus. Ein Klick auf den Rest der Zeile hebt sie nur hervor, als Lesehilfe. Unter der Tabelle setzen vier Knöpfe viele Kästchen auf einmal: alle markieren, keine markieren, umkehren, und „Gleicher Ort“ für alle, die am selben Ort sind wie der Schüler der hervorgehobenen Zeile. „Alle“ meint, wer im Moment der Aktion Schüler ist, also auch später Hinzugekommene.
- **Übersicht:** Jede Zeile zeigt den Ort des Schülers und sein Niveau in jedem Modul. Die Liste aktualisiert sich bei jedem Ortswechsel.
- **Privilegien:** `lep_view_players` öffnet das Pult und zeigt die Übersicht. Jede Aktion nennt ihr eigenes Privileg und ist nur für den sichtbar, der es hat. `lep_send_players` erlaubt Schicken und Zurückholen.
- **Protokoll:** Jede Aktion wird festgehalten: Zeitpunkt, Kontoname der Lehrkraft, Aktion, Ziele.
- **Textfeld:** Unter der Tabelle steht ein Feld für einen Text an die Schüler. Aktionen, die den Schülern etwas zeigen, bekommen ihn mit.
- **Aktionen:** Eine Aktion wirkt auf die markierten Schüler oder, wenn sie es so anmeldet, auf die ganze Welt oder auf genau den Schüler der hervorgehobenen Zeile. Aktionen können eine Gruppe mit Überschrift bilden und als Schalter ihre geltende Stellung anzeigen.

Erste Version:

- In einen Lernraum schicken (Modul und Station), zurückholen. Wer geschickt wird, landet in seinem eigenen Raum. Wer zurückgeholt wird, kommt dorthin, wo er vorher war.
- Festhalten: Wer geschickt wurde, kann den Raum nicht selbst verlassen, bis die Lehrkraft ihn zurückholt oder freigibt. Wer freiwillig hineingegangen ist, bleibt frei. Wird er dort von der Lehrkraft „geschickt“, ist er ab dann festgehalten. Die Übersicht zeigt, wer festgehalten ist.
- Freigeben: hebt das Festhalten auf, ohne den Schüler herauszuholen.
- Ist keine Lehrkraft mehr angemeldet, also niemand, der das Pult öffnen darf, sind alle frei. Das gilt für alles, was Lehrkräfte einzelnen Schülern auferlegen, auch für das Stummschalten. So sperrt ein Verbindungsabbruch der Lehrkraft, etwa im Fernunterricht, niemanden ein. Auch ein Neustart des Servers gibt alle frei, das Neuanmelden eines Schülers nicht.
- Aufmerksamkeitsmodus an/aus, mit eigenem Text.
- Unterrichtsmodus umschalten.
- Tageszeit der Welt steuern (Abschnitt 10.3).
- Unsichtbar zu einem Schüler springen (Zuschauen). Ziel ist der Schüler der hervorgehobenen Zeile. Die Lehrkraft landet an seiner Stelle und ist unsichtbar: keine Figur, kein Namensschild, keine Schrittgeräusche, nicht anklickbar. Der Schüler erfährt davon nichts. Eine Zeile am Bildschirm erinnert die Lehrkraft an den Zustand. „Zurück“ bringt sie an die Stelle, von der sie kam, und macht sie sichtbar. Verlässt sie den Ort auf anderem Weg oder meldet sie sich ab, ist sie ebenfalls wieder sichtbar. Privileg: `lep_watch_players`.
- Übersicht: wer ist wo, wer bearbeitet was.
- Reiter „Web-Zugang“ (Abschnitt 11.4). Das Pult hat dafür Reiter: „Schüler“ mit Liste und Aktionen, daneben weitere, die Mods anmelden.
- Für die Schulverwaltung: Lehrkräfte ernennen. Dabei entsteht das Konto der Lehrkraft mit frei gewähltem Namen, das Startpasswort wird einmal angezeigt. Das Backend verteilt das Konto in alle Welten. Die erste Person der Schulverwaltung legt der Server-Admin an.

Grundsätze:

- Aktionen teleportieren nie selbst, sie rufen die Ortsverwaltung auf.
- Rechte werden bei jedem Knopfdruck neu geprüft.
- Angefangene Aufgaben bleiben erhalten, wenn jemand herausgeholt wird.
- Chatbefehle als Notlösung.

### 10.2 Unterrichtsmodi

Ein Schalter im Pult mit drei Stellungen. Er gilt für die ganze Welt und regelt, wohin Schüler von sich aus gehen dürfen.

| Modus | Wildnis | Lobby | Lernräume |
|---|---|---|---|
| Freizeit | offen | offen | freiwillig offen |
| Freiarbeit | gesperrt | offen | freiwillig offen |
| Unterricht | gesperrt | offen | nur, wenn die Lehrkraft schickt |

- **Gesperrt wird dort, wo Schüler sich selbst bewegen:** an den Portalen, am Eingang und am Ausgang der Lernräume. Was die Lehrkraft auslöst, etwa Schicken, Zurückholen oder der Aufmerksamkeitsmodus, läuft daran vorbei.
- **Unterricht:** Ein Schüler betritt und verlässt Lernräume nicht selbst, auch wenn er vorher freiwillig hineingegangen war.
- **Wildnis räumen:** Schließt der Modus die Wildnis, holt der Server alle Schüler von dort in die Halle der Lobby. Die Stelle, an der sie standen, wird gemerkt. Ist die Wildnis wieder offen, bringt das Portal der Halle sie beim nächsten Durchgang dorthin zurück. Wer sich bei gesperrter Wildnis dort anmeldet oder nach dem Tod an seinem Bett erscheint, landet ebenfalls in der Halle.
- **Lehrkräfte** sind vom Modus ausgenommen.
- **Ohne Lehrkraft** gilt Freizeit: sobald niemand mehr angemeldet ist, der das Pult öffnen darf, und nach einem Neustart des Servers.
- **Privileg:** `lep_set_mode`. Die Schüler lesen bei jedem Umschalten im Chat, was jetzt gilt.

### 10.3 Tageszeit

Die Lehrkraft steuert die Tageszeit am Pult. Sie gilt für die ganze Welt, also für die ganze Gruppe.

- **Zeit setzen:** Morgen (6 Uhr), Mittag (12 Uhr), Abend (18 Uhr), Nacht (0 Uhr).
- **Schalter mit drei Stellungen:** Zeit läuft, dauernd Tag, dauernd Nacht. Bei „dauernd“ steht die Zeit still, am Mittag oder um Mitternacht. Das Pult zeigt die geltende Stellung.
- Wer bei „dauernd“ eine Zeit setzt, stellt den Schalter damit auf „Zeit läuft“.
- Die Knöpfe wirken auf die Welt und brauchen keine markierten Schüler.
- Angehalten wird über Luantis Einstellung `time_speed`. Der vorige Wert wird gemerkt und mit „Zeit läuft“ wiederhergestellt.
- Die Einstellung bleibt über einen Neustart des Servers erhalten.
- In den Lernräumen spielt die Tageszeit keine Rolle, dort ist es immer hell. Die Aktion betrifft Wildnis und Lobby.
- Die Aktion hat ein eigenes Privileg im Bündel „Lehrkraft“: `lep_set_time`. Luantis eingebautes `settime` wird nicht vergeben, weil es den Chatbefehl freischaltet und am Pult vorbeiführt.

### 10.4 Aufmerksamkeitsmodus

Die Lehrkraft holt sich die Aufmerksamkeit einzelner oder aller Schüler. Wer erfasst ist, sitzt in einer dunklen Zelle, sieht nur den Text der Lehrkraft und kann weder schreiben noch lesen.

**Zelle**

- Jeder Schüler hat eine eigene Zelle hoch über der Welt: ein Block Grundfläche, zwei Blöcke hoch, schwarze unzerstörbare Wände, kein Licht, kein Ausgang.
- Die Zelle ist ein Raumtyp von `lep_rooms`. Wie in jedem Lernraum ist das Survival-Inventar weggelegt.
- Statt den Schüler an Ort und Stelle einzufrieren, wird er versetzt. So kann ihm in der Wildnis nichts zustoßen, während er nicht handeln kann, und kein Mod muss Physik oder Privilegien anfassen.

**Wirkung**

- **Bewegungsunfähig:** In der Zelle ist kein Platz zum Laufen, und es gibt nichts zu bauen oder abzubauen.
- **Blind:** schwarzes Vollbild als HUD, darauf der Text der Lehrkraft. Schnellleiste, Herzen, Fadenkreuz und Chat sind ausgeblendet. Offene Fenster werden geschlossen, das Inventarfenster öffnet nicht.
- **Taub:** Der Schüler sendet nichts, auch keine Befehle, und empfängt weder Chat noch Privatnachrichten. Dafür verteilt `lep_chat` die Nachrichten selbst. Meldungen des Servers an alle, etwa wer sich anmeldet, sieht er nach dem Ende im Chatverlauf.
- **Still:** Der Server kann den Ton eines Clients nicht abschalten. In der Zelle gibt es aber keine Geräusche der Umgebung, und die Musik der Lobby endet mit dem Ortswechsel.
- **Unverwundbar:** ergibt sich aus der Zelle.

**Regeln**

- Der Text kommt aus dem Textfeld des Pults. Bleibt es leer, steht dort „Bitte achte auf deine Lehrkraft.“
- Beim Ausschalten kommt der Schüler an genau die Stelle zurück, an der er stand, in Wildnis, Lobby und Lernraum. War er in einen Lernraum geschickt, ist er dort wieder festgehalten. Im Rechenraum bekommt er eine neue Aufgabe desselben Typs, sein Fortschritt bleibt.
- Der Zustand übersteht Neuanmelden.
- Ist keine Lehrkraft mehr angemeldet, endet der Modus für alle, ebenso bei einem Neustart des Servers. Wer zu dem Zeitpunkt abgemeldet war, wird bei seiner nächsten Anmeldung zurückgebracht.
- Holt etwas anderes den Schüler aus der Zelle, etwa „In den Rechenraum schicken“, endet der Modus dort.
- Einzelne Schüler können ausgenommen werden: Die Aktion wirkt auf die Markierten.
- Wer das Pult öffnen darf, wird selbst nicht erfasst.
- Privileg: `lep_set_attention`.

### 10.5 Rechte

Privilegien beschreiben Handlungen, keine Rollen. Bündel sind nur Vorlagen im Pult.

| Bündel | Darf | Wer |
|---|---|---|
| Lehrkraft | Schüler lenken, Aufmerksamkeit schalten, Tageszeit steuern, zuschauen, Web-Zugang einrichten | alle Lehrkräfte |
| Schulverwaltung | zusätzlich: Lehrkräfte ernennen, Gruppen anlegen, Lehrkräfte Gruppen zuordnen, Jahresabschluss | ein bis zwei Personen |
| Server-Admin | Technik: Mods, Einstellungen, Welten anlegen | Betreiber |

Zwei Ebenen:

- **Was jemand darf** regeln Privilegien im Spiel. Sie gelten in jeder Welt.
- **Bei wem** regelt die Zuordnung von Lehrkraft zu Gruppe im Backend. Verwalten, Fortschritt sehen und Belohnungen festlegen geht nur für eigene Gruppen.

Wer zur Schulverwaltung gehört, sagt das Privileg `lep_manage_school`. Die Welten melden seine Träger ans Backend wie die Träger von `lep_web_access`. Wer es in mindestens einer Welt hat, gilt in der Web-Anwendung als Schulverwaltung und sieht alle Gruppen. Alle anderen Lehrkräfte sehen nur die Gruppen, denen sie zugeordnet sind. Bis es das Ernennen im Pult gibt, vergibt der Server-Admin das Privileg.

Regeln für das Ernennen:

- Niemand vergibt mehr, als er selbst hat.
- Vergeben wird nur über das Pult.
- Die letzte Person der Schulverwaltung kann sich nicht selbst entfernen.
- Jede Vergabe und jeder Entzug wird protokolliert.

## 11. Web-Anwendung

### 11.1 Aufbau

- Backend in Rust, das auch die gebaute Oberfläche ausliefert.
- Oberfläche in Vue mit Pinia und Router, geschrieben in JavaScript ohne TypeScript-Syntax, gebaut mit Vite. Gestaltung mit Tailwind CSS, ohne Komponentenbibliothek.
- **Mehrsprachig von Anfang an:** `vue-i18n` mit Deutsch und Englisch. Kein Text steht direkt in einer Seite, eine Lint-Regel prüft das. Die Sprache folgt dem Browser und lässt sich in der Kopfzeile umschalten. Datum und Zahlen stellt der Browser in der gewählten Sprache dar.
- Das Backend meldet Fehler mit einem festen Code, den die Oberfläche übersetzt. Der englische Satz daneben ist für Protokolle und Entwickler.
- Titel von Modulen, Aufgabentypen und Trophäen kommen aus der Welt und sind vorerst deutsch, auch in der englischen Oberfläche. Sollen sie mitwechseln, muss die Welt jeden Titel in allen ihren Sprachen melden.
- Das Backend liefert die gebaute Oberfläche aus dem Ordner aus, den die Einstellung `LEP_FRONTEND` nennt. Beim Entwickeln läuft die Oberfläche über Vite und reicht `/api` an das Backend weiter.
- SQLite als Datenbank.
- Bibliotheken des Backends: `axum` als Webserver, `sqlx` für SQLite mit Migrationen im Repository, `utoipa` für die OpenAPI-Beschreibung.
- Einstellungen des Backends kommen aus Umgebungsvariablen.
- Zwei getrennte Schnittstellen: eine für den Browser (mit Anmeldung), eine für Welten und Agenten (mit Schlüssel).
- Mailversand per SMTP über das Webhosting-Postfach, Port 587 mit Anmeldung. Hetzner sperrt auf Cloud-Servern die ausgehenden Ports 25 und 465, Port 587 ist frei.
- Die Typen der Schnittstelle liegen einmal in einem gemeinsamen Rust-Paket (`crates/protocol`), das Backend und Agent nutzen.
- OpenAPI-Beschreibung aus den Rust-Typen. Daraus werden die Typen der Oberfläche erzeugt und über JSDoc-Kommentare eingebunden. Eine automatische Prüfung meldet, wenn Oberfläche und Schnittstelle auseinanderlaufen. Die Nachrichten des Mods werden in den Lua-Tests gegen dasselbe Schema geprüft.

### 11.2 Brücke

Luanti-Mods können keine Anfragen annehmen und keine WebSocket-Verbindung aufbauen. Deshalb ruft immer die Welt an:

- **Spiel → Web:** Ereignisse sofort senden. Jedes Ereignis hat eine eindeutige ID, das Backend verwirft Doppelte.
- **Web → Spiel:** Die Brücke holt Aufträge per Long Polling ab.
- HTTPS mit einem eigenen Schlüssel pro Welt.
- Die Schule braucht dafür keinen offenen Port nach außen.
- Fällt die Verbindung aus, läuft das Spiel weiter: lokale Kopie der Einstellungen, Warteschlange für Ereignisse.

Die Brücke braucht einen Eintrag in `secure.http_mods`. Sie ist kein vertrauenswürdiger Mod und bleibt in der Sandbox.

**Welten und Schlüssel**

- Eine Welt hat im Backend eine feste Kennung, einen änderbaren Namen und einen Schlüssel.
- Der Schlüssel ist zufällig und wird nur beim Anlegen angezeigt. Das Backend speichert nur seinen Hashwert.
- Welten lassen sich im Terminal anlegen, auflisten und mit einem neuen Schlüssel versehen (`lep-backend world ...`). Diese Befehle bleiben auch, wenn es die Oberfläche gibt: für die Ersteinrichtung und für den Fall, dass die Oberfläche nicht erreichbar ist.
- In der Welt stehen Adresse und Schlüssel in der `minetest.conf`, nie im Repository.

**Ereignisse**

- Die Welt sendet bis zu 100 Ereignisse pro Anfrage, das älteste zuerst.
- Das Backend antwortet für jedes Ereignis: angenommen, schon bekannt, unbekannte Art oder ungültiger Inhalt. In allen vier Fällen löscht die Welt das Ereignis. Unbekannte und ungültige blockieren so die Warteschlange nicht, die Welt vermerkt sie im Log.
- **Reihenfolge beim Aktualisieren:** erst das Backend, dann die Welten. Ein Backend, das älter ist als die Mods einer Welt, kennt deren neue Ereignisse nicht. Die Welt verwirft sie dann. Für den Stand ist das harmlos, er lässt sich neu anfordern, Protokolleinträge aus dieser Zeit fehlen dem Backend dauerhaft. Die Brücke meldet den Fall einmal deutlich im Log und zeigt die Zahl der verworfenen Ereignisse bei `/lep_bridge`.
- Die Warteschlange liegt im Speicher des Mods und übersteht einen Neustart. Gelöscht wird erst nach der Antwort des Backends.
- Sie hält höchstens 50 000 Ereignisse. Danach fallen die ältesten weg, mit Meldung im Log. Die Protokolldateien der Welt sind davon unabhängig.
- Nach einem Fehlschlag wartet die Brücke 1, 2, 5, 10, 30 und dann je 60 Sekunden.

**Aufträge**

- Die Anfrage nach Aufträgen bleibt bis zu 25 Sekunden offen und kehrt zurück, sobald einer da ist.
- Ein Auftrag wird so lange ausgegeben, bis die Welt sein Ergebnis gemeldet hat. Er kann deshalb mehrfach ankommen. Jeder Auftrag muss so gebaut sein, dass doppeltes Ausführen nicht schadet.
- Andere Mods melden bei der Brücke an, welche Aufträge sie ausführen, und stellen Ereignisse über sie ein. Kein anderer Mod spricht selbst mit dem Netz.

**HTTPS**

- Das Backend selbst spricht HTTP. Auf dem Server steht ein Webserver wie Caddy oder nginx davor, der HTTPS und das Zertifikat übernimmt.

**Schema**

- Die OpenAPI-Beschreibung ist als `api/openapi.json` eingecheckt. Ein Test des Backends schlägt fehl, wenn sie nicht zum Code passt. Die Lua-Tests der Brücke prüfen ihre Nachrichten gegen diese Datei.

### 11.3 Agent (Schritt 7)

Ein kleines Programm in Rust, einmal pro Spielserver. Es legt Welten an, hält sie am Laufen und räumt sie wieder weg. Mit Schülern, Fortschritt und Protokollen hat es nichts zu tun: Das ist Sache der Brücke. Brücke und Agent wissen nichts voneinander.

Gebaut wird der Agent am Anfang von Schritt 7. Dieser Abschnitt legt fest, wie ein Spielserver aufgebaut ist und was der Agent darf, damit bis dahin nichts entsteht, was ihm im Weg steht.

**Grundsätze**

- Der Agent ruft das Backend an, nie umgekehrt: HTTPS und Long Polling wie die Brücke, mit einem eigenen Schlüssel pro Maschine. Der Spielserver braucht dafür keinen offenen Port.
- Er kennt eine feste Liste von Aufträgen und führt keine beliebigen Befehle aus.
- Er läuft unter einem eigenen Benutzer ohne Administratorrechte.
- Zur Laufzeit spricht er nur mit dem Backend. Er lädt nichts aus dem Netz nach.
- Jeder Auftrag hat eine eindeutige Kennung. Ein Auftrag, der zweimal ankommt, wird einmal ausgeführt.
- Fällt das Backend aus, laufen die Welten weiter. Der Agent meldet sich wieder, sobald es erreichbar ist.

**Aufbau eines Spielservers**

Angenommen wird ein Linux mit systemd, in der Regel Debian.

- **Benutzer:** ein Systembenutzer ohne Anmeldung, in den Beispielen `lep`. Ihm gehört alles, was der Agent anfasst. Der Server-Admin legt ihn einmal an:

  ```sh
  sudo useradd --system --shell /usr/bin/nologin --user-group --create-home --home-dir /var/lib/lep lep
  ```

- **Luanti** kommt aus dem Paket des Systems. Der Agent installiert keine Software.
- **Ordner** unter `/var/lib/lep`:

  | Ordner | Inhalt |
  |---|---|
  | `worlds/<Kennung>/` | eine Welt: Karte, Spielerdaten, Einstellungen, Protokolle |
  | `templates/<Version>/` | Spiel und Mods einer Version, vom Agenten ausgepackt |
  | `backups/<Kennung>/` | Sicherungen einer Welt, mit Datum |
  | `archive/<Kennung>/` | Welten, die aus dem Betrieb genommen sind |

  Ordner heißen nach der festen Kennung der Welt, nie nach dem Namen der Gruppe. Der Name kann sich ändern, und er käme sonst aus einer Eingabe im Browser in einen Pfad.
- **Einstellungen des Agenten** in `/etc/lep/agent.toml`: Adresse des Backends, Schlüssel der Maschine, Bereich der Ports. Die Datei ist nur für `lep` lesbar.
- **Ports:** Der Agent vergibt jeder Welt einen Port aus einem festen Bereich und meldet ihn dem Backend. Die Firewall öffnet der Server-Admin einmal für den ganzen Bereich.

**Dienste**

- Jede Welt ist ein Dienst des Systems aus einer Vorlage: `lep-world@<Kennung>.service`, mit `User=lep`. systemd startet eine abgestürzte Welt neu, und die Welten laufen weiter, wenn der Agent selbst neu startet.
- Der Agent ist selbst ein Dienst, `lep-agent.service`, ebenfalls als `lep`.
- Eine Polkit-Regel erlaubt dem Benutzer `lep` genau drei Dinge: Dienste starten, stoppen und neu starten, deren Name mit `lep-world@` beginnt. Mehr darf er an systemd nicht.
- Welche Welten laufen sollen, weiß der Agent. Nach einem Neustart der Maschine startet er sie. So muss er keine Dienste im System ein- oder austragen, wofür er weitergehende Rechte bräuchte.
- Der Server-Admin sieht die Welten mit den gewohnten Befehlen: `systemctl status lep-world@<Kennung>`, `journalctl -u lep-world@<Kennung>`.

Einmalig als root einzurichten sind also: der Benutzer, die Dienstvorlage, die Polkit-Regel, die Einstellungen und der Dienst des Agenten. Danach braucht der Betrieb keine Root-Rechte mehr.

**Vorlage einer Welt**

- Spiel und Mods stecken im Programm des Agenten. Wer den Agenten in einer Version installiert, hat genau die Mods dieser Version. Agent und Vorlage können nicht auseinanderlaufen, und auf dem Spielserver braucht es weder Git noch Zugriff auf fremde Quellen.
- Beim Bau des Agenten werden die fremden Mods in der festen Version aus `third_party/mods.toml` geladen und eingepackt. Das Repository enthält weiter keine Kopien.
- Der Agent enthält damit fremde Mods und liefert ihre Lizenztexte mit. Das stellt der Bau sicher.
- Beim ersten Bedarf packt der Agent seine Vorlage nach `templates/<Version>/` aus. Jede Welt verweist auf eine Version.
- Den Agenten installiert und aktualisiert der Server-Admin von Hand. Er lädt sich nicht selbst nach.

**Aufträge**

| Auftrag | Was geschieht |
|---|---|
| Welt anlegen | Ordner anlegen, Einstellungen schreiben, Port vergeben, Schlüssel der Brücke eintragen |
| Starten, Stoppen, Neustarten | den Dienst der Welt steuern |
| Welt aktualisieren | stoppen, auf die Vorlage des installierten Agenten umstellen, starten. Karte und Spielerdaten bleiben |
| Sichern | Kopie des Weltordners mit Datum nach `backups/` |
| Archivieren | stoppen, sichern, nach `archive/` verschieben |
| Wiederherstellen | eine archivierte Welt zurück in den Betrieb holen |
| Endgültig löschen | Archiv und Sicherungen einer Welt entfernen. Diesen Auftrag schicken nur der Jahresabschluss und das Löschen auf Verlangen (Abschnitt 12) |
| Logdatei leeren | Luantis eigene Logdatei einer Welt leeren, in der Chatnachrichten stehen (Abschnitt 12) |

Ohne Auftrag meldet der Agent regelmäßig den Zustand: welche Welten laufen, auf welchem Port, mit welcher Version, und wie viel Platz auf der Platte frei ist. Die Web-Anwendung zeigt das bei der Gruppe.

Regeln für alle Aufträge:

- Ein Auftrag nennt die Kennung einer Welt und feste Werte, sonst nichts. Die Kennung muss die Form haben, die das Backend vergibt.
- Pfade entstehen nur aus dieser Kennung unter `/var/lib/lep`. Der Agent baut nie eine Befehlszeile aus Werten eines Auftrags und ruft keine Shell auf.
- Ein Auftrag, den der Agent nicht kennt, wird abgelehnt und gemeldet.

**Archivieren und Jahresabschluss**

Es gibt einen einzigen Zeitpunkt, zu dem Welten endgültig verschwinden: den Jahresabschluss.

- Eine Gruppe, die nicht mehr gebraucht wird, wird in der Web-Anwendung archiviert. Ihre Welt ist damit aus dem Betrieb, aber nicht verloren, und lässt sich wiederherstellen.
- „Gruppe löschen“ gibt es nicht, und keine Frist, die von selbst abläuft.
- Der Jahresabschluss schickt „Endgültig löschen“ für jede archivierte Welt und entfernt alle Sicherungen. Laufende Welten werden danach frisch gesichert.
- Archive und Sicherungen enthalten die Protokolle ihrer Welt. Weil sie mit dem Jahresabschluss verschwinden, bleibt auch dort nichts länger als ein Jahr.

**Schlüssel**

- Der Schlüssel der Maschine entsteht im Backend mit einem Befehl, wie heute der Schlüssel einer Welt. Der Server-Admin trägt ihn einmal in die Einstellungen des Agenten ein.
- Der Schlüssel einer Welt entsteht weiter im Backend. Mit dem Agenten reicht das Backend ihn im Auftrag „Welt anlegen“ durch, und kein Mensch sieht ihn mehr.
- Der Schlüssel der Maschine öffnet nur die Schnittstelle des Agenten, nicht die der Welten oder der Lehrkräfte.

**Folgen für die Web-Anwendung**

- Mit dem Agenten legt die Schulverwaltung Gruppen im Browser an (Abschnitt 5). Das Backend wählt eine Maschine, schickt den Auftrag und zeigt, wann die Welt läuft.
- Bis dahin legt der Server-Admin Gruppe und Welt von Hand an.

**Testumgebung**

Der Agent muss sich ohne systemd und ohne Root-Rechte ausprobieren lassen. Dafür bekommt er eine zweite Art, Welten zu führen: als eigene Prozesse in einem Ordner der Testumgebung. Diese Art ist nur für die Entwicklung da. Die Aufträge und ihre Prüfungen sind in beiden Arten dieselben.

**Offen, zu klären beim Bau**

- **Erste Konten einer neuen Welt:** Eine frisch angelegte Welt kennt keine Lehrkraft. Das löst die Verteilung der Konten in Schritt 7.
- **Sichern im Betrieb:** Eine Kopie der Karte, während die Welt läuft, kann unvollständig sein. Zu entscheiden ist, ob die Welt dafür kurz stoppt oder die Datenbank eine Sicherung im Betrieb erlaubt.
- **Wann gesichert wird:** nach Zeitplan des Agenten oder auf Auftrag des Backends, und wie viele Sicherungen bleiben.
- **Mehrere Maschinen:** Nach welcher Regel das Backend die Maschine für eine neue Welt wählt.
- **Andere Systeme als Debian:** Pfade wie `/usr/bin/nologin` und der Name des Luanti-Pakets unterscheiden sich. Die Einrichtung wird für Debian beschrieben.

### 11.4 Anmeldung der Lehrkräfte

Registrierung im Pult, Reiter „Web-Zugang“:

- E-Mail-Adresse eintragen oder ändern.
- Status sehen: nicht eingerichtet, Bestätigung ausstehend, bestätigt.
- Bestätigungsmail erneut senden, höchstens einmal pro Minute.
- Web-Zugang entfernen.

Den Reiter sieht, wer das Privileg `lep_web_access` hat. Ist die Welt nicht mit dem Backend verbunden, sagt der Reiter das und bietet nichts an.

Ablauf:

1. Die Lehrkraft trägt ihre dienstliche Adresse ein.
2. Die Welt meldet sie ans Backend.
3. Das Backend schickt eine Bestätigungsmail, auf Deutsch und Englisch in einer Mail.
4. Der Link öffnet eine Seite der Oberfläche. Erst ein Klick auf den Knopf dort bestätigt die Adresse. So verbraucht ein Mailprogramm, das Links vorab prüft, den Link nicht.
5. Das Backend meldet den neuen Status per Auftrag an die Welt, das Pult zeigt ihn an.

Anmeldung im Browser: Adresse eingeben, Link per Mail, Klick. Eine Registrierungsseite gibt es nicht.

- Ein Link gilt 15 Minuten und nur einmal. Das Backend speichert nur seinen Hash.
- Auch dieser Link öffnet eine Seite, auf der erst ein Klick anmeldet.
- Einen Link bekommt nur, wer eine bestätigte Adresse hat und in mindestens einer Welt das Privileg `lep_web_access`. Pro Konto geht höchstens eine Mail pro Minute raus, ein neuer Link macht den alten ungültig.
- Danach hält eine Sitzung die Anmeldung, 12 Stunden ab dem Klick. Sie verlängert sich nicht: Auf einem Schulrechner, den mehrere nutzen, endet sie spätestens am nächsten Tag von selbst. „Abmelden“ beendet sie sofort.
- Die Sitzung ist ein Cookie mit zufälligem Wert, das Skripte der Seite nicht lesen können und das der Browser nur an die Web-Anwendung selbst sendet. Das Backend speichert nur den Hash.
- Jede Anfrage prüft, ob das Privileg noch in einer Welt gilt. „Web-Zugang entfernen“ im Pult beendet alle Sitzungen des Kontos.
- Das Formular antwortet immer gleich, egal ob die Adresse bekannt ist.
- Ohne Anmeldung zeigt die Oberfläche nur die Seiten zum Anmelden und zum Bestätigen einer Adresse.
- Beim Ändern gilt die alte Adresse, bis die neue bestätigt ist.
- Eine Adresse gehört zu höchstens einem Konto.
- Einen Einmal-Code als Ersatz für die Mail gibt es nicht. Wer die Adresse ohne Mail bestätigen könnte, bekäme danach die Anmeldelinks trotzdem nicht, und eine vertippte Adresse ließe sich so bestätigen.

Wer Lehrkraft ist, sagt die Welt:

- Eine Lehrkraft ist im Backend ein Kontoname, über alle Welten hinweg.
- Jede Welt meldet die Liste der Konten, die bei ihr `lep_web_access` haben, beim Start und bei jeder Änderung. Das Backend nimmt Meldungen zum Web-Zugang nur für Konten dieser Liste an.
- Hat ein Konto das Privileg in keiner Welt mehr, sperrt das Backend den Zugang sofort. Die Adresse bleibt gespeichert, bis die Lehrkraft den Zugang entfernt oder das Konto gelöscht wird. Bekommt sie das Privileg zurück, gilt der Zugang wieder.

Wo die Adresse liegt:

- Die Welt speichert die Adresse nicht. Sie steht nur in der Warteschlange der Brücke, bis das Backend sie hat.
- Im Pult steht eine gekürzte Form, etwa `m…@schule.example`.
- Das Protokoll des Pults hält fest, dass eine Lehrkraft ihren Web-Zugang geändert hat, nicht die Adresse.

Mails verschickt das Backend über einen Mailserver per SMTP, im Hintergrund: Wer einen Link anfordert, bekommt die Antwort sofort, egal ob eine Mail rausgeht. Ohne eingestellten Mailserver schreibt es jede Mail in sein Terminal, das ist der Weg der Testumgebung. Die Adresse in den Links kommt aus der Einstellung `LEP_PUBLIC_URL`.

Ohne Anmeldung sagt das Backend über sich nur, ob es arbeiten kann. Version und Einzelheiten sieht, wer angemeldet ist.

### 11.5 Funktionen

- Konten für Schüler anlegen, Namen neu würfeln, Zugangszettel drucken. Die Namen der Kinder bleiben dabei im Browser (Abschnitt 6.1).
- Wunschnamen sehen, entfernen und das Ändern sperren. Neue Namen sind markiert. Die Liste der Schüler lässt sich nach Wunschname und Kontoname durchsuchen.
- Passwörter zurücksetzen.
- Schüler in eine andere Gruppe verschieben.
- Niveau pro Schüler und Modul setzen, Startniveau pro Gruppe festlegen, automatischen Aufstieg sperren.
- Fortschritt pro Gruppe, Schüler und Modul in Prozent des Pensums, Export als CSV.
- Fragensets hochladen und zuweisen.
- Belohnungstabellen pro Gruppe.
- Belohnungs- und Chatprotokoll einsehen.
- Jahresabschluss.

### 11.6 Zuständigkeiten

**Grundsatz: Die Welt schreibt, das Backend spiegelt.**

- Lernfortschritt, Trophäen und Protokolle entstehen nur in der Welt. Sie meldet jeden neuen Stand als Ereignis, das Backend bewahrt ihn auf.
- Das Backend ändert diese Daten nie selbst. Setzt eine Lehrkraft im Browser ein Niveau, geht ein Auftrag an die Welt. Die Welt setzt es und meldet den neuen Stand zurück.
- So schreibt immer nur eine Stelle, und es gibt keine widersprüchlichen Stände. Fällt die Verbindung aus, rechnet die Welt weiter, und die Warteschlange liefert nach.

| Backend bewahrt auf | Welt führt |
|---|---|
| Konten und ihre Zuordnung zu Welten | Ort, eingefroren, Inventar |
| Gruppen, Zuordnung Lehrkraft zu Gruppe | Belohnungskiste, Truhenzustand |
| Fragensets, Zuweisungen, Belohnungstabellen | laufende Aufgaben |
| Spiegel von Lernniveau, Pensum und Trophäen, als Quelle für Oberfläche und Gruppenwechsel | Lernniveau, Pensum, Trophäen |
| Spiegel der Protokolle des laufenden Jahres | Protokolldateien, lokale Kopie der Einstellungen, Warteschlange für Ereignisse |

**Was die Welt meldet**

- **Module:** die Lernmodule der Welt mit Titel, Niveaus und Aufgabentypen, bei jedem Start.
- **Fortschritt:** pro Schüler und Modul Niveau, Sperre, Pensum in Prozent und Stand je Aufgabentyp. Gemeldet wird nach jeder Änderung der ganze Stand, nie eine Änderung. Ein älterer Stand, der verspätet ankommt, überschreibt keinen neueren.
- **Trophäen:** pro Schüler die ganze Liste.
- **Protokolle:** jeder Eintrag von Belohnungen, Chat, Schildtexten und Pult, mit Zeitpunkt und Kontoname.
- **Erster Abgleich:** Beim ersten Kontakt sendet die Welt den Stand aller bekannten Schüler. Das Backend kann ihn per Auftrag erneut anfordern.
- **Keine Nachlieferung alter Protokolle:** Gemeldet wird, was ab der Verbindung geschieht. Was vorher in den Protokolldateien stand, bleibt dort. Im Betrieb ist eine Welt von Anfang an verbunden, und alte Einträge nachträglich in die Cloud zu schieben, passt nicht zur begrenzten Aufbewahrung.
- Texte für Menschen, etwa Titel, verlassen die Welt auf Deutsch.

**Was die Lehrkraft im Browser ändert**

- Die Seite „Fortschritt“ einer Gruppe zeigt je Schüler und Modul Niveau, Pensum, Sperre und Trophäen. Gezeigt werden die Konten, die in der Welt angelegt sind. Wer noch nichts gelöst hat, steht am Anfang von Niveau 1.
- Niveau setzen und Aufstieg sperren oder freigeben sind Aufträge an die Welt. Das Backend ändert seinen Stand nie selbst: Die Welt führt aus und meldet den neuen Stand wie nach jeder Änderung.
- Bis die Welt geantwortet hat, zeigt die Seite den alten Stand mit dem Hinweis „Änderung wartet auf die Welt“. Lehnt die Welt ab, steht das dort, bis eine Änderung gelingt.
- Die Welt hält jede dieser Änderungen im Protokoll des Pults fest, unter dem Konto der Lehrkraft. Der Auftrag nennt es dafür.
- Ob eine Lehrkraft die Änderung bestellen darf, entscheidet das Backend über die Zuordnung zur Gruppe. Die Welt prüft, ob es Konto, Modul und Niveau gibt.
- Trophäen und Meilensteine sind verdient und werden nur angezeigt.

## 12. Datenschutz

**Grundsätze**

- Zufällige Kontonamen statt Klarnamen. Die Zuordnung zu Personen bleibt bei der Lehrkraft.
- Dauerhaft wird nur der Stand gespeichert, nicht der Verlauf. Der Verlauf steht nur in den Protokollen, und die werden mit dem Jahresabschluss gelöscht.
- Protokolle speichern nur den Kontonamen. Der Wunschname wird erst beim Anzeigen dazugeholt.
- E-Mail-Adressen gibt es nur von Lehrkräften.
- Schüler haben keinen Zugang zur Web-Anwendung.

**Datenfluss**

Fortschritt, Belohnungsprotokoll und Chatprotokoll gehen vom Spielserver der Schule zum Cloud-Server. Der Transport läuft über HTTPS mit eigenem Schlüssel pro Welt.

**Protokolle**

Es gibt mehrere Protokolle: Chat, Schildtexte, Belohnungen, Aktionen am Pult und Wunschnamen. Alle werden gleich verwaltet.

- Jedes Protokoll ist eine Datei im Ordner der Welt, an die nur angehängt wird. Eine Zeile ist ein Eintrag mit Zeitpunkt und Kontoname.
- Die gemeinsame Technik liegt in `lep_core`. Kein Mod baut ein eigenes Protokoll.
- Alle Protokolle bleiben bis zum Jahresabschluss, also höchstens ein Jahr. Der Jahresabschluss löscht sie vollständig. Eine kürzere eigene Frist gibt es nicht.
- Einsicht haben nur Lehrkräfte der Gruppe. Schüler sehen ihr eigenes Belohnungsprotokoll.
- Die Schüler werden darauf hingewiesen, dass der Chat mitgeschrieben wird.
- Ein Jahr ist lang und muss gegenüber Schule und Eltern begründet werden, etwa mit der Aufklärung von Mobbing-Vorfällen und von Streit um Belohnungen.
- Das Belohnungsprotokoll zeigt, wann ein Schüler welche Aufgabe gelöst hat. Es ist damit eine Lernhistorie des laufenden Jahres. Auch das gehört in die Information an Schule und Eltern.

**Zähler des Awards-Mods**

- Der Awards-Mod zählt pro Spieler, wie oft er welche Blockart abgebaut, gesetzt oder hergestellt hat. Das ist ein Stand ohne Zeitpunkte, aber es sind Daten über das Spielverhalten.
- Sie liegen in der Welt und werden beim Jahresabschluss gelöscht.

**Wunschnamen**

Viele Kinder wählen ihren Vornamen. Die Welt kann nicht erkennen, ob ein Name echt ist, und niemand gibt Namen vorab frei. Lehrkräfte sollen deshalb Nachnamen und volle Namen entfernen, sobald sie sie sehen. Bis dahin ist ein solcher Name im Spiel sichtbar. Der Wunschname gehört zu den Kontodaten und wird mit dem Konto gelöscht. Das Protokoll der Wunschnamen enthält auch entfernte Namen und wird wie alle Protokolle beim Jahresabschluss gelöscht.

**Jahresabschluss**

Der Jahresabschluss ist ein einziger Schalter für die ganze Schule. Er ist der einzige Zeitpunkt, zu dem Daten in großem Umfang gelöscht werden. Es gibt daneben keine Fristen, die von selbst ablaufen, und keinen Abschluss für einzelne Gruppen: Eine Regel ohne Ausnahmen lässt sich erklären, und niemand muss sich merken, welche Gruppe schon abgeschlossen ist.

- Löscht alle Jahresdaten aller Gruppen.
- Löscht alle archivierten Welten und alle Sicherungen (Abschnitt 11.3).
- Zeigt vorher an, was gelöscht wird, auch die archivierten Gruppen, und bietet einen Export an. Eine versehentlich archivierte Gruppe lässt sich an dieser Stelle noch wiederherstellen.
- Das Backend schickt den Welten den Auftrag, ihre lokalen Kopien zu löschen.
- Die Löschung wird ohne Inhalte vermerkt: wer, wann, welcher Umfang.

**Löschen auf Verlangen**

Verlangen Eltern oder ein Schüler die Löschung, wartet die Schule nicht auf den Jahresabschluss.

- Die Schulverwaltung löscht ein einzelnes Konto sofort: Kontodaten, Stand und die Einträge des Kontos in den Protokollen, im Backend und in der Welt.
- Die Löschung wird ohne Inhalte vermerkt: wer, wann, welches Konto.
- Aus einer Sicherung lässt sich ein einzelnes Konto nicht entfernen. Deshalb werden alle Sicherungen der betroffenen Welt sofort gelöscht. Die Welt wird danach frisch gesichert.
- Dasselbe gilt für eine archivierte Welt, in der das Konto liegt: Sie wird endgültig gelöscht.
- Die Web-Anwendung zeigt vorher an, welche Sicherungen und welche archivierten Welten dabei verschwinden.
- Das ist die Ausnahme. Der gewöhnliche Weg bleibt der Jahresabschluss.

**Außerhalb des Backends**

- Luanti schreibt Chatnachrichten in seine eigene Logdatei auf dem Spielserver. Sie muss regelmäßig geleert werden, anfangs vom Admin, später vom Agenten.
- Schilder und Bücher der Schüler liegen in der Karte und verschwinden erst mit der Welt.

**Organisatorisch**

- Vertrag zur Auftragsverarbeitung für Cloud-Server und Webhosting.
- Den Datenschutzbeauftragten der Schule früh einbinden.
- Ob Schüler den Spielserver nur im Schulnetz oder auch von zu Hause erreichen, entscheidet die Schule.

## 13. Technische Leitlinien

Aus dem Luanti Modding Book:

- **Zwei Schichten pro Mod:** ein Kern in reinem Lua ohne Engine-Aufrufe und eine dünne Schicht zum Spiel.
- **Beobachter-Muster** zwischen Mods.
- **Eingaben aus Fenstern nie trauen.** Rechte beim Absenden prüfen, Zustand pro Spieler auf dem Server halten.
- **Sensible Block-Metadaten als privat markieren.**
- **HUD statt Fenster**, wenn keine Eingabe nötig ist.
- **Keine Spielerobjekte speichern**, nur Namen.
- **Speicher-Backend vom Rest trennen.**

Weil Formspecs selbst geschrieben werden, bekommt das Projekt eine kleine gemeinsame Hilfsschicht: Zustand pro Spieler, erneute Rechteprüfung beim Absenden, Maskieren von Texten. Jedes Fenster nutzt sie.

Tests: Busted für die Lua-Kerne, Luacheck als statische Prüfung. Luacheck stellt auch sicher, dass die Kerne in `src/` keine Engine-Aufrufe enthalten. Später mtt für Tests im laufenden Server.

Fremd-Mods werden nicht ins Repository kopiert. `third_party/mods.toml` nennt Quelle und feste Version jedes fremden Mods, ein Skript lädt sie. Aktualisierungen sind damit eine sichtbare Änderung in einer Datei.

## 14. Mods

### 14.1 Fremde Mods

| Bedarf | Mod | Lizenz |
|---|---|---|
| Grundstücksschutz, abschließbare Türen und Kisten | Protector (TenPlus1) | MIT für Code, CC BY 3.0 für Medien |
| Monster und Tiere (später) | Mobs Redo, Mobs Monster, Mobs Animal | MIT |
| Logikschaltungen (später) | Mesecons, ohne `mesecons_luacontroller` | LGPL 3 für Code, Creative Commons für Medien |
| Erfolge im Survival-Teil | Awards (rubenwardy) | MIT |
| Lesbare Schrift auf Schildern | signs_lib (mt-mods) | LGPL 3 für Code, CC BY-SA 4.0 für Medien |

Bewusst nicht verwendet: Classroom Manager (eigenes Pult), Account Manager (Konten kommen aus dem Backend), flow (Formspecs werden selbst geschrieben).

### 14.2 Eigene Mods

Alle eigenen Mods liegen als Modpack unter `mods/`. Die Namen sind auf ContentDB frei (geprüft am 15. November 2026). Jeder Mod hat einen Kern in reinem Lua (`src/`) und eine Schicht zum Spiel (`game/`). Einen eigenen Kern-Mod pro Lernmodul gibt es deshalb nicht.

| Mod | Aufgabe |
|---|---|
| `lep_core` | Gemeinsame Hilfen: Anzeigename, Formspec-Hilfsschicht, Einstellungen |
| `lep_places` | Ortsverwaltung: Ortswechsel, Inventare, Rechte |
| `lep_lobby` | Gemeinsamer Bereich, persönliche Räume, Schutzzone |
| `lep_portals` | Festes und persönliches Portalpaar, Lernhalle mit den Portalen der Module |
| `lep_rooms` | Lernräume bauen, zuteilen, schützen und neu bauen |
| `lep_survival` | Regeln der Survival-Welt: Rezepte, die fremde Mods ersetzen |
| `lep_progress` | Ergebnisse annehmen, Niveau und Pensum führen, Ereignisse verteilen, kurze Aufgaben vermitteln |
| `lep_rewards` | Regeln, Tageslimit, Auszahlung in Kiste oder Inventar, Protokoll |
| `lep_trophies` | Meilensteine, Ausstellung im Raum |
| `lep_math` | Rechnen: Aufgabengenerator, Rechenraum mit Anzeige und Tastenfeld |
| `lep_quest_chest` | Aufgabentruhe in der Wildnis: erzeugen, Fenster, Ablauf |
| `lep_desk` | Lehrerpult: Zielauswahl, Aktionen, Web-Zugang, Ernennen |
| `lep_attention` | Aufmerksamkeitsmodus: Zelle, schwarzes Vollbild mit Text, Chat-Sperre |
| `lep_chat` | Protokoll für Chat und Schildtexte, Stummschalten, Verteilung der Nachrichten |
| `lep_accounts` | Geschlossene Welt: wer hinein darf. Konten anlegen und Passwörter setzen auf Auftrag |
| `lep_bridge` | Verbindung zum Backend: Warteschlange für Ereignisse, Aufträge per Long Polling |
| `lep_quiz` | Textfragen: Fragensets, Dialogfenster |
| `lep_tz` | Technisches Zeichnen: Datenmodell, Generator, Prüfung, Baustein, Raum |
| `lep_logic` | Logikrätsel: Mesecons-Räume, Prüflauf |

### 14.3 Projektstruktur

Die Verzeichnisstruktur des Repositorys steht in der `README.md`.

## 15. Reihenfolge der Umsetzung

1. **Projektgerüst:** Mod-Namen prüfen, Testumgebung, Kern-Mod.
2. **Ortsverwaltung, Lobby, Portale, Lernraum.**
3. **Fortschritt, Belohnung, Trophäen.**
4. **Rechnen und Aufgabentruhe.** Prüft, ob die Schnittstellen tragen.
5. **Lehrerpult, Aufmerksamkeitsmodus, Chat.**
6. **Backend und Brücke:** Konten, Gruppen, E-Mail-Anmeldung, Wunschnamen, Fortschritt, Protokolle, Jahresabschluss.
7. **Agent und mehrere Welten:** zuerst der Agent, der Welten anlegt, startet und stoppt, dann Verteilung der Konten und Gruppenwechsel. Weitere Welten entstehen so von Anfang an über ihn. Dazu gehört, dass die Schulverwaltung Lehrerkonten anlegt: Bis dahin gibt es in einer geschlossenen Welt keinen Weg zu einem neuen Lehrerkonto außer über den Admin.
8. **Textfragen** mit GIFT-Import.
9. **TZ-Modul.**
10. **Logikrätsel.**

Später: Monster.

Bis Schritt 5 läuft alles in einer einzigen Welt ohne Web-Anwendung, mit lokal angelegten Konten. Die Schnittstellen werden von Anfang an so gebaut, dass Schritt 6 und 7 nur andocken.

## 16. Offene Punkte

Bei der Umsetzung des jeweiligen Teils:

1. **Pensum:** Aufgabentypen pro Niveau für jedes Modul, und wie oft ein Typ richtig gelöst sein muss (Vorschlag: fünfmal).
2. **Kontonamen:** Luantis genaue Längengrenze prüfen.
3. **Mesecons:** Stand der letzten Version prüfen.
4. **GIFT-Export:** Mit einem ByCS-Zugang ausprobieren, ob Lehrkräfte Fragen exportieren können.
5. **TZ:** Die Stationen auf die Niveaus verteilen.

6. **Raumlicht:** Luanti 5.18 kann die Helligkeit pro Spieler einstellen (`set_lighting`, Feld `static.light_curve`). Das könnte die leuchtende Luft in den Lernräumen ersetzen. Zwei kurze Versuche blieben ohne klares Ergebnis. Erneut prüfen, sobald auch die Testumgebung des Nutzers 5.18 hat.

7. **Tasten hervorheben:** Im Rechenraum könnte die Taste unter dem Fadenkreuz heller werden. Luanti meldet dem Server nicht, worauf ein Spieler zeigt. Der Server müsste die Blickrichtung etwa zehnmal pro Sekunde prüfen und die Taste austauschen. Zurückgestellt, weil der Client den anvisierten Block schon umrandet und der Aufwand den Nutzen vorerst nicht lohnt.

8. **Aufgabentruhen finden:** Eine neue Truhe wird im Chat angekündigt und leuchtet schwach. Ob das reicht oder ob ein Wegweiser im HUD nötig ist, zeigt der Betrieb.

Vor einem Einsatz an einer Schule:

9. **Datenschutz** mit der Schule klären, einschließlich der Aufbewahrung des Chatprotokolls.

## 17. Quellen

- [LehrplanPLUS Mittelschule, Technik 7](https://www.lehrplanplus.bayern.de/fachlehrplan/mittelschule/7/t/regelklasse)
- [ISB: Technische räumliche Freihandskizzen II (Realschule, Werken 8)](https://www.lehrplanplus.bayern.de/sixcms/media.php/71/RSWerken8_Erg%C3%A4nzende%20Informationen_TZ_Technische%20r%C3%A4umliche%20Freihandskizzen%20II.pdf)
- [ISB: Die fertigungsgerechte Werkzeichnung II (Realschule, Werken 9)](https://www.lehrplanplus.bayern.de/sixcms/media.php/71/RSWerken9_Erg%C3%A4nzende%20Informationen_TZ_Die%20fertigungsgerechte%20Werkzeichnung%20II.pdf)
- [Luanti Modding Book: Architektur](https://rubenwardy.com/minetest_modding_book/en/quality/clean_arch.html)
- [Luanti Modding Book: Unit-Tests](https://rubenwardy.com/minetest_modding_book/en/quality/unit_testing.html)
- [Luanti Modding Book: Sicherheit](https://rubenwardy.com/minetest_modding_book/en/quality/security.html)
- [Luanti Modding Book: Speicherung](https://rubenwardy.com/minetest_modding_book/en/map/storage.html)
- [Luanti Modding Book: Privilegien](https://rubenwardy.com/minetest_modding_book/en/players/privileges.html)
- [Luanti Modding Book: Spielerphysik](https://rubenwardy.com/minetest_modding_book/en/players/player_physics.html)
- [Luanti-Dokumentation: HTTP-API](https://docs.luanti.org/for-creators/api/http-api/)
- [Luanti-Dokumentation: Datenbank-Backends](https://docs.luanti.org/server/database-backends)
- [Luanti-Dokumentation: Right to a Name](https://docs.luanti.org/for-creators/right-to-a-name/)
- [ContentDB: Protector](https://content.luanti.org/packages/tenplus1/protector/)
- [ContentDB: Mobs Redo API](https://content.luanti.org/packages/TenPlus1/mobs/)
- [ContentDB: Mesecons](https://content.luanti.org/packages/Jeija/mesecons/)
- [mtt, Test-Framework](https://content.luanti.org/packages/BuckarooBanzay/mtt/)
- [Moodle: GIFT-Format](https://docs.moodle.org/de/GIFT)
