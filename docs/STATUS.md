# Stan Pelikana — beta po przeglądzie kodu (2026-10-27)

Etapy 0–8 i Pro\*C (P) są zakończone. Macierz funkcji (`docs/FEATURES.md`) ma **438** wierszy:

| Stan | Liczba |
|---|---|
| ✅ zrobione, potwierdzone testem | 409 |
| 👁 potwierdzone zrzutem ekranu | 19 |
| ⚠️ częściowo | 4 |
| pominięte decyzją | 6 |

Żaden wiersz nie ma stanu „do zrobienia”. Co testować w becie i znane ograniczenia: [`docs/BETA.md`](BETA.md).

Po trzech betach (7.9.0, 8.4.0, 8.7.0) cały kod przeszedł dogłębny przegląd (D168), zależności są aktualne (D167),
a kompilacja i CI nie zgłaszają ostrzeżeń (D166).

## Jak sprawdzić

- `make test-unit` — testy bez bazy i bez SSH: pakiet, agent.
- `make test-ssh` — testy SSH na lokalnym `sshd` i Pro\*C (każdy zestaw osobno, z limitem czasu — jak w CI).
- `make testdb && make test` — testy z bazą testową w kontenerze (Oracle Free 26ai + utPLSQL).
- Dodatkowe środowiska w kontenerach (D156–D159):
  - `scripts/testdb.sh owm` — Workspace Manager;
  - `ords-up` — ORDS;
  - `ldap-up` — katalog LDAP z aliasami Oracle Net;
  - `kdc-up` / `kdc-linux` — Kerberos.
- `scripts/screenshots.sh` — zrzuty okien w tle (D113, D148).
- `python3 scripts/l10n.py check --strict` — komplet tłumaczeń en/de/es/uk.
- CI:
  - macOS: budowanie, testy jednostkowe, testy SSH, aplikacja;
  - Linux: warstwa bazy na Oracle Free z utPLSQL i Workspace Managerem.

## Próba na dużej bazie

Pelikan przeszedł próbę tylko do odczytu na kopii dużej bazy produkcyjnej właściciela: Oracle 19c, dziesiątki tysięcy
obiektów, setki tysięcy linii PL/SQL, łącze z opóźnieniem około 50 ms (D151, D152, D164, D165).

| Obszar | Wynik |
|---|---|
| Lekser, konspekt, zwijanie, inspekcja, formater | 3000 jednostek bez błędów; formater idempotentny |
| Pobieranie hurtowe (metadane, eksport, porównania) | 4,9 razy szybsze |
| Analiza nazw — czas | pakiet z 13,5 tys. linii: 34 s → 1,8 s |
| Analiza nazw — fałszywe alarmy na poprawnym kodzie | 478 → 1 |
| Znajdź obiekty bazy (860 tys. linii) | 31–85 s → 2–3 s |
| Diagram ER (378 / 2000 tabel) | 263 s → 4,4 s / 98 s → 6,6 s |
| Znajdź obiekty — definicje tabel | 58 s → 4,9 s |
| Eksport DDL / porównanie obiektów | 2 s → 0,2 s na obiekt |
| Dokumentacja schematu (1826 obiektów) | ponad 20 min → 15 s |

Próba wykryła też błąd: program z innego schematu kompilowałby się w schemacie sesji. Jest poprawiony.

## Do potwierdzenia przez właściciela

- **Pro\*C na AIX 6.1 / ksh88**:
  - Pipeline wdrożenia, skrypty, Stop i parsery `proc`/`xlc` są przetestowane na lokalnym `sshd` z ksh93 (D54).
  - Próbki komunikatów z prawdziwego serwera warto podmienić w fixture'ach.
- **Microsoft Entra ID** (SD-AUTH-001) — wymaga dzierżawy Azure (D82).
- **Quick Look** (MAC-QL-001) — rozszerzenie zbudowane; przy podpisie własnym macOS może go nie załadować (D95).
- **Kerberos na macOS** (PD-CONN-014):
  - Na Linuksie działa z KDC w kontenerze.
  - Na macOS adapter Kerberos z Instant Client koliduje z Kerberos.framework w procesie z AppKit.
  - Pelikan zgłasza czytelny błąd zamiast się wywracać (D159).
  - Pełne rozwiązanie (proces pomocniczy bez AppKit) odłożone na przyszłość (D161).
- **Wydania** — pierwsza publiczna beta to 7.9.0 (D161); kolejne szkice publikuje właściciel
  (`gh release edit vX.Y.Z --draft=false`).

## Ograniczenia (wiersze częściowe)

| ID | Funkcja | Stan |
|---|---|---|
| PD-CONN-014 | Uwierzytelnianie zewnętrzne / Kerberos | ⚠️ działa na Linuksie; na macOS blokada zamiast awarii (D159) |
| SD-AUTH-001 | Uwierzytelnianie Entra ID | ⚠️ zbudowane, bez próby na Azure |
| MAC-QL-001 | Quick Look dla plików SQL | ⚠️ zbudowane, wymaga podpisu z notaryzacją |
| MAC-UI-001 | Natywne karty, pełny ekran, tryby jasny i ciemny | ⚠️ karty własne w jednym oknie (D15) |
