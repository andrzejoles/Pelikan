# ADR 0001 — Sterowniki bazy: ODPI-C + Instant Client (domyślny) i OracleNIO (thin)

Stan: przyjęty 2026-10-22. Decyzja właściciela (PROMPT §4.1): dwa sterowniki za wspólnym protokołem, najpierw pełny
Instant Client, potem thin.

## Kontekst
Pelikan musi obsłużyć wszystko, co PL/SQL Developer (OCI): starsze bazy, Kerberos, wallet, TNS/LDAP, DBMS_DEBUG, typy
obiektowe, LOB, REF CURSOR, przerwanie wywołania, proxy user, zmianę hasła. Sterownik w czystym Swifcie byłby wygodny
(bez instalacji Instant Client), ale nie pokrywa wszystkiego.

## Decyzja
1. **Instant Client przez ODPI-C** (oracle/odpi v26.0.0, UPL/Apache 2.0, źródła dołączone jako cel C — D8). ODPI ładuje
   `libclntsh` dynamicznie, więc pakiet buduje się bez Instant Client; Pelikan go nie dołącza (licencja — D7), tylko
   wykrywa (`InstantClientLocator`) i prowadzi użytkownika przez instalację.
2. **OracleNIO** (lovetodream/oracle-nio, Apache 2.0, SSWG incubation, wydanie 1.0.0-rc.4 — **przedpremierowe**) jako
   alternatywa: bez Instant Client, SwiftNIO, async/await. Wersja przypięta dokładnie; aktualizacja do 1.0.0 po wydaniu.
3. Oba za protokołem `DatabaseSession` (PelikanDB). Okna i narzędzia znają tylko protokół i `DriverCapabilities`;
   funkcja niedostępna w sterowniku jest wyszarzona z podpowiedzią „przełącz na Instant Client”.

## Macierz możliwości

| Możliwość | Instant Client (ODPI-C) | Thin (OracleNIO, commit 7cda9e0) | Uwagi / weryfikacja |
|---|---|---|---|
| Wersje baz | 11.2+ (klient 23.26 łączy się z 19c+ oficjalnie, starsze wg macierzy zgodności Oracle) | 12.1+ (12c z dodatkową konfiguracją), testowane 18–23 | ✅ 26ai na bazie testowej (IC) |
| EZConnect | ✅ | ✅ host/port/usługa lub SID | |
| tnsnames.ora / sqlnet.ora / TNS_ADMIN | ✅ | ✅ alias rozwijany przez Pelikana do deskryptora (TNSNames); sqlnet.ora ❌ | ✅ |
| LDAP | ✅ | ❌ | |
| Wallet / mTLS (ADB) | ✅ | ❌ TCPS w Pelikanie wyłączony (komunikat „użyj Instant Client”) | test komunikatu |
| Kerberos / uwierzytelnianie zewnętrzne | ✅ | ❌ | |
| Tokeny OCI IAM / OAuth2 | ✅ (ODPI accessToken) | ⚠️ niesprawdzone przez autora | |
| SYSDBA/SYSOPER… | ✅ | ⚠️ do weryfikacji | |
| Proxy user | ✅ (`user[schema]`) | ⚠️ do weryfikacji | |
| Zmiana wygasłego hasła | ✅ (newPassword) | ❌ komunikat | |
| DBMS_DEBUG | ✅ (wywołania PL/SQL w drugiej sesji) | ✅ w zasadzie (to tylko PL/SQL) — do weryfikacji | debuger Etap 3 |
| DBMS_DEBUG_JDWP | ✅ (Pelikan jako serwer JDWP na porcie) | ✅ (niezależne od sterownika) | wymaga ACL po stronie bazy |
| LOB (CLOB/BLOB/NCLOB/BFILE) | ✅ (test `lobJsonRowid`) | ✅ lokator, odczyt do limitu, CLOB w AL16UTF16 (test `types`) | ✅ |
| Typy obiektowe i kolekcje | ✅ (dpiObject) | ⚠️ ograniczone — do weryfikacji | debuger/Test Window |
| REF CURSOR, kursory zagnieżdżone | ✅ (test `refCursor`) | ✅ (do weryfikacji zagnieżdżonych) | |
| Niejawne wyniki (DBMS_SQL.RETURN_RESULT) | ✅ (test `implicitResults`) | ⚠️ do weryfikacji | |
| JSON, VECTOR, BOOLEAN (23ai) | ✅ | ✅ JSON/BOOLEAN, VECTOR — do weryfikacji | |
| DBMS_OUTPUT | ✅ (PL/SQL) | ✅ (PL/SQL) | |
| Przerwanie (break) | ✅ OCIBreak (test `breakExecution`) | ❌ brak w API OracleNIO — „Przerwij” wyszarzone (test) | ✅ |
| Pobieranie | tablicowe, NUMBER jako tekst — 1 mln wierszy × 4 kol.: 1,2 s | strumieniowe; NUMBER/DATE dekodowane przez Pelikana z surowych bajtów (bez Double) — 1 mln: 4,3 s | ✅ Release |
| Linux (CI) | ✅ Instant Client Linux | ✅ | ✅ CI |

## Konsekwencje
- Testy integracyjne warstwy bazy są sparametryzowane sterownikiem; funkcje nieobsługiwane przez thin mają test
  czytelnego komunikatu (`DatabaseError.unsupported`).
- Instant Client: ekran pomocy przy braku (link do strony Oracle, instrukcja dla DMG, wykryte ścieżki).
- Zmiana decyzji: kolejny sterownik = kolejna implementacja `DatabaseSession` + `DriverKind`.
