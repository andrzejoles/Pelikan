# Verbindungen

Eine Verbindung ist eine gespeicherte Definition: wohin verbunden wird, als wer und mit welchen Sicherheitsregeln.
Definitionen werden ohne Passwörter gespeichert — Passwörter landen ausschließlich im macOS-Schlüsselbund.

## Verbindungsliste

Der Tab **Verbindungen** in der linken Spalte zeigt die Definitionen in Ordnern, der Ordner **Zuletzt** die zuletzt
verwendeten. Unter einer Verbindung sind ihre offenen Fenster zu sehen.

- Ein Doppelklick auf eine Verbindung verbindet sie als **Hauptverbindung** (in der Liste fett). Neue Fenster öffnen
  sich auf der Hauptverbindung.
- Kontextmenü der Verbindung: **Als Hauptverbindung verbinden**, **Verbinden** (ohne die Hauptverbindung zu ändern),
  **Trennen**, **Neues Fenster** (SQL-, Programm- oder Testfenster oder SQL*Plus-Konsole auf dieser Verbindung), **Fenster der
  Verbindung zeigen**, **Fenster der Verbindung schließen**, **Fenster der Verbindung neu verbinden**, **Aktuelles
  Schema festlegen …**, **Bearbeiten …**, **Unter anderem Namen kopieren …** (Kopie im selben Ordner, mit den
  gespeicherten Passwörtern), **In Ordner verschieben** und **Löschen …**.
- Ordner und Verbindungen sind alphabetisch sortiert. Eine Verbindung, die mit der Maus auf einen Ordner gezogen wird,
  landet darin, auf freiem Platz der Liste — auf der obersten Ebene.
- Die Schaltflächen über der Liste legen eine neue Verbindung (**+**) und einen Ordner an und aktualisieren die Liste.
- **Ordner entfernen** (Kontextmenü des Ordners, Entf-Taste auf dem ausgewählten Ordner oder **Start › Verbindungen ›
  Ordner entfernen** mit Auswahl unter den leeren Ordnern) entfernt nur einen leeren Ordner — ohne Verbindungen und
  Unterordner, daher ohne Rückfrage. Bei einem nicht leeren Ordner nennt eine Meldung (und der Tooltip des
  Menüeintrags), wie viele Verbindungen und Unterordner zuerst zu verschieben oder zu löschen sind. Einen Ordner mit
  Zuordnungsregel (aus einem Import) entfernen Sie nach einer Bestätigung — passende Verbindungen kehren auf die oberste
  Ebene zurück. Der Ordner **Zuletzt** lässt sich nicht entfernen. Entf auf einer Verbindung ist **Löschen …** mit
  Rückfrage. In Skripten wird ein Ordner per ID oder Pfad („Team / Archiv“) angegeben; ein eindeutiger Name genügt.

Sie können auch das Anmeldefenster verwenden: **Sitzung › Anmelden …** (⇧⌘L). Es zeigt alle Definitionen mit einem
Suchfeld und ermöglicht es, eine neue Verbindung anzulegen oder eine vorhandene zu bearbeiten. **Sitzung ›
Hauptverbindung abmelden** beendet die Sitzungen der Hauptverbindung.

## Neue Verbindung

Wählen Sie **Sitzung › Verbindungen › Neue Verbindung …** oder klicken Sie in der Verbindungsliste auf **+**. Das
Definitionsfenster hat vier Tabs.

### Tab „Allgemein“

- **Name** — der Name in der Liste (leer bedeutet `benutzer@datenbank`). Für lokale Testdatenbanken eignen sich Namen
  mit Präfix, z. B. `dev_test`.
- **Ordner** und **Umgebung**: *Entwicklung*, *Test*, *Produktion* oder *Sonstige*. Die Umgebung bestimmt die Farbe des
  Zeigers (Test — orange, Produktion — rot), die Bestätigung von Änderungen und was der KI-Agent darf. **Eigene
  Zeigerfarbe** ersetzt die Umgebungsfarbe.
- **Benutzer**, **Passwort** und **Passwort im Schlüsselbund sichern**. Ohne Sichern fragt Pelikan beim ersten Verbinden
  nach dem Passwort und behält es nur bis zum Beenden der Anwendung im Speicher. Passt ein gespeichertes Passwort nicht
  mehr (ORA-01017), fragt Pelikan erneut danach.
