# Stan Pelikana — przed pierwszą betą (2026-10-24)

Etapy 0–8 i Pro\*C (P) są zakończone. Macierz funkcji (`docs/FEATURES.md`) ma **434** wiersze:

| Stan | Liczba |
|---|---|
| ✅ zrobione, potwierdzone testem | 405 |
| 👁 potwierdzone zrzutem ekranu | 18 |
| ⚠️ częściowo | 5 |
| pominięte decyzją | 6 |

Żaden wiersz nie ma stanu „do zrobienia”. Co testować w becie i znane ograniczenia: [`docs/BETA.md`](BETA.md).

## Jak sprawdzić

- `make test-unit` — testy bez bazy: pakiet, agent, SSH na lokalnym `sshd`, Pro\*C.
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
obiektów, setki tysięcy linii PL/SQL, łącze z opóźnieniem około 50 ms (D151, D152).

| Obszar | Wynik |
|---|---|
| Lekser, konspekt, zwijanie, inspekcja, formater | 3000 jednostek bez błędów; formater idempotentny |
| Pobieranie hurtowe (metadane, eksport, porównania) | 4,9 razy szybsze |
| Analiza nazw — czas | pakiet z 13,5 tys. linii: 34 s → 1,8 s |
| Analiza nazw — fałszywe alarmy na poprawnym kodzie | 478 → 1 |

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
  - Pełne rozwiązanie to proces pomocniczy bez AppKit — do decyzji.
- **Szkice wydań** na GitHubie — publikuje właściciel (`gh release edit vX.Y.Z --draft=false`).

## Ograniczenia (wiersze częściowe)

| ID | Funkcja | Stan |
|---|---|---|
| PD-CONN-014 | Uwierzytelnianie zewnętrzne / Kerberos | ⚠️ działa na Linuksie; na macOS blokada zamiast awarii (D159) |
| PD-UI-003 | Narzędzia dokowane i pływające | ⚠️ karty lewej kolumny i osobne okna, bez swobodnego dokowania (D112) |
| SD-AUTH-001 | Uwierzytelnianie Entra ID | ⚠️ zbudowane, bez próby na Azure |
| MAC-QL-001 | Quick Look dla plików SQL | ⚠️ zbudowane, wymaga podpisu z notaryzacją |
| MAC-UI-001 | Natywne karty, pełny ekran, tryby jasny i ciemny | ⚠️ karty własne w jednym oknie (D15) |
