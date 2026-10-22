# ADR 0002 — Parser SQL/PL/SQL: własny tolerancyjny lekser i parser zstępujący

Stan: przyjęty 2026-10-22.

## Kontekst
Edytor potrzebuje podświetlania i Code Assistant bez opóźnień w pakiecie 50 000 linii, odpornych na niekompletny kod
w trakcie pisania. Klasyfikacja poleceń dla agenta, dzielenie skryptów, Code Contents, zwijanie, refaktoryzacja,
Beautifier i rozwiązywanie nazw potrzebują struktury kodu.

## Opcje
1. Wygenerowany parser ANTLR z `antlr/grammars-v4` (PlSqlParser.g4): pełna gramatyka, ale runtime ANTLR dla Swifta jest
   wolny dla dużych plików, nietolerancyjny (błędy przerywają drzewo), duża zależność.
2. tree-sitter z gramatyką SQL: szybki i przyrostowy, ale brak dojrzałej gramatyki PL/SQL Oracle; zależność C.
3. **Własny lekser przyrostowy + parser zstępujący (recursive descent) tolerancyjny na błędy.**

## Decyzja
Opcja 3. Lekser (PelikanSQL/Lexer.swift) działa na UTF-16, emituje stan na końcu linii (`LexState`) — edytor leksuje
tylko zmienione linie, dopóki stan końca linii się nie zmienia. Parser strukturalny (Etap 2) buduje „lekkie” drzewo:
jednostki (pakiet, procedura, funkcja, typ, wyzwalacz), deklaracje (zmienne, typy, kursory, wyjątki, podprogramy),
bloki i instrukcje sterujące (IF/LOOP/CASE/BEGIN…END) z zakresami tekstu, oraz polecenia SQL z listą tabel/aliasów i
kolumn — wystarczy do Code Contents, Code Hierarchy, zwijania, hiperłączy, Code Assistant (kontekst aliasów) i
inspekcji. Błąd składni nie przerywa parsowania (synchronizacja na `;`, `END`, słowach kluczowych bloków).
Gramatyka `grammars-v4` służy jako źródło wiedzy i korpus testów (pliki `.sql` z jej testów + przykłady z dokumentacji
Oracle); fuzzing (losowe obcięcia i mutacje plików korpusu) gwarantuje, że parser nie wywraca się na żadnym wejściu.

## Konsekwencje
- Pełna walidacja składni należy do serwera (kompilacja); parser nie musi akceptować dokładnie języka Oracle.
- Wydajność mierzona testami w Release (lekser 50 000 linii, parsowanie pakietu, przyrostowe przeleksowanie linii).
- Klasyfikator poleceń (bezpieczeństwo agenta) jest konserwatywny: nierozpoznane = `unknown` = najwyższe ryzyko.
