#!/usr/bin/env python3
"""Aktualizacja docs/progress/status.json z wiersza poleceń, potem generowanie raportu (scripts/progress.py).

Użycie:
  scripts/status.py task "Opis bieżącego zadania"
  scripts/status.py done "Co zostało zrobione"          (dopisuje na początek listy „Zrobione”)
  scripts/status.py next "Krok 1" "Krok 2" …            (zastępuje listę następnych kroków)
  scripts/status.py stage 1 "Nazwa etapu"               (bieżący etap; poprzednie oznaczane jako zakończone)
  scripts/status.py block "Tytuł" "Szczegóły"           (blokada, wyróżniona w raporcie)
  scripts/status.py unblock "Tytuł"
  scripts/status.py limit "Znane ograniczenie"
  scripts/status.py tests KATEGORIA total passed failed skipped
  scripts/status.py perf "Nazwa" "Wynik" "Cel" ok|fail
  scripts/status.py shot img/plik.png "Tytuł" "Porównanie z wzorcem"
  scripts/status.py ci                                  (tylko odświeża raport i sygnał)
Każde wywołanie aktualizuje „ostatni sygnał” i generuje raport.
"""
from __future__ import annotations

import datetime as dt
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATUS = ROOT / "docs/progress/status.json"


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 2
    s = json.loads(STATUS.read_text(encoding="utf-8")) if STATUS.exists() else {}
    cmd, args = argv[0], argv[1:]
    now = dt.datetime.now().astimezone().isoformat(timespec="seconds")
    if cmd == "task":
        s["task"] = args[0]
    elif cmd == "done":
        s.setdefault("done", []).insert(0, args[0])
        s["done"] = s["done"][:40]
    elif cmd == "next":
        s["next"] = list(args)
    elif cmd == "stage":
        sid = int(args[0])
        s["stage"] = {"id": sid, "name": args[1] if len(args) > 1 else s.get("stage", {}).get("name", "")}
        for st in s.get("stages", []):
            st["state"] = "zakończony" if st["id"] < sid else ("w toku" if st["id"] == sid else st.get("state", "do zrobienia"))
    elif cmd == "block":
        s.setdefault("blockers", []).append({"title": args[0], "detail": args[1] if len(args) > 1 else "", "since": now})
    elif cmd == "unblock":
        s["blockers"] = [b for b in s.get("blockers", []) if b.get("title") != args[0]]
    elif cmd == "limit":
        if args[0] not in s.setdefault("limitations", []):
            s["limitations"].append(args[0])
    elif cmd == "tests":
        cat, total, passed, failed, skipped = args[0], *map(int, args[1:5])
        s.setdefault("tests", {})[cat] = {"total": total, "passed": passed, "failed": failed, "skipped": skipped, "at": now}
    elif cmd == "perf":
        name, value, target, ok = args
        perf = [p for p in s.get("performance", []) if p.get("name") != name]
        perf.append({"name": name, "value": value, "target": target, "ok": ok == "ok"})
        s["performance"] = perf
    elif cmd == "shot":
        f, title, ref = args[0], args[1], args[2] if len(args) > 2 else ""
        shots = [x for x in s.get("screenshots", []) if x.get("file") != f]
        shots.insert(0, {"file": f, "title": title, "reference": ref})
        s["screenshots"] = shots
    elif cmd != "ci":
        print(f"Nieznane polecenie: {cmd}", file=sys.stderr)
        return 2
    s["heartbeat"] = now
    STATUS.write_text(json.dumps(s, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return subprocess.call([sys.executable, str(ROOT / "scripts/progress.py")])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
