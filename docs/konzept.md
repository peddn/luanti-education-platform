# Luanti Education Platform (LEP): Konzept

Fassung 20 · 15. November 2026 · Status: Konzept, noch kein Code

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
| Welten anlegen | Zunächst von Hand durch den Server-Admin, später durch einen Agenten |

### Gruppen und Konten

| Thema | Entscheidung |
|---|---|
| Gruppe | Klasse, Kurs oder freie Gruppe, technisch dasselbe. Meist eine Klasse |
| Zugehörigkeit | Ein Schüler gehört zu genau einer Gruppe |
| Gruppen anlegen | Nur die Schulverwaltung |
| Quelle für Konten | Das Backend. Welten legen Konten auf Auftrag an |
| Kontoname | Zufällige Kombination aus Adjektiv und Nomen, z. B. `lustiger_loewe` |
| Wunschname | Vom Schüler beantragt, von der Lehrkraft freigegeben, nur Anzeige |
| Lebensdauer | Das Konto wächst mit dem Schüler mit |
| Bleibt erhalten | Lernniveau, Meilensteine, Trophäen, Wunschname |
| Jährlich gelöscht | Chatprotokolle, Belohnungsprotokoll, einzelne Aufgabenversuche, Pult-Protokolle |
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
| Auszahlung | In die Belohnungskiste im eigenen Lobby-Raum |
| Niveau | Beliebig viele Niveaus pro Modul, von der Lehrkraft pro Schüler gesetzt |
| Aufstieg | Automatisch beim Abschluss eines Niveaus, von der Lehrkraft sperrbar |
| Belohnt wird | Nur für Aufgaben auf dem eigenen Niveau und darüber |
| Größen | Klein (Aufgabe), mittel (Aufgabentruhe), groß (Niveau abgeschlossen) |
| Begrenzung | Tageslimit als Anzahl: 10 belohnte Aufgaben und 5 Truhen |
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

**Gruppenwechsel eines Schülers:** Das Konto wandert in die neue Welt. Lernniveau und Trophäen gehen mit, der übrige Besitz bleibt in der alten Welt. Die Web-Anwendung weist beim Verschieben darauf hin.

**Schuljahreswechsel:** Pro Gruppe weiterführen (bei Bedarf umbenennen), archivieren oder löschen. Dazu kommt der Jahresabschluss (Abschnitt 12).

## 6. Konten und Namen

### 6.1 Kontoname

Das Backend würfelt aus zwei gepflegten Wortlisten eine Kombination aus Adjektiv und Nomen und prüft, ob sie an der Schule frei ist.

- Nur Buchstaben, Ziffern, Bindestrich und Unterstrich, keine Umlaute.
- Höchstens 19 Zeichen. Luantis genaue Grenze liegt vermutlich bei 20 und wird bei der Umsetzung geprüft.
- Jedes Nomen trägt sein Geschlecht, damit die Endung des Adjektivs stimmt.
- Nur freundliche Wörter, bei denen keine Kombination spöttisch klingt.
- Die Lehrkraft kann einzelne Namen vor dem Ausdrucken der Zugangszettel neu würfeln.

Der Kontoname bleibt für immer der Anmeldename. Konto, Besitz und Grundstücke hängen an ihm.

### 6.2 Wunschname

1. Der Schüler beantragt im Spiel einen Wunschnamen, am Türschild seines Lobby-Raums.
2. Der Antrag geht über die Brücke ans Backend.
3. Die Lehrkraft der Gruppe gibt ihn in der Web-Anwendung frei oder lehnt ab.
4. Nach der Freigabe zeigt das Spiel den Wunschnamen an.

Regeln:

- Der Wunschname ist nur eine Anzeige.
- Eindeutig pro Welt. Er darf keinem Kontonamen, keinem anderen Wunschnamen und keinem Namen einer Lehrkraft gleichen.
- Umlaute erlaubt, Länge begrenzt.
- Die Lehrkraft kann jederzeit widerrufen.
- Ein neuer Antrag ist einmal im Monat möglich.
- Genau eine Funktion „Anzeigename dieses Spielers“ bedient alle Stellen: Name über der Figur, Chat, Türschild, Pult.
- Lehrkräfte sehen immer beides.

### 6.3 Zwei Arten von Daten

