# Pro*C: Remote-Build über SSH

Pelikan baut Pro*C-Programme auf einem Server (z. B. AIX) über SSH: Es holt Änderungen aus dem Git-Repository in die
Working Copy auf dem Server, führt `make` aus, installiert die Binärdateien und führt eine Deployment-Historie mit
Rückrollmöglichkeit.

## SSH-Ziele

Unter **SSH-Ziele** definieren Sie einen Server: Host, Port, Benutzer, Authentifizierung (Schlüssel, SSH-Agent oder
Passwort), Kodierung, Umgebung (ORACLE_HOME, LIBPATH, PATH), Basisverzeichnis, Backup-Verzeichnis, Branch und
Build-Befehl. Das SSH-Passwort oder die Schlüssel-Passphrase landet im Schlüsselbund, und die Zieldefinitionen werden
ohne Geheimnisse gespeichert. Ziele kennzeichnen Sie als UAT oder PROD.

**Testen** prüft die Anmeldung, die Version des Systems und des SSH-Servers, die Verfügbarkeit von `make`, `git`,
`compress`/`gzip`, den Branch und den sauberen Zustand der Working Copy sowie die Beschreibbarkeit der Verzeichnisse.

## Deployment

Ein Deployment führt nacheinander aus: Sperre (jeweils nur ein Deployment), Prüfung der Working Copy (manuelle
Änderungen auf dem Server halten das Deployment an), `git pull --ff-only`, Sicherung der Binärdateien, `make`,
Installation und Eintrag in die Historie. Pelikan führt auf dem Server niemals Merge oder Reset aus. Vor einem
Deployment auf PROD müssen Sie den Namen des Ziels eingeben.

Die Konsole zeigt die Schritte mit Dauer und Ergebnis; Fehler des Pro*C-Compilers (`PCC-…`) und von IBM XL C (`1506-…`)
sind anklickbar und öffnen die Datei an der Fehlerstelle. **Stopp** bricht das Deployment ab und hebt die Sperre immer
auf. **Zurückrollen** stellt die vorherigen Binärdateien oder eine ausgewählte Sicherung wieder her.
