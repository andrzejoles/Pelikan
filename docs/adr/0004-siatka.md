# ADR 0004 — Siatka wyników: NSTableView (view-based) z własnym modelem danych i zaznaczenia

Stan: przyjęty 2026-10-22.

## Wymagania
Miliony wierszy przewijane płynnie (dociąganie porcjami), setki kolumn, edycja w miejscu, zaznaczanie bloków komórek,
blokada kolumn i wierszy (scroll lock), sortowanie lokalne, NULL na kolorowym tle, przyciski komórek (LOB, data),
Single Record View, kopiowanie, dostępność.

## Opcje
1. **NSTableView** (view-based): wirtualizacja wierszy wbudowana (pyta tylko o widoczne), sprawdzona wydajność dla
   milionów wierszy przy lekkich widokach komórek i stałej wysokości wiersza; dostępność; przenoszenie kolumn.
2. Własny widok rysowany Core Graphics/Core Text: maksymalna wydajność i pełna kontrola zaznaczenia blokowego, ale cała
   obsługa klawiatury, edycji, dostępności do napisania.
3. NSCollectionView z układem siatki: elastyczny, ale cięższy przy setkach kolumn.

## Decyzja
Opcja 1 z rozszerzeniami:
- Model `ResultGridModel` (PelikanWorkspace, bez AppKit): wiersze w porcjach (`RowBatch`), sformatowane wartości
  liczone leniwie i buforowane, dociąganie przy zbliżeniu do końca (prefetch), stan edycji (zmiany oczekujące).
- Komórki: własna lekka podklasa NSView rysująca tekst (`NSAttributedString.draw`) zamiast NSTextField w każdej
  komórce; stała wysokość wiersza (`usesAutomaticRowHeights = false`); reużycie widoków.
- Zaznaczenie bloków komórek: własny model zaznaczenia (prostokąty komórek) rysowany na wierzchu; zaznaczenie wierszy
  i kolumn przez nagłówki.
- Blokada kolumn: druga NSTableView zsynchronizowana pionowo (zamrożone kolumny po lewej) — znany wzorzec.
- Pierwsza kolumna z numerem wiersza (jak we wzorcu).
Kryterium (Etap 1, test w Release): 1 000 000 wierszy × 10 kolumn — przewijanie bez zacięć (pomiar czasu klatki
podczas przewijania programowego), pamięć < 1 GB.

## Konsekwencje
Jeśli wydajność rysowania tekstu w komórkach nie wystarczy przy setkach kolumn, rysowanie przechodzi do jednego widoku
wiersza (cały wiersz w jednym `draw`), zachowując NSTableView jako kontener wirtualizacji.
