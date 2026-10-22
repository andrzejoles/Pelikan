# utPLSQL v3 — wiedza do Etapu 4

Źródła:
- utPLSQL v3.2.3 (https://github.com/utPLSQL/utPLSQL/releases/tag/v.3.2.3), dokumentacja https://www.utplsql.org/utPLSQL/latest/
  (lokalnie w paczce wydania `docs/userguide/*.html`), specyfikacja `source/api/ut_runner.pks`.
- Wtyczka PL/SQL Developer: https://github.com/utPLSQL/utPLSQL-PLSQL-Developer (Apache 2.0, C#, wydanie 1.2.4) — korzysta z
  biblioteki https://github.com/utPLSQL/utPLSQL-dotnet-api (`RealTimeTestRunner`).
- Rozszerzenie SQL Developer: https://github.com/utPLSQL/utPLSQL-SQLDeveloper (Apache 2.0, Java).

## API (ut_runner)
- `ut_runner.version` → np. `v.3.2.3.4508` (na bazie testowej); `version_compatibility_check`.
- `ut_runner.run(a_paths ut_varchar2_list, a_reporters ut_reporters, a_color_console, a_coverage_schemes,
  a_source_file_mappings, a_test_file_mappings, a_include_objects, a_exclude_objects, a_fail_on_errors,
  a_client_character_set, a_force_manual_rollback, a_random_test_order, a_random_test_order_seed, a_tags,
  a_include_schema_expr, a_include_object_expr, a_exclude_schema_expr, a_exclude_object_expr)`.
  Ścieżki: `schemat`, `schemat.pakiet`, `schemat.pakiet.procedura`, `schemat:ścieżka.suity` (suitepath).
- `ut_runner.get_suites_info(a_owner, a_package_name)` / `get_suites_info(a_path)` — pipelined `ut_suite_item_info`
  (object_owner, object_name, item_name, item_description, item_type, item_line_no, path, disabled_flag,
  disabled_reason, tags) → eksplorator testów.
- `is_test`, `is_suite`, `has_suites`, `get_reporters_list`, `rebuild_annotation_cache`, `purge_cache`,
  `coverage_start/stop`.
- Reportery v3.2.3: ut_documentation_reporter, ut_realtime_reporter, ut_junit_reporter, ut_tfs_junit_reporter,
  ut_xunit_reporter, ut_teamcity_reporter, ut_tap_reporter, ut_sonar_test_reporter, ut_debug_reporter,
  ut_coverage_html_reporter, ut_coverage_cobertura_reporter, ut_coverage_sonar_reporter (+ coveralls w dokumentacji).

## Jak wtyczka PL/SQL Developer uruchamia testy (odwzorować natywnie)
1. Dwie sesje tego samego połączenia: **produkująca** i **konsumująca**.
2. Sesja produkująca wykonuje blok:
   ```sql
   DECLARE l_rep ut_realtime_reporter := ut_realtime_reporter();
   BEGIN l_rep.set_reporter_id(:id); l_rep.output_buffer.init();
         ut_runner.run(a_paths => ut_varchar2_list(...), a_reporters => ut_reporters(l_rep)); END;
   ```
   (z pokryciem: dodatkowo `ut_coverage_html_reporter` z drugim identyfikatorem, `a_coverage_schemes`,
   `a_include_objects`, `a_exclude_objects`, `dbms_output.enable(NULL)`).
3. Sesja konsumująca równolegle: `l_rep.set_reporter_id(:id); :c := l_rep.get_lines_cursor();` i czyta wiersze
   kursora — każdy to dokument XML zdarzenia (`pre-run` ze strukturą suit, `pre-suite`, `pre-test`, `post-test` z
   wynikiem, czasem, oczekiwaniami/błędami, DBMS_OUTPUT testu, `post-suite`, `post-run` z licznikami).
4. Raport pokrycia HTML z bufora reportera pokrycia (CLOB) → plik tymczasowy → przeglądarka.
- Interfejs wtyczki: przyciski „wszystkie testy użytkownika”, „pokrycie”, „ścieżka” (okno z polem ścieżki); menu
  Object Browsera (pakiet, ciało, procedura, użytkownik); uruchamianie z Program Window; okno wyników (drzewo/lista,
  czasy, błędy, filtr statusu checkboxami (1.1.0), sortowanie, dwuklik → ciało pakietu, ponowne uruchomienie z/bez
  pokrycia, uruchomienie pojedynczego testu z menu); okno pokrycia (schematy, include/exclude) i raport HTML.

## Rozszerzenie SQL Developer (dodatkowo)
- Debugowanie testu (debuger PL/SQL na wygenerowanym bloku; dłuższy limit czasu reportera realtime).
- Pokrycie dla wybranych pakietów z obiektami ustalanymi z zależności w słowniku.
- Generowanie szkieletu pakietu testowego z istniejącego pakietu/typu/funkcji/procedury (kompiluje się i wykonuje).
- Szablony kodu `ut_…` (Ctrl+Spacja), snippety adnotacji i oczekiwań (przeciąganie).
- Integracja z oddgen (uruchamianie suitepath, masowe generowanie do plików).

## Adnotacje (do Code Assistant i walidacji)
`--%suite(opis)`, `--%suitepath(a.b.c)`, `--%displayname(opis)`, `--%test(opis)`, `--%context(opis)` / `--%endcontext`,
`--%name(nazwa)`, `--%beforeall`, `--%afterall`, `--%beforeeach`, `--%aftereach`, `--%beforetest(proc[,…])`,
`--%aftertest(proc[,…])` (wszystkie przyjmują listę `[[owner.]package.]procedure`), `--%throws(wyjątek|-kod[,…])`,
`--%disabled(powód)`, `--%rollback(auto|manual)`, `--%tags(t1,t2)`.

## Oczekiwania (Code Assistant)
`ut.expect(actual).to_equal(expected)` / `.not_to_equal`, `to_be_null`, `to_be_not_null`, `to_be_true`, `to_be_false`,
`to_be_between(a,b)`, `to_be_greater_than`, `to_be_greater_or_equal`, `to_be_less_than`, `to_be_less_or_equal`,
`to_be_like(wzorzec[,escape])`, `to_match(regex[,flagi])`, `to_be_empty`, `to_have_count(n)`, `to_contain`,
`to_be_within(odległość).of_(x)`, `to_be_within_pct`; porównania kursorów/kolekcji/obiektów: `.join_by`, `.include`,
`.exclude`, `.unordered`, `.unordered_columns`; `ut.fail(komunikat)`.

## Baza testowa
utPLSQL instalowany przez `scripts/testdb.sh seed` (`install_headless.sql`, schemat UT3, publiczne synonimy);
przykładowy pakiet `test_emp_api` (5 testów, 1 celowo nieudany: „Actual: 2975 (number) was expected to equal: 1”).
Pokrycie wymaga uprawnień (DBMS_PROFILER/DBMS_PLSQL_CODE_COVERAGE) i zapisuje dane profilera — ostrzeżenie w interfejsie.