- **Datenbank** — eine EZConnect-Adresse `host:port/dienst` (z. B. `db.example.com:1521/FREEPDB1`), ein Alias aus
  `tnsnames.ora` (die Schaltfläche **TNS** neben dem Feld schlägt Aliase aus der Konfiguration vor), ein vollständiger
  Deskriptor oder eine Adresse `tcps://…` für verschlüsselte Verbindungen.
- **Verbinden als**: Normal, SYSDBA, SYSOPER, SYSBACKUP, SYSDG, SYSKM oder SYSASM.
- **Authentifizierung**: *Passwort*, *Oracle Wallet (Passwortspeicher)*, *Extern (Kerberos, Betriebssystem)*, *Microsoft
  Entra ID (Browser)* oder *OAuth2-Token aus Datei* (unten beschrieben).
- **Treiber**: *Instant Client (empfohlen)* oder *Thin (ohne Instant Client)*. Thin unterstützt kein TCPS und keine
  Wallets, keine externe Authentifizierung, kein Ändern eines abgelaufenen Passworts und kein Unterbrechen der
  Ausführung.

Klicken Sie auf **Testen**, um die Verbindung zu prüfen, und dann auf **Speichern**.

### Tab „Erweitert“

- **Proxy: Zielschema** — Anmeldung mit einem Proxy-Benutzer in ein anderes Schema (`benutzer[schema]`).
- **Konfigurationsverzeichnis (tnsnames.ora)** — ein eigenes TNS-Verzeichnis für diese Verbindung.
- **TLS-Wallet (mTLS, z. B. Autonomous Database)** — ein Verzeichnis mit `cwallet.sso`. Die Schaltfläche **ZIP
  importieren …** entpackt ein aus der Cloud-Konsole heruntergeladenes Wallet-Archiv neben die ZIP-Datei und setzt
  gleich auch das Konfigurationsverzeichnis.
- **Edition (EBR)** und **Workspace (DBMS_WM)** — Edition und Workspace, die nach der Anmeldung gesetzt werden.
- **Diagnostics/Tuning-Pack-Lizenz** — siehe *Lizenzen der Oracle-Packs* unten.
- **Aktuelles Schema** — `ALTER SESSION SET CURRENT_SCHEMA` in jeder Sitzung.
- **Schreibgeschützt (Änderungen an Daten und Objekten blockiert)** — siehe unten.
- **Beim Start der App verbinden**.
- **Sitzungsinitialisierungsskript** — Befehle, die in jeder neuen Sitzung dieser Verbindung ausgeführt werden (getrennt
  durch `;`, PL/SQL-Blöcke mit `/` abgeschlossen).
- **Meldung bei Anmeldung** — ein Text, der nach dem Verbinden angezeigt wird, z. B. der Hinweis, dass es sich um eine
  gemeinsam genutzte Datenbank handelt.

### Tab „SSH-Tunnel“

Wenn die Datenbank nur über einen Zwischenserver erreichbar ist, aktivieren Sie **Über SSH-Tunnel verbinden** und geben
Sie an:

- **SSH-Server (Bastion)**, z. B. `bastion.example.com`, **Port** und **SSH-Benutzer**;
- **Datei mit privatem Schlüssel** — ein leeres Feld bedeutet den SSH-Agenten und die Einstellungen aus `~/.ssh/config`;
- optional einen **Zwischenhost (ProxyJump)**;
- oder **SSH-Anmeldung mit Passwort (statt Schlüssel)** und **SSH-Passwort**.

Der Tunnel verwendet das System-`ssh`, daher funktionieren Ihre Konfiguration `~/.ssh/config`, der SSH-Agent (mit
`ssh-add --apple-use-keychain` hinzugefügte Schlüssel) und die Datei der bekannten Hosts. Geben Sie Host und Port der
Datenbank im Feld **Datenbank** so an, wie der SSH-Server sie sieht (z. B. `db.internal.example.com:1521/DIENST`). Das
SSH-Passwort wird nur im Schlüsselbund gespeichert und über eine einmalige Pipe an `ssh` übergeben — niemals über
Befehlsargumente, Umgebungsvariablen oder Dateien. Ein Tunnel bedient alle Sitzungen der Verbindung und schließt sich
zusammen mit der letzten von ihnen.

### Tab „KI-Agent“

Einstellungen für den Zugriff von KI-Agenten auf die Verbindung: ob der Agent sie überhaupt sieht, ob er Daten und
Objekte ändern darf (mit Ihrer Zustimmung), ein eigener Datenbankbenutzer für den Agenten und maskierte Spalten. Sie
werden im Kapitel *KI-Agenten* beschrieben.

