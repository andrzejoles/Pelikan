#!/usr/bin/env python3
"""Wbudowane motywy kolorowania składni (D227) z repozytorium tinted-theming/schemes (MIT).

Użycie: scripts/syntax-schemes.py KATALOG_SCHEMES > Packages/PelikanKit/Sources/PelikanWorkspace/Syntax/SyntaxSchemesBuiltin.swift

KATALOG_SCHEMES to klon https://github.com/tinted-theming/schemes (podkatalogi base16/ i base24/). Do Pelikana trafia
tylko 16 barw palety (base00–base0F) wybranych schematów; przydział barw do kategorii tokenów robi
`SyntaxScheme.base16` (także dla schematów importowanych przez użytkownika).
"""
import os
import re
import sys

# (system, plik bez rozszerzenia, nazwa w Pelikanie albo None — nazwa ze schematu)
SCHEMES = [
    # Ciemne
    ("base16", "solarized-dark", None), ("base16", "selenized-dark", "Selenized Dark"), ("base16", "selenized-black", "Selenized Black"),
    ("base16", "gruvbox-dark-hard", "Gruvbox Dark Hard"), ("base16", "gruvbox-dark-medium", "Gruvbox Dark"),
    ("base16", "gruvbox-dark-soft", "Gruvbox Dark Soft"), ("base16", "gruvbox-material-dark-medium", "Gruvbox Material Dark"),
    ("base16", "dracula", None), ("base16", "monokai", None), ("base16", "nord", None), ("base16", "onedark", "One Dark"),
    ("base16", "tomorrow-night", None), ("base16", "tomorrow-night-eighties", None),
    ("base16", "github-dark", "GitHub Dark"), ("base16", "github-dark-dimmed", "GitHub Dark Dimmed"),
    ("base16", "github-dark-high-contrast", "GitHub Dark High Contrast"), ("base16", "github-dark-colorblind", "GitHub Dark Colorblind"),
    ("base16", "catppuccin-frappe", "Catppuccin Frappé"), ("base16", "catppuccin-macchiato", None), ("base16", "catppuccin-mocha", None),
    ("base16", "tokyo-night-dark", "Tokyo Night"), ("base16", "tokyo-night-storm", None), ("base16", "tokyo-night-moon", None),
    ("base16", "ayu-dark", None), ("base16", "ayu-mirage", None),
    ("base16", "material", None), ("base16", "material-darker", None), ("base16", "material-palenight", None),
    ("base16", "oceanicnext", "Oceanic Next"), ("base16", "rose-pine", None), ("base16", "rose-pine-moon", None),
    ("base16", "everforest", "Everforest Dark"), ("base16", "everforest-dark-hard", "Everforest Dark Hard"),
    ("base16", "kanagawa", None), ("base16", "kanagawa-dragon", None), ("base16", "darcula", "Darcula"),
    ("base24", "dark-plus", "Dark+ (Visual Studio Code)"), ("base16", "zenburn", None), ("base16", "nova", None),
    ("base16", "horizon-dark", None), ("base16", "shades-of-purple", "Shades of Purple"), ("base16", "spacemacs", None),
    ("base16", "papercolor-dark", "PaperColor Dark"), ("base16", "oxocarbon-dark", None), ("base16", "twilight", None),
    ("base16", "railscasts", None), ("base16", "jellybeans", None), ("base16", "irblack", "IR Black"),
    ("base16", "google-dark", None), ("base16", "windows-highcontrast", "Windows High Contrast"), ("base16", "edge-dark", None),
    ("base16", "flexoki-dark", None), ("base16", "vesper", None), ("base16", "xcode-dusk", "Xcode Dusk"),
    ("base16", "snazzy", None), ("base16", "seti", "Seti UI"), ("base16", "primer-dark", None),
    ("base16", "penumbra-dark-contrast-plus", "Penumbra Dark Contrast+"), ("base24", "cobalt2", "Cobalt2"),
    ("base24", "embarcadero", "Embarcadero"), ("base24", "borland", "Borland"), ("base24", "molokai", None),
    ("base24", "wombat", None),         # Jasne
    ("base16", "solarized-light", None), ("base16", "selenized-light", "Selenized Light"), ("base16", "selenized-white", "Selenized White"),
    ("base16", "gruvbox-light-hard", "Gruvbox Light Hard"), ("base16", "gruvbox-light-medium", "Gruvbox Light"),
    ("base16", "gruvbox-light-soft", "Gruvbox Light Soft"), ("base16", "gruvbox-material-light-medium", "Gruvbox Material Light"),
    ("base24", "alucard", "Alucard (Dracula Light)"), ("base16", "one-light", None), ("base16", "tomorrow", None),
    ("base16", "github", "GitHub Light"), ("base16", "github-light-high-contrast", "GitHub Light High Contrast"),
    ("base16", "github-light-colorblind", "GitHub Light Colorblind"), ("base16", "catppuccin-latte", None),
    ("base16", "tokyo-night-light", None), ("base16", "ayu-light", None), ("base16", "rose-pine-dawn", None),
    ("base16", "everforest-light-hard", "Everforest Light Hard"), ("base16", "everforest-light-medium", "Everforest Light"),
    ("base16", "nord-light", None), ("base16", "papercolor-light", "PaperColor Light"), ("base16", "oxocarbon-light", None),
    ("base16", "google-light", None), ("base16", "windows-highcontrast-light", "Windows High Contrast Light"),
    ("base16", "edge-light", None), ("base16", "flexoki-light", None), ("base16", "cupertino", "Cupertino (Xcode)"),
    ("base16", "primer-light", None), ("base16", "penumbra-light-contrast-plus", "Penumbra Light Contrast+"),
    ("base16", "atelier-sulphurpool-light", None),     ("base16", "ia-light", "iA Light"), ("base16", "standardized-light", "Standardized Light"),
            ]


