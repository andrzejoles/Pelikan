# Pro*C: Remote-Build über SSH

Mit Pelikan bearbeiten Sie Pro*C-Programme lokal und bauen sie auf einem Server (z. B. AIX) über SSH, in einem
Git-basierten Ablauf: Änderungen gelangen über `git pull` in die Arbeitskopie (working copy) auf dem Server, und Pelikan
führt dort `make` aus, installiert die Binärdateien und führt eine Deployment-Historie mit der Möglichkeit,
zurückzusetzen. Pelikan sendet Quelltexte nie direkt auf den Server, führt auf dem Server weder `merge` noch `reset` aus
und führt kein `git push` aus.

Die Befehle stehen im Menü **Werkzeuge › Pro*C-Remote-Build**.

## SSH-Ziele

**Werkzeuge › Pro*C-Remote-Build › SSH-Ziele …** öffnet die Zielverwaltung — die Server, auf die Sie ausrollen. Ziele
können Sie in Ordnern gruppieren, duplizieren und löschen. Das Zielformular:

- **Verbindung**: Name, Ordner, Umgebung **UAT** oder **PROD** (mit Farbe), Host, Port, Benutzer und Authentifizierung —
  **Schlüsseldatei** (optional mit Schlüsselpasswort), **SSH-Agent** oder **SSH-Passwort**. SSH-Passwort und
  Schlüsselpasswort speichern Sie im Schlüsselbund (**Im Schlüsselbund sichern**); bei aktiviertem Touch-ID-Schutz
  (**Einstellungen › Oracle › Verbindungspasswörter**) bestätigt Pelikan ihre Verwendung einmal pro Ziel. **Alte
  Algorithmen (AIX 6.1 und ältere Server)** aktiviert SSH-Algorithmen, die alte Server unterstützen. **Namenskodierung**
  und **Konsolenkodierung** (UTF-8 oder ISO-8859-2) legen fest, wie Pelikan Dateinamen kodiert und die Ausgabe liest.
- **Verzeichnisse auf dem Server**: Basisverzeichnis, Backup-Verzeichnis, Working Copy sowie Unterverzeichnisse für
  Quelltexte und Binärdateien.
- **Git und Build**: Branch, Remote, Build-Befehl (z. B. `make`) und die Liste der Binärdateien (durch Komma getrennt).
- **Shell-Umgebung**: Pfad zu `ksh`, `ORACLE_HOME`, `LIBPATH`, `PATH` und weitere Variablen (`NAME=wert`) — eine nicht
  interaktive Shell liest `.profile` nicht, daher geben Sie hier an, was der Build braucht.

Zieldefinitionen werden ohne Geheimnisse gespeichert; **SSH-Ziele exportieren …** und **SSH-Ziele importieren …**
übertragen sie zwischen Computern. Auf dem Server sind keine Oracle-Passwörter nötig — Pro*C muss auf dem Server
eingerichtet sein.

### Ein Ziel testen

**Testen** (in der Verwaltung oder **Werkzeuge › Pro*C-Remote-Build › SSH-Ziel testen**) prüft: die Version des
SSH-Servers, die Anmeldung, das System (`uname -a`, auf AIX `oslevel -s`), die Verfügbarkeit von `make`, `git` und
`compress`/`gzip`, Branch und Sauberkeit der Working Copy (`git status --porcelain`) sowie die Schreibbarkeit der
Verzeichnisse. Ein fehlendes Backup-Verzeichnis legt Pelikan nach Ihrer Bestätigung an.

Beim ersten Test eines neuen Servers zeigt Pelikan den Fingerabdruck seines Schlüssels (SHA256) und speichert den
Schlüssel erst nach Ihrer Bestätigung in known_hosts – vergleichen Sie den Fingerabdruck mit dem Ihres Administrators.
Eine Bereitstellung auf einen Server mit unbestätigtem Schlüssel wird abgewiesen, ein Server mit geändertem Schlüssel
immer.