| | Bleibt mit dem Konto | Wird jährlich gelöscht |
|---|---|---|
| Was | Lernniveau pro Modul, Meilensteine, Trophäen, Wunschname | Chatprotokolle, Belohnungsprotokoll, einzelne Aufgabenversuche, Pult-Protokolle |
| Löschen | beim Schulaustritt | per Jahresabschluss und automatischer Frist |

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
- **Bau.** Ein Raum entsteht spätestens beim ersten Betreten. Für eine ganze Klasse lassen sich Räume vorab bauen. Die Brücke nutzt das später beim Anlegen von Konten.
- **Neubau.** Ein Raum lässt sich von Grund auf neu bauen: neue Hülle, leerer Innenraum, neu eingerichtet. Was darin gebaut war, geht verloren. Das Lernmodul erfährt es über ein Ereignis. Jeder Raumtyp hat eine Versionsnummer. Erhöht ein Modul sie, werden alte Räume beim nächsten Betreten von selbst neu gebaut.
- **Verlassen.** Führt vorerst in die Wildnis. Mit der Lobby führt es dorthin zurück, woher der Schüler kam.

### 7.3 Erscheinen

- **Erste Anmeldung:** Lobby.
- **Weitere Anmeldungen:** Ort des Ausloggens, auch im Lernraum. Wer eingefroren ausloggt, bleibt eingefroren.
- **Tod:** Lobby, außer man hat ein Bett. Der Besitz bleibt wie in Minetest Game am Todesort.

### 7.4 Portale

**Aussehen und Benutzung**

- Ein Portal steht senkrecht. Der Rahmen ist außen 3 breit und 4 hoch, innen ist eine Fläche von 1 × 2 frei. Die vier Ecken des Rahmens dürfen fehlen.
- Die Fläche ist violett und leuchtet. Wer etwa eine Sekunde darin steht, wird versetzt und kommt einen Schritt vor dem Zielportal an.
- Jeder Ortswechsel durch ein Portal läuft über die Ortsverwaltung.

**Festes Paar**

- Ein Portal steht in der Mitte der Halle, eines in der Wildnis am Startpunkt der Welt auf einer kleinen Plattform.
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

Portale werden selbst gebaut. Vorhandene Portal-Mods bilden frei verknüpfbare Reisenetze oder verknüpfen Orte statt Spieler und passen nicht zu diesen Regeln. Geprüft wurde auch die Portal-Schnittstelle des Nether-Mods.

### 7.5 Lobby

**Halle.** Der gemeinsame Bereich ist eine Halle hoch über der Welt, unterhalb der Lernräume.

- **Form:** ein Zylinder mit einer Kuppel darüber. Innenradius 15 Blöcke, 4 Blöcke senkrechte Wand, in der Mitte 19 Blöcke hoch.
- **Material:** Wand und Kuppel aus Glas. Der Boden ist fast schwarz (Obsidian), mit einer kreisrunden Glasscheibe von 11 Blöcken Durchmesser in der Mitte. Durch sie sieht man den Himmel, nicht die Landschaft.
- **Licht:** zwei Leuchtringe im Boden, einer lückenlos unter der Glaswand und einer um die Glasscheibe, dazu das leuchtende Portal in der Mitte. Nachts ist es dadurch nirgends dunkel.
- **Tiere:** Unter der Kuppel schweben Glühwürmchen, weiter unten Schmetterlinge. Sie sind Schmuck an festen Plätzen und lassen sich nicht fangen.
- **Musik:** In der Halle läuft leise eine eigene Hintergrundmusik in Schleife. Sie beginnt beim Betreten und blendet beim Verlassen aus. Einen Schalter dafür gibt es nicht, wer keine Musik möchte, stellt sie am eigenen Client ab.
- **Inhalt:** das feste Portal zur Wildnis in der Mitte auf der Glasscheibe, dazu Portale zu freiwilligen Aufgaben und die Anzeigetafel.
- **Gänge:** Vier Gänge verlassen die Halle, einer in jede Himmelsrichtung. Sie führen zu den persönlichen Räumen.
- **Schutz:** Niemand kann in der Lobby bauen oder abbauen, niemand nimmt Schaden. Alle Blöcke sind unzerstörbar.

Die Halle wird aus Code erzeugt. Eine von Hand gebaute Halle kann sie später ersetzen. Der Rest des Mods fragt die Halle nur nach vier Dingen: dem Startpunkt für ankommende Spieler, dem Platz für das Portal, Anfang und Richtung der vier Gänge und dem geschützten Bereich. Das Einbinden eines Bauplans wird erst gebaut, wenn es eine solche Halle gibt.

