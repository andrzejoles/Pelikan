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
    sed -e "s|@OUT@|$OUT|g" -e "s|@ROOT@|$ROOT|g" "$script" > "$run"
    rm -f "$run.done"
    rm -rf "$DATA/Recovery"
    started=$(date +%s)
    # Instancje sprzed startu (np. aplikacja Debug właściciela z tej samej ścieżki) — tych nie wolno fotografować ani
    # zamykać; zrzut tylko z nowego procesu.
    before=" $(pgrep -f "$APP/Contents/MacOS/Pelikan" | tr '\n' ' ' || true) "
    open -g -n --env PELIKAN_DATA_DIR="$DATA" --env PELIKAN_UI_SCRIPT="$run" "$APP"
    for _ in $(seq 1 120); do [ -f "$run.done" ] && break; sleep 0.5; done
    sleep 1.5
    pid=""
    for p in $(pgrep -f "$APP/Contents/MacOS/Pelikan" || true); do
        [[ "$before" == *" $p "* ]] || pid=$p
    done
    [ -n "$pid" ] || { echo "$name: instancja scenariusza nie działa (nie wystartowała albo już się zakończyła) — bez zrzutu" >&2; continue; }
    # Nazwa pliku od tytułu okna (kolejność okien między przebiegami nie jest stała): 17-narzedzia-dbms-scheduler.png,
    # okno główne — „glowne”; powtórzony tytuł dostaje numer.
    while IFS=$'\t' read -r wid title size; do
        slug=$(python3 -c 'import sys,re,unicodedata
t=sys.argv[1]
t="glowne" if t.startswith("Pelikan — ") else t
t=t.replace("ł","l").replace("Ł","L")
t=unicodedata.normalize("NFKD",t).encode("ascii","ignore").decode().lower()
print(re.sub(r"[^a-z0-9]+","-",t).strip("-") or "okno")' "$title")
        file="$OUT/$name-$slug.png"
        n=2
        while [ -f "$file" ] && [ "$(stat -f %m "$file")" -ge "$started" ]; do file="$OUT/$name-$slug-$n.png"; n=$((n + 1)); done
        screencapture -l "$wid" -o -x "$file"
        echo "$(basename "$file")  $title  $size"
    done < <(swift "$ROOT/scripts/screenshots/windows.swift" "$pid" 2>/dev/null)
    kill "$pid" 2>/dev/null || true
    sleep 1
done
