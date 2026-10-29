# Agenci AI

Pelikan pozwala pracować z agentem AI uruchomionym w terminalu wbudowanym w okno — np. Claude Code — który widzi Twoje
okna i bazę wyłącznie przez narzędzia Pelikana i na zasadach, które kontrolujesz. Agent może czytać kod i dane,
analizować plany, pisać i formatować kod w oknach, a zmiany w bazie wykonuje dopiero po Twojej zgodzie.

## Obsługiwane programy

| Agent | Polecenie | Jak dostaje serwer MCP Pelikana |
|---|---|---|
| Claude Code | `claude` | `--mcp-config` tylko dla tej sesji |
| Codex CLI | `codex` | `-c mcp_servers…` tylko dla tej sesji |
| Grok CLI | `grok` | zmienna `GROK_CONFIG` tylko dla tej sesji |
| Antigravity | `agy` | jednorazowa rejestracja serwera „pelikan” — tylko po Twojej zgodzie |

Program agenta instalujesz sam i logujesz się w nim na swoje konto dostawcy. Pelikan szuka polecenia w ścieżce `PATH`
Twojej powłoki logowania. Listę programów zmienisz w **Ustawienia › Agenci** (**Dodaj CLI**, **Przywróć domyślne**).

Serwer MCP Pelikana jest dostępny tylko dla sesji uruchomionej z Pelikana: komunikacja idzie przez gniazdo Unix
dostępne wyłącznie dla Twojego konta (bez portów sieciowych), a każda sesja ma własny, jednorazowy token przekazywany
programowi w środowisku i unieważniany po zakończeniu sesji. Antigravity nie pozwala podać serwera na jedną sesję,
dlatego Pelikan pyta o zgodę na stałą rejestrację; poza sesjami uruchomionymi z Pelikana zarejestrowany serwer odrzuca
każde połączenie.

## Uruchamianie agenta

1. Wybierz **Narzędzia › Agent AI › Uruchom Claude Code** (albo inny program).
2. Pojawi się **macierz uprawnień sesji**: lista narzędzi z poziomem dostępu. Możesz obniżyć poziom wybranych narzędzi
   albo kliknąć **Wszystko tylko do odczytu**. Podnieść poziomu nie można. Kliknij **Uruchom**.
3. Po prawej stronie okna otworzy się **panel agenta** z terminalem programu. Pracujesz z agentem jak w zwykłym
   terminalu.

Katalogiem roboczym agenta jest folder pliku aktywnego okna (np. projektu), a gdy okno nie ma pliku — tymczasowy
katalog sesji. Panel pokażesz i ukryjesz przez **Widok › Panel agenta**.

![Panel agenta po prawej stronie okna głównego](../img/panel-agenta.png)

Pod terminalem panel pokazuje **aktywność agenta**: każde wywołanie narzędzia z czasem, stanem (w toku, zatwierdzone,
odrzucone, błąd) oraz parametrami i wynikiem, a także licznik próśb czekających na zgodę. Przyciski: **Cofnij
sesję…**, **Zakończ** i **Dziennik**.

## Poziomy dostępu

Każda komenda Pelikana ma poziom dostępu agenta:

- **Brak** — agent nie widzi tej funkcji;
- **Odczyt** — agent widzi stan albo wynik, niczego nie zmienia;
- **Za zgodą** — agent zgłasza operację, a Ty ją zatwierdzasz po obejrzeniu podglądu;
- **Pełny** — agent wykonuje operację bez pytania, ale tylko taką, którą da się cofnąć (np. zmiana tekstu w oknie), i
  wszystko trafia do dziennika.

Obowiązuje najniższy z poziomów: komendy, macierzy sesji i połączenia. Na połączeniu **tylko do odczytu** albo bez
zgody na zmiany (karta **Agent AI** definicji połączenia) agent ma najwyżej **Odczyt**. Na połączeniach produkcyjnych
zgoda na zmiany jest domyślnie wyłączona.

Narzędzia agenta w skrócie:

- **Odczyt**: lista połączeń (tylko aliasy), stan okien i treść edytora, wyszukiwanie i opis obiektów, źródła, DDL,
  zależności i użycia, zapytania, plan wykonania, błędy kompilacji, DBMS_OUTPUT, testy utPLSQL i ich wyniki, pokrycie,
  lista sesji;
- **Pełny** (cofane): otwarcie obiektu albo nowego okna, wstawienie i zamiana tekstu, formatowanie, przejście do
  linii;
- **Za zgodą**: kompilacja, wykonanie polecenia i skryptu, COMMIT, ROLLBACK, utworzenie i wygenerowanie pakietu
  testowego, uruchomienie testów utPLSQL, instalacja utPLSQL.

Agent **nie ma** dostępu do okna poleceń i polecenia HOST, powłoki systemu przez Pelikana, debugera, okna Sesje (poza
odczytem listy sesji) i kończenia sesji, SQL Trace, raportów AWR/ASH/ADDM, SQL Monitor i SQL Tuning Advisor, zdalnego
buildu Pro*C, narzędzi użytkownika ani do haseł, hostów, portów i nazw użytkowników połączeń.

## Okno zgody

Gdy agent chce zmienić bazę, Pelikan pokazuje okno **Zgoda na operację agenta** z pełnym podglądem: polecenia,
obiekty, na które wpływa (z tabelami, wyzwalaczami i obiektami zależnymi), szacowaną liczbę wierszy, plan wykonania i
argumenty. Gdy zmiany nie da się cofnąć (COMMIT, DDL na tabeli), okno mówi to wprost czerwonym ostrzeżeniem.

