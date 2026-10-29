# Einführung und erster Start

Pelikan ist eine native macOS-Umgebung für die Arbeit mit Oracle-Datenbanken: zum Schreiben und Ausführen von SQL, zum
Erstellen, Testen und Debuggen von PL/SQL-Code, zum Durchsuchen und Bearbeiten von Datenbankobjekten, für utPLSQL-Tests
sowie für Werkzeuge zum Vergleichen, Exportieren und Administrieren. Fensteraufbau und Tastenkürzel entsprechen PL/SQL
Developer, sodass dessen Benutzer vertraute Fenster wiederfinden: **SQL Window**, **SQL*Plus-Konsole**, **Program
Window**, **Test Window**, **Explain Plan Window** und **Object Browser** (Tab **Objekte**).

Diese Anleitung beschreibt, wie Sie typische Aufgaben erledigen. Die vollständige Liste der Befehle mit ihren aktuellen
Tastenkürzeln steht im letzten Kapitel, **Tastaturkurzbefehle**, das von der Anwendung erzeugt wird.

## Voraussetzungen

- Ein Mac mit Apple-Prozessor (M1 oder neuer) und macOS 27 oder neuer.
- Oracle Instant Client für macOS (ARM64) — das Paket Basic oder Basic Light. Pelikan enthält ihn nicht (die
  Oracle-Lizenz erlaubt das nicht), daher laden Sie ihn selbst von der Oracle-Website herunter. Ohne Instant Client
  funktioniert der *Thin*-Treiber mit Einschränkungen (siehe unten).
- Eine Oracle-Datenbank. Pelikan wird auf Oracle Database 26ai Free entwickelt und getestet; die
  Data-Dictionary-Abfragen haben Varianten für die Versionen 19c, 21c und 23ai. Auf älteren Versionen können einige
  Ordner und Funktionen fehlen.

## Installation

