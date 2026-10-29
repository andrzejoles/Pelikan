# Glosariusz nazewnictwa interfejsu (pl)

Słownik przyjętych polskich nazw w interfejsie Pelikana: pojęcie → nazwa w Pelikanie → uzasadnienie i źródło.
Obowiązuje przy dodawaniu nowych tekstów (D195). Krótszy słownik dla użytkownika z odpowiednikami w PL/SQL
Developerze: [`docs/GLOSSARY.md`](../GLOSSARY.md).

Źródła: **macOS** — polska lokalizacja systemu i aplikacji Apple (Finder, TextEdit, Xcode) oraz Apple HIG;
**VS** — Visual Studio / VS Code po polsku (terminologia Microsoft); **JB/Eclipse** — polskie wersje JetBrains
i Eclipse (Babel); **Oracle** — polska terminologia baz danych i Oracle; **git** — git-gui i TortoiseGit po polsku.

## Zasady

1. **Czynności w trybie rozkazującym**, pierwsze słowo wielką literą (jak w polskim macOS): „Odśwież plan”,
   „Zamień na wielkie litery”, „Przełącz punkt przerwania” — nie rzeczowniki („Odświeżanie”, „Wielkie litery”).
   Rzeczownik zostaje przy przełącznikach z ptaszkiem w menu (np. „Zawijaj wiersze”, „Podstawianie zmiennych”) i przy
   nazwach okien/narzędzi otwieranych komendą („Generator danych…”, „Eksport tabel…”).
2. **Wielokropek „…”** tylko wtedy, gdy czynność otwiera okno z pytaniem albo wyborem przed wykonaniem (HIG).
3. **Ta sama czynność — ta sama nazwa** w menu, na wstążce, w palecie, na przyciskach i w instrukcji. Etykieta na
   wstążce może być krótsza („Zapisz zmiany (Post)” przy „Zapisz zmiany w bazie (Post)”), ale nie innym słowem.
4. **Panele i okna Pelikana po polsku**, tak jak w menu Widok: Przeglądarka obiektów, Przeglądarka plików, Zawartość
   kodu, Okno SQL, Okno poleceń. Nazwa angielska wzorca tylko jako słowo kluczowe wyszukiwania komend.
5. **Nazwy własne narzędzi wzorca** bez tłumaczenia tam, gdzie są nazwą narzędzia: Explain Plan, Code Assistant
   (sekcja ustawień), Query Builder, Query By Example, Large Data Editor, Test Manager, SQL Monitor, Instance Viewer,
   Database Diff, Autotrace, AutoCommit, AutoReplace, AutoSelect. Przyciski czynności w tych narzędziach — po polsku.
6. **Słowa SQL w nawiasie** przy polskiej czynności, gdy użytkownik zna je z Oracle: „Zatwierdź (COMMIT)”,
   „Wycofaj (ROLLBACK)”, „Zakończ sesję (Kill)”, „Zapisz zmiany w bazie (Post)”.
7. **Zmiana nazwy komendy** = dawną nazwę dopisać do słów kluczowych (`CommandSearch.keywords`), żeby wyszukiwanie
   czynności i paleta znajdowały ją po starej nazwie; tłumaczenia przenieść na nowy klucz (`scripts/l10n.py`).
8. Teksty dziennika (`Log.*`), komunikaty SP2-/ORA- i nazwy techniczne nie są nazewnictwem interfejsu.

## macOS — menu standardowe

