# Einstellungen und Tastaturkurzbefehle

## Fenster „Einstellungen“

Sie öffnen es über **Pelikan › Einstellungen …** (⌘,). Änderungen werden sofort gespeichert — es gibt keine Schaltfläche
„Anwenden“. Das Feld **Einstellungen suchen** oben findet eine Einstellung nach ihrem Namen (in der Sprache der
Oberfläche) und springt zum passenden Tab.

| Tab | Was Sie festlegen |
|---|---|
| Allgemein | Sitzungsmodus (Multi, Dual, Single), Verhalten beim Abmelden mit offener Transaktion, Verbindungsprüfung, Anheften der Verbindung neuer Fenster, Verbindungsfarben und Regeln `benutzer@datenbank`, Erscheinungsbild (wie System, hell, dunkel), Oberflächenschrift (Schriftart, Stil, Größe), Sprache der Oberfläche, Startverzeichnisse und zusätzliche Dateiendungen, Nachfrage zum Speichern neuer Fenster; Spezifikation und Body in getrennten Dateien (Endungen, Öffnen des Paars); von einem anderen Programm auf der Festplatte geänderte Dateien (Erkennung, Neuladen ohne Nachfrage) |
| SQL Window | AutoSelect, AutoCommit, Bestätigung von COMMIT und ROLLBACK, AutoCommit im Test Window, Zeilen pro Seite, Zahlendarstellung, Auto Format im Large Data Editor, Statistiken, DBMS_OUTPUT (aktiviert, Leeren vor der Ausführung), Formate für DATE und TIMESTAMP |
| Editor | Schriften von Editor, Ergebnisraster und Object Browser (Schriftart, Stil, Größe; Ligaturen) und Farben, Codevorschlag (automatisch nach einem Punkt, Abgleich, Schreibweise, Standardfunktionen, Darstellung von „(alle)“), AutoReplace, Merken des Fensterzustands, Schreibweise von Schlüsselwörtern, Hervorhebungen, Zeilenstatus, Umbruch, Sonderzeichen, Einrückungen und Tabulatoren, Codeinhalt in neuen Fenstern und Reihenfolge seiner Elemente |
| Formatierer | PL/SQL-Formatierungsregeln und automatische Formatierung (nach dem Öffnen aus der Datenbank, vor dem Kompilieren, vor dem Speichern) |
| Tastatur | Kurzbefehlprofil und eigene Kurzbefehle für Befehle |
| Oracle | Instant Client, NLS-Einstellungen der Sitzung, Schließen inaktiver Sitzungen, Version der Oracle-Dokumentation für F1, Touch ID für gespeicherte Passwörter, Oracle Net und Oracle Wallet, Compiler, Debugger, Compiler-Hinweise und Namenskonventionen, DBA_-Views |
| Object Browser | sichtbare Ordner und Reihenfolge, Bestätigung der Rekompilierung, Aktionen beim Ziehen, benannte Filter, Benutzerordner |
| Werkzeuge | Websuchen, externer Editor, externe Vergleichsanzeige, Dokumente, Sicherungskopien und Fensterwiederherstellung, Fragen „Nicht mehr fragen“ |
| Agenten | Agentenprogramme, strikter Modus, Limits für Aufrufe und Abfragen des Agenten |
| Sets | Einstellungssets, Export und Import, Schnellzugriffsleiste |

Einige Einstellungen wirken erst nach einem Neustart von Pelikan: das Instant-Client-Verzeichnis, Oracle Net und Oracle
Wallet sowie die Sprache der Oberfläche.

### Sicherungskopien und Wiederherstellung

Im Tab **Werkzeuge** aktivieren Sie eine Kopie der vorherigen Dateiversion beim Speichern (`datei.~ext`) sowie das
Aufbewahren nicht gespeicherter Fenster zur Wiederherstellung nach einem unerwarteten Beenden (Snapshot in einem
festgelegten Intervall, optional auch vor jeder Ausführung). Nach einem Absturz bietet Pelikan an, die Fenster
wiederherzustellen; Sie können das auch später über **Datei › Fenster wiederherstellen …** tun.

