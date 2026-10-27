#!/usr/bin/env python3
"""Generator raportu postępów Pelikana (sama biblioteka standardowa).

Źródła danych:
  docs/progress/status.json   stan pracy (etap, zadanie, blokady, testy, wydajność, zrzuty) — aktualizowany ręcznie
  docs/FEATURES.md            macierz funkcji (z niej liczony jest postęp)
  docs/DECISIONS.md           ostatnie decyzje
  historia gita               oś czasu (commity, scalone PR, tagi)
  gh (opcjonalnie)            stan CI na main i szkice wydań — bez sieci raport też się generuje

Wynik: docs/progress/index.html (commitowany) i kopia w ~/Pelikan-raport/index.html (+ img/).
Raport nie może zawierać haseł, adresów baz, nazw użytkowników baz ani danych z bazy.

Użycie: scripts/progress.py [--heartbeat] [--no-gh] [--no-copy]
  --heartbeat   aktualizuje pole „ostatni sygnał” w status.json przed generowaniem
"""
from __future__ import annotations

import datetime as dt
import html
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
PROGRESS = DOCS / "progress"
STATUS = PROGRESS / "status.json"
FEATURES = DOCS / "FEATURES.md"
DECISIONS = DOCS / "DECISIONS.md"
OUT = PROGRESS / "index.html"
COPY_DIR = Path(os.environ.get("PELIKAN_REPORT_DIR", str(Path.home() / "Pelikan-raport")))
REPO = "andrzejoles/Pelikan"
GH = f"https://github.com/{REPO}"

# Waga stanu wiersza macierzy w postępie. Wiersze pominięte (z uzasadnieniem) nie liczą się do mianownika.
STATE_WEIGHTS = [
    ("✅", 1.0, "done", "✅ test"),
    ("👁", 1.0, "done", "👁 sprawdzone ręcznie"),
    ("⚠️", 0.75, "warn", "⚠️ bez weryfikacji"),
    ("w toku", 0.25, "wip", "w toku"),
    ("pominięte", None, "skip", "pominięte"),
    ("do zrobienia", 0.0, "todo", "do zrobienia"),
]

GROUPS = [
    ("PL/SQL Developer", ("PD-",)),
    ("Dodatki SD/DB/DG", ("SD-", "SC-", "DB-", "DG-")),
    ("utPLSQL", ("UT-",)),
    ("Agenci AI", ("AI-",)),
    ("Platforma i macOS", ("MAC-", "PL-")),
]


def esc(s: object) -> str:
    return html.escape(str(s), quote=True)


def run(cmd: list[str], timeout: int = 15) -> str:
    try:
        return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=timeout, check=False).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def now_local() -> dt.datetime:
    return dt.datetime.now().astimezone()


def fmt_time(iso: str | None) -> str:
    if not iso:
        return "—"
    try:
        t = dt.datetime.fromisoformat(iso)
    except ValueError:
        return esc(iso)
    if t.tzinfo is None:
        t = t.astimezone()
    return t.astimezone().strftime("%Y-%m-%d %H:%M")


