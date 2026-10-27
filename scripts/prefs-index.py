#!/usr/bin/env python3
"""Indeks wyszukiwarki Preferencji (PD-PREF-001) z etykiet paneli w App/Sources/Preferences.

Uruchomienie bez argumentów zapisuje App/Sources/Preferences/PreferenceIndex.swift; `--check` kończy się błędem,
gdy plik jest nieaktualny (CI). Etykiety: Section, Toggle, Picker, TextField, Stepper, ColorPicker z `L10n.tr("…")`,
kontrolki własne Preferencji z etykietą w pierwszym argumencie (FontFamilyPicker(title:), directoryRow, colorRow),
FontWeightPicker (stała etykieta „Styl” z AppFonts.swift),
etykiety `Text(L10n.tr("…"))` (także obie gałęzie `warunek ? … : …`) w domknięciu Stepper/Toggle oraz pola TextField z etykietą z listy `ForEach([…])`
(np. katalogi startowe, NLS) — w strukturach `…Pane: View` wymienionych w PreferencesView. Przyciski są pomijane
(to czynności, nie ustawienia). Etykieta w indeksie to klucz L10n (interpolacja `\\(…)` → `%@`, `%` → `%%`);
wyszukiwarka pokazuje `%@` jako „…”.
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from l10n import ParseError, parse_key, skip_interpolation, strip_comments  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIR = ROOT / "App/Sources/Preferences"
OUT = DIR / "PreferenceIndex.swift"
# Literał klucza zaczyna się na końcu dopasowania (cudzysłów otwierający).
STRING = r'"(?:[^"\\\n]|\\.)*"'
CONTROL = re.compile(r'\b(?:Section|Toggle|Picker|TextField|Stepper|ColorPicker|FontFamilyPicker|directoryRow|colorRow)\(\s*(?:title:\s*)?L10n\.tr\(\s*(?=")')
# Kontrolki własne z etykietą ustaloną w ich kodzie (nie w wywołaniu) — klucz musi być taki jak tam.
FIXED_LABELS = {re.compile(r'\bFontWeightPicker\('): "Styl"}
CLOSURE_LABEL = re.compile(r'\b(?:Stepper|Toggle)\((?:[^{}"\n]|' + STRING + r')*?\)\s*\{\s*Text\(')
TR = re.compile(r'L10n\.tr\(\s*(?=")')
LABEL_LIST = re.compile(r'\bForEach\(\[((?:[^\]"]|' + STRING + r')*)\][^{]*\{\s*(?:\w+\s*,\s*)?(\w+)\s+in\s+TextField\(\s*(\w+)\s*,')


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


def labels(src):
    """Klucze etykiet ustawień w kolejności występowania w źródle panelu."""
    found = []
    starts = [m.end() for m in CONTROL.finditer(src)]
    for m in CLOSURE_LABEL.finditer(src):
        try:
            end = skip_interpolation(src, m.end())
        except ParseError:
            continue
        starts += [m.end() + t.end() for t in TR.finditer(src[m.end():end])]
    for i in starts:
        try:
            found.append((i, parse_key(src, i)[0]))
        except ParseError:
            pass
    for pattern, key in FIXED_LABELS.items():
        found += [(m.start(), key) for m in pattern.finditer(src)]
    for m in LABEL_LIST.finditer(src):
        if m.group(2) != m.group(3):
            continue
        items = m.group(1)
        calls = [c.end() for c in TR.finditer(items)]
        starts = calls or [c.start() for c in re.finditer(STRING, items)]
        for i in starts:
            try:
                found.append((m.start(1) + i, parse_key(items, i)[0]))
            except ParseError:
                pass
    return [key for _, key in sorted(found)]


def swift_literal(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def generate():
    order, sources = panes()
    lines = []
    for pane in order:
        seen = set()
        for label in labels(strip_comments(sources.get(pane, ""))):
            if not label.strip() or label in seen:
                continue
            seen.add(label)
            lines.append(f'        ("{pane}", "{swift_literal(label)}"),')
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
