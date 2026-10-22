# ADR 0005 — Model okien: jedno okno główne z kartami dokumentów (SDI jak we wzorcu) i panelami narzędzi

Stan: przyjęty 2026-10-22.

## Kontekst
PL/SQL Developer ma okno główne z narzędziami dokowanymi (Object Browser, Connection List, Window List, Templates…) i
dokumentami w trybie MDI (wiele okien w obszarze) albo SDI (jedno okno na całym obszarze z kartami). Natywne karty macOS
(`NSWindow.tabbingMode`) robią z każdej karty osobne NSWindow — panele boczne musiałyby być w każdym oknie osobno, co
łamie układ wzorca (wspólny Object Browser i Window List).

## Decyzja
- Jedno `NSWindow` główne na instancję (można otworzyć kolejne okno główne — jak „New Instance” we wzorcu, Cmd+N
  w menu Window): `NSSplitViewController` z lewą kolumną narzędzi (Object Browser, Connection List, Window List,
  Templates, File Browser jako karty/sekcje), obszarem dokumentów z **własnym paskiem kart** (SDI wzorca: zamknij,
  zamknij z lewej/prawej, przeciąganie, środkowy klik zamyka, menu karty) i opcjonalnym prawym panelem (Bookmarks,
  Search, Clipboard, agent).
- MDI wzorca (swobodne okna w obszarze) nie ma odpowiednika w HIG — zamiast niego: **odłączenie dokumentu do osobnego
  okna** (dokument w NSWindow z tym samym kontrolerem) i podział obszaru na dwa dokumenty obok siebie. Zapisane w
  macierzy jako zgodne funkcjonalnie (PD-UI-004).
- Pełny ekran, tryb ciemny i jasny, menu wg HIG; paski narzędzi okna dokumentu (jak paski okien wzorca).

## Konsekwencje
Window List i karty pokazują ten sam model (`Workspace.documents`); agent widzi stan z modelu (`get_state`).
