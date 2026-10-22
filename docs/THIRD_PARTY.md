# Zależności zewnętrzne

| Komponent | Wersja (przypięta) | Licencja | Użycie | Decyzja |
|---|---|---|---|---|
| ODPI-C (oracle/odpi) | v26.0.0 — źródła w `Packages/PelikanKit/Sources/CODPI` | UPL 1.0 / Apache 2.0 | sterownik Instant Client | D8, ADR 0001 |
| Oracle Instant Client | nie dołączany; użytkownik instaluje sam (lokalnie 23.26.2) | Oracle Technology Network Development and Distribution License for Instant Client | biblioteka klienta OCI ładowana w czasie działania | D7 |
| OracleNIO (lovetodream/oracle-nio) | 1.0.0-rc.4 (Etap 1) | Apache 2.0 | sterownik thin | ADR 0001 |
| SwiftTerm | 1.99.0 (Etap 5, jak Bifold) | MIT | terminal panelu agenta | PROMPT §4.1 |
| Sparkle | 2.9.6 (jak Bifold) | MIT | aktualizacje | PROMPT §4.1 |
| swift-sdk MCP (modelcontextprotocol/swift-sdk) | 0.12.1 (Etap 5, jak Bifold D17) | MIT | serwer MCP w aplikacji | Bifold D17 |

Narzędzia deweloperskie (nie trafiają do aplikacji): XcodeGen, Colima + Docker CLI (MIT/Apache), obraz
`gvenzl/oracle-free` (Oracle Database Free — licencja Oracle Free Use; tylko lokalna baza testowa), utPLSQL v3.2.3
(Apache 2.0; instalowany w bazie testowej przez `scripts/testdb.sh`), poppler (`pdftotext`, analiza dokumentacji).