## Umgebungen und Schutz vor Fehlern

- Die Farbe der Verbindung ist in der Verbindungsliste, auf dem Fenster-Tab (ein Punkt vor dem Namen), in der Fensterliste und in der Statusleiste
  zu sehen. Die Option **Editorhintergrund in Verbindungsfarbe** (**Einstellungen › Allgemein**) färbt auch den
  Hintergrund des Editors. Im selben Tab können Sie Farbregeln nach dem Muster `benutzer@datenbank` hinzufügen (z. B.
  `sys@*`) — sie haben Vorrang vor der Umgebungsfarbe.
- Auf einer **Produktionsverbindung** erfordern Befehle, die Daten oder Objekte ändern (DML, DDL, PL/SQL-Blöcke), eine
  Bestätigung im Fenster „Änderungen auf der Produktionsverbindung“.
- Eine **schreibgeschützte** Verbindung weist vor dem Senden an die Datenbank alles außer Abfragen und Sitzungssteuerung
  zurück — auch `SELECT … FOR UPDATE` und PL/SQL-Blöcke. In der Statusleiste des Fensters steht dann „schreibgeschützt“.
- Pelikan schreibt eine Transaktion nie selbst fest. Beim Schließen eines Fensters oder der Anwendung mit offener
  Transaktion fragt es, ob festgeschrieben (COMMIT) oder zurückgerollt (ROLLBACK) werden soll; das Verhalten beim
  Abmelden ändern Sie unter **Einstellungen › Allgemein › Abmelden mit offener Transaktion**.

## Passwörter und Touch ID

Datenbank- und SSH-Passwörter werden ausschließlich im Anmeldeschlüsselbund von macOS gespeichert (ohne
iCloud-Synchronisierung). Sie gelangen nicht in Dateien, Protokolle, den Befehlsverlauf oder Prozessargumente.

Unter **Einstellungen › Oracle › Verbindungspasswörter** können Sie **Vor Verwendung eines gespeicherten Passworts Touch
ID oder Mac-Passwort verlangen** aktivieren. Pelikan fragt dann während der Laufzeit der Anwendung einmal pro Verbindung
nach einer Bestätigung — auch dann, wenn ein KI-Agent die Verbindung verwendet.

Ist das Passwort in der Datenbank abgelaufen (ORA-28001), zeigt Pelikan ein Fenster zur Passwortänderung: Geben Sie das
neue Passwort zweimal ein. Ist das Sichern aktiviert, ersetzt das neue Passwort das alte im Schlüsselbund, sobald die
Verbindung gelingt.

Sie können das Passwort auch jederzeit ändern: **Sitzung › Passwort ändern …** (die Verbindung muss geöffnet sein).
Pelikan ändert es über die OCI-Schnittstelle — das Passwort erscheint weder im SQL-Text noch im Befehlsverlauf — und
speichert das neue im Schlüsselbund, wenn die Verbindung ihr Passwort speichert.

## Oracle Wallet

Pelikan unterstützt zwei Arten von Wallets:

- **Passwortspeicher** (Secure External Password Store) — Anmeldung ohne Passwort in Pelikan (`/@alias`). Das
  Wallet-Verzeichnis und das Oracle-Net-Konfigurationsverzeichnis geben Sie unter **Einstellungen › Oracle › Oracle Net
  und Oracle Wallet** an; Pelikan zeigt dort den Status des Wallets an (ein Auto-Login-Wallet `cwallet.sso` ist
  erforderlich). Wählen Sie in der Verbindungsdefinition die Authentifizierung *Oracle Wallet (Passwortspeicher)*. Das
  Feld **Datenbank** muss genau der im Wallet gespeicherte Alias oder Connect-String sein. Änderungen in diesem
  Abschnitt der Einstellungen wirken nach einem Neustart von Pelikan.
- **TLS-Wallet** (mTLS, z. B. Autonomous Database) — wird im Tab **Erweitert** der Verbindungsdefinition festgelegt.

Passwörter aus dem Wallet gelangen nie zu Pelikan.

## Weitere Authentifizierungsarten

- **Extern (Kerberos, Betriebssystem)** — Anmeldung mit Anmeldedaten des Betriebssystems oder mit Kerberos.
- **Microsoft Entra ID (Browser)** — für Oracle-Datenbanken auf Azure. Sie geben die Mandanten-ID, die ID der
  Client-Anwendung und den URI der Datenbankanwendung an; Instant Client 23 öffnet einen Browser für die Anmeldung und
  übergibt das Token selbst an die Datenbank. Pelikan sieht und speichert das Token nicht. Erfordert eine
  TCPS-Verbindung.