def load(path):
    d = {"palette": {}}
    for line in open(path, encoding="utf-8"):
        m = re.match(r'\s*(\w+):\s*(?:"([^"]*)"|\'([^\']*)\'|([^#\s][^#]*?))\s*(?:#.*)?$', line)
        if not m:
            continue
        k = m.group(1)
        v = next(x for x in m.groups()[1:] if x is not None).strip()
        if re.fullmatch(r"base0[0-9A-Fa-f]", k):
            d["palette"][k.upper().replace("BASE", "base")] = v.lstrip("#").lower()
        elif k in ("name", "author", "variant"):
            d[k] = v
    return d


def swift(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def main():
    src = sys.argv[1]
    out, seen = [], set()
    for system, name, title in SCHEMES:
        path = next((p for p in (os.path.join(src, system, name + e) for e in (".yaml", ".yml")) if os.path.exists(p)), None)
        if not path:
            sys.exit(f"Brak schematu {system}/{name}")
        d = load(path)
        pal = [d["palette"]["base0%X" % i] for i in range(16)]
        dark = d.get("variant", "dark") == "dark"
        sid = name if system == "base16" else name + "-b24"
        assert sid not in seen, sid
        seen.add(sid)
        author = re.sub(r"\s*\(?<?https?://\S+>?\)?", "", d.get("author", "")).strip().rstrip(",")
        out.append(f'        B("{sid}", "{swift(title or d["name"])}", "{swift(author)}", {"true" if dark else "false"}, "{" ".join(pal)}"),')
    print("// Wygenerowane przez scripts/syntax-schemes.py z tinted-theming/schemes (MIT) — nie edytować ręcznie.")
    print("// Licencja palet: docs/licenses/tinted-theming-schemes.txt.")
    print("")
    print("extension SyntaxScheme {")
    print("    /// Palety base16 wbudowanych motywów (identyfikator, nazwa, autor, ciemny, base00…base0F).")
    print("    static let base16Builtin: [Base16Entry] = [")
    print("\n".join(out))
    print("    ]")
    print("}")
    print(f"// {len(out)} schematów", file=sys.stderr)


if __name__ == "__main__":
    main()
