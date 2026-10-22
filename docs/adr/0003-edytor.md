# ADR 0003 — Edytor kodu: własny widok na TextKit 2 (NSTextView)

Stan: przyjęty 2026-10-22.

## Wymagania
Duże pliki (pakiet 50 000 linii) bez opóźnień w pisaniu, podświetlanie składni, zwijanie, numery linii i margines z
punktami przerwania, pokryciem testami, zakładkami i statusem linii, zaznaczenie kolumnowe, wiele kursorów (jeśli we
wzorcu — jest kolumnowe), Code Assistant (okno podpowiedzi), hiperłącza (Cmd+klik), podświetlanie wystąpień, split view.

## Opcje
1. **STTextView** (TextKit 2): gotowy widok z gutterem i wieloma kursorami, ale licencja **GPLv3 lub komercyjna** —
   niezgodna z dystrybucją Pelikana na MIT bez zakupu (zakupy wykluczone, PROMPT §13). Odrzucone.
2. Własny renderer (Core Text, własny model tekstu): pełna kontrola, ogromny koszt (IME, dostępność, wyszukiwanie,
   cofanie, sprawdzanie pisowni) — ryzyko jakości na macOS.
3. **NSTextView z TextKit 2** (NSTextLayoutManager, NSTextContentStorage) + własne rozszerzenia.

## Decyzja
Opcja 3. Elementy:
- Podświetlanie przez **atrybuty renderowania** (`NSTextLayoutManager.setRenderingAttributes`) dla widocznego
  fragmentu — bez zmiany `NSTextStorage` (brak przeliczania layoutu przy każdym naciśnięciu), lekser przyrostowy (ADR 0002)
  przelicza tylko zmienione linie; kolory z motywu (jasny/ciemny).
- Margines: własny `NSRulerView` (numery linii, status linii, punkty przerwania, pokrycie, zakładki, znaczniki zwinięcia).
- Zwijanie: ukrywanie akapitów przez delegata `NSTextContentManager`/`NSTextContentStorage` (filtrowanie elementów)
  z zastępczym znacznikiem; zakresy z parsera strukturalnego.
- Zaznaczenie kolumnowe i wiele kursorów: NSTextView wspiera wiele zakresów zaznaczenia (`selectedRanges`) — Option+
  przeciąganie daje zaznaczenie prostokątne; pisanie w wielu zakresach obsługujemy we własnej nadklasie.
- Code Assistant: okno podrzędne (NSPanel bez fokusu) z listą (NSTableView), filtrowanie w tle na cache metadanych.
- Split view: dwa NSTextView na wspólnym `NSTextContentStorage` (TextKit 2 wspiera wiele menedżerów układu).
- Jeżeli testy wydajności w Release (Etap 2: pisanie w pakiecie 50 000 linii < 16 ms na znak, otwarcie < 1 s) nie
  przejdą — fallback: TextKit 1 z `NSLayoutManager` i `allowsNonContiguousLayout` (znany, szybki dla dużych plików).

## Konsekwencje
Dostajemy IME, dostępność (VoiceOver), sprawdzanie pisowni, cofanie i wyszukiwanie systemowe za darmo; ryzyko to
wydajność TextKit 2 przy bardzo dużych plikach — mierzone od pierwszej wersji edytora.