**Persönliche Räume** an den vier Gängen, einer pro Schüler:

- Die Räume liegen auf beiden Seiten jedes Gangs. Neue Räume werden reihum auf die vier Gänge verteilt, damit kein Gang viel länger wird als die anderen. Bei 30 Schülern ist kein Raum weiter als 30 Blöcke von der Halle entfernt.
- Ein Raum ist innen 5 × 4 × 5 Blöcke groß. Wände und Decke sind aus Silbersandstein, von außen sieht man nicht hinein. Licht geben je eine Lampe in Boden und Decke.
- **Tür:** Jeder Raum hat eine Tür, die dem Besitzer gehorcht. Er öffnet und schließt sie mit einem Klick. Offen heißt Besuch willkommen, geschlossen heißt gesperrt. Andere können eine geschlossene Tür von außen nicht öffnen und eine offene nicht schließen. Wer im Raum steht, kann eine geschlossene Tür immer von innen öffnen, damit niemand eingesperrt wird. Schließen kann sie nur der Besitzer. Lehrkräfte kommen immer hinein. Die Tür ist zu Beginn offen und lässt sich nicht abbauen.
- Gänge und Räume gehören zum Ort Lobby. Schutz und Musik gelten dort wie in der Halle.

- Persönliches Portal.
- Belohnungskiste: Nur der Besitzer öffnet sie, und er kann nur entnehmen.
- Feste Plätze für Trophäen (Sockel, Wandhalter).
- Türschild über dem Eingang mit dem Anzeigenamen in lesbarer Schrift, dort wird auch der Wunschname beantragt. Kontonamen stehen in zwei Zeilen, getrennt am Unterstrich. Umlaute brauchen eine zweite Schrift von signs_lib, sie wird mit den Wunschnamen eingeschaltet.
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
- Aufmerksamkeitsmodus beibehalten,
- den vorigen Ort merken.

Bei jeder Anmeldung werden Rechte und Zustand passend zum aktuellen Ort neu gesetzt. So bleibt nach einem Absturz kein Flugrecht in der Wildnis hängen.

**Ortstypen.** Andere Mods melden Ortstypen bei `lep_places` an, mit dem dort geltenden Inventar und den dort geltenden Rechten. Die Wildnis ist von Anfang an angemeldet.

**Inventar.** Gespeichert wird nur das Survival-Inventar: Hauptinventar und Handwerksfeld. Beim Betreten eines Lernraums wird es gesichert und geleert, der Lernraum gibt dem Spieler seine Gegenstände neu. Beim Verlassen werden die Lern-Gegenstände verworfen und das Survival-Inventar zurückgegeben. Lebenspunkte bleiben unverändert.

**Zurück.** `lep_places` merkt sich pro Spieler, ob er zuletzt in der Lobby oder in der Wildnis war. Wer einen Lernraum verlässt, kommt dorthin zurück. Lernräume selbst zählen dabei nicht.

**Rechte.** `lep_places` vergibt die Rechte eines Ortes selbst und merkt sich pro Spieler, welche es vergeben hat. Entzogen werden nur diese. Wer ein Recht ohnehin hat, etwa eine Lehrkraft das Flugrecht, behält es.

Lern-Gegenstände lassen sich außerhalb der Lernräume nicht verwenden.

## 8. Lernen

### 8.1 Fortschritt

Die Lernmodule melden nur, was passiert ist: wer, Modul und Thema, Niveau, gelöst ja/nein, Versuche, benutzte Hilfen, Dauer. Sie entscheiden nichts.

Der Fortschritts-Mod verteilt diese Ereignisse nach dem Beobachter-Muster. Belohnung, Trophäen, Brücke und die Übersicht im Pult melden sich dort an. Ein Lernmodul weiß nichts von Diamanten.

Ein Modul fragt umgekehrt nur ab: „Auf welchem Niveau steht dieser Schüler bei mir?“ und „Welche Aufgabensets sind ihm zugewiesen?“

Module, die kurze Aufgaben im Dialogfenster stellen können (Rechnen, Textfragen), melden diese Fähigkeit an. Die Aufgabentruhe nutzt sie.

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
- Der Prozentwert ist der Anteil der geschafften Aufgabentypen.
- Bei 100 % ist das Niveau abgeschlossen.
- Bei Textfragen ordnet die Lehrkraft ein Fragenset einem Niveau zu. Der Prozentwert ist der Anteil richtig gelöster Fragen.

