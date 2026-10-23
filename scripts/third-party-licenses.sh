#!/usr/bin/env bash
# Teksty licencji bibliotek dołączanych do aplikacji (ODPI-C, pakiety SPM: OracleNIO z zależnościami, Sparkle) w jednym
# pliku. Oracle Instant Client nie jest dołączany (licencja Oracle — D7); użytkownik instaluje go sam.
# Użycie: scripts/third-party-licenses.sh plik_wyjściowy
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?Podaj plik wyjściowy}"
{
    echo "Pelikan — licencje bibliotek zewnętrznych"
    echo "========================================="
    echo
    echo "Pelikan: licencja MIT, © 2026 Andrzej Oleś w kooperacji z Claude AI (plik LICENSE w repozytorium)."
    for f in "$ROOT/Packages/PelikanKit/Sources/CODPI/LICENSE.txt" "$ROOT/Packages/PelikanKit/Sources/CODPI/NOTICE.txt" \
             "$ROOT"/build/DerivedData.noindex/SourcePackages/checkouts/*/{LICENSE,LICENSE.txt,LICENSE.md,NOTICE,NOTICE.txt}; do
        [ -f "$f" ] || continue
        name="$(basename "$(dirname "$f")")"
        [ "$name" = "CODPI" ] && name="ODPI-C (oracle/odpi)"
        echo
        echo "----------------------------------------------------------------------"
        echo "$name — $(basename "$f")"
        echo "----------------------------------------------------------------------"
        cat "$f"
    done
} > "$OUT"
