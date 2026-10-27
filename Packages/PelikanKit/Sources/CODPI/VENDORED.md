ODPI-C v26.0.0 (https://github.com/oracle/odpi, tag v26.0.0) — źródła bez zmian.
Licencja: UPL 1.0 lub Apache 2.0 (LICENSE.txt). Instant Client ładowany dynamicznie w czasie działania (dlopen).

Ostrzeżenia kompilatora C są wyciszone (`-Wno-everything` w Package.swift — kod dostawcy, bez zmian). Znane zgłoszenia
Clang Static Analyzer (`xcodebuild analyze`, v26.0.0), najpewniej fałszywe alarmy (ścieżki nieosiągalne przy poprawnej
odpowiedzi OCI) — nie poprawiamy ich lokalnie:
- `dpiVar.c:702`, `dpiVar.c:819` — `objectIndicator` może być NULL (core.NullDereference);
- `dpiStmt.c:287` (`typeInfo`), `dpiStmt.c:992` — core.NullDereference;
- `dpiObject.c:621`, `:926`, `:958` — niezainicjalizowany argument wywołania (core.CallAndMessage).
Przy aktualizacji ODPI-C: porównać wynik `analyze` z tą listą; nowe zgłoszenia przejrzeć przed scaleniem.
