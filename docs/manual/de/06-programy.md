# Program Window und Object Browser

## Object Browser

Ein Baum der Objekte des aktuellen Schemas (oder des im Filter gewählten) mit Ordnern nach Typ: Tabellen, Views, Pakete,
Typen, Trigger, Sequenzen und unter 23ai auch MLE-Module und Domains. Das Kontextmenü eines Objekts öffnet dessen
Quelltext, zeigt Beschreibung, DDL, Abhängigkeiten und Daten und ermöglicht es, das Objekt zu kompilieren oder zu
löschen. Ungültige Objekte sind gekennzeichnet.

## Program Window

Das Program Window bearbeitet PL/SQL-Code: Pakete (Spezifikation und Body auf getrennten Tabs), Prozeduren, Funktionen,
Typen und Trigger. **Ausführen** (F8) kompiliert den Code in der Datenbank, und Kompilierfehler erscheinen unter dem
Editor — ein Klick springt zur Zeile. Die Code-Gliederung (Code Contents) zeigt die Struktur der Einheit, und
**Zur Deklaration springen** führt zur Stelle, an der ein Bezeichner deklariert ist.

Der Editor schlägt Namen von Tabellen, Spalten, Paketen und deren Elementen vor, faltet Blöcke, hebt `BEGIN`/`END`-Paare
hervor, formatiert Code (**Formatierer**) gemäß den Einstellungen und führt einen lokalen Versionsverlauf der Datei.
Templates fügen fertige Codefragmente ein.

## Codeanalyse

Während Sie tippen, unterstreicht Pelikan unbekannte Tabellen, Spalten und Aliasse und weist auf Probleme hin: nicht
verwendete Variablen, Code nach `RETURN`, `UPDATE`/`DELETE` ohne `WHERE`, implizite Konvertierungen. **Find Usages**
sucht Verwendungen eines Objekts in der Datenbank und in den Projektdateien, und **Umbenennen** zeigt vor dem Anwenden
eine Vorschau der Änderungen.

## Dateien und Kodierung

Dateien behalten ihre Kodierung (UTF-8, ISO-8859-2, Windows-1250) und ihre Zeilenenden. Ein Zeichen, das sich in der
Kodierung der Datei nicht speichern lässt, verhindert das Speichern und wird genau angezeigt — die Kodierung kann nur
ausdrücklich geändert werden (**Datei › Dateikodierung**).
