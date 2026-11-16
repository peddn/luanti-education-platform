# frontend

Oberfläche der Web-Anwendung: Vue mit Pinia und Router, JavaScript mit JSDoc, Tailwind CSS, zweisprachig mit `vue-i18n` (Deutsch und Englisch).

Starten, bauen und die Regeln für Texte, Fehlercodes und Typen stehen in [docs/entwicklungsumgebung.md](../docs/entwicklungsumgebung.md), Abschnitt 6.

```sh
scripts/frontend-run.sh          # Entwicklungsserver auf http://127.0.0.1:5173
scripts/frontend-run.sh build    # baut nach frontend/dist, das Backend liefert es aus
scripts/test.sh frontend         # Lint, Typprüfung, Tests, Bau
```

Lizenz: AGPL-3.0-or-later. Siehe [LICENSE.md](../LICENSE.md).
