# Testy utPLSQL

Pelikan ma wbudowaną obsługę utPLSQL — biblioteki testów jednostkowych dla PL/SQL: uruchamianie testów z wynikami na
żywo, pokrycie kodu, generowanie szkieletów testów i nawigację między pakietem a jego testami. Komendy są w menu
**Narzędzia › utPLSQL**.

## Instalacja utPLSQL w bazie

**Narzędzia › utPLSQL › utPLSQL: wersja w bazie** sprawdza, czy utPLSQL jest zainstalowany i w jakiej wersji.

Jeśli go nie ma, **utPLSQL: instaluj lub aktualizuj…** pobierze oficjalne wydanie z GitHuba, sprawdzi jego sumę
kontrolną i wykona skrypty instalacyjne w widocznym oknie poleceń. Ta komenda działa tylko na połączeniach
deweloperskich i testowych i zawsze pyta o potwierdzenie. Nowy właściciel utPLSQL dostaje losowe hasło, którego nikt
nie zna, a jego konto jest od razu blokowane. Na bazach współdzielonych instalację zwykle wykonuje administrator.

## Pisanie testów

- **utPLSQL: generuj pakiet testowy** — gdy kursor jest w pakiecie (albo pakiet jest zaznaczony w Przeglądarce
  obiektów), otwiera okno programu ze szkieletem pakietu testowego: suita i po jednym teście na każdą procedurę i
  funkcję, z `ut.fail` do uzupełnienia. Szkielet kompiluje się i uruchamia od razu.
- Okno szablonów ma folder **utPLSQL** z szablonami pakietu testowego, testu, oczekiwanego wyjątku, kontekstu,
  oczekiwań i porównania kursorów.
- Podpowiedź kodu zna adnotacje (po `--%`) i matchery (po `ut.expect(…).`).
- Przy kompilacji specyfikacji pakietu testowego Pelikan ostrzega o nieznanych adnotacjach, procedurach wskazanych w
  `--%beforeall`, `--%aftereach` itp., których nie ma w specyfikacji, `--%test` bez `--%suite` i niesparowanych
  `--%context`/`--%endcontext`.
- **utPLSQL: przejdź do testu / testowanego pakietu** (⌃⌘T) przełącza między pakietem a jego pakietem testowym (według
  nazwy `test_nazwa` albo zależności).

## Uruchamianie testów

| Komenda | Skrót (macOS) | Co uruchamia |
|---|---|---|
| utPLSQL: uruchom wszystkie testy | ⇧⌘U | wszystkie testy bieżącego użytkownika |
| utPLSQL: uruchom test pod kursorem | ⌃⌘U | procedurę testową pod kursorem albo cały pakiet testowy |
| utPLSQL: uruchom testy ze ścieżki… | — | ścieżki `schemat.pakiet.procedura` albo `schemat:ścieżka.suity`, kilka po przecinku |
| utPLSQL: uruchom z opcjami… | — | ścieżki, pokrycie, schematy pokrycia, obiekty uwzględniane i pomijane |
| utPLSQL: uruchom ponownie nieudane | — | testy, które nie przeszły w ostatnim przebiegu |
| utPLSQL: przerwij | — | trwający przebieg |

W profilu PL/SQL Developer skróty to ⌃⇧U (wszystkie), ⌃⌥U (pod kursorem) i ⌃⇧T (przejście do testu). Testy
zaznaczonego pakietu, procedury albo użytkownika uruchomisz też przez **Narzędzia › Obiekt › Uruchom testy utPLSQL**.

## Eksplorator testów

**Widok › Eksplorator testów utPLSQL** pokazuje drzewo suit, kontekstów i testów bieżącego użytkownika z wynikiem
ostatniego przebiegu. Drzewo odświeża się po kompilacji; dwuklik na teście otwiera jego adnotację w specyfikacji.
Zaznaczone testy uruchomisz przyciskiem **Uruchom** albo **Uruchom z pokryciem**.

## Okno wyników

Wyniki pojawiają się na żywo: pasek postępu, liczniki i nazwa bieżącego testu. Testy wykonują się w osobnych sesjach,
więc okna Pelikana pozostają dostępne.

- Drzewo suit, kontekstów i testów z czasami i stanami: **Sukces**, **Niepowodzenia**, **Błędy**, **Wyłączone**.
  **Pokaż:** filtruje według stanu, **Sortuj:** zmienia kolejność (kolejność wykonania, nazwa, czas, stan).
- Szczegóły testu: komunikat oczekiwania, **Oczekiwane** i **Otrzymane** obok siebie z wyróżnieniem różnic (także
  wiersze kursorów), **Stos błędu** z przejściem do linii, DBMS_OUTPUT testu i **Otwórz źródło testu**.
- Menu testu pozwala uruchomić pojedynczy test ponownie, a **Ponownie nieudane** — wszystkie nieudane.
- **Historia** przechowuje 20 ostatnich przebiegów; **Zmiany** pokazuje, które testy zmieniły stan względem
  poprzedniego przebiegu.

## Pokrycie kodu

**utPLSQL: testy z pokryciem kodu** (albo **Uruchom z pokryciem**) zbiera pokrycie dla bieżącego schematu; w oknie
**uruchom z opcjami…** wskażesz inne schematy oraz obiekty uwzględniane i pomijane.

- W oknie programu linie są oznaczone na marginesie: zielone — pokryte, żółte — częściowo, czerwone — niepokryte.
- Pasek stanu pokazuje procent pokrycia obiektu i schematu.
- **Raport pokrycia** otwiera raport HTML utPLSQL w przeglądarce.

Pokrycie korzysta z danych profilera — przed pierwszym takim przebiegiem w sesji Pelikan przypomina o wymaganych
uprawnieniach.

## Debugowanie testu

**Debugowanie › utPLSQL: debuguj test pod kursorem** otwiera okno testu z wywołaniem `ut.run` dla tego testu, ustawia
punkt przerwania w procedurze testowej i uruchamia debuger (zobacz rozdział *Okno testu, debuger i profiler*).

## Wyniki dla CI

- **utPLSQL: eksport wyników…** uruchamia testy z reporterem JUnit, Sonar, TeamCity albo TAP (albo z raportem pokrycia
  Cobertura, Sonar, HTML) i zapisuje wynik do pliku.
- **utPLSQL: skrypt dla wiersza poleceń** tworzy skrypt SQL*Plus/SQLcl uruchamiający te same testy z wynikiem JUnit
  oraz skrypt powłoki. Skrypty nie zawierają hasła — podasz je w CI z własnego magazynu sekretów.
