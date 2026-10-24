#!/usr/bin/env python3
"""Teksty interfejsu Pelikana: klucze `L10n.tr("…")` ze źródeł Swift ↔ `App/Resources/Localizable.xcstrings`.

Klucz = polski tekst literału; każda interpolacja `\\(…)` to `%@`, a `%` to `%%` (tak samo buduje go `L10n.Key`).

  scripts/l10n.py extract            dopisuje nowe klucze do katalogu, usuwa klucze, których nie ma w źródłach
  scripts/l10n.py check [--strict]   klucze ze źródeł bez wpisu w katalogu (--strict: także bez tłumaczeń)
  scripts/l10n.py export LANG [N]    JSON {klucz: ""} kluczy bez tłumaczenia na LANG (stdout; N — limit)
  scripts/l10n.py import LANG PLIK   wczytuje JSON {klucz: tłumaczenie}; placeholdery muszą się zgadzać
  scripts/l10n.py stats              liczba kluczy i tłumaczeń na język
"""
import json
import os
import plistlib
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = [os.path.join(ROOT, "Packages/PelikanKit/Sources"), os.path.join(ROOT, "App/Sources")]
CATALOG = os.path.join(ROOT, "App/Resources/Localizable.xcstrings")
LANGUAGES = ["en", "de", "es", "uk"]
SIMPLE_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "\\": "\\", '"': '"', "'": "'"}


class ParseError(Exception):
    pass


def skip_string(src, i):
    """Pomija literał zaczynający się w src[i] == '"' (także w interpolacji); zwraca indeks za nim."""
    if src.startswith('"""', i):
        end = src.find('"""', i + 3)
        if end < 0:
            raise ParseError("niedomknięty literał wieloliniowy")
        return end + 3
    i += 1
    while i < len(src):
        c = src[i]
        if c == "\\":
            if i + 1 < len(src) and src[i + 1] == "(":
                i = skip_interpolation(src, i + 2)
                continue
            i += 2
            continue
        if c == '"':
            return i + 1
        if c == "\n":
            raise ParseError("koniec linii w literale")
        i += 1
    raise ParseError("niedomknięty literał")


def skip_interpolation(src, i):
    """src[i] — pierwszy znak po `\\(`; zwraca indeks za zamykającym nawiasem."""
    depth = 1
    while i < len(src):
        c = src[i]
        if c == '"':
            i = skip_string(src, i)
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ParseError("niedomknięta interpolacja")


def parse_key(src, i):
    """src[i] == '"' — literał klucza; zwraca (klucz, indeks za literałem)."""
    if src.startswith('"""', i):
        raise ParseError("literał wieloliniowy w L10n.tr nie jest obsługiwany")
    out = []
    i += 1
    while i < len(src):
        c = src[i]
        if c == "\\":
            n = src[i + 1]
            if n == "(":
                i = skip_interpolation(src, i + 2)
                out.append("%@")
                continue
            if n == "u":
                m = re.match(r"u\{([0-9A-Fa-f]{1,8})\}", src[i + 1:])
                if not m:
                    raise ParseError("zła sekwencja \\u")
                out.append(chr(int(m.group(1), 16)))
                i += 1 + len(m.group(0))
                continue
            if n not in SIMPLE_ESCAPES:
                raise ParseError("nieznana sekwencja \\" + n)
            out.append(SIMPLE_ESCAPES[n].replace("%", "%%"))
            i += 2
            continue
        if c == '"':
            return "".join(out), i + 1
        if c == "\n":
            raise ParseError("koniec linii w literale")
        out.append("%%" if c == "%" else c)
        i += 1
    raise ParseError("niedomknięty literał")


CALL = re.compile(r"L10n\.tr\(\s*")


def strip_comments(src):
    """Zastępuje komentarze spacjami (z zachowaniem pozycji), pomijając literały."""
    out = list(src)
    i = 0
    while i < len(src):
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = len(src) if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = len(src) if j < 0 else j + 2
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
        elif src[i] == '"':
            try:
                i = skip_string(src, i)
            except ParseError:
                i += 1
        else:
            i += 1
    return "".join(out)


def extract_keys():
    keys = {}
    errors = []
    for base in SOURCES:
        for dirpath, _, files in os.walk(base):
            for f in sorted(files):
                if not f.endswith(".swift"):
                    continue
                path = os.path.join(dirpath, f)
                with open(path, encoding="utf-8") as fh:
                    src = strip_comments(fh.read())
                if "L10n.swift" in path:
                    continue
                for m in CALL.finditer(src):
                    i = m.end()
                    line = src.count("\n", 0, m.start()) + 1
                    rel = os.path.relpath(path, ROOT)
                    if i >= len(src) or src[i] != '"':
                        errors.append(f"{rel}:{line}: L10n.tr bez literału")
                        continue
                    try:
                        key, _ = parse_key(src, i)
                    except ParseError as e:
                        errors.append(f"{rel}:{line}: {e}")
                        continue
                    keys.setdefault(key, f"{rel}:{line}")
    for key in services_menu_keys():
        keys.setdefault(key, "App/Info.plist (NSServices)")
    return keys, errors


