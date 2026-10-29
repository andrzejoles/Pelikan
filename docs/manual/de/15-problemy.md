# Fehlerbehebung und Einschränkungen

## Häufigste Probleme

### macOS lässt Pelikan nicht starten

Pelikan ist nicht von Apple notarisiert. Öffnen Sie beim ersten Start **Systemeinstellungen › Datenschutz & Sicherheit**
und klicken Sie auf **Dennoch öffnen** (siehe Kapitel *Einführung*).

### „Oracle Instant Client fehlt“

- Laden Sie Instant Client für macOS in der Version **ARM64** (Basic oder Basic Light) herunter und entpacken bzw.
  installieren Sie ihn gemäß der Anleitung von Oracle.
- Geben Sie das Verzeichnis mit der Datei `libclntsh.dylib` unter **Einstellungen › Oracle › Oracle Instant Client** an
  und starten Sie Pelikan neu.
- Liegt der Client im Ordner „Downloads“ und hat macOS nach dem Zugriff von Pelikan auf diesen Ordner gefragt und Sie
  haben abgelehnt, ändern Sie das unter **Systemeinstellungen › Datenschutz & Sicherheit › Dateien und Ordner** oder
  verschieben Sie den Client an einen anderen Ort.
- Vorübergehend können Sie die Verbindung auf den *Thin*-Treiber umstellen (Tab **Allgemein** der
  Verbindungsdefinition).

### Ich kann mich nicht verbinden

- Klicken Sie in der Verbindungsdefinition auf **Testen** — die Meldung der Datenbank oder des Oracle-Clients nennt die
  Ursache.
- **ORA-12154 / TNS:** Der Alias wurde nicht gefunden — prüfen Sie das Konfigurationsverzeichnis (Tab **Erweitert** oder
  **Einstellungen › Oracle › Oracle Net und Oracle Wallet**) oder verwenden Sie eine Adresse `host:port/dienst`.
- **ORA-01017:** falsches Passwort — Pelikan fragt erneut danach; aktivieren Sie das Sichern, um das Passwort im
  Schlüsselbund zu ersetzen.
- **ORA-28001:** Das Passwort ist abgelaufen — Pelikan zeigt das Fenster zur Passwortänderung.
- **Oracle Wallet:** Das Feld **Datenbank** muss genau der im Wallet gespeicherte Alias sein, und das Wallet muss die
  Datei `cwallet.sso` (Auto-Login) enthalten. Den Status des Wallets sehen Sie unter **Einstellungen › Oracle**.
  Änderungen in diesem Abschnitt wirken nach einem Neustart.
- **SSH-Tunnel:** Pelikan verwendet das System-`ssh` — prüfen Sie im Terminal, ob `ssh benutzer@bastion.example.com`
  funktioniert (Schlüssel im SSH-Agenten, bekannter Host). Geben Sie die Datenbankadresse so an, wie der SSH-Server sie
  sieht.
- **Touch ID:** Wenn Sie die Bestätigung gespeicherter Passwörter aktiviert haben und den Systemdialog abbrechen, wird
  die Verbindung nicht hergestellt.

### Ein Tastenkürzel funktioniert nicht

- F-Tasten: Aktivieren Sie in den Systemeinstellungen ihre Verwendung als Standard-Funktionstasten oder drücken Sie sie
  zusammen mit der fn-Taste.
- ⌃F8, ⌃F2, ⌃F3 und andere Kurzbefehle mit ⌃ können von macOS belegt sein (**Systemeinstellungen › Tastatur ›
  Tastaturkurzbefehle**). Verwenden Sie die Entsprechung mit ⌘ (z. B. ⇧⌘↩ statt ⌃F8) oder deaktivieren Sie den
  Systemkurzbefehl.
- ⌃Leertaste wechselt in macOS standardmäßig die Eingabequelle — den Codevorschlag rufen Sie mit ⌥⎋ auf.
- Prüfen Sie den Kurzbefehl des Befehls in der Befehlspalette (⇧⌘P) oder unter **Einstellungen › Tastatur**.

### Eine Abfrage dauert zu lange

**Unterbrechen** (⌘.) unterbricht Ausführung und Abruf. Reagiert die Datenbank nicht (z. B. während `DBMS_SESSION.SLEEP`
oder beim Thin-Treiber, der keine Unterbrechung unterstützt), verwenden Sie **Sitzung › Fenstersitzung beenden (Kill)**
— erfordert das Privileg ALTER SYSTEM.

### Ich kann ein Ergebnis im Raster nicht bearbeiten

Die Abfrage muss die Spalte `ROWID` liefern (z. B. `select t.*, t.rowid from tabelle t`). Am einfachsten verwenden Sie
**Daten bearbeiten** aus dem Menü der Tabelle im Object Browser. Eine schreibgeschützte Verbindung blockiert das
Speichern.

