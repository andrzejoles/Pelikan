#!/usr/bin/env python3
"""Scala konflikt w docs/progress/status.json (raport generowany): listy wpisów z obu stron bez powtórzeń,
pola pojedyncze ze strony bieżącej gałęzi; potem `scripts/status.py` regeneruje HTML."""
import json, subprocess, sys

def side(n):
    return json.loads(subprocess.check_output(["git", "show", f":{n}:docs/progress/status.json"], text=True))

ours, theirs = side(2), side(3)
merged = dict(ours)
for k, v in ours.items():
    if isinstance(v, list):
        seen, out = set(), []
        for e in v + theirs.get(k, []):
            key = json.dumps(e, sort_keys=True, ensure_ascii=False)
            if key not in seen:
                seen.add(key)
                out.append(e)
        merged[k] = out
merged["heartbeat"] = max(str(ours.get("heartbeat", "")), str(theirs.get("heartbeat", "")))
with open("docs/progress/status.json", "w", encoding="utf-8") as f:
    json.dump(merged, f, ensure_ascii=False, indent=2)
print("status.json scalony", file=sys.stderr)