SERVICES_PREFIX = "$(PELIKAN_APP_NAME): "


def services_menu_keys():
    """Nazwy usług z NSServices bez przedrostka z nazwą aplikacji; tłumaczenia trafiają do ServicesMenu.strings
    (scripts/services-menu.py przy budowaniu)."""
    with open(os.path.join(ROOT, "App/Info.plist"), "rb") as fh:
        info = plistlib.load(fh)
    names = [s.get("NSMenuItem", {}).get("default", "") for s in info.get("NSServices", [])]
    return [n[len(SERVICES_PREFIX):] if n.startswith(SERVICES_PREFIX) else n for n in names if n]


def load_catalog():
    with open(CATALOG, encoding="utf-8") as fh:
        return json.load(fh)


def save_catalog(cat):
    cat["strings"] = dict(sorted(cat["strings"].items(), key=lambda kv: kv[0]))
    with open(CATALOG, "w", encoding="utf-8") as fh:
        json.dump(cat, fh, ensure_ascii=False, indent=2, separators=(",", " : "))
        fh.write("\n")


def placeholders(s):
    """Liczba argumentów: `%@` kolejno albo najwyższy numer `%n$@`."""
    t = s.replace("%%", "")
    positional = [int(n) for n in re.findall(r"%(\d+)\$@", t)]
    plain = len(re.findall(r"%@", t))
    return max([plain] + positional)


def translation(entry, lang):
    unit = entry.get("localizations", {}).get(lang, {}).get("stringUnit")
    return unit.get("value") if unit and unit.get("state") == "translated" else None


def cmd_extract():
    keys, errors = extract_keys()
    for e in errors:
        print("błąd:", e, file=sys.stderr)
    cat = load_catalog()
    strings = cat.setdefault("strings", {})
    added = 0
    for k in keys:
        e = strings.get(k)
        if e is None:
            strings[k] = {}
            added += 1
    # Teksty usunięte ze źródeł znikają z katalogu (razem z tłumaczeniami) — katalog = dokładnie klucze ze źródeł.
    removed = [k for k in strings if k not in keys]
    for k in removed:
        del strings[k]
    save_catalog(cat)
    print(f"klucze w źródłach: {len(keys)}, nowe: {added}, usunięte: {len(removed)}")
    return 1 if errors else 0


def cmd_check(strict):
    keys, errors = extract_keys()
    for e in errors:
        print("błąd:", e)
    strings = load_catalog().get("strings", {})
    missing = [k for k in keys if k not in strings]
    for k in missing[:50]:
        print(f"brak w katalogu: {keys[k]}: {k!r}")
    bad = 0
    for k, e in strings.items():
        for lang in LANGUAGES:
            t = translation(e, lang)
            if t is not None and placeholders(t) != placeholders(k):
                print(f"placeholdery [{lang}] {k!r} → {t!r}")
                bad += 1
    untranslated = 0
    if strict:
        for lang in LANGUAGES:
            n = sum(1 for k in keys if translation(strings.get(k, {}), lang) is None)
            if n:
                print(f"{lang}: bez tłumaczenia {n}")
                untranslated += n
    print(f"klucze: {len(keys)}, brak w katalogu: {len(missing)}, złe placeholdery: {bad}")
    return 1 if errors or missing or bad or untranslated else 0


def cmd_export(lang, limit):
    keys, _ = extract_keys()
    strings = load_catalog().get("strings", {})
    out = {k: "" for k in sorted(keys) if translation(strings.get(k, {}), lang) is None}
    if limit:
        out = dict(list(out.items())[:limit])
    json.dump(out, sys.stdout, ensure_ascii=False, indent=1)
    print()
    return 0


def cmd_import(lang, path):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    cat = load_catalog()
    strings = cat.setdefault("strings", {})
    ok = rejected = 0
    for k, v in data.items():
        if not isinstance(v, str) or not v.strip():
            continue
        if placeholders(v) != placeholders(k):
            print(f"odrzucone (placeholdery): {k!r} → {v!r}", file=sys.stderr)
            rejected += 1
            continue
        e = strings.setdefault(k, {})
        e.setdefault("localizations", {})[lang] = {"stringUnit": {"state": "translated", "value": v}}
        ok += 1
    save_catalog(cat)
    print(f"{lang}: zaimportowano {ok}, odrzucono {rejected}")
    return 1 if rejected else 0


def cmd_stats():
    keys, _ = extract_keys()
    strings = load_catalog().get("strings", {})
    print(f"klucze w źródłach: {len(keys)}, w katalogu: {len(strings)}")
    for lang in LANGUAGES:
        n = sum(1 for k in keys if translation(strings.get(k, {}), lang) is not None)
        print(f"  {lang}: {n}/{len(keys)}")
    return 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    c = argv[1]
    if c == "extract":
        return cmd_extract()
    if c == "check":
        return cmd_check("--strict" in argv)
    if c == "export" and len(argv) >= 3:
        return cmd_export(argv[2], int(argv[3]) if len(argv) > 3 else 0)
    if c == "import" and len(argv) == 4:
        return cmd_import(argv[2], argv[3])
    if c == "stats":
        return cmd_stats()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