**Abschluss und Aufstieg**

- Nach dem Abschluss eines Niveaus steigt der Schüler automatisch ins nächste auf.
- Der automatische Aufstieg ist voreingestellt an. Die Lehrkraft kann ihn pro Schüler sperren.
- Die Lehrkraft kann das Niveau jederzeit von Hand ändern.
- Nach dem letzten Niveau ist das Modul abgeschlossen. Aufgaben und Belohnungen gibt es weiter, im Rahmen des Tageslimits.

**Begriffe**

Ein Niveau ist ein Schwierigkeitsgrad, gezählt ab 1. Die Abfolge von Aufgaben oder Räumen innerhalb eines Niveaus heißt Station, nicht Level.

**Wo das Niveau gesetzt wird**

In der Web-Anwendung. Bis sie existiert, genügt ein einfacher Chatbefehl für Lehrkräfte. Ein eigener Reiter im Pult wäre doppelte Arbeit.

### 8.3 Belohnungen

**Größen und Anlässe**

- Naturalien, ausgezahlt in die Belohnungskiste.
- Drei Größen, die die zuständige Lehrkraft pro Gruppe in der Web-Anwendung mit Gegenständen füllt. Bis es sie gibt, kommen sie aus den Einstellungen des Servers.

| Anlass | Größe | Voreinstellung |
|---|---|---|
| Aufgabe gelöst | klein | 1 Eisenbarren |
| Aufgabentruhe gelöst | mittel | 1 Goldbarren |
| Niveau abgeschlossen | mittel | 1 Goldbarren |
| Etappe abgeschlossen | groß | 1 Diamant |

**Etappen**

- Ein Modul kennzeichnet einzelne Niveaus als Etappe. Das letzte Niveau ist immer eine.
- Nur der Abschluss einer Etappe bringt die große Belohnung. So bleibt sie auch bei Modulen mit vielen Niveaus etwas Besonderes.
- Dieselben Etappen gelten für die Trophäen.

**Regeln**

- Tageslimit als Anzahl: 10 belohnte Aufgaben und 5 Truhen pro Tag. Der Tag wechselt um Mitternacht nach der Uhr des Servers. Abgeschlossene Niveaus und Etappen zählen nicht mit.
- Ist das Limit erreicht, kann der Schüler weiter Aufgaben lösen. Sie zählen fürs Pensum, bringen aber nichts mehr.
- Faustregel: Eine Aufgabe bringt etwas mehr, als man in derselben Zeit abbauen könnte.
- Keine Zufallsbelohnungen. Die Belohnung steht vorher fest und ist sichtbar.
- Belohnung nur auf dem eigenen Niveau und darüber. Weil die Lehrkraft das Niveau passend setzt, ist das für alle fair.
- Textfragen belohnen nur beim ersten Lösen, Multiple Choice voll nur im ersten Versuch.

**Belohnungskiste**

- Sie steht im persönlichen Raum. Nur der Besitzer kann sie öffnen, und er kann nur herausnehmen.
- Der Inhalt gehört zum Konto, nicht zum Block. Belohnungen kommen auch an, wenn der Schüler abgemeldet ist.
- Ist die Kiste voll, wartet der Rest und rückt nach, sobald Platz ist.

**Protokoll**

- Jede Belohnung wird protokolliert: Zeitpunkt, Kontoname, Größe, Anlass, Modul, Niveau, Aufgabentyp, Inhalt.
- Das Protokoll hilft bei Streitfällen. Schüler sehen ihr eigenes, Lehrkräfte das ihrer Schüler.
- Verwaltung und Löschung wie bei allen Protokollen, siehe Abschnitt 12.

### 8.4 Trophäen

- Ein eigener Mod meldet sich beim Fortschritts-Mod an und vergibt Trophäen für Meilensteine.
- Schema der Meilensteine:
  - Etappe abgeschlossen: eine Trophäe pro Etappe und Modul (Etappen siehe Abschnitt 8.3),
  - gelöste Aufgaben pro Modul: 10, 50, 100,
  - gelöste Aufgabentruhen: 10, 50,
  - Fragenset zu mindestens 80 % richtig abgeschlossen.