def ago(iso: str | None) -> str:
    if not iso:
        return ""
    try:
        t = dt.datetime.fromisoformat(iso)
    except ValueError:
        return ""
    if t.tzinfo is None:
        t = t.astimezone()
    mins = int((now_local() - t).total_seconds() // 60)
    if mins < 1:
        return "przed chwilą"
    if mins < 60:
        return f"{mins} min temu"
    if mins < 48 * 60:
        return f"{mins // 60} h {mins % 60} min temu"
    return f"{mins // 1440} dni temu"


# ---------------------------------------------------------------- dane

def load_status() -> dict:
    if STATUS.exists():
        return json.loads(STATUS.read_text(encoding="utf-8"))
    return {}


def parse_features() -> list[dict]:
    """Wiersze tabel z FEATURES.md, których pierwsza kolumna to identyfikator (np. PD-SQLW-012)."""
    rows: list[dict] = []
    if not FEATURES.exists():
        return rows
    header: list[str] | None = None
    section = ""
    for line in FEATURES.read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            section = line.lstrip("#").strip()
            header = None
            continue
        if not line.startswith("|"):
            header = None
            continue
        # `\|` — znak `|` w treści komórki (GitHub), nie granica kolumny.
        cells = [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", line.strip().strip("|"))]
        if header is None:
            header = [c.lower() for c in cells]
            continue
        if all(set(c) <= set("-: ") for c in cells):
            continue
        if not re.match(r"^[A-Z]{2,3}-[A-Z0-9]+-\d+", cells[0]):
            continue
        row = dict(zip(header, cells))
        row["_id"] = cells[0]
        row["_section"] = section
        rows.append(row)
    return rows


def col(row: dict, *names: str) -> str:
    for n in names:
        for k, v in row.items():
            if k.startswith(n):
                return v
    return ""


def classify(state: str) -> tuple[float | None, str]:
    s = state.lower()
    for marker, weight, cls, _ in STATE_WEIGHTS:
        if marker.lower() in s:
            return weight, cls
    return 0.0, "todo"


def progress_of(rows: list[dict]) -> tuple[float, int, int, int]:
    """(procent, zrobione, w mianowniku, pominięte)."""
    total = 0
    score = 0.0
    done = 0
    skipped = 0
    for r in rows:
        w, cls = classify(col(r, "stan"))
        if w is None:
            skipped += 1
            continue
        total += 1
        score += w
        if cls == "done":
            done += 1
    return (100.0 * score / total if total else 0.0), done, total, skipped


def parse_decisions(limit: int = 12) -> list[tuple[str, str]]:
    if not DECISIONS.exists():
        return []
    text = DECISIONS.read_text(encoding="utf-8")
    parts = re.split(r"^### ", text, flags=re.M)[1:]
    out = []
    for p in parts:
        title, _, body = p.partition("\n")
        out.append((title.strip(), body.strip()))
    return out[-limit:][::-1]


def git_timeline(limit: int = 40) -> list[dict]:
    fmt = "%H%x1f%h%x1f%ad%x1f%s%x1f%P"
    raw = run(["git", "log", "--all", f"--max-count={limit}", "--date=iso-strict", f"--format={fmt}"])
    tags: dict[str, list[str]] = {}
    for line in run(["git", "show-ref", "--tags", "-d"]).splitlines():
        sha, ref = line.split(" ", 1)
        name = ref.replace("refs/tags/", "").replace("^{}", "")
        tags.setdefault(sha, []).append(name)
    items = []
    for line in raw.splitlines():
        f = line.split("\x1f")
        if len(f) < 5:
            continue
        sha, short, date, subj, parents = f
        m = re.match(r"Merge pull request #(\d+) from \S+", subj)
        items.append({
            "sha": sha, "short": short, "date": date, "subject": subj,
            "merge": bool(m) or len(parents.split()) > 1, "pr": m.group(1) if m else None,
            "tags": sorted(set(tags.get(sha, []))),
        })
    return items


def gh_json(args: list[str]) -> list | dict | None:
    if not shutil.which("gh"):
        return None
    out = run(["gh", *args], timeout=20)
    try:
        return json.loads(out) if out.strip() else None
    except json.JSONDecodeError:
        return None


def ci_status(use_gh: bool, status: dict) -> dict:
    if use_gh:
        runs = gh_json(["run", "list", "--repo", REPO, "--branch", "main", "--limit", "1",
                        "--json", "status,conclusion,url,displayTitle,createdAt,headSha"])
        if isinstance(runs, list) and runs:
            return runs[0]
        if isinstance(runs, list):
            return {"status": "brak przebiegów"}
    return status.get("ci", {}) or {}


def gh_prs(use_gh: bool) -> list:
    if not use_gh:
        return []
    prs = gh_json(["pr", "list", "--repo", REPO, "--state", "all", "--limit", "15",
                   "--json", "number,title,state,url,mergedAt,createdAt,headRefName"])
    return prs if isinstance(prs, list) else []


def gh_releases(use_gh: bool) -> list:
    if not use_gh:
        return []
    rel = gh_json(["release", "list", "--repo", REPO, "--limit", "10",
                   "--json", "tagName,name,isDraft,createdAt"])
    return rel if isinstance(rel, list) else []


# ---------------------------------------------------------------- HTML

CSS = """
:root{--bg:#f6f7f9;--fg:#1d2330;--muted:#5d6675;--card:#fff;--line:#dfe3ea;--accent:#1f6feb;
--ok:#1a7f37;--warn:#9a6700;--bad:#cf222e;--wip:#8250df;--todo:#8c959f;--skip:#adb5bd;--hl:#fff8c5}
@media (prefers-color-scheme:dark){:root{--bg:#0f1218;--fg:#e6e9ef;--muted:#9aa4b2;--card:#171b23;--line:#2b313c;
--accent:#58a6ff;--ok:#3fb950;--warn:#d29922;--bad:#f85149;--wip:#a371f7;--todo:#6e7681;--skip:#484f58;--hl:#3b2e00}}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{max-width:1180px;margin:0 auto;padding:16px}
h1{font-size:24px;margin:4px 0}h2{font-size:18px;margin:28px 0 10px;border-bottom:1px solid var(--line);padding-bottom:4px}
h3{font-size:15px;margin:14px 0 6px}
a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}
.muted{color:var(--muted)}.small{font-size:13px}
.grid{display:grid;gap:12px;grid-template-columns:repeat(auto-fit,minmax(220px,1fr))}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px}
.kv{display:flex;justify-content:space-between;gap:8px}.kv b{font-weight:600}
.bar{height:10px;background:var(--line);border-radius:5px;overflow:hidden;margin:6px 0 2px}
.bar>span{display:block;height:100%;background:var(--accent)}
.pill{display:inline-block;border-radius:999px;padding:1px 8px;font-size:12px;border:1px solid var(--line);white-space:nowrap}
.done{color:var(--ok)}.warn{color:var(--warn)}.wip{color:var(--wip)}.todo{color:var(--todo)}.skip{color:var(--skip)}.bad{color:var(--bad)}
.alert{border-left:4px solid var(--bad);background:var(--card);padding:10px 14px;border-radius:6px;margin:8px 0}
.alert.q{border-left-color:var(--warn)}
table{border-collapse:collapse;width:100%;font-size:13px}
th,td{border-bottom:1px solid var(--line);padding:5px 6px;text-align:left;vertical-align:top}
th{position:sticky;top:0;background:var(--card);font-weight:600}
.tablewrap{overflow-x:auto;max-height:70vh;overflow-y:auto;border:1px solid var(--line);border-radius:8px;background:var(--card)}
.filters{display:flex;flex-wrap:wrap;gap:8px;margin:8px 0}
.filters input,.filters select{font:inherit;padding:5px 8px;border:1px solid var(--line);border-radius:6px;background:var(--card);color:var(--fg)}
.filters input{flex:1;min-width:180px}
.tl li{margin:3px 0}.tl code{font-size:12px}
.shots{display:grid;gap:10px;grid-template-columns:repeat(auto-fill,minmax(200px,1fr))}
.shots figure{margin:0}.shots img{width:100%;border:1px solid var(--line);border-radius:6px;cursor:zoom-in}
.shots figcaption{font-size:12px;color:var(--muted)}
.lightbox{display:none;position:fixed;inset:0;background:rgba(0,0,0,.85);z-index:10;align-items:center;justify-content:center}
.lightbox:target{display:flex}.lightbox img{max-width:96vw;max-height:92vh}
details{margin:4px 0}summary{cursor:pointer}
pre{white-space:pre-wrap;font-size:12px}
@media (max-width:600px){main{padding:12px 16px}h1{font-size:20px}.hide-sm{display:none}}
"""

JS = """
function filt(){const q=document.getElementById('q').value.toLowerCase();
const st=document.getElementById('fs').value,et=document.getElementById('fe').value,sr=document.getElementById('fg').value;
let n=0;document.querySelectorAll('#fm tbody tr').forEach(tr=>{const ok=(!q||tr.textContent.toLowerCase().includes(q))
&&(!st||tr.dataset.cls===st)&&(!et||tr.dataset.stage===et)&&(!sr||tr.dataset.group===sr);tr.style.display=ok?'':'none';if(ok)n++});
document.getElementById('fn').textContent=n;}
"""


def bar(pct: float) -> str:
    return f'<div class="bar"><span style="width:{pct:.1f}%"></span></div>'


def section_header(status: dict, version: str, ci: dict) -> str:
    stage = status.get("stage", {})
    concl = ci.get("conclusion") or ci.get("status") or "nieznany"
    cls = {"success": "done", "failure": "bad", "cancelled": "warn"}.get(concl, "wip")
    ci_html = f'<span class="{cls}">{esc(concl)}</span>'
    if ci.get("url"):
        ci_html = f'<a href="{esc(ci["url"])}">{ci_html}</a>'
    hb = status.get("heartbeat")
    return f"""
<header>
<h1>Pelikan — raport postępów</h1>
<div class="muted small">Natywne IDE dla Oracle PL/SQL na macOS · <a href="{GH}">{REPO}</a> · strona odświeża się co 30 s</div>
<div class="grid" style="margin-top:12px">
 <div class="card"><div class="kv"><span>Wersja</span><b>{esc(version)}</b></div>
  <div class="kv"><span>Raport wygenerowany</span><b>{now_local().strftime('%Y-%m-%d %H:%M')}</b></div>
  <div class="kv"><span>Ostatni sygnał</span><b>{fmt_time(hb)}</b></div><div class="small muted" style="text-align:right">{esc(ago(hb))}</div></div>
 <div class="card"><div class="kv"><span>Bieżący etap</span><b>{esc(stage.get('id', '—'))}</b></div>
  <div class="small">{esc(stage.get('name', ''))}</div>
  <div class="kv" style="margin-top:6px"><span>Zadanie</span></div><div class="small">{esc(status.get('task', '—'))}</div></div>
 <div class="card"><div class="kv"><span>CI na main</span><b>{ci_html}</b></div>
  <div class="small muted">{esc(ci.get('displayTitle', ''))}</div><div class="small muted">{fmt_time(ci.get('createdAt'))}</div></div>
</div>
</header>"""


def section_progress(rows: list[dict], status: dict) -> str:
    pct, done, total, skipped = progress_of(rows)
    parts = [f'<h2>Postęp</h2><div class="card"><div class="kv"><span>Ogółem (z macierzy funkcji)</span>'
             f'<b>{pct:.1f}%</b></div>{bar(pct)}<div class="small muted">{done} z {total} funkcji zrobionych'
             f'{f", {skipped} pominiętych z uzasadnieniem" if skipped else ""}; '
             f'wagi: ✅/👁 = 1, ⚠️ = 0,75, w toku = 0,25</div></div>']
    parts.append('<h3>Według obszaru</h3><div class="grid">')
    for name, prefixes in GROUPS:
        sub = [r for r in rows if r["_id"].startswith(prefixes)]
        if not sub:
            continue
        p, d, t, _ = progress_of(sub)
        parts.append(f'<div class="card"><div class="kv"><span>{esc(name)}</span><b>{p:.0f}%</b></div>{bar(p)}'
                     f'<div class="small muted">{d}/{t}</div></div>')
    parts.append('</div><h3>Według etapu</h3><div class="grid">')
    names = {str(s.get("id")): s.get("name", "") for s in status.get("stages", [])}
    stages = sorted({col(r, "etap") for r in rows if col(r, "etap")}, key=lambda s: (len(s), s))
    for st in stages:
        sub = [r for r in rows if col(r, "etap") == st]
        p, d, t, _ = progress_of(sub)
        parts.append(f'<div class="card"><div class="kv"><span>Etap {esc(st)}</span><b>{p:.0f}%</b></div>'
                     f'<div class="small muted">{esc(names.get(st, ""))}</div>{bar(p)}<div class="small muted">{d}/{t}</div></div>')
    parts.append("</div>")
    if not rows:
        parts.append('<p class="muted">Macierz funkcji (docs/FEATURES.md) jeszcze nie powstała — Etap 0.</p>')
    return "".join(parts)


def section_matrix(rows: list[dict]) -> str:
    if not rows:
        return ""
    stages = sorted({col(r, "etap") for r in rows if col(r, "etap")}, key=lambda s: (len(s), s))
    opts_stage = "".join(f'<option value="{esc(s)}">Etap {esc(s)}</option>' for s in stages)
    opts_state = "".join(f'<option value="{cls}">{esc(label)}</option>' for _, _, cls, label in STATE_WEIGHTS)
    opts_group = "".join(f'<option value="{esc(g)}">{esc(g)}</option>' for g, _ in GROUPS)
    body = []
    for r in rows:
        _, cls = classify(col(r, "stan"))
        group = next((g for g, pre in GROUPS if r["_id"].startswith(pre)), "")
        src = col(r, "źródło")
        m = re.search(r"\((https?://[^)\s]+)\)|(https?://\S+)", src)
        url = (m.group(1) or m.group(2)) if m else ""
        src_html = f'<a href="{esc(url)}">źródło</a>' if url else esc(re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", src))
        body.append(
            f'<tr data-cls="{cls}" data-stage="{esc(col(r, "etap"))}" data-group="{esc(group)}">'
            f'<td><code>{esc(r["_id"])}</code></td><td>{esc(col(r, "funkcja"))}</td>'
            f'<td class="hide-sm">{esc(col(r, "okno", "menu"))}</td><td>{esc(col(r, "etap"))}</td>'
            f'<td class="hide-sm">{esc(col(r, "priorytet"))}</td><td class="hide-sm">{esc(col(r, "agent", "poziom"))}</td>'
            f'<td class="{cls}">{esc(col(r, "stan"))}</td><td class="hide-sm">{src_html}</td></tr>')
    return f"""
<h2>Macierz funkcji</h2>
<div class="small muted">Legenda: ✅ zweryfikowane testem automatycznym · 👁 sprawdzone ręcznie w działającej aplikacji (zrzuty ekranu)
· ⚠️ zaimplementowane, bez weryfikacji na żywo (powód w kolumnie) · w toku · do zrobienia · pominięte (z uzasadnieniem)</div>
<div class="filters"><input id="q" placeholder="Szukaj (identyfikator, funkcja, okno…)" oninput="filt()">
<select id="fe" onchange="filt()"><option value="">Wszystkie etapy</option>{opts_stage}</select>
<select id="fs" onchange="filt()"><option value="">Wszystkie stany</option>{opts_state}</select>
<select id="fg" onchange="filt()"><option value="">Wszystkie źródła</option>{opts_group}</select>
<span class="small muted" style="align-self:center">wierszy: <b id="fn">{len(rows)}</b></span></div>
<div class="tablewrap"><table id="fm"><thead><tr><th>ID</th><th>Funkcja</th><th class="hide-sm">Okno / menu</th><th>Etap</th>
<th class="hide-sm">Prior.</th><th class="hide-sm">Agent</th><th>Stan</th><th class="hide-sm">Źródło</th></tr></thead>
<tbody>{''.join(body)}</tbody></table></div>"""


def section_timeline(commits: list[dict], prs: list, releases: list) -> str:
    out = ['<h2>Oś czasu</h2><div class="grid">']
    out.append('<div class="card"><h3>Ostatnie commity</h3><ul class="tl small">')
    for c in commits[:25]:
        label = esc(c["subject"])
        if c["pr"]:
            label = f'<b>scalenie <a href="{GH}/pull/{c["pr"]}">PR #{c["pr"]}</a></b>'
        tags = "".join(f' <span class="pill">{esc(t)}</span>' for t in c["tags"])
        out.append(f'<li><a href="{GH}/commit/{c["sha"]}"><code>{c["short"]}</code></a> '
                   f'<span class="muted">{fmt_time(c["date"])}</span> {label}{tags}</li>')
    out.append("</ul></div>")
    out.append('<div class="card"><h3>Pull requesty</h3><ul class="tl small">')
    if not prs:
        out.append('<li class="muted">brak danych (gh niedostępne albo jeszcze brak PR)</li>')
    for p in prs:
        st = "scalony" if p.get("mergedAt") else p.get("state", "").lower()
        cls = "done" if p.get("mergedAt") else ("wip" if p.get("state") == "OPEN" else "skip")
        out.append(f'<li><a href="{esc(p.get("url", ""))}">#{p.get("number")}</a> {esc(p.get("title", ""))} '
                   f'<span class="pill {cls}">{esc(st)}</span></li>')
    out.append('</ul><h3>Wydania (szkice)</h3><ul class="tl small">')
    if not releases:
        out.append('<li class="muted">brak</li>')
    for r in releases:
        out.append(f'<li><a href="{GH}/releases/tag/{esc(r.get("tagName", ""))}">{esc(r.get("name") or r.get("tagName"))}</a> '
                   f'<span class="pill">{"szkic" if r.get("isDraft") else "opublikowane"}</span> '
                   f'<span class="muted">{fmt_time(r.get("createdAt"))}</span></li>')
    out.append("</ul></div></div>")
    return "".join(out)


def section_tests(status: dict) -> str:
    tests = status.get("tests", {})
    perf = status.get("performance", [])
    out = ['<h2>Testy</h2><div class="grid">']
    labels = {"unit": "Jednostkowe", "integration": "Integracyjne (baza)", "security": "Bezpieczeństwa",
              "ui": "Interfejsu (XCUITest)", "performance": "Wydajności (Release)", "e2e": "E2E z CLI agentów"}
    for key, label in labels.items():
        t = tests.get(key)
        if not t:
            out.append(f'<div class="card"><b>{label}</b><div class="small muted">jeszcze brak</div></div>')
            continue
        total, passed, failed, skipped = (t.get(k, 0) for k in ("total", "passed", "failed", "skipped"))
        pct = 100.0 * passed / total if total else 0
        cls = "bad" if failed else "done"
        out.append(f'<div class="card"><div class="kv"><b>{label}</b><span class="{cls}">{passed}/{total}</span></div>{bar(pct)}'
                   f'<div class="small muted">czerwone: <span class="{"bad" if failed else ""}">{failed}</span> · pominięte: {skipped}'
                   f'{" · " + esc(fmt_time(t.get("at"))) if t.get("at") else ""}</div></div>')
    out.append("</div>")
    if perf:
        out.append('<h3>Pomiary wydajności</h3><div class="tablewrap"><table><thead><tr><th>Pomiar</th><th>Wynik</th>'
                   '<th>Cel</th><th>Stan</th></tr></thead><tbody>')
        for p in perf:
            ok = p.get("ok")
            out.append(f'<tr><td>{esc(p.get("name"))}</td><td>{esc(p.get("value"))}</td><td>{esc(p.get("target"))}</td>'
                       f'<td class="{"done" if ok else "bad" if ok is False else "muted"}">{"✅" if ok else "❌" if ok is False else "—"}</td></tr>')
        out.append("</tbody></table></div>")
    return "".join(out)


def section_shots(status: dict) -> str:
    shots = status.get("screenshots", [])
    out = ['<h2>Zrzuty ekranu</h2>']
    if not shots:
        return out[0] + '<p class="muted">Jeszcze brak — pojawią się z pierwszymi oknami aplikacji.</p>'
    out.append('<div class="shots">')
    boxes = []
    for i, s in enumerate(shots[:24]):
        f = esc(s.get("file", ""))
        out.append(f'<figure><a href="#shot{i}"><img src="{f}" alt="{esc(s.get("title", ""))}" loading="lazy"></a>'
                   f'<figcaption><b>{esc(s.get("title", ""))}</b><br>{esc(s.get("reference", ""))}</figcaption></figure>')
        boxes.append(f'<a class="lightbox" id="shot{i}" href="#_"><img src="{f}" alt=""></a>')
    out.append("</div>")
    out.extend(boxes)
    return "".join(out)


def section_decisions_blockers(status: dict) -> str:
    out = ['<h2>Blokady i pytania do właściciela</h2>']
    blockers = status.get("blockers", [])
    questions = status.get("questions", [])
    if not blockers and not questions:
        out.append('<p class="muted">Brak blokad.</p>')
    for b in blockers:
        out.append(f'<div class="alert"><b>Blokada:</b> {esc(b.get("title", b) if isinstance(b, dict) else b)}'
                   f'{"<div class=small>" + esc(b.get("detail", "")) + "</div>" if isinstance(b, dict) and b.get("detail") else ""}</div>')
    for q in questions:
        out.append(f'<div class="alert q"><b>Pytanie:</b> {esc(q)}</div>')
    out.append('<div class="grid"><div class="card"><h3>Zrobione</h3><ul class="small">')
    out.extend(f'<li class="done">✔ <span style="color:var(--fg)">{esc(n)}</span></li>' for n in status.get("done", []))
    out.append('</ul></div><div class="card"><h3>Następne kroki</h3><ol class="small">')
    out.extend(f"<li>{esc(n)}</li>" for n in status.get("next", []))
    out.append('</ol></div><div class="card"><h3>Znane ograniczenia</h3><ul class="small">')
    out.extend(f"<li>{esc(n)}</li>" for n in status.get("limitations", []))
    out.append("</ul></div></div>")
    out.append('<h2>Ostatnie decyzje</h2><div class="small muted">Pełna lista: '
               f'<a href="{GH}/blob/main/docs/DECISIONS.md">docs/DECISIONS.md</a></div>')
    for title, body in parse_decisions():
        out.append(f"<details><summary><b>{esc(title)}</b></summary><pre>{esc(body)}</pre></details>")
    return "".join(out)


def section_stages(status: dict) -> str:
    stages = status.get("stages", [])
    if not stages:
        return ""
    out = ['<h2>Etapy</h2><div class="tablewrap"><table><thead><tr><th>Etap</th><th>Zakres</th><th>Stan</th></tr></thead><tbody>']
    for s in stages:
        st = s.get("state", "")
        cls = {"zakończony": "done", "w toku": "wip"}.get(st, "todo")
        out.append(f'<tr><td>{esc(s.get("id"))}</td><td>{esc(s.get("name"))}</td><td class="{cls}">{esc(st)}</td></tr>')
    out.append("</tbody></table></div>")
    return "".join(out)


def build(use_gh: bool) -> str:
    status = load_status()
    rows = parse_features()
    version = run(["scripts/version.sh"]).strip() or "0.0.0"
    ci = ci_status(use_gh, status)
    body = "".join([
        section_header(status, version, ci),
        section_progress(rows, status),
        section_stages(status),
        section_decisions_blockers(status),
        section_matrix(rows),
        section_timeline(git_timeline(), gh_prs(use_gh), gh_releases(use_gh)),
        section_tests(status),
        section_shots(status),
    ])
    return f"""<!doctype html>
<html lang="pl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="30">
<meta name="color-scheme" content="light dark">
<title>Pelikan — postęp</title>
<style>{CSS}</style></head>
<body><main>{body}
<p class="small muted" style="margin-top:32px">Wygenerowane przez scripts/progress.py · Andrzej Oleś w kooperacji z Claude AI</p>
</main><script>{JS}</script></body></html>
"""


def main() -> int:
    args = set(sys.argv[1:])
    if "--heartbeat" in args:
        status = load_status()
        status["heartbeat"] = now_local().isoformat(timespec="seconds")
        STATUS.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    page = build(use_gh="--no-gh" not in args)
    OUT.write_text(page, encoding="utf-8")
    if "--no-copy" not in args:
        COPY_DIR.mkdir(parents=True, exist_ok=True)
        (COPY_DIR / "index.html").write_text(page, encoding="utf-8")
        src_img = PROGRESS / "img"
        if src_img.is_dir():
            dst = COPY_DIR / "img"
            dst.mkdir(exist_ok=True)
            for f in src_img.iterdir():
                if f.is_file():
                    shutil.copy2(f, dst / f.name)
    print(f"Raport: {OUT.relative_to(ROOT)}" + ("" if "--no-copy" in args else f" i file://{COPY_DIR}/index.html"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
