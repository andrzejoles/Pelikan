# Zależności zewnętrzne

| Komponent | Wersja (przypięta) | Licencja | Użycie | Decyzja |
|---|---|---|---|---|
| ODPI-C (oracle/odpi) | v26.0.0 — źródła w `Packages/PelikanKit/Sources/CODPI` | UPL 1.0 / Apache 2.0 | sterownik Instant Client | D8, ADR 0001 |
| Oracle Instant Client | nie dołączany; użytkownik instaluje sam (lokalnie 23.26.2 — najnowszy dla macOS arm64; CI Linux 23.26.4) | Oracle Technology Network Development and Distribution License for Instant Client | biblioteka klienta OCI ładowana w czasie działania | D7 |
| OracleNIO (lovetodream/oracle-nio) | commit 7cda9e0 z main (po 1.0.0-rc.4) | Apache 2.0 | sterownik thin | ADR 0001, D20 |
| SwiftNIO, swift-nio-ssl, swift-nio-transport-services, swift-crypto, swift-asn1, swift-log, swift-atomics, swift-collections, swift-async-algorithms, swift-system, swift-service-lifecycle, swift-distributed-tracing, swift-syntax (zależności OracleNIO; swift-crypto także bezpośrednio — SHA-256 na Linuksie) | wg Package.resolved (swift-crypto 5.x) | Apache 2.0 | sterownik thin | D20 |
| SwiftTerm | 1.99.1 | MIT | terminal panelu agenta | PROMPT §4.1 |
| Sparkle | 2.10.1 | MIT | aktualizacje | PROMPT §4.1 |
| swift-sdk MCP (modelcontextprotocol/swift-sdk) | 0.12.1 (najnowsze; jak Bifold D17) | MIT | serwer MCP w aplikacji | Bifold D17 |

Narzędzia deweloperskie (nie trafiają do aplikacji): XcodeGen, Colima + Docker CLI (MIT/Apache), obraz
`gvenzl/oracle-free` (Oracle Database Free — licencja Oracle Free Use; tylko lokalna baza testowa), utPLSQL v3.2.3
(Apache 2.0; instalowany w bazie testowej przez `scripts/testdb.sh`), poppler (`pdftotext`, analiza dokumentacji).