## Deployment

1. Öffnen Sie ein Projekt mit einem lokalen Git-Repository (Pelikan vergleicht es mit dem Server). Ohne Projekt
   funktioniert das Deployment, aber ohne Informationen über lokale Commits.
2. Wählen Sie **Werkzeuge › Pro*C-Remote-Build › Auf Ziel deployen …** und ein Ziel. Das Fenster zeigt eine
   **Zusammenfassung**: den Commit auf dem Server und im Remote, die auszurollenden Commits, `git diff --stat` und
   Warnungen — z. B. nicht gepushte lokale Commits oder ein Deployment eines Commits auf PROD, der nicht auf UAT war.
3. Bei einem **PROD**-Ziel müssen Sie zur Bestätigung den Namen des Ziels eingeben.
4. Klicken Sie auf **Deployen**.

Auf dem Server führt Pelikan nacheinander aus:

1. setzt eine **Sperre** (auf einem Ziel kann nur ein Deployment gleichzeitig laufen);
2. prüft Branch und Sauberkeit der Working Copy — manuelle Änderungen auf dem Server halten das Deployment vor `pull`
   an;
3. `git pull --ff-only`;
4. eine Sicherung der Binärdateien (mit Datum und Commit im Namen, mit `compress` oder `gzip` gepackt, mit begrenzter
   Anzahl von Kopien);
5. `make` (Build-Befehl);
6. die Installation der neuen Binärdateien (die vorherige Version bleibt als `.prev` erhalten);
7. einen Eintrag in der Deployment-Historie auf dem Server und in Pelikan.

## Deployment-Konsole

Die **Deployment-Konsole** zeigt die Schritte mit Zeit und Ergebnis sowie die Live-Ausgabe. Fehler des Pro*C-Compilers
(`PCC-…`, auch `PLS-…`) und des Compilers IBM XL C (`1506-…`) sind anklickbar — sie öffnen die Datei im lokalen
Repository in der Fehlerzeile. Die Option **Nur Fehler und Warnungen** filtert die Ausgabe, **Protokoll speichern …**
speichert sie in eine Datei.

**Werkzeuge › Pro*C-Remote-Build › Deployment anhalten** (oder **Stopp** in der Konsole) unterbricht den Build auf dem
Server (auch die von `make` gestarteten Prozesse) und hebt immer die eigene Sperre auf. Eine zurückgebliebene Sperre
eines anderen Deployments heben Sie manuell über **Zielsperre aufheben …** auf — nur wenn Sie sicher sind, dass gerade
niemand ausrollt (auf PROD nach Eingabe des Zielnamens).

## Zurücksetzen und Historie

- **Binärdatei zurücksetzen …** tauscht die aktuelle Binärdatei gegen die vorherige Version (`.prev`) oder stellt eine
  ausgewählte Sicherung wieder her (entpackt, mit den Rechten der aktuellen Binärdatei).
- **Deployment-Verlauf** zeigt die Deployments aus Pelikan (mit vollständigem Protokoll) und die auf dem Server
  gespeicherte Historie.
- **Git- und Deployment-Status** stellt zusammen: den lokalen Branch und nicht gepushte Commits, den Stand des Remote,
  das letzte Deployment aus der Historie und den Commit (HEAD) auf jedem Server. **git fetch und aktualisieren** holt
  den Stand des Remote ohne Rückfragen im Terminal.

## Dateikodierung

Quelltexte auf älteren Servern liegen oft in ISO-8859-2 vor. Pelikan erkennt die Kodierung vorhandener Dateien und
ändert sie nicht stillschweigend: Ein Zeichen, das sich in der Kodierung der Datei nicht speichern lässt, blockiert das
Speichern mit genauer Angabe der Stelle. Die Kodierung ändern Sie nur ausdrücklich (**Datei › Dateikodierung …**); ein
Projekt kann außerdem die Kodierung seiner Dateien vorgeben.