![Okno zgody na operację agenta](../img/zgoda-agenta.png)

Okno jest zaprojektowane tak, żeby nie zatwierdzić niczego przypadkiem:

- nie ma przycisku domyślnego — ↩ (np. naciśnięty podczas pisania w terminalu agenta) niczego nie zatwierdza;
- **Zezwól** staje się aktywny dopiero po 0,8 sekundy;
- Esc odrzuca prośbę (**Odmów**);
- kolejne prośby czekają w kolejce, aż rozpatrzysz bieżącą.

## Transakcje i cofanie

- Agent ma **własne sesje bazy** — nie widzi Twojej niezatwierdzonej transakcji i nie może jej zatwierdzić. W
  V$SESSION jego sesje mają MODULE „Pelikan agent”, a ACTION — nazwę narzędzia.
- Zapytania agenta wykonują się w transakcji tylko do odczytu, z limitami liczby wierszy, czasu i rozmiaru wyniku
  (**Ustawienia › Agenci › Zapytania agenta**; domyślnie 500 wierszy, 30 s i 1 MB) oraz limitem wywołań na minutę.
  Zapytanie musi być jednym poleceniem SELECT/WITH, bez `FOR UPDATE` i bez funkcji zdefiniowanych w klauzuli WITH.
- **DML agenta zostaje niezatwierdzone**, dopóki nie zgodzisz się osobno na COMMIT. Zamknięcie sesji agenta wycofuje
  niezatwierdzone zmiany (ROLLBACK). DDL agenta jest odrzucane, gdy agent ma niezatwierdzone DML (DDL zatwierdziłoby
  je niejawnie).
- Bloki PL/SQL i `CALL` agenta też są odrzucane przy niezatwierdzonym DML — mogłyby je zatwierdzić (COMMIT w kodzie,
  DDL dynamiczne, transakcje autonomiczne). Okno zgody ostrzega, że bloku PL/SQL nie da się cofnąć. Okno poleceń jest
  dla agenta niedostępne: nie odczyta ani nie zmieni jego tekstu.
- Przed zmianą kodu obiektu (pakiet, procedura, widok…) Pelikan zapisuje poprzednią wersję. **Narzędzia › Agent AI ›
  Cofnij sesję agenta…** (albo **Cofnij sesję…** w panelu) przywraca kod obiektów sprzed sesji, usuwa obiekty
  utworzone przez agenta, cofa zmiany tekstu w oknach i zamyka okna otwarte przez agenta. Obiekt zmieniony później
  przez kogoś innego to konflikt — jest pomijany, chyba że wybierzesz **Cofnij z wymuszeniem**. Zmian zatwierdzonych
  (COMMIT) i DDL na tabelach nie da się cofnąć.
- **Narzędzia › Agent AI › Zakończ sesję agenta** kończy program agenta, unieważnia token, wycofuje niezatwierdzone
  zmiany agenta i zamyka jego sesje bazy.

## Ustawienia połączenia dla agenta

Karta **Agent AI** w definicji połączenia:

- **Agent widzi to połączenie (tylko alias i środowisko)** — wyłącz, żeby ukryć połączenie przed agentem.
- **Agent może zmieniać dane i obiekty (za zgodą)** — domyślnie wyłączone dla środowiska produkcyjnego.
- **Osobny użytkownik bazy dla agenta** — agent łączy się przez proxy `główny[agent]` jako użytkownik z ograniczonymi
  uprawnieniami (np. tylko SELECT). Administrator musi nadać `ALTER USER agent GRANT CONNECT THROUGH główny`; drugie
  hasło nie jest potrzebne. Zalecane dla produkcji.
- **Kolumny maskowane dla agenta** — nazwy kolumn (np. `PESEL, EMAIL`) albo `SCHEMAT.TABELA.KOLUMNA`. Wartości są
  maskowane w wynikach, a zapytania odwołujące się do tych kolumn — odrzucane.

Pamiętaj: wszystko, co agent przeczyta (kod, wyniki zapytań), trafia do dostawcy modelu AI. Maskowanie działa po
nazwie kolumny i jest ułatwieniem, a nie granicą bezpieczeństwa — kolumnę można odczytać np. przez widok z inną nazwą.
Prawdziwą granicą są uprawnienia użytkownika bazy, z którego korzysta agent. Funkcje wywoływane w zapytaniach mogą
mieć skutki uboczne (np. transakcje autonomiczne) — także przed tym chronią tylko uprawnienia.

## Tryb ścisły

**Ustawienia › Agenci › Tryb ścisły** (domyślnie włączony) uruchamia program agenta bez jego własnej powłoki i edycji
plików — tylko z narzędziami Pelikana, o ile dany program na to pozwala. Gdy nie pozwala, panel agenta pokazuje
ostrzeżenie. Program agenta w trybie pełnym działa z uprawnieniami Twojego konta macOS — Pelikan ostrzega, ale go nie
ogranicza.

## Dziennik agentów

Każde wywołanie narzędzia — także odrzucone — trafia do dziennika (pliki JSONL w katalogu danych Pelikana, bez tokenu
i haseł). **Narzędzia › Agent AI › Dziennik agentów…** (albo **Dziennik** w panelu) otwiera przeglądarkę dziennika z
czasem, narzędziem, decyzją oraz argumentami i wynikiem.
