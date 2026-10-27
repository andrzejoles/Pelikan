# Pelikan — nowości w wydaniach

Wydania stabilne od 1.0.0 (numeracja: D184). Historia bet 7.9.0–10.5.0: [`docs/BETA.md`](BETA.md).

## 1.0.0 — pierwsze wydanie stabilne

Pelikan wychodzi z bety. To natywne IDE dla Oracle SQL i PL/SQL na macOS (Apple Silicon): okna SQL, poleceń,
programu i testu z debugerem i profilerem, testy utPLSQL, przeglądarka i edytory obiektów, porównanie schematów,
raporty, notatniki SQL, narzędzia DBA oraz bezpieczne API MCP dla agentów AI. Interfejs po polsku, angielsku,
niemiecku, hiszpańsku i ukraińsku. Wersje 7.9–10.5 były testowane na prawdziwych bazach, także w próbie tylko do
odczytu na dużej bazie produkcyjnej (Oracle 19c).

Nowe od ostatniej bety (10.4.0):

- **Panele narzędzi** — okna narzędzi (Sesje, Znajdź obiekty, To-Do, instrukcja, edytory tabel, eksport, raporty
  i inne) otwierają się w panelu po prawej stronie okna głównego, każde w karcie. Kartę przeciągasz do panelu na dole
  albo poza panele (osobne okno); okno narzędzia wraca do panelu przyciskiem na pasku tytułu. Pelikan zapamiętuje
  miejsce każdego rodzaju narzędzia. Domyślne miejsce (także osobne okna jak dotąd) i autoukrywanie paneli ustawisz
  w **Preferencje › Ogólne › Panele narzędzi**, polecenia są w **Widok › Panele narzędzi**.
- **Numeracja wersji** — od 1.0.0 numer mówi, co się zmieniło: poprawki podnoszą ostatnią cyfrę, nowe funkcje
  środkową. Zainstalowane bety (10.x) zaktualizują się do 1.0.0 same.

Znane ograniczenia: Kerberos na macOS niedostępny (błąd adaptera Oracle w procesie z AppKit), logowanie Entra ID bez
próby na Azure, podgląd Quick Look wymaga notaryzacji, karty okien własne zamiast natywnych kart macOS — szczegóły
w [`docs/STATUS.md`](STATUS.md).