- **OAuth2-Token aus Datei** — ein vorab mit einem externen Werkzeug (z. B. Azure CLI) erzeugtes Token; Sie geben die
  Token-Datei oder das Token-Verzeichnis an.

## Fenster, Sitzungen und Fensterverbindung

Jedes Fenster hat seine eigene Verbindung, die in der Statusleiste zu sehen ist. Klicken Sie darauf, um das Fenster auf
eine andere Verbindung umzuschalten; hat das Fenster eine offene Transaktion, fragt Pelikan zuerst nach COMMIT oder
ROLLBACK. Ein Fenster mit **angehefteter** Verbindung (📌) behält sie, wenn Sie die Hauptverbindung wechseln; das
standardmäßige Anheften neuer Fenster aktivieren Sie unter **Einstellungen › Allgemein**.

Sitzungsmodus (**Einstellungen › Allgemein › Sitzungsmodus**):

- **Multi** (Standard) — jedes Fenster hat eine eigene Datenbanksitzung, sodass eine lange Abfrage in einem Fenster die
  anderen nicht blockiert und die Transaktionen der Fenster unabhängig sind;
- **Dual** — die Fenster teilen sich eine Sitzung, die Kompilierung hat eine eigene;
- **Single** — alles in einer Sitzung.

Pelikan prüft alle 60 Sekunden, ob die Verbindung noch besteht (das Intervall ändern Sie in den Einstellungen), und
reagiert auf ihren Verlust. Optional schließt es die Sitzungen von Fenstern, die länger als eine festgelegte Zeit
inaktiv sind, sofern sie keine offene Transaktion haben (**Einstellungen › Oracle**).

Lässt sich eine Abfrage nicht unterbrechen (**Unterbrechen**, ⌘.), verwenden Sie **Sitzung › Fenstersitzung beenden
(Kill)** — Pelikan beendet die Sitzung des Fensters in der Datenbank aus einer separaten Sitzung (erfordert das Privileg
ALTER SYSTEM) und verbindet das Fenster neu.

**Sitzung › Verbindungskonsole** öffnet ein der Verbindung zugeordnetes SQL Window (eines pro Verbindung). Sein Inhalt
wird automatisch gespeichert und kehrt beim erneuten Öffnen zurück, auch nach einem Neustart von Pelikan — ein guter Ort
für griffbereite Abfragen.

## Export und Import von Definitionen

**Sitzung › Verbindungen › Verbindungsdefinitionen exportieren …** speichert die Definitionen samt Ordnern ohne
Passwörter in einer JSON-Datei. **Verbindungsdefinitionen importieren …** lädt sie auf einem anderen Mac; die Passwörter
geben Sie beim ersten Verbinden ein.

**Sitzung › Verbindungen › Verbindungen mit Passwörtern exportieren …** speichert die Definitionen zusammen mit den
Passwörtern der Datenbanken und SSH-Tunnel — etwa um Verbindungen auf einen neuen Mac zu übertragen oder ein Jahre altes
Passwort für ein anderes Werkzeug abzulesen. Der Export erfordert die Bestätigung durch den Mac-Besitzer (Touch ID oder
Passwort). Passwörter können **mit einer Passphrase verschlüsselt** (ohne Passphrase nicht wiederherstellbar) oder im
**Klartext** gespeichert werden — dann warnt Pelikan zusätzlich, und jeder mit der Datei kann sie lesen. **Definitionen
importieren …** erkennt eine Datei mit Passwörtern, fragt bei Verschlüsselung nach der Passphrase, speichert die
Passwörter im Schlüsselbund und **löscht die Datei**.

## Lizenzen der Oracle-Packs

AWR-, ASH- und ADDM-Berichte erfordern das kostenpflichtige Oracle Diagnostics Pack, SQL Monitor und SQL Tuning Advisor
das Tuning Pack. Bei der ersten Verwendung einer solchen Funktion fragt Pelikan, welche Lizenz die Datenbank hat
(*Diagnostics und Tuning Pack*, *Nur Diagnostics Pack*, *Keine Lizenz*), und merkt sich die Antwort in der
Verbindungsdefinition (ändern können Sie sie im Tab **Erweitert**). Die Funktion arbeitet auch dann nicht, wenn der
Datenbankparameter `CONTROL_MANAGEMENT_PACK_ACCESS` sie nicht zulässt.