- Die konkreten Trophäen entstehen mit jedem Modul.
- Trophäen sind nicht übertragbar und lassen sich nur im eigenen Lobby-Raum aufstellen.
- Trophäen sind Daten im Backend. Der Raum zeigt sie nur an. Nach einem Gruppenwechsel baut die neue Welt den Raum mit denselben Trophäen wieder auf.
- Der vorhandene Awards-Mod wird nicht verwendet: Er speichert lokal in der Welt und ist nur noch in Wartung.

### 8.5 Aufgabentruhe

- Schüler können sie nicht herstellen und nicht abbauen.
- Herkunft: von der Welt erzeugt oder von der Lehrkraft aufgestellt.
- Truhen erscheinen laufend neu an zufälligen Orten.
- Jeder Schüler kann jede Truhe einmal öffnen und bekommt seine eigene Belohnung.
- Nach dem ersten Öffnen bleibt die Truhe noch etwa 10 Minuten stehen, damit Begleiter sie auch lösen können. Dann verschwindet sie.
- Die Aufgabe richtet sich nach dem Niveau des Öffnenden, die Belohnung ist gleich.
- Nach einem Fehlversuch: Wartezeit, dann eine neue Aufgabe.
- Aufgabe und Lösung merkt sich der Server pro Spieler. Die Lösung steht nie im Fenster. Die Truhendaten sind als privat markiert.

### 8.6 Rechnen

- Aufgaben werden erzeugt.
- Jedes Niveau hat eine Liste von Aufgabentypen (Zahlenraum, Rechenarten, später Brüche).
- „3,5“ und „3.5“ gelten beide.
- Zeitdruck nur optional.

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
- **Chat:** frei und ohne Filter. Jede Nachricht wird protokolliert, auch Privatnachrichten. Lehrkräfte können stummschalten. Pro Welt abschaltbar.
- **Schilder:** Schüler dürfen Schilder aufstellen und beschriften. Der Text ist für alle lesbar. Schildtexte werden wie Chatnachrichten protokolliert, mit Kontoname und Ort. Das Protokoll entsteht zusammen mit dem Chatprotokoll.
- **Abschließbare Türen, Falltüren und Kisten:** von Protector. Sie folgen dem Schutzbereich: Wer dort als Mitglied eingetragen ist, kann sie benutzen. Die entsprechenden Rezepte aus Minetest Game (Stahltür, Stahlfalltür, abschließbare Kiste) sind entfernt, damit es nicht zwei Sorten gibt. Das erledigt `lep_survival`.
- **Betten, Knochen, einfache Türen und Kisten:** aus Minetest Game.

Eigene Mods fragen den Schutz nur über Luantis Standardfunktion ab, nie direkt bei Protector. So bleibt der Schutz-Mod austauschbar.

## 10. Lehrkraft im Spiel

### 10.1 Lehrerpult

Ein eigener Mod mit selbst geschriebenem Fenster. Oben die Zielauswahl (alle, einzelne Schüler), darunter die Aktionen. Aktionen sind registrierbare Bausteine, damit Lernmodule eigene Knöpfe ergänzen können.

Erste Version:

- In einen Lernraum schicken (Modul und Station), zurückholen.
- Aufmerksamkeitsmodus an/aus, mit eigenem Text.
- Unterrichtsmodus umschalten.
- Tageszeit der Welt steuern (Abschnitt 10.3).
- Unsichtbar zu einem Schüler springen.
- Übersicht: wer ist wo, wer bearbeitet was.
- Reiter „Web-Zugang“ (Abschnitt 11.4).
- Für die Schulverwaltung: Lehrkräfte ernennen. Dabei entsteht das Konto der Lehrkraft mit frei gewähltem Namen, das Startpasswort wird einmal angezeigt. Das Backend verteilt das Konto in alle Welten. Die erste Person der Schulverwaltung legt der Server-Admin an.

Grundsätze:

- Aktionen teleportieren nie selbst, sie rufen die Ortsverwaltung auf.
- Rechte werden bei jedem Knopfdruck neu geprüft.
- Angefangene Aufgaben bleiben erhalten, wenn jemand herausgeholt wird.
- Chatbefehle als Notlösung.

### 10.2 Unterrichtsmodi

- **Unterricht:** nur zugewiesene Aufgaben, die Wildnis ist gesperrt.
- **Freiarbeit:** Lobby und freiwillige Aufgaben.
- **Freizeit:** alles offen.

