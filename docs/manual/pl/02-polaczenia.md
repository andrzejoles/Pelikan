# Połączenia i bezpieczeństwo haseł

## Definicja połączenia

Połączenie ma nazwę, folder, użytkownika, bazę (EZConnect `host:port/usługa`, `tcps://…` albo alias z `tnsnames.ora`),
rolę (Normal, SYSDBA…), opcjonalnie użytkownika proxy, edycję (EBR) i środowisko: deweloperskie, testowe albo
produkcyjne. Połączenia produkcyjne mają kolor ostrzegawczy, a polecenia zmieniające dane wymagają tam potwierdzenia.

Połączenie może być **tylko do odczytu** — Pelikan odrzuca wtedy DML, DDL i PL/SQL zanim trafią do bazy.

## Hasła

Hasła są przechowywane wyłącznie w **Pęku kluczy** macOS (logowanie, bez synchronizacji iCloud) i nigdy nie trafiają do
plików, logów ani argumentów procesów. Hasło zapisuje się dopiero po udanym połączeniu i tylko wtedy, gdy zaznaczysz
**Zapamiętaj hasło w Pęku kluczy**.

W **Preferencje › Oracle** możesz włączyć **Wymagaj Touch ID albo hasła Maca przed użyciem zapisanego hasła** — Pelikan
zapyta wtedy raz na połączenie w trakcie działania aplikacji.

## Oracle Wallet

Pelikan obsługuje dwa rodzaje portfela:

- **magazyn haseł** (Secure External Password Store) — logowanie `/@alias` bez podawania hasła; katalog portfela
  wskazujesz w **Preferencje › Oracle › Oracle Net i Oracle Wallet**, a w połączeniu wybierasz uwierzytelnianie
  *Oracle Wallet*. Pole „Baza” musi być dokładnie aliasem zapisanym w portfelu;
- **portfel TLS** (np. Autonomous Database) — katalog portfela w definicji połączenia; archiwum ZIP z portalu
  rozpakujesz przyciskiem **Importuj ZIP…**.

## Inne sposoby uwierzytelniania

- **Zewnętrzne** (Kerberos, system operacyjny).
- **Microsoft Entra ID** — Instant Client 23 otwiera przeglądarkę do logowania i sam przekazuje token bazie; Pelikan
  tokenu nie widzi i nie zapisuje.
- **Token OAuth2 z pliku** — token przygotowany wcześniej narzędziem zewnętrznym.
- **Tunel SSH** — połączenie przez serwer pośredni (klucz albo agent SSH).

## Licencje pakietów Oracle

Raporty AWR, ASH, ADDM, SQL Monitor i SQL Tuning Advisor wymagają płatnych pakietów Oracle Diagnostics/Tuning Pack.
Przy pierwszym użyciu Pelikan pyta, czy baza ma licencję, i zapamiętuje odpowiedź w definicji połączenia.
