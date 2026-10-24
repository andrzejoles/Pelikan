#!/usr/bin/env python3
"""Indeks wyszukiwarki Preferencji (PD-PREF-001) z etykiet paneli w App/Sources/Preferences.

Uruchomienie bez argumentów zapisuje App/Sources/Preferences/PreferenceIndex.swift; `--check` kończy się błędem,
gdy plik jest nieaktualny (CI). Etykiety: Section, Toggle, Picker, TextField, Stepper, Button, ColorPicker z
`L10n.tr("…")` bez interpolacji, w strukturach `…Pane: View` wymienionych w PreferencesView.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIR = ROOT / "App/Sources/Preferences"
OUT = DIR / "PreferenceIndex.swift"
CONTROL = re.compile(r'\b(Section|Toggle|Picker|TextField|Stepper|Button|ColorPicker)\(\s*L10n\.tr\("((?:[^"\\]|\\.)*)"\)')


def panes():
    order = re.findall(r'(\w+Pane)\(workspace: workspace\)\.(?:tag|tabItem)', (DIR / "PreferencesView.swift").read_text(encoding="utf-8"))
    sources = {}
    for f in sorted(DIR.glob("*.swift")):
        if f.name == OUT.name:
            continue
        text = f.read_text(encoding="utf-8")
        starts = [(m.start(), m.group(1)) for m in re.finditer(r'^struct (\w+): View', text, re.M)]
        for i, (pos, name) in enumerate(starts):
            end = starts[i + 1][0] if i + 1 < len(starts) else len(text)
            sources[name] = text[pos:end]
    return order, sources


def generate():
    order, sources = panes()
    lines = []
    for pane in order:
        seen = set()
        for _, label in CONTROL.findall(sources.get(pane, "")):
            if "\\(" in label or label in seen:
                continue
            seen.add(label)
            lines.append(f'        ("{pane}", "{label}"),')
    return (
        "// Wygenerowane przez scripts/prefs-index.py — nie edytować ręcznie.\n\n"
        "/// Etykiety ustawień według panelu dla wyszukiwarki Preferencji (PD-PREF-001); teksty to klucze L10n.\n"
        "enum PreferenceIndex {\n"
        "    static let entries: [(pane: String, label: String)] = [\n"
        + "\n".join(lines)
        + "\n    ]\n}\n"
    )


if __name__ == "__main__":
    text = generate()
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
            sys.exit("PreferenceIndex.swift jest nieaktualny — uruchom scripts/prefs-index.py")
        print("indeks preferencji aktualny")
    else:
        OUT.write_text(text, encoding="utf-8")
        print(f"zapisano {OUT.relative_to(ROOT)}: {text.count(chr(10) + '        (')} etykiet")