### 10.3 Tageszeit

Die Lehrkraft steuert die Tageszeit am Pult. Sie gilt für die ganze Welt, also für die ganze Gruppe.

- **Zeit setzen:** Morgen, Mittag, Abend, Nacht.
- **Schalter mit drei Stellungen:** Zeit läuft, dauernd Tag, dauernd Nacht. Bei „dauernd“ steht die Zeit still.
- Die Einstellung bleibt über einen Neustart des Servers erhalten.
- In den Lernräumen spielt die Tageszeit keine Rolle, dort ist es immer hell. Die Aktion betrifft Wildnis und Lobby.
- Die Aktion hat ein eigenes Privileg im Bündel „Lehrkraft“. Luantis eingebautes `settime` wird nicht vergeben, weil es den Chatbefehl freischaltet und am Pult vorbeiführt.

### 10.4 Aufmerksamkeitsmodus

- **Bewegungsunfähig:** Laufen, Springen, Bauen und Abbauen gesperrt.
- **Blind:** bildschirmfüllendes HUD-Bild mit Text der Lehrkraft. Offene Fenster werden geschlossen, das Inventar öffnet nicht.
- **Taub:** kein Chat in beide Richtungen. Der Server unterdrückt die Klänge, die er selbst abspielt.
- Unverwundbar während der Sperre.
- Der Zustand übersteht Neuanmelden.
- Einzelne Schüler können ausgenommen werden.
- Wer das Privileg zum Schalten hat, wird selbst nicht erfasst.
- Physik-Änderungen laufen über player_monoids, damit sich Mods nicht gegenseitig überschreiben. Ortsgebundene Rechte wie das Flugrecht vergibt `lep_places` (Abschnitt 7.6).

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

Regeln für das Ernennen:

- Niemand vergibt mehr, als er selbst hat.
- Vergeben wird nur über das Pult.
- Die letzte Person der Schulverwaltung kann sich nicht selbst entfernen.
- Jede Vergabe und jeder Entzug wird protokolliert.

## 11. Web-Anwendung

### 11.1 Aufbau

- Backend in Rust, das auch die gebaute Oberfläche ausliefert.
- Oberfläche in Vue mit Pinia und Router.
- SQLite als Datenbank.
- Zwei getrennte Schnittstellen: eine für den Browser (mit Anmeldung), eine für Welten und Agenten (mit Schlüssel).
- Mailversand per SMTP über das Webhosting-Postfach, Port 587 mit Anmeldung. Hetzner sperrt auf Cloud-Servern die ausgehenden Ports 25 und 465, Port 587 ist frei.
- Die Typen der Schnittstelle liegen einmal in einem gemeinsamen Rust-Paket (`crates/protocol`), das Backend und Agent nutzen.
- OpenAPI-Beschreibung aus den Rust-Typen, TypeScript-Typen daraus erzeugt. Die Nachrichten des Mods werden in den Lua-Tests gegen dasselbe Schema geprüft.

### 11.2 Brücke

Luanti-Mods können keine Anfragen annehmen und keine WebSocket-Verbindung aufbauen. Deshalb ruft immer die Welt an:

- **Spiel → Web:** Ereignisse sofort senden. Jedes Ereignis hat eine eindeutige ID, das Backend verwirft Doppelte.
- **Web → Spiel:** Die Brücke holt Aufträge per Long Polling ab.
- HTTPS mit einem eigenen Schlüssel pro Welt.
- Die Schule braucht dafür keinen offenen Port nach außen.
- Fällt die Verbindung aus, läuft das Spiel weiter: lokale Kopie der Einstellungen, Warteschlange für Ereignisse.

Die Brücke braucht einen Eintrag in `secure.http_mods`. Sie ist kein vertrauenswürdiger Mod und bleibt in der Sandbox.

### 11.3 Agent (später)

Ein kleines Programm in Rust, einmal pro Spielserver.

- Ruft das Backend wie die Brücke per HTTPS und Long Polling an, mit eigenem Schlüssel pro Maschine.
- Legt Welten aus einer Vorlage an, startet und stoppt sie, meldet den Zustand, sichert, archiviert und löscht.
- Kennt nur eine feste Liste von Aufträgen und führt keine beliebigen Befehle aus.
- Läuft unter einem eigenen Benutzer ohne Administratorrechte.
- Brücke und Agent wissen nichts voneinander.

