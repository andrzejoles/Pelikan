#!/usr/bin/env bash
# Przebieg zrzutów w tle (D30): aplikacja Debug uruchamiana bez aktywacji (open -g -n) z osobnym katalogiem danych
# i skryptem komend (PELIKAN_UI_SCRIPT), zrzuty pojedynczych okien przez `screencapture -l` (okna nie wychodzą na
# wierzch, nic nie steruje klawiaturą ani myszą). Połączenie z bazą testową przez portfel SEPS — bez hasła.
#
# Użycie: scripts/screenshots.sh [scenariusz…]   (bez argumentów — wszystkie z scripts/screenshots/*.json)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/DerivedData.noindex/Build/Products/Debug/Pelikan.app"
OUT="$ROOT/docs/screenshots"
WORK="${TMPDIR:-/tmp}/pelikan-shots"
mkdir -p "$OUT" "$WORK"
[ -d "$APP" ] || (cd "$ROOT" && make build)
# Instant Client poza ~/Downloads (folder chroniony — aplikacja Debug wywołałaby pytanie macOS o dostęp).
if [ ! -d "$ROOT/.testdb/instantclient" ]; then
    IC=$(ls -d "$HOME"/Downloads/instantclient_* 2>/dev/null | sort | tail -1)
    [ -n "$IC" ] || { echo "Brak Instant Client" >&2; exit 1; }
    rsync -a "$IC/" "$ROOT/.testdb/instantclient/"
fi
# Katalog danych z połączeniem portfelowym — generowany przez kod Pelikana (test ScreenshotFixtureTests).
DATA="$WORK/data"
rm -rf "$DATA" && mkdir -p "$DATA"
(cd "$ROOT/Packages/PelikanKit" && PELIKAN_SCREENSHOT_FIXTURE="$DATA" swift test --filter ScreenshotFixtureTests >/dev/null)
scenarios=("$@")
if [ ${#scenarios[@]} -eq 0 ]; then
    for f in "$ROOT"/scripts/screenshots/*.json; do scenarios+=("$(basename "$f" .json)"); done
fi
for name in "${scenarios[@]}"; do
    script="$ROOT/scripts/screenshots/$name.json"
    [ -f "$script" ] || { echo "Brak scenariusza $name" >&2; continue; }
    run="$WORK/$name.json"
    # @OUT@ w scenariuszu — katalog zrzutów (bez ścieżek domowych w repozytorium).
    sed "s|@OUT@|$OUT|g" "$script" > "$run"
    rm -f "$run.done"
    rm -rf "$DATA/Recovery"
    open -g -n --env PELIKAN_DATA_DIR="$DATA" --env PELIKAN_UI_SCRIPT="$run" "$APP"
    for _ in $(seq 1 120); do [ -f "$run.done" ] && break; sleep 0.5; done
    sleep 1.5
    pid=$(pgrep -n -f "$APP/Contents/MacOS/Pelikan" || true)
    [ -n "$pid" ] || { echo "$name: aplikacja nie wystartowała" >&2; continue; }
    i=0
    while IFS=$'\t' read -r wid title size; do
        i=$((i + 1))
        file="$OUT/$name-$i.png"
        screencapture -l "$wid" -o -x "$file"
        echo "$name-$i.png  $title  $size"
    done < <(swift "$ROOT/scripts/screenshots/windows.swift" "$pid" 2>/dev/null)
    kill "$pid" 2>/dev/null || true
    sleep 1
done
