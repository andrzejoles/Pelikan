# Domyślne skróty PL/SQL Developer — stan weryfikacji

Źródła: UG 17 (rozdziały w nawiasach), forum producenta
https://forums.allroundautomations.com/threads/execute-query-in-sql-windows.13153 (Hilarion, 2014: „F8 … all statements
… unless text is selected; Ctrl+F8 will execute only the current statement; AutoSelect … reverses”).

| Skrót | Funkcja | Stan |
|---|---|---|
| F1 | pomoc kontekstowa | potwierdzone (UG 25.8, 36) |
| F5 | Explain Plan z zaznaczenia | potwierdzone (UG 6.1) |
| F8 | Execute (wszystkie polecenia lub zaznaczenie; z AutoSelect — bieżące) | potwierdzone (UG 8.2, forum) |
| Ctrl+F8 | Execute current statement (odwrotnie do AutoSelect) | potwierdzone (forum, NF10) |
| F11 / F12 | nagrywanie / odtwarzanie makra | potwierdzone (UG 25.11) |
| Ctrl+E | Recall Statement | potwierdzone (UG 25.5) |
| Ctrl+F | Find & Replace | potwierdzone (UG 25.3) |
| Ctrl+G | Go to line | potwierdzone (UG 25.12) |
| Ctrl+K n / Ctrl+Q n | ustaw / idź do zakładki | potwierdzone (UG 25.13) — sekwencja dwuklawiszowa (Etap 2) |
| Ctrl+− | komentarz linii | potwierdzone (UG 25.1, NF15) |
| Ctrl+Tab / Ctrl+Shift+Tab | następne / poprzednie okno | potwierdzone (UG 23.16, NF11) |
| Ctrl+Del | usuń następne słowo | potwierdzone (NF9) |
| Ctrl + / − (klawiatura numeryczna) | rozmiar czcionki edytora i siatki | potwierdzone (NF13) |
| F10 / Shift+F10 | Commit / Rollback | **do weryfikacji** (powszechnie używane; brak w UG) |
| Shift+Esc | Break | **do weryfikacji** |
| F9, Ctrl+R, Ctrl+N, Ctrl+O, Ctrl+T, Ctrl+B | debuger: start, run, step into, step over, step out, punkt przerwania | **do weryfikacji** |

Pełna lista funkcji z domyślnymi klawiszami jest tylko w Preferences → Key Configuration wzorca. Właściciel może ją
wyeksportować (Preferences → Export) — wtedy uzupełnimy profil.
