#!/usr/bin/env bash
# Teksty licencji bibliotek dołączanych do aplikacji w jednym pliku: ODPI-C (źródła w CODPI) i wszystkie pakiety SPM
# z Package.resolved projektu Xcode (OracleNIO z zależnościami, Sparkle, SwiftTerm z zależnościami, swift-sdk MCP
# z eventsource…) — z wersją i rewizją. Lista z Package.resolved, nie z katalogu checkouts (Xcode nie usuwa tam
# pakietów wypadłych z grafu); brak checkoutu albo licencji przypiętego pakietu = błąd.
# Oracle Instant Client nie jest dołączany (licencja Oracle — D7); użytkownik instaluje go sam.
# Użycie: scripts/third-party-licenses.sh plik_wyjściowy
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?Podaj plik wyjściowy}"
RESOLVED="$ROOT/Pelikan.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
CHECKOUTS="$ROOT/build/DerivedData.noindex/SourcePackages/checkouts"

section() {
    echo
    echo "----------------------------------------------------------------------"
    echo "$1 — $(basename "$2")"
    echo "----------------------------------------------------------------------"
    cat "$2"
}

# Wiersze „katalog<TAB>nazwa wersja (rewizja)”; katalog checkoutu = ostatni człon adresu bez .git.
pins="$(python3 -I -c '
import json, sys
for p in json.load(open(sys.argv[1]))["pins"]:
    s = p["state"]
    d = p["location"].rstrip("/").rsplit("/", 1)[-1]
    d = d[:-4] if d.endswith(".git") else d
    v = s.get("version") or s.get("branch") or "commit"
    print("%s\t%s %s (%s)" % (d, p["identity"], v, s["revision"][:7]))
' "$RESOLVED")"
[ -n "$pins" ] || { echo "Brak pakietów w $RESOLVED" >&2; exit 1; }

{
    echo "Pelikan — licencje bibliotek zewnętrznych"
    echo "========================================="
    echo
    echo "Pelikan: licencja MIT, © 2026 Andrzej Oleś w kooperacji z Claude AI (plik LICENSE w repozytorium)."
    for f in "$ROOT/Packages/PelikanKit/Sources/CODPI/LICENSE.txt" "$ROOT/Packages/PelikanKit/Sources/CODPI/NOTICE.txt"; do
        section "ODPI-C (oracle/odpi) v26.0.0" "$f"
    done
    while IFS=$'\t' read -r dir title; do
        [ -d "$CHECKOUTS/$dir" ] || { echo "Brak checkoutu $dir ($title) w $CHECKOUTS — najpierw zbuduj aplikację" >&2; exit 1; }
        found=0
        for f in "$CHECKOUTS/$dir"/{LICENSE,LICENSE.txt,LICENSE.md,NOTICE,NOTICE.txt}; do
            [ -f "$f" ] || continue
            section "$title" "$f"
            found=1
        done
        [ "$found" = 1 ] || { echo "Brak pliku licencji w $dir ($title)" >&2; exit 1; }
    done <<< "$pins"
} > "$OUT"
