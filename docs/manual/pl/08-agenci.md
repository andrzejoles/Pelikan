# Agenci AI

Pelikan udostępnia narzędzia agentom AI uruchamianym w terminalu (Claude Code, Codex, Grok, Antigravity) przez serwer
MCP dostępny tylko dla danej sesji. Agent działa w **panelu agenta** obok okien.

## Zasady bezpieczeństwa

- Agent widzi połączenia tylko pod nazwą (aliasem) — nigdy haseł, adresów ani nazw użytkowników.
- Agent ma **własną sesję bazy** (oznaczoną w V$SESSION), opcjonalnie przez użytkownika proxy z ograniczonymi
  uprawnieniami. Zapytania wykonuje w transakcji tylko do odczytu, z limitami wierszy i czasu.
- Zmiany (DML, DDL, kompilacja) wymagają **Twojej zgody** w oknie zgody z podglądem polecenia i obiektów, których
  dotyczą. DML zostaje niezatwierdzony, dopóki nie zgodzisz się na COMMIT.
- Na połączeniach produkcyjnych agent ma tylko odczyt. Agent nie ma dostępu do Command Window, poleceń systemu
  operacyjnego, debugera ani raportów AWR/ASH.
- Wskazane kolumny mogą być maskowane w wynikach dla agenta.
- **Cofnij sesję agenta** przywraca obiekty zmienione przez agenta do stanu sprzed zmian (z wykrywaniem konfliktów).

Uprawnienia, lista programów i dziennik działań są w **Preferencje › Agenci**.