### Fragen „Nicht mehr fragen“

Einige Fragen (z. B. die Bestätigung von COMMIT, das Verschieben in den Papierkorb) haben ein Feld **Nicht mehr fragen**
— Pelikan merkt sich dann Ihre Antwort. Die Liste der gemerkten Antworten und die Schaltfläche **Wieder anzeigen**
finden Sie im Tab **Werkzeuge**. Bestätigungen von Änderungen auf der Produktion und Zustimmungen für KI-Agenten lassen
sich auf diese Weise nicht abschalten.

## Einstellungssets

Mit Sets können Sie für verschiedene Verbindungen unterschiedliche Einstellungen haben — z. B. ein anderes Datumsformat
für eine Datenbank oder strengere Regeln für die Produktion. Pelikan wendet die Sets in dieser Reihenfolge an (vom
wichtigsten): **Persönlich (Verbindung)**, **Persönlich**, **Verbindungsstandard**, **Standard** für alle Verbindungen.
Verbindungssets haben ein Muster `benutzer@datenbank` oder einen Verbindungsnamen mit `*` und `%` (z. B. `app@prod*`)
und gelten, wenn die Hauptverbindung dazu passt.

![Tab „Sets“ in den Einstellungen](../img/zestawy-preferencji.png)

Im Tab **Sets** (oder über **Werkzeuge › Einstellungen › Einstellungssets …**):

1. Fügen Sie ein Set hinzu: Wählen Sie die Art, geben Sie Namen und Verbindungsmuster ein, klicken Sie auf
   **Hinzufügen**.
2. Wählen Sie im Feld **Änderungen in den Einstellungen speichern in** das Set, das Sie bearbeiten möchten. Von da an
   landen Änderungen in den anderen Tabs in diesem Set.
3. Bei den Einstellungen sehen Sie, aus welchem Set der Wert stammt; **Erben** entfernt den Wert aus dem bearbeiteten
   Set.

**Export und Import** speichert ausgewählte Abschnitte der geltenden Einstellungen in eine JSON-Datei (**Werkzeuge ›
Einstellungen › Einstellungen exportieren …**) und lädt sie in das bearbeitete Set (**Einstellungen importieren …**).
Der Export enthält weder Passwörter noch den Dateiverlauf.

## Symbolleiste und Schnellzugriff

**Ansicht › Symbolleiste anpassen …** ändert den Aufbau der Leiste mit dem Standardfenster von macOS. Die Gruppe
**Schnellzugriff** in der Leiste enthält beliebige Befehle (bis zu 20) — Sie fügen sie im Tab **Sets**
(**Schnellzugriffsleiste**) oder über die Befehlspalette hinzu.

## Tastatur

Wählen Sie im Tab **Tastatur** das Profil: **PL/SQL Developer (F-Tasten, Ctrl)** oder **macOS (Cmd)**. Suchen Sie einen
Befehl und nehmen Sie einen eigenen Kurzbefehl auf — Pelikan warnt vor einem Konflikt mit einem anderen Kurzbefehl.
**Kurzbefehle des Befehls entfernen**, **Standard für den Befehl** und **Alle Standardwerte wiederherstellen** machen
Änderungen rückgängig. Das Menü zeigt einen Kurzbefehl pro Befehl, es funktionieren aber alle seine Kurzbefehle.

## Die wichtigsten Kurzbefehle

