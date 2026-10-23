# Test Window, debuger i utPLSQL

## Test Window

Test Window uruchamia blok PL/SQL ze zmiennymi wiązanymi, których wartości wpisujesz w tabeli pod blokiem. Po
wykonaniu tabela pokazuje wartości wyjściowe, a karty — DBMS_OUTPUT, statystyki i profil wykonania. Testy zapisuje się
w plikach `.tst`.

## Debuger

**Uruchom z debugowaniem** wykonuje test krokowo: **Wejdź** (wejście do podprogramu), **Przejdź** (następna linia),
**Wyjdź** (powrót z podprogramu), punkty przerwania (także warunkowe), podgląd i zmiana wartości zmiennych oraz stos
wywołań. Debuger wymaga uprawnień `DEBUG CONNECT SESSION` i `DEBUG ANY PROCEDURE` (albo `DEBUG` na obiekcie).

## Profiler

Profiler (DBMS_PROFILER albo DBMS_HPROF) mierzy czas wykonania każdej linii i podprogramu, a statystyki sesji pokazują
zmianę liczników podczas testu.

## utPLSQL

Eksplorator testów pokazuje pakiety testowe utPLSQL w bazie. Testy uruchomisz dla pakietu, zestawu albo całego schematu;
wyniki z czasem i komunikatami błędów pojawiają się w drzewie, a pokrycie kodu — w edytorze. Generator tworzy szkielet
pakietu testowego dla wybranego pakietu. Pelikan może też zainstalować utPLSQL w schemacie (po potwierdzeniu).