| Pojęcie | W Pelikanie | Uzasadnienie / źródło |
|---|---|---|
| Settings… (⌘,) | **Ustawienia…**; okno **Ustawienia**; Narzędzia › Ustawienia › Eksportuj/Importuj ustawienia…, Zestawy ustawień… | macOS 13+ (HIG: „Settings” zamiast „Preferences”); wcześniej okno nazywało się „Preferencje”, choć menu już „Ustawienia…” (D195) |
| Undo / Redo | Cofnij / **Powtórz** | macOS (wcześniej „Ponów”, które w Pelikanie znaczy „Retry”) |
| Cut / Copy / Paste / Select All | Wytnij / Kopiuj / Wklej / Zaznacz wszystko | macOS |
| Minimize / Zoom | **Zminimalizuj** / Powiększ | macOS (wcześniej „Minimalizuj”) |
| Hide / Hide Others / Show All / Quit | Ukryj … / Ukryj pozostałe / Pokaż wszystkie / Zakończ … | macOS |
| Save As… / Print… / Close Window | Zapisz jako… / Drukuj… / Zamknij okno | macOS |
| Move to Trash / Show in Finder | Przenieś do Kosza / Pokaż w Finderze | macOS |
| Duplicate | **Duplikuj** (np. „Duplikuj połączenie…”) | macOS (Plik › Duplikuj); wcześniej „Kopiuj połączenie…” — kopiowanie kojarzy się ze schowkiem |
| Customize Toolbar… | Dostosuj pasek narzędzi… | macOS |
| double-click | **dwukrotne kliknięcie**, „kliknij dwukrotnie” | macOS; wcześniej potoczne „dwuklik” |

## Edytor i IDE

| Pojęcie | W Pelikanie | Uzasadnienie / źródło |
|---|---|---|
| Find / Replace / Replace All / Find Next | Znajdź i zamień… / Zamień / Zamień wszystko / Znajdź następne | macOS, VS |
| Go to Line / Go to Declaration | Przejdź do linii… / Przejdź do deklaracji | VS |
| Find Usages / Rename (refactoring) | Znajdź użycia / Zmień nazwę… | JB, VS |
| Extract method / constant | **Wyodrębnij** procedurę… / stałą lokalną… / stałą globalną… | VS („Wyodrębnij metodę”); wcześniej „Wydziel” |
| Toggle line comment | **Przełącz komentarz linii** | VS („Przełącz komentarz wiersza”); wcześniej rzeczownik „Komentarz linii” |
| Upper / lower case | **Zamień na wielkie litery** / **Zamień na małe litery** (także „… w komórkach” w siatce) | czynność, nie stan; wcześniej „Wielkie litery” |
| Line start (first non-blank) | **Przejdź do pierwszego znaku linii** | czynność; wcześniej „Pierwszy znak w linii” |
| Code completion (Code Assistant) | **Pokaż podpowiedzi kodu**; Odśwież podpowiedzi kodu; sekcja ustawień „Code Assistant” | czynność; nazwa narzędzia wzorca w ustawieniach zostaje |
| Code Contents | **Zawartość kodu** (panel, menu, opisy) | nazwa panelu z menu Widok; wcześniej w opisach „Code Contents” |
| Code Hierarchy | hierarchia kodu | |
| Snippets | **Fragmenty kodu** (Widok › Fragmenty kodu; Wstaw/Zapisz/Usuń fragment kodu) | VS („Fragmenty kodu”); wcześniej „snippet” |
| Template | Szablon | |
| Bookmark | Zakładka | VS |
| Fold / Unfold | Zwiń / Rozwiń (blok, wszystko) | VS, JB |
| Beautifier / Format | Formatuj kod PL/SQL; karta ustawień „Formater” | |
| Multiple cursors | Wiele kursorów | |
| Build / Make (projekt) | **Kompiluj projekt** / **Kompiluj zmienione** | VS („Kompiluj” = Build); kompilacja PL/SQL to kompilacja, nie „budowanie”; wcześniej „Buduj projekt” / „Make projektu” |

## Debuger

| Pojęcie | W Pelikanie | Uzasadnienie / źródło |
|---|---|---|
| Start / Stop debugging | Rozpocznij debugowanie / Zatrzymaj debugowanie | VS |
| Step into / Step over / Step out | **Krok do** / **Krok przez** / **Wyjdź z podprogramu** | VS po polsku; wcześniej „Wejdź / Przejdź / Wyjdź” (dwuznaczne — „Wyjdź” to też zamknięcie, „Przejdź” — przejście do miejsca) |
| Run to cursor / to exception | Wykonaj do kursora / Wykonaj do wyjątku | |
| Toggle breakpoint | **Przełącz punkt przerwania**; Punkty przerwania… (lista) | VS; wcześniej rzeczownik „Punkt przerwania” |
| Watch | Obserwuj wyrażenie / Usuń z obserwowanych; panel „Obserwowane” | VS (zmienne obserwowane) |
| Call stack | Stos wywołań; Ramka stosu wywołań | VS |

## Oracle i bazy danych