### Der Debugger hält nicht an

- Prüfen Sie die Berechtigungen `DEBUG CONNECT SESSION` und `DEBUG ANY PROCEDURE` (oder `DEBUG` auf dem Objekt) —
  **Debuggen › Debugger-Privilegien …** bereitet die Befehle für den Administrator vor.
- Kompilieren Sie das Objekt mit Debug-Informationen (**Werkzeuge › Objekt › Debug-Informationen hinzufügen**).
- Ein Haltepunkt mit leerer Markierung wurde von der Datenbank nicht angenommen (z. B. eine Zeile ohne ausführbaren
  Code).

### AWR-Bericht / SQL Monitor funktioniert nicht

Prüfen Sie die Lizenzangabe in der Verbindungsdefinition (Tab **Erweitert**) und den Datenbankparameter
`CONTROL_MANAGEMENT_PACK_ACCESS`. Funktionen des Tuning Pack erfordern den Wert `DIAGNOSTIC+TUNING`.

Der Fehler ORA-00904 „DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_HTML: invalid identifier“ bedeutet ein fehlendes
EXECUTE-Recht auf das Paket `SYS.DBMS_WORKLOAD_REPOSITORY` (ADDM-Bericht — auch `SYS.DBMS_ADDM`): In SQL antwortet Oracle dann
mit „invalid identifier“ statt mit fehlenden Rechten. Das Recht kommt meist über die Rolle DBA; außerdem ist eine Lizenz
für Oracle Diagnostics Pack nötig. Pelikan prüft das Recht vor dem AWR-, ASH- und ADDM-Bericht und nennt den
GRANT-Befehl für den Datenbankadministrator, z. B. `GRANT EXECUTE ON SYS.DBMS_WORKLOAD_REPOSITORY TO SCOTT;`.

### Der Agent startet nicht

- Pelikan sucht das Agentenprogramm im `PATH` Ihrer Login-Shell — prüfen Sie im Terminal, ob der Befehl (z. B. `claude`)
  funktioniert.
- Der Agent sieht die Verbindung nicht: Prüfen Sie den Tab **KI-Agent** in der Verbindungsdefinition.
- Der Agent kann nichts ändern: Die Verbindung ist schreibgeschützt, eine Produktionsverbindung ohne Zustimmung zu
  Änderungen, oder Sie haben die Stufe des Werkzeugs in der Berechtigungsmatrix der Sitzung gesenkt.

### Pelikan wurde unerwartet beendet

Beim nächsten Start bietet Pelikan an, nicht gespeicherte Fenster wiederherzustellen (auch später: **Datei › Fenster
wiederherstellen …**), sofern unter **Einstellungen › Werkzeuge** das Aufbewahren nicht gespeicherter Fenster aktiviert
ist. Dateiänderungen finden Sie auch im lokalen Verlauf (**Datei › Lokaler Verlauf**).

### Anwendungsprotokoll

Pelikan führt ein Ereignisprotokoll: Start, Verbindungen und ihre Fehler (ORA-Code), abgeschlossene Anweisungen (Art,
Dauer, Zeilenzahl), Hintergrundaufgaben, Debugger, Tests, SSH-Tunnel, KI-Agenten und Updates. **Hilfe ›
Anwendungsprotokoll** öffnet es in der macOS-Konsole; die Datei liegt in `~/Library/Logs/Pelikan`, und dieselben
Einträge gehen in das Systemprotokoll (Subsystem von Pelikan in der Konsole). Dateien sind höchstens 2 MB groß,
Pelikan behält die letzten fünf.

Das Protokoll enthält nie Passwörter, SQL-Anweisungstexte oder Daten aus der Datenbank. Namen von Verbindungen,
Servern und Objekten sowie Dateipfade sind standardmäßig ausgeblendet oder durch einen Hash ersetzt (derselbe Name hat
immer denselben Hash). Unter **Einstellungen › Allgemein › Anwendungsprotokoll** wählen Sie den Umfang (*Warnungen und
Fehler*, *Ereignisse*, *Details — Diagnose*) und können Namen anzeigen lassen — hilfreich bei der Fehlersuche auf dem
eigenen Rechner.

## Bekannte Einschränkungen

Die folgenden Funktionen arbeiten anders als im Vorbild, sind unvollständig oder wurden nicht in einer echten Umgebung
geprüft:

- Der **Thin-Treiber** unterstützt kein TCPS und keine Wallets, keine externe Authentifizierung, kein Ändern eines
  abgelaufenen Passworts und kein Unterbrechen der Ausführung. CLOB und DBMS_OUTPUT liest er bis 65 535 Zeichen
  (längere mit Kürzungshinweis), und eine Abfrage mit einer Spalte INTERVAL YEAR TO MONTH oder BFILE beendet die App
  (Fehler der Bibliothek OracleNIO) — für solche Daten den Instant-Client-Treiber verwenden.
