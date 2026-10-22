# Pelikan

Natywne IDE dla baz Oracle (SQL, PL/SQL) na macOS z Apple Silicon. Układ i sposób działania wzorowane na
klasycznych IDE dla PL/SQL, z wbudowanymi testami jednostkowymi utPLSQL, wybranymi funkcjami z innych
narzędzi bazodanowych (tylko w zakresie Oracle) i bezpiecznym API dla agentów AI (Claude Code, Codex CLI,
Grok CLI, Antigravity) przez lokalny serwer MCP.

> Projekt jest w budowie. Wymagania: [`docs/PROMPT.md`](docs/PROMPT.md), plan: [`docs/PLAN.md`](docs/PLAN.md),
> stan: raport postępów w `docs/progress/index.html`.

Pelikan nie jest produktem Oracle ani Allround Automations i nie jest z nimi powiązany. Nazwy „Oracle” i
„PL/SQL” są znakami towarowymi Oracle Corporation; używamy ich wyłącznie do opisu zgodności.

## Wymagania

- macOS 27 na Apple Silicon (arm64)
- Oracle Instant Client dla macOS ARM64 (sterownik domyślny) — instrukcja w aplikacji przy pierwszym połączeniu

## Autor i licencja

Andrzej Oleś w kooperacji z Claude AI · licencja MIT ([`LICENSE`](LICENSE))