| Pojęcie | W Pelikanie | Uzasadnienie / źródło |
|---|---|---|
| Explain plan | Plan wykonania; okno **Okno planu (Explain Plan)**; przycisk/wstążka **Odśwież plan** | Oracle; przycisk liczy plan ponownie dla tekstu okna — wcześniej „Wyjaśnij” (kalka „Explain”) i „Wyznacz plan” |
| Commit / Rollback | Zatwierdź (COMMIT) / Wycofaj (ROLLBACK); na wstążce **Zatwierdź** / **Wycofaj** | Oracle; wcześniej na wstążce same słowa SQL |
| Post (zmiany siatki) | **Zapisz zmiany w bazie (Post)** | DML bez COMMIT — „Zatwierdź” jest zarezerwowane dla COMMIT; wcześniej „Zatwierdź zmiany (Post)” |
| Kill session | **Zakończ sesję (Kill)**, Zakończ natychmiast; „Zakończ sesję okna (Kill)” | wcześniej „Zabij sesję” (kalka); zgodnie z istniejącą komendą okna |
| INVALID (status) | **nieprawidłowe obiekty**; Kompiluj nieprawidłowe obiekty… | jedno słowo zamiast „niepoprawne”/„nieprawidłowe” na przemian |
| Session / Cursor | Sesja / Kursor | |
| Package / spec / body | Pakiet; specyfikacja, ciało | |
| Trigger / Sequence / Synonym / Index | Wyzwalacz / Sekwencja / Synonim / Indeks | |
| Materialized view | Widok zmaterializowany | |
| Database link | Łącze bazy danych | |
| Constraint | Więzy (integralności) — także raport predefiniowany i dokumentacja schematu | Oracle; wcześniej raport „Ograniczenia” |
| Schema / Data dictionary | Schemat / Słownik danych | |
| Recycle bin | Kosz (Opróżnij kosz…, Przywróć z kosza…) | |
| Job (Scheduler) / Queue | Zadanie / Kolejka | |
| Tablespace | Przestrzeń tabel | |
| Privileges / Role | Uprawnienia / Rola | |

## Narzędzia, git i wdrożenia Pro*C

| Pojęcie | W Pelikanie | Uzasadnienie / źródło |
|---|---|---|
| Object Browser | **Przeglądarka obiektów** (także karta ustawień, filtr nazwany, opisy) | nazwa z menu Widok; wcześniej mieszane z „Object Browser” |
| File Browser | **Przeglądarka plików** | jw. |
| SQL Window / Command Window | **okno SQL** / **okno poleceń** (także sekcja ustawień „Okno SQL”) | jw. |
| Find Database Objects | Znajdź obiekty bazy… (kryteria wyszukiwania obiektów bazy) | |
| Working copy | **kopia robocza** | git-gui, TortoiseGit; wcześniej „working copy” |
| Backup | **kopia zapasowa**, katalog kopii zapasowych | macOS; wcześniej „backup” |
| Auto refresh | Automatyczne odświeżanie… (menu), **Autoodświeżanie** (krótka etykieta) | pisownia łączna jak Autoukrywanie, Autozapis |
| Bend point (diagram) | **punkt załamania** linii relacji | wcześniej „punkt łamania” |

## Rozważone i pozostawione

- **Workset** — nazwa funkcji wzorca w dziesiątkach tekstów i nazwach plików; polski „zestaw roboczy” zostaje
  w opisach słownika użytkownika.
- **build / binarka / remote / commit / HEAD** w zdalnym buildzie Pro*C — żargon tego przepływu (git, make), znany
  użytkownikom; tłumaczenie byłoby mniej czytelne.
- **Zadokuj, Autoukrywanie** — przyjęte w polskim Visual Studio.
- **Rekompiluj** — utrwalone w środowisku Oracle (rekompilacja obiektów).
- **Upuść** (przeciągnij i upuść) — polski macOS.
- **To-Do**, **Dialog** (karta okna poleceń), tryby sesji **Single / Multi / Dual** — nazwy wzorca.
- **Znaki specjalne**, **Status linii** — przełączniki widoku z nazwami wzorca; opis wyjaśnia skutek.
- **Sprawdź uaktualnienia…** — tekst zgodny z dotychczasową lokalizacją Sparkle w Pelikanie.