1. Laden Sie das neueste Release von der Projektseite herunter:
   [github.com/andrzejoles/Pelikan/releases](https://github.com/andrzejoles/Pelikan/releases) — eine `.dmg`-Datei oder
   ein `.pkg`-Installationsprogramm.
2. Ziehen Sie **Pelikan** aus dem `.dmg`-Image auf den Ordner **Programme (Applications)**. Das
   `.pkg`-Installationsprogramm erledigt das selbst.
3. Starten Sie Pelikan aus dem Ordner „Programme“.

### Gatekeeper-Warnung beim ersten Start

Pelikan ist mit dem eigenen Zertifikat des Autors („Pelikan Self-Signed“) signiert, aber nicht von Apple notarisiert
(dafür wäre ein kostenpflichtiges Entwicklerkonto nötig). Deshalb blockiert macOS die Anwendung beim ersten Start und
zeigt eine Warnung an. So öffnen Sie sie:

1. Schließen Sie das Warnfenster.
2. Öffnen Sie **Systemeinstellungen › Datenschutz & Sicherheit**, scrollen Sie zum Abschnitt **Sicherheit** und klicken
   Sie bei der Meldung zu Pelikan auf **Dennoch öffnen**.
3. Bestätigen Sie mit Ihrem Passwort oder mit Touch ID.

Das ist nur einmal nötig. Die gleichbleibende Signatur sorgt außerdem dafür, dass macOS nach einem Update nicht erneut
nach dem Zugriff von Pelikan auf die Passwörter im Schlüsselbund fragt.

## Oracle Instant Client

Laden Sie „Instant Client for macOS (ARM64)“, Paket **Basic** oder **Basic Light**, von
[oracle.com](https://www.oracle.com/database/technologies/instant-client/macos-arm64-downloads.html) herunter und
installieren Sie ihn gemäß der Anleitung von Oracle. Pelikan sucht die Bibliothek `libclntsh.dylib` in dieser
Reihenfolge:

1. das unter **Einstellungen › Oracle › Oracle Instant Client** angegebene Verzeichnis;
2. `/opt/homebrew/lib`, `/usr/local/lib`, `/usr/local/oracle/instantclient` und die Verzeichnisse
   `/opt/oracle/instantclient*`;
3. Verzeichnisse `instantclient_*` in Ihren Ordnern **Downloads** und **Programme** (neueste Version zuerst).

Beim Durchsuchen des Ordners „Downloads“ kann macOS fragen, ob Pelikan darauf zugreifen darf — das ist eine gewöhnliche
Datenschutzabfrage des Systems. Wenn Sie sie vermeiden möchten, geben Sie das Client-Verzeichnis von Hand an: **Pelikan
› Einstellungen …** (⌘,), Tab **Oracle**, Schaltfläche **Auswählen …**. Eine Änderung des Verzeichnisses wirkt nach
einem Neustart von Pelikan.

Ohne Instant Client können Sie sich mit dem *Thin*-Treiber verbinden (Auswahl in der Verbindungsdefinition, siehe
Kapitel *Verbindungen*). Thin unterstützt keine TCPS-Verbindungen und kein Oracle Wallet, keine externe
Authentifizierung, kein Ändern eines abgelaufenen Passworts und kein Unterbrechen der Ausführung (**Unterbrechen**).

## Erste Schritte

1. Klicken Sie in der linken Spalte auf den Tab **Verbindungen** und dann auf die Schaltfläche **+** (oder wählen Sie
   **Sitzung › Verbindungen › Neue Verbindung …**).
2. Geben Sie Name, Benutzer, Passwort und Datenbank ein (`host:port/dienst` oder einen Alias aus `tnsnames.ora`), wählen
   Sie die Umgebung und klicken Sie auf **Testen** und dann auf **Speichern**.
3. Doppelklicken Sie auf die Verbindung in der Liste — sie wird zur **Hauptverbindung** (fett dargestellt).
4. Öffnen Sie ein neues SQL Window (**Datei › Neu › SQL Window**, ⌘N), geben Sie eine Abfrage ein und führen Sie sie mit
   F8 oder ⌘↩ aus.

![Hauptfenster: Verbindungsliste links, SQL Window mit einem Abfrageergebnis](../img/okno-glowne.png)

## Hauptfenster

Pelikan hat ein Hauptfenster:

- **Linke Spalte** mit den Tabs **Verbindungen** (Verbindungsliste mit Ordnern und zuletzt verwendeten Verbindungen),
  **Objekte** (Object Browser), **Fenster** (Liste der offenen Fenster), **Templates** und **Dateien** (File Browser).
- **Dokument-Tabs** in der Mitte — jedes SQL-, Programm-, Test- oder Planfenster hat einen eigenen Tab mit einem
  farbigen Typbuchstaben: S — SQL Window, P — Program Window, T — Test Window, C — SQL*Plus-Konsole, E — Explain Plan
  Window, R — Report Window, D — Diagrammfenster, N — SQL-Notizbuch. Ein Mittelklick auf einen Tab schließt das Fenster;
  das Tab-Menü schließt die übrigen Fenster oder die Fenster links bzw. rechts.
- **Symbolleiste** mit den häufigsten Aktionen (neues Fenster, öffnen, speichern, ausführen, unterbrechen, COMMIT,
  ROLLBACK, anmelden) und der Gruppe **Schnellzugriff**. Den Aufbau ändern Sie über **Ansicht › Symbolleiste anpassen …**.
- **Statusleiste** des Fensters: die Verbindung des Fensters (mit Umgebungsfarbe, Anheften 📌 und Kennzeichnung „nur
  Lesen“), der Transaktionsstatus („● Transaktion offen“), Zeilenzahl und Ausführungszeit, Cursorposition sowie der
  Git-Branch der Datei. Ein Klick auf den Verbindungsnamen ermöglicht es, die Verbindung des Fensters zu wechseln.
- **Werkzeugbereiche** rechts und unten — Werkzeuge (Sitzungen, Datenbankobjekte suchen, To-Do-Einträge,
  Zwischenablage-Verlauf, diese Anleitung, Tabelleneditoren, Export und Import, Berichte und mehr) öffnen sich
  standardmäßig im rechten Bereich, jedes in einem eigenen Tab. Ziehen Sie einen Tab in den anderen Bereich oder aus
  den Bereichen heraus — das Werkzeug erhält dann ein eigenes Fenster an der Ablagestelle; dasselbe tun das Tab-Menü
  und die Tasten im Kopf des Bereichs. Ein Werkzeugfenster kehrt mit der Taste in seiner Titelleiste in einen Bereich
  zurück. Pelikan merkt sich den Ort jeder Werkzeugart. Ein eingeklappter Bereich mit Werkzeugen zeigt in der
  Statusleiste eine Taste mit ihrer Anzahl. Die Befehle stehen unter **Ansicht › Werkzeugbereiche**; unter
  **Einstellungen › Allgemein › Werkzeugbereiche** wählen Sie den Ort neuer Werkzeuge (auch eigene Fenster) und das
  automatische Ausblenden. Die Kurzbefehle eines angedockten Werkzeugs (Return, Esc) wirken nur, solange der Cursor in
  diesem Werkzeug steht.
- **Agentenbereich** rechts (standardmäßig eingeklappt) — das Terminal des KI-Agenten mit einer Liste seiner Aktionen.
  Er wird über **Ansicht › Agentenbereich** angezeigt (siehe Kapitel *KI-Agenten*).

Der Fenstertitel zeigt die Hauptverbindung und das aktive Workset, der Untertitel das aktuelle Fenster.

## Menüband und „Aktionen suchen“

Unter der Symbolleiste liegt das **Menüband** — jede Aktion mit einem Klick, ohne Suchen in Menüs und ohne Tastenkürzel
zu merken. Die festen Registerkarten sind **Start** (neue Fenster, Dateien, Ausführung, COMMIT und ROLLBACK, Verbindung,
Suche), **Bearbeiten**, **Objekte**, **Debuggen und Testen**, **Werkzeuge**, **Berichte** und **Ansicht**. Bei einem
Programm-, Ergebnis-, Diagramm-, Berichts-, Notizbuch-, Planfenster oder einer SQL*Plus-Konsole erscheint eine farbige
**Kontextregisterkarte** (z. B. **Programm** mit Kompilierung, Einheiten, Vergleich mit der Quelle in der Datenbank und
Tests). Das Menüband merkt sich die gewählte Registerkarte je Fensterart und kehrt beim Fensterwechsel dorthin zurück.

Häufige Aktionen haben große Schaltflächen, andere kleine; seltenere stehen in den Auswahllisten der Gruppen (mit ▾).
Der Tooltip einer Schaltfläche zeigt Beschreibung und Tastenkürzel, so lernen Sie die Kürzel nebenbei. Rechtsklick auf
eine Schaltfläche fügt den Befehl zum Schnellzugriff hinzu. Doppelklick auf eine Registerkarte oder der Pfeil rechts
reduziert das Menüband auf die Registerkarten; **Ansicht › Menüband** blendet es aus (auch unter **Einstellungen ›
Allgemein › Menüband**).

Das Feld **Aktionen suchen…** rechts neben den Registerkarten findet jeden Befehl — tippen Sie ein paar Buchstaben:
„plan“, „export tabel“, ein Wort ohne polnische Sonderzeichen oder einen englischen Namen aus PL/SQL Developer, z. B.
„beautifier“, „compile invalid“. Die Treffer zeigen, wo der Befehl im Menüband liegt, sein Tastenkürzel und ob er gerade
verfügbar ist; Eingabe oder ein Klick führt ihn aus.

## Befehlspalette

Jede Aktion in Pelikan ist ein Befehl: Er hat einen Menüeintrag, ein optionales Tastenkürzel und eine Beschreibung
seiner Auswirkungen. Die **Befehlspalette** (**Ansicht › Befehlspalette …**, ⇧⌘P) sucht Befehle nach Namen und zeigt, in
welchem Menü sie stehen und welches Tastenkürzel sie haben. So finden Sie am schnellsten eine Funktion, deren Platz im
Menü Sie nicht mehr wissen.

## Tastaturprofile

Pelikan hat zwei Kurzbefehlprofile: **PL/SQL Developer** (F- und Ctrl-Tasten — z. B. F8 führt aus, F9 startet das
Debuggen) und **macOS** (Kurzbefehle mit ⌘). In beiden Profilen funktionieren die ⌘-Entsprechungen, z. B. führt ⌘↩ einen
Befehl aus. Das Profil wählen Sie unter **Einstellungen › Tastatur**. Wenn die Tasten F1–F12 Helligkeit oder Lautstärke
steuern, aktivieren Sie in den Systemeinstellungen die Option, sie als Standard-Funktionstasten zu verwenden, oder
drücken Sie sie zusammen mit der fn-Taste.

## Updates

Pelikan prüft einmal täglich, ob es ein neues Release gibt, und bietet die Installation an. Sie können auch manuell
prüfen: **Pelikan › Nach Updates suchen …**. Jedes Release ist mit dem Schlüssel des Autors signiert — die Anwendung
akzeptiert keine Datei aus einer anderen Quelle. Einstellungen, Verbindungen und Passwörter bleiben unverändert.

## Sprachen

Die Oberfläche ist auf Polnisch, Englisch, Deutsch, Spanisch und Ukrainisch verfügbar. Die Sprache wählen Sie unter
**Einstellungen › Allgemein › Sprache der Benutzeroberfläche**; die Änderung wirkt nach einem Neustart. Die Namen
einiger Fenster und Werkzeuge (z. B. Explain Plan, Large Data Editor, Query Builder) bleiben in ihrer Originalform.

## Wo Pelikan seine Daten speichert

Verbindungsdefinitionen (ohne Passwörter), Einstellungen, Verlauf, Worksets, der lokale Dateiverlauf, das
Agentenprotokoll und weitere Anwendungsdaten liegen im Verzeichnis `~/Library/Application Support/Pelikan`. Passwörter
liegen ausschließlich im macOS-Schlüsselbund — siehe Kapitel *Sicherheit und Datenschutz*.

## Hilfe

- **Hilfe › Pelikan-Hilfe** (⇧⌘/) öffnet diese Anleitung.
- **F1** im Editor öffnet die Oracle-Dokumentation zum Wort unter dem Cursor (Fehlercode, Paket, Dictionary-View,
  SQL-Befehl).
- **Hilfe › Oracle-Dokumentation …** durchsucht die Oracle-Handbücher der gewählten Version.

## Über Pelikan

Pelikan ist ein offenes Projekt unter der MIT-Lizenz:
[github.com/andrzejoles/Pelikan](https://github.com/andrzejoles/Pelikan). Autor: Andrzej Oleś w kooperacji z Claude AI.
Die Lizenzen der verwendeten Bibliotheken stehen in der Datei „Licencje zewnętrzne“ (Lizenzen Dritter), die der
Anwendung beiliegt.