| Aktion | Profil PL/SQL Developer | Profil macOS |
|---|---|---|
| Neues SQL Window / Program Window | ⌘N / ⇧⌘N | ⌘N / ⇧⌘N |
| Ausführen | F8, ⌘↩ | ⌘↩, F8 |
| Umgekehrt zu AutoSelect ausführen | ⌃F8, ⇧⌘↩ | ⇧⌘↩, ⌃F8 |
| Unterbrechen | ⇧⎋, ⌘. | ⌘. |
| Festschreiben (COMMIT) / Zurückrollen (ROLLBACK) | F10 / ⇧F10 (auch ⌥⌘↩ / ⌥⌘⌫) | ⌥⌘↩ / ⌥⌘⌫ (auch F10 / ⇧F10) |
| Explain Plan | F5 | F5 |
| Anmelden … | ⇧⌘L | ⇧⌘L |
| Codevorschlag | ⌃Leertaste | ⌥⎋, ⌃Leertaste |
| Zur Deklaration springen | ⌃⌥D, ⌃⌘J | ⌃⌘J |
| Befehlsverlauf | ⌃E, ⇧⌘H | ⇧⌘H |
| Suchen und Ersetzen / Gehe zu Zeile | ⌃F, ⌘F / ⌃G, ⌘L | ⌘F / ⌘L |
| Zeilenkommentar | ⌃−, ⌘/ | ⌘/ |
| PL/SQL-Code formatieren | ⇧⌘F | ⇧⌘F |
| In Editoren und Dateien suchen | ⌥⇧⌘F | ⌥⇧⌘F |
| Datenbankobjekte suchen | ⌃⇧O, ⇧⌘O | ⇧⌘O |
| Debugger: starten / beenden | F9 / ⇧F9 | F9 / ⇧F9 |
| Debugger: fortfahren, hineinspringen, überspringen, herausspringen | ⌃R, ⌃N, ⌃O, ⌃T | ⌃R, ⌃N, ⌃O, ⌃T |
| Haltepunkt | ⌃B | ⌃B |
| utPLSQL: alle Tests / Test unter dem Cursor | ⌃⇧U, ⇧⌘U / ⌃⌥U, ⌃⌘U | ⇧⌘U / ⌃⌘U |
| Makro: aufnehmen / abspielen | F11 / F12 | F11 / F12 |
| Nächstes / vorheriges Fenster | ⌃⇥ / ⌃⇧⇥ | ⇧⌘] / ⇧⌘[ |
| Befehlspalette | ⇧⌘P | ⇧⌘P |
| Oracle-Kontexthilfe / Anleitung | F1 / ⇧⌘/ | F1 / ⇧⌘/ |

Die vollständige Liste der Befehle mit ihren aktuellen Kurzbefehlen (einschließlich Ihrer Änderungen) enthält das letzte
Kapitel der Anleitung, **Tastaturkurzbefehle**. Die Tasten F1–F12 arbeiten als Funktionstasten, nachdem Sie diese Option
in den Systemeinstellungen von macOS aktiviert haben, oder zusammen mit der fn-Taste; einige Kurzbefehle mit ⌃ (z. B.
⌃F8, ⌃F2, ⌃F3) fängt macOS ab — verwenden Sie die Entsprechung mit ⌘ oder deaktivieren Sie den Systemkurzbefehl.

## Start mit Parametern

Pelikan lässt sich mit Parametern starten, z. B. aus dem Terminal:

```
open -a Pelikan --args connection=dev_test editobject=APP.EMP_API
```

Unterstützt werden u. a. `connection` (Name einer Verbindung oder `benutzer@datenbank`), `viewobject`, `editobject`,
`commandfile`, `project`, `workset`, `readonly` (Muster der Verbindungen, die bei diesem Start schreibgeschützt geöffnet
werden), `noloaddesktop` sowie Dateipfade. Auch die Adresse `pelikan://open?connection=…` funktioniert. Ein Passwort in
den Parametern wird nicht unterstützt — `userid=u/passwort@db` wird ohne Passwort und mit einer Warnung angenommen, und
das Passwort stammt aus dem Schlüsselbund oder aus einer Abfrage.

Eine `pelikan://`-Adresse kann jede Webseite oder Nachricht öffnen; sie akzeptiert daher nur das Öffnen (Verbindung,
Objekt, Datei, Workset, Projekt, `readonly`) – ein `commandfile`-Skript aus einer solchen Adresse führt Pelikan nie
aus.
