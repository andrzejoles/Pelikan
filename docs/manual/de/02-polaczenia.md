# Verbindungen und Passwortsicherheit

## Verbindungsdefinition

Eine Verbindung hat einen Namen, einen Ordner, einen Benutzer, eine Datenbank (EZConnect `host:port/usługa`, `tcps://…`
oder ein Alias aus `tnsnames.ora`), eine Rolle (Normal, SYSDBA…), optional einen Proxy-Benutzer, eine Edition (EBR) und
eine Umgebung: Entwicklung, Test oder Produktion. Produktionsverbindungen haben eine Warnfarbe, und Befehle, die Daten
ändern, müssen dort bestätigt werden.

Eine Verbindung kann **schreibgeschützt** sein — Pelikan weist DML, DDL und PL/SQL dann zurück, bevor sie die Datenbank
erreichen.

## Passwörter

Passwörter werden ausschließlich im macOS-**Schlüsselbund** gespeichert (Anmeldung, ohne iCloud-Synchronisierung) und
gelangen nie in Dateien, Protokolle oder Prozessargumente. Ein Passwort wird erst nach einer erfolgreichen Verbindung
gespeichert und nur dann, wenn Sie **Passwort im Schlüsselbund sichern** aktivieren.

Unter **Einstellungen › Oracle** können Sie
**Vor Verwendung eines gespeicherten Passworts Touch ID oder Mac-Passwort verlangen** aktivieren — Pelikan fragt dann
einmal pro Verbindung, solange die App läuft.

## Oracle Wallet

Pelikan unterstützt zwei Arten von Wallets:

- **Passwortspeicher** (Secure External Password Store) — Anmeldung mit `/@alias` ohne Passworteingabe; das
  Wallet-Verzeichnis geben Sie unter **Einstellungen › Oracle › Oracle Net und Oracle Wallet** an, und in der
  Verbindung wählen Sie die Authentifizierung *Oracle Wallet*. Das Feld „Datenbank“ muss genau dem im Wallet
  gespeicherten Alias entsprechen;
- **TLS-Wallet** (z. B. Autonomous Database) — das Wallet-Verzeichnis wird in der Verbindungsdefinition angegeben; ein
  ZIP-Archiv aus dem Portal entpacken Sie mit der Schaltfläche **ZIP importieren …**.

## Weitere Authentifizierungsarten

- **Extern** (Kerberos, Betriebssystem).
- **Microsoft Entra ID** — Instant Client 23 öffnet zur Anmeldung den Browser und übergibt das Token selbst an die
  Datenbank; Pelikan sieht und speichert das Token nicht.
- **OAuth2-Token aus Datei** — ein zuvor mit einem externen Werkzeug erstelltes Token.
- **SSH-Tunnel** — Verbindung über einen Zwischenserver (Schlüssel oder SSH-Agent).

## Lizenzen für Oracle-Packs

Die Berichte AWR, ASH, ADDM, SQL Monitor und SQL Tuning Advisor erfordern die kostenpflichtigen Oracle
Diagnostics/Tuning Packs. Bei der ersten Verwendung fragt Pelikan, ob die Datenbank lizenziert ist, und speichert die
Antwort in der Verbindungsdefinition.
