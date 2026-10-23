# KI-Agenten

Pelikan stellt KI-Agenten, die im Terminal laufen (Claude Code, Codex, Grok, Antigravity), Werkzeuge über einen
MCP-Server bereit, der nur für die jeweilige Sitzung erreichbar ist. Der Agent arbeitet im **Agentenbereich** neben den
Fenstern.

## Sicherheitsregeln

- Der Agent sieht Verbindungen nur unter ihrem Namen (Alias) — niemals Passwörter, Adressen oder Benutzernamen.
- Der Agent hat eine **eigene Datenbanksitzung** (in V$SESSION gekennzeichnet), optional über einen Proxy-Benutzer mit
  eingeschränkten Berechtigungen. Abfragen führt er in einer schreibgeschützten Transaktion aus, mit Zeilen- und
  Zeitlimits.
- Änderungen (DML, DDL, Kompilierung) erfordern **Ihre Zustimmung** in einem Zustimmungsdialog mit Vorschau des Befehls
  und der betroffenen Objekte. DML bleibt nicht festgeschrieben, bis Sie einem COMMIT zustimmen.
- Auf Produktionsverbindungen hat der Agent nur Lesezugriff. Der Agent hat keinen Zugriff auf das Command Window,
  Betriebssystembefehle, den Debugger oder AWR/ASH-Berichte.
- Ausgewählte Spalten können in den Ergebnissen für den Agenten maskiert werden.
- **Agentensitzung rückgängig machen** setzt die vom Agenten geänderten Objekte auf den Stand vor den Änderungen zurück
  (mit Konflikterkennung).

Berechtigungen, die Liste der Programme und das Aktivitätsprotokoll finden Sie unter **Einstellungen › Agenten**.