Bis dahin legt der Server-Admin Welten mit einem Skript an und trägt den Schlüssel ein, den die Web-Anwendung für die neue Gruppe ausgibt.

### 11.4 Anmeldung der Lehrkräfte

Registrierung im Pult, Reiter „Web-Zugang“:

- E-Mail-Adresse eintragen oder ändern.
- Status sehen: nicht eingerichtet, Bestätigung ausstehend, bestätigt.
- Bestätigungsmail erneut senden.
- Einmal-Code erzeugen, falls die Mail nicht ankommt.
- Web-Zugang entfernen.

Ablauf:

1. Die Lehrkraft trägt ihre dienstliche Adresse ein.
2. Die Welt meldet sie ans Backend.
3. Das Backend schickt eine Bestätigungsmail.
4. Nach dem Klick gilt die Adresse.

Anmeldung im Browser: Adresse eingeben, Link per Mail, Klick. Eine Registrierungsseite gibt es nicht.

- Der Link gilt etwa 15 Minuten und nur einmal.
- Danach hält eine Sitzung die Anmeldung.
- Das Formular antwortet immer gleich, egal ob die Adresse bekannt ist.
- Beim Ändern gilt die alte Adresse, bis die neue bestätigt ist.
- Werden die Privilegien entzogen, sperrt das Backend den Zugang sofort.

### 11.5 Funktionen

- Gruppen anlegen, Schülerlisten hochladen, Namen neu würfeln, Zugangszettel drucken.
- Wunschnamen freigeben.
- Passwörter zurücksetzen.
- Schüler in eine andere Gruppe verschieben.
- Niveau pro Schüler und Modul setzen, Startniveau pro Gruppe festlegen, automatischen Aufstieg sperren.
- Fortschritt pro Gruppe, Schüler und Modul in Prozent des Pensums, Export als CSV.
- Fragensets hochladen und zuweisen.
- Belohnungstabellen pro Gruppe.
- Belohnungs- und Chatprotokoll einsehen.
- Jahresabschluss.

### 11.6 Zuständigkeiten

| Backend führt | Welt führt |
|---|---|
| Konten und ihre Zuordnung zu Welten | Ort, eingefroren, Inventar |
| Gruppen, Zuordnung Lehrkraft zu Gruppe | Belohnungskiste, Truhenzustand |
| Fragensets, Zuweisungen, Belohnungstabellen | laufende Aufgaben |
| Lernniveau, Meilensteine, Trophäen | lokale Kopie der Einstellungen |
| Protokolle des laufenden Jahres | Warteschlange für Ereignisse |

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

Es gibt mehrere Protokolle: Chat, Schildtexte, Belohnungen und Aktionen am Pult. Alle werden gleich verwaltet.

- Jedes Protokoll ist eine Datei im Ordner der Welt, an die nur angehängt wird. Eine Zeile ist ein Eintrag mit Zeitpunkt und Kontoname.
- Die gemeinsame Technik liegt in `lep_core`. Kein Mod baut ein eigenes Protokoll.
- Alle Protokolle bleiben bis zum Jahresabschluss, also höchstens ein Jahr. Der Jahresabschluss löscht sie vollständig. Eine kürzere eigene Frist gibt es nicht.
- Einsicht haben nur Lehrkräfte der Gruppe. Schüler sehen ihr eigenes Belohnungsprotokoll.
- Die Schüler werden darauf hingewiesen, dass der Chat mitgeschrieben wird.
- Ein Jahr ist lang und muss gegenüber Schule und Eltern begründet werden, etwa mit der Aufklärung von Mobbing-Vorfällen und von Streit um Belohnungen.
- Das Belohnungsprotokoll zeigt, wann ein Schüler welche Aufgabe gelöst hat. Es ist damit eine Lernhistorie des laufenden Jahres. Auch das gehört in die Information an Schule und Eltern.

**Wunschnamen**

Viele Kinder wählen ihren Vornamen. Lehrkräfte sollen Nachnamen und volle Namen ablehnen. Der Wunschname gehört zu den Kontodaten und wird mit dem Konto gelöscht.

**Jahresabschluss**