- **Kerberos** unter macOS: Wenn `sqlnet.ora` KERBEROS5 aktiviert, endet die Verbindung mit einer verständlichen
  Fehlermeldung (der Adapter des Instant Client kollidiert in der App mit dem Kerberos des Systems); unter Linux
  funktioniert die Anmeldung mit Ticket. **Microsoft Entra ID** und **TCPS-Verbindungen** sind nach der
  Oracle-Dokumentation umgesetzt, aber nicht mit Azure oder einem TCPS-Listener geprüft. **LDAP**
  (Verzeichnisbenennung): Pelikan löst den Alias selbst über anonymes LDAPv3 auf — ohne LDAPS und ohne Wallet-Bindung.
- **Debugger**: kein Debuggen über DBMS_DEBUG_JDWP; in Triggern sind die Werte von `:new` und `:old` nicht verfügbar; in
  einer Zeile kann es nur einen Haltepunkt geben.
- Das **Raster** kann keine Spalten oder Zeilen fixieren (einfrieren).
- **SQL*Plus-Konsole**: Die Befehle `COPY` und `SET ENVVAR` werden nicht unterstützt.
- Der **Event Monitor** liest kein DBMS_OUTPUT anderer Sitzungen (Oracle stellt das nicht bereit).
- Die **Werkzeuge in der linken Spalte** sind Tabs eines Bereichs (Verbindungen, Objekte, Fenster, Templates, Dateien);
  sie lassen sich nicht frei andocken oder automatisch ausblenden. Dokumente sind Tabs eines Hauptfensters,
  keine nativen macOS-Tabs.
- **Quick Look** für SQL-Dateien (Vorschau im Finder) funktioniert möglicherweise nicht — macOS kann eine mit einem
  selbst signierten Zertifikat signierte Erweiterung ablehnen.
- Der **Pro*C-Remote-Build** wurde auf einem lokalen SSH-Server mit der Shell ksh93 getestet; die Parser für die
  Meldungen von `proc` und `xlc` entstanden anhand der Dokumentation. Der Betrieb auf AIX 6.1 (ksh88) wartet auf eine
  Bestätigung auf einem echten Server.
- **Ausgelassen** in dieser Version: der ODBC-Importer (ersetzt durch die Text- und Excel-Importer und den
  Importassistenten), APEXlang, Liquibase (`lb` aus SQLcl).
- **VoiceOver**: Die Oberflächenelemente haben Bedienungshilfen-Beschriftungen, die Anwendung wurde aber noch nicht mit
  VoiceOver geprüft.

## Fehler melden

Fehler und Vorschläge melden Sie auf der Projektseite:
[github.com/andrzejoles/Pelikan/issues](https://github.com/andrzejoles/Pelikan/issues). Fügen Sie keine Passwörter,
Servernamen oder Daten aus Produktionsdatenbanken bei — eine Beschreibung der Schritte und die Fehlermeldung genügen.

Am einfachsten melden Sie aus der App: **Hilfe › Problem melden…** (auch im Menüband: **Ansicht › Hilfe**), die
Schaltfläche **Problem melden…** in einer Fehlermeldung oder die Frage nach einem unerwarteten Beenden von Pelikan (mit
Absturzbeschreibung aus dem macOS-Bericht: Ausnahme und Stack — ohne Pfade). Geben Sie im Meldungsfenster Titel und
Beschreibung ein, wählen Sie, ob Umgebung und letzte Protokolleinträge beigefügt werden, und prüfen Sie die Vorschau.
**Meldung auf GitHub öffnen** öffnet die Seite einer neuen Meldung mit ausgefülltem Text (eine Kopie liegt in der
Zwischenablage) — Sie senden sie von Ihrem eigenen GitHub-Konto; Pelikan sendet nichts selbst. Meldungen sind
öffentlich: Der Text durchläuft den Filter für Passwörter und Home-Pfad, und das Protokoll verbirgt Namen standardmäßig.

Fügen Sie der Meldung das Protokoll bei: **Hilfe › Protokoll exportieren…** speichert es zusammen mit einer
Beschreibung der Umgebung (Version, System, Treiber) in eine Textdatei. Prüfen Sie die Datei vor dem Senden,
besonders wenn Namen angezeigt wurden.

## Glossar

Die polnischen Namen der Fenster und Begriffe in Pelikan und ihre Entsprechungen in PL/SQL Developer (z. B. *Okno SQL* —
SQL Window, *Przeglądarka obiektów* — Object Browser, *Zapisz zmiany w bazie (Post)* — Post changes) enthält das Glossar:
[docs/GLOSSARY.md](https://github.com/andrzejoles/Pelikan/blob/main/docs/GLOSSARY.md).
