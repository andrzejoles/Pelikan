#!/usr/bin/env python3
"""Tłumaczenia nazw usług macOS (menu Usługi) — <język>.lproj/ServicesMenu.strings w zbudowanej aplikacji.

Nazwy w NSServices (App/Info.plist) mają przedrostek z nazwą aplikacji z Config/Brand.xcconfig, a klucze
ServicesMenu.strings muszą być nazwami po rozwinięciu — dlatego plik powstaje przy budowaniu (faza skryptu celu
Pelikan), z tłumaczeń w String Catalog (klucz = nazwa bez przedrostka; scripts/l10n.py dopisuje ją do katalogu).
Bez argumentów czyta zmienne budowania Xcode; `services-menu.py <Info.plist> <Resources>` — ręcznie.
"""
import json
import os
import plistlib
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "App/Resources/Localizable.xcstrings")
LANGS = ["en", "de", "es", "uk"]


def quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def main(argv):
    if len(argv) == 3:
        info_path, resources = argv[1], argv[2]
    else:
        build = os.environ["TARGET_BUILD_DIR"]
        info_path = os.path.join(build, os.environ["INFOPLIST_PATH"])
        resources = os.path.join(build, os.environ["UNLOCALIZED_RESOURCES_FOLDER_PATH"])
    with open(info_path, "rb") as fh:
        info = plistlib.load(fh)
    prefix = info["CFBundleName"] + ": "
    with open(CATALOG, encoding="utf-8") as fh:
        strings = json.load(fh)["strings"]
    names = [s["NSMenuItem"]["default"] for s in info.get("NSServices", []) if "NSMenuItem" in s]
    for lang in LANGS:
        lines = []
        for name in names:
            key = name[len(prefix):] if name.startswith(prefix) else name
            unit = strings.get(key, {}).get("localizations", {}).get(lang, {}).get("stringUnit", {})
            if unit.get("state") != "translated":
                print(f"error: brak tłumaczenia {lang} usługi „{key}” (scripts/l10n.py)", file=sys.stderr)
                return 1
            value = unit["value"]
            lines.append(f"{quote(name)} = {quote(prefix + value if name.startswith(prefix) else value)};")
        out = os.path.join(resources, f"{lang}.lproj")
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, "ServicesMenu.strings"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