- Löscht alle Jahresdaten, für die ganze Schule oder einzelne Gruppen.
- Zeigt vorher an, was gelöscht wird, und bietet einen Export an.
- Das Backend schickt den Welten den Auftrag, ihre lokalen Kopien zu löschen.
- Die Löschung wird ohne Inhalte vermerkt: wer, wann, welcher Umfang.

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
| Physik zusammenführen | player_monoids | Apache 2.0 |
| Lesbare Schrift auf Schildern | signs_lib (mt-mods) | LGPL 3 für Code, CC BY-SA 4.0 für Medien |

Bewusst nicht verwendet: Classroom Manager (eigenes Pult), Account Manager (Konten kommen aus dem Backend), Awards (Trophäen sind Backend-Daten), flow (Formspecs werden selbst geschrieben).

### 14.2 Eigene Mods

Alle eigenen Mods liegen als Modpack unter `mods/`. Die Namen sind auf ContentDB frei (geprüft am 15. November 2026). Jeder Mod hat einen Kern in reinem Lua (`src/`) und eine Schicht zum Spiel (`game/`). Einen eigenen Kern-Mod pro Lernmodul gibt es deshalb nicht.

| Mod | Aufgabe |
|---|---|
| `lep_core` | Gemeinsame Hilfen: Anzeigename, Formspec-Hilfsschicht, Einstellungen |
| `lep_places` | Ortsverwaltung: Ortswechsel, Inventare, Rechte |
| `lep_lobby` | Gemeinsamer Bereich, persönliche Räume, Schutzzone |
| `lep_portals` | Festes und persönliches Portalpaar |
| `lep_rooms` | Lernräume bauen, zuteilen, schützen und neu bauen |
| `lep_survival` | Regeln der Survival-Welt: Rezepte, die fremde Mods ersetzen |
| `lep_progress` | Ergebnisse annehmen, Niveau und Pensum führen, Ereignisse verteilen |
| `lep_rewards` | Regeln, Tageslimit, Belohnungskiste, Protokoll |
| `lep_trophies` | Meilensteine, Ausstellung im Raum |
| `lep_math` | Rechnen: Aufgabengenerator, Dialogfenster |
| `lep_quest_chest` | Aufgabentruhe in der Wildnis |
| `lep_desk` | Lehrerpult: Zielauswahl, Aktionen, Web-Zugang, Ernennen |
| `lep_attention` | Aufmerksamkeitsmodus: Einfrieren, Overlay, Chat-Sperre |
| `lep_chat` | Protokoll, Stummschalten |
| `lep_bridge` | Verbindung zum Backend, Konten anlegen, Warteschlange |
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
7. **Mehrere Welten:** Verteilung der Konten, Gruppenwechsel.
8. **Textfragen** mit GIFT-Import.
9. **TZ-Modul.**
10. **Logikrätsel.**

Später: Agent, Monster.

Bis Schritt 5 läuft alles in einer einzigen Welt ohne Web-Anwendung, mit lokal angelegten Konten. Die Schnittstellen werden von Anfang an so gebaut, dass Schritt 6 und 7 nur andocken.

## 16. Offene Punkte

Bei der Umsetzung des jeweiligen Teils:

1. **Pensum:** Aufgabentypen pro Niveau für jedes Modul, und wie oft ein Typ richtig gelöst sein muss (Vorschlag: fünfmal).
2. **Kontonamen:** Luantis genaue Längengrenze prüfen.
3. **Mesecons:** Stand der letzten Version prüfen.
4. **GIFT-Export:** Mit einem ByCS-Zugang ausprobieren, ob Lehrkräfte Fragen exportieren können.
5. **TZ:** Die Stationen auf die Niveaus verteilen.

6. **Raumlicht:** Luanti 5.18 kann die Helligkeit pro Spieler einstellen (`set_lighting`, Feld `static.light_curve`). Das könnte die leuchtende Luft in den Lernräumen ersetzen. Zwei kurze Versuche blieben ohne klares Ergebnis. Erneut prüfen, sobald auch die Testumgebung des Nutzers 5.18 hat.

Vor einem Einsatz an einer Schule:

7. **Datenschutz** mit der Schule klären, einschließlich der Aufbewahrung des Chatprotokolls.

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
- [ContentDB: player_monoids](https://content.luanti.org/packages/Byakuren/player_monoids/)
- [mtt, Test-Framework](https://content.luanti.org/packages/BuckarooBanzay/mtt/)
- [Moodle: GIFT-Format](https://docs.moodle.org/de/GIFT)
