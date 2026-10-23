# ADR 0006 — Debuger PL/SQL: DBMS_DEBUG w dwóch sesjach, JDWP jako druga ścieżka

Stan: przyjęty 2026-10-23.

## Kontekst
Etap 3 wymaga debugera jak we wzorcu (UG 5.10): Start/Run, Step into (także do wyzwalacza), Step over, Step out,
Run to cursor, punkty przerwania z warunkami i licznikiem, przerwanie na wyjątku, stos wywołań, zmienne lokalne i
globalne z rekordami, kolekcjami i obiektami, `:old`/`:new`, obserwowane wyrażenia. Baza testowa (Oracle Free 26ai)
ma pakiety `DBMS_DEBUG` (oznaczony jako przestarzały, ale dostępny i używany przez narzędzia klasy PL/SQL Developer)
oraz `DBMS_DEBUG_JDWP` (SQL Developer). Agent nie ma dostępu do debugera (PROMPT §7).

## Opcje
1. **DBMS_DEBUG** — dwie sesje: docelowa (`INITIALIZE` → identyfikator, `DEBUG_ON`, wykonanie bloku) i nadzorująca
   (`ATTACH_SESSION`, `SYNCHRONIZE`, `CONTINUE` z flagami kroku, `SET_BREAKPOINT`, `GET_VALUE`, `PRINT_BACKTRACE`,
   `GET_INDEXES` dla kolekcji, `SET_OER_BREAKPOINT`). Całość przez zwykłe wywołania PL/SQL w sterowniku.
2. **DBMS_DEBUG_JDWP** — baza łączy się do klienta przez protokół JDWP (Pelikan musiałby nasłuchiwać na porcie TCP,
   a baza mieć ACL `jdwp`); bogatszy model (wątki, obiekty), ale wymaga konfiguracji sieci i uprawnień po stronie bazy.

## Decyzja
Opcja 1 jako podstawa (działa w każdej bazie bez ACL i bez otwierania portu na komputerze użytkownika), z warstwą
`DebuggerEngine` niezależną od protokołu, żeby JDWP (opcja 2) mógł dojść później jako drugi „transport”.
Sesja docelowa to sesja okna testowego; sesja nadzorująca — osobna sesja tego samego połączenia. Wykonanie bloku w
sesji docelowej jest asynchroniczne (wywołanie trwa do końca programu), a nadzorująca obsługuje zdarzenia w pętli
`SYNCHRONIZE`/`CONTINUE`. Przed uruchomieniem jednostki są kompilowane z informacją debugowania (`COMPILE DEBUG` /
`PLSQL_OPTIMIZE_LEVEL`), za zgodą użytkownika na produkcji. Wartości złożone (rekordy, kolekcje, obiekty) czytane są
przez `GET_VALUE` po nazwach pól i indeksach z `GET_INDEXES`, budując drzewo w modelu zmiennych.

## Konsekwencje
- Debuger nie wymaga zmian sieci ani ACL; potrzebne uprawnienie `DEBUG CONNECT SESSION` (i `DEBUG ANY PROCEDURE`
  dla cudzych obiektów) — komunikat z instrukcją, gdy brak.
- `DBMS_DEBUG` jest przestarzały: przy jego usunięciu z przyszłych wersji Oracle ścieżką zastępczą jest JDWP;
  wykrywanie dostępności pakietu przy starcie sesji debugowania.
- Testy integracyjne debugera działają na bazie testowej (krokowanie przez pakiet z wyzwalaczem, rekord, kolekcja).
