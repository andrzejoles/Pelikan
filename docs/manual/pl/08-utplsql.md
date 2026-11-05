# Testy utPLSQL

## Do czego to służy

**Test jednostkowy** to mały program, który wywołuje Twój kod i sprawdza, czy wynik jest taki, jak oczekiwany — np.
„po podwyżce o 10% pensja 9500 wynosi 10450”. Testy uruchamiasz po każdej zmianie: jeśli coś zepsułeś, test od razu to
pokaże, zanim błąd trafi do użytkowników. **utPLSQL** to najpopularniejsza biblioteka testów dla PL/SQL: testy pisze
się jako pakiety z komentarzami-adnotacjami (`--%suite`, `--%test`), a sprawdzenia — wywołaniami
`ut.expect(…).to_equal(…)`. utPLSQL automatycznie wycofuje zmiany danych zrobione przez test, więc testy nie psują
danych.

**Kiedy użyć:** dla każdego pakietu z logiką biznesową. Dobry zwyczaj: najpierw test, który pokazuje błąd, potem
poprawka, po której test przechodzi.

Pelikan ma wbudowaną obsługę utPLSQL — biblioteki testów jednostkowych dla PL/SQL: uruchamianie testów z wynikami na
żywo, pokrycie kodu, generowanie szkieletów testów i nawigację między pakietem a jego testami. Komendy są w menu
**Narzędzia › utPLSQL**.

## Instalacja utPLSQL w bazie

**Narzędzia › utPLSQL › utPLSQL: wersja w bazie** sprawdza, czy utPLSQL jest zainstalowany i w jakiej wersji.

Jeśli go nie ma, **utPLSQL: instaluj lub aktualizuj…** pobierze oficjalne wydanie z GitHuba, sprawdzi jego sumę
kontrolną i wykona skrypty instalacyjne w widocznej konsoli SQL*Plus. Ta komenda działa tylko na połączeniach
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

> **Ćwiczenie: uruchom testy pakietu ćwiczeniowego.**
>
> Wymaga utPLSQL w bazie (sprawdź **utPLSQL: wersja w bazie**) i pakietu `PEL_EMP_API_TEST` ze skryptu w rozdziale 1.
>
> 1. W Przeglądarce obiektów otwórz **Edytuj** na pakiecie **PEL_EMP_API_TEST** i obejrzyj specyfikację.
>    *Wynik:* adnotacja `--%suite` nazywa zestaw testów, każda `--%test` — jeden test, a `--%throws(-20001)` mówi, że
>    test ma się zakończyć tym błędem.
> 2. Postaw kursor w specyfikacji i naciśnij **⌃⌘U** (uruchom test pod kursorem).
>    *Wynik:* otwiera się okno wyników z paskiem postępu; trzy testy na zielono — **Sukces**.
> 3. W ciele testu zmień oczekiwaną wartość w `raise_salary_ten_percent` z `10450` na `10000` i skompiluj (F8).
> 4. Uruchom testy jeszcze raz (**⌃⌘U**).
>    *Wynik:* jeden test na czerwono (**Niepowodzenia**). W szczegółach testu: **Oczekiwane** 10000, **Otrzymane**
>    10450 — od razu widać, co się nie zgadza.
> 5. Przywróć `10450`, skompiluj i uruchom **Ponownie nieudane**.
>    *Wynik:* wszystko na zielono.
> 6. Sprawdź w oknie SQL `SELECT salary FROM pel_employees WHERE emp_id = 2;`.
>    *Wynik:* 9500 — utPLSQL wycofał podwyżkę zrobioną przez test.
>
> **Ćwiczenie: test dla nowej funkcji.** Jeśli w rozdziale 6 dopisałeś funkcję `department_name`, dopisz do pakietu
> testowego test (deklaracja w specyfikacji z `--%test(…)` i procedura w ciele) z
> `ut.expect(pel_emp_api.department_name(2)).to_equal('Informatyka');` i uruchom go.

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
ostatniego przebiegu. Drzewo odświeża się po kompilacji; dwukrotne kliknięcie testu otwiera jego adnotację w specyfikacji.
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

**Jak czytać pokrycie:** czerwone linie to kod, którego żaden test nie wykonał — błąd w nim nie zostanie wykryty.
Pokrycie 100% nie znaczy, że kod jest bezbłędny, ale niskie pokrycie znaczy, że testy sprawdzają niewiele. Uruchom
testy `PEL_EMP_API_TEST` z pokryciem i otwórz ciało `PEL_EMP_API`: procedury `hire` i `print_department` będą
czerwone — nie mają testów.

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
