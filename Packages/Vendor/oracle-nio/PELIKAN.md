# OracleNIO w Pelikanie — kopia z poprawkami

Źródło: [lovetodream/oracle-nio](https://github.com/lovetodream/oracle-nio), commit
`7cda9e0c416a0cb21acf070ba70ce4ff575121b0` (2026-09-29, „Add data processing benchmarks and improve numeric parsing
(#126)”), licencja Apache 2.0 (`LICENSE`, `NOTICE.txt`, `CONTRIBUTORS.md`). Kopia od D239: poprawki dekodera i protokołu,
których nie ma w wydaniach biblioteki (stan `main` z 2026-11-07 — bez zmian w tych miejscach).

Zakres kopii: cele `OracleNIO` i `_OracleConnectionPoolModule` (`Sources/`, bez dokumentacji DocC); manifest bez makr
(swift-syntax), serwera testowego, testów i benchmarków. Ostrzeżenia kompilatora kodu biblioteki wyciszone (`-suppress-warnings`), jak przy
zależności zdalnej; zmienione pliki są bez ostrzeżeń. Każdy zmieniony plik ma w nagłówku wiersz „Zmienione dla Pelikana”,
a zmienione miejsca — komentarz „Pelikan:”.

## Zmiany

| Plik | Zmiana | Wcześniej |
|---|---|---|
| `Messages/OracleBackendMessage+RowData.swift` | INTERVAL YEAR TO MONTH, UROWID (fizyczny i logiczny, także ponad 253 bajty) i BFILE (lokator bez rozmiaru i porcji — jak `read_lob_with_length` w python-oracledb) w danych wiersza; inny nieobsługiwany typ — błąd dekodowania | `fatalError` — koniec procesu |
| `Messages/DescribeInfo.swift` | Nieobsługiwany typ kolumny (np. REF) — błąd dekodowania | wyjątek innego rodzaju → `preconditionFailure` w dekoderze |
| `Messages/Coding/OracleBackendMessageDecoder.swift` | Każdy nieoczekiwany błąd dekodowania zamyka połączenie z opisem | `preconditionFailure` |
| `Extensions/ByteBuffer/ByteBuffer+UB.swift`, `+SB.swift` | Liczby UB i SB dowolnej długości 0–8 bajtów, SB ze znakiem w bajcie długości (jak python-oracledb) | długości 3, 5–7 kończyły proces; znak gubiony; 200 czytane jako −56, rozmiar LOB-a 40 000 — ujemny |
| `Data/LOB.swift`, `Constants.swift` | LOB typu BFILE z danych wiersza; `open`/`close` dla BFILE jako FILE_OPEN (tylko odczyt) i FILE_CLOSE; publiczne `read(offset:amount:on:)` | BFILE nieobsługiwany; odczyt tylko od początku |
| `OracleChannelHandler.swift` | Kontekst operacji na LOB-ie czyszczony także po błędzie serwera | odpowiedź następnego polecenia czytana jako odpowiedź LOB-a — koniec procesu albo zawieszenie (np. brak pliku BFILE) |
| `ConnectionStateMachine/StatementStateMachine.swift`, `ConnectionStateMachine.swift`, `OracleChannelHandler.swift` | Zamknięcie niepełnego wyniku bez znacznika przerwania: dobierane jest tylko pobieranie w drodze, kursor zamykany z następnym poleceniem (jak python-oracledb przy zamknięciu kursora) | znacznik trafiający na pobieranie w drodze zawieszał sesję; kursor zostawał otwarty na serwerze (ORA-01000 po ~300 zamkniętych wynikach) |
| `OracleRowStream.swift`, `StatementStateMachine.swift`, `OracleChannelHandler.swift` | Pusty wynik zapytania z opisem kolumn | brak kolumn — siatka bez nagłówków, „Edit data” pustej tabeli bez wierszy do wstawienia |
| `ConnectionStateMachine.swift`, `OracleChannelHandler.swift` | Błąd w trakcie polecenia: stan polecenia zapisany; błąd zrywający połączenie zamyka je (po nieczytelnej odpowiedzi — gniazdo bez wylogowania); błąd dekodowania z przyczyną | zmieniana kopia stanu → `preconditionFailure`; wylogowanie na rozsynchronizowanym połączeniu wisiało |
| `Connection/OracleConnection.swift`, `Data/LOB.swift` | Zadanie do zamkniętego kanału kończy się od razu błędem | zapis przepadał bez śladu — wywołujący czekał bez końca (np. ROLLBACK po zerwanym połączeniu) |

Ograniczenie biblioteki bez zmian: połączenie obsługuje jedno polecenie naraz, a strumień wierszy zapytania zajmuje je
do wyczerpania. Sterownik Pelikana szereguje więc operacje sesji i przed każdą inną dobiera otwarty strumień do bufora
(D240, `ThinSession.settle`).

## Aktualizacja do nowszej wersji

1. Porównać pliki z tabeli z nowym wydaniem (`git diff 7cda9e0 <nowy> -- <plik>` w klonie biblioteki).
2. Skopiować nowe `Sources/OracleNIO` i `Sources/OracleConnectionPoolModule`, przenieść zmiany oznaczone „Pelikan:” (te,
   których biblioteka nie przejęła), uzupełnić manifest o nowe zależności.
3. `make test` z bazą testową — testy sterownika thin (`ThinDriverTests.swift`) sprawdzają każdą zmianę z tabeli.
