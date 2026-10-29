#!/usr/bin/env bash
# Przebieg zrzutów w tle (D30, D113, D196): aplikacja Debug uruchamiana bez aktywacji (open -g -n) z osobnym katalogiem
# danych i skryptem komend (PELIKAN_UI_SCRIPT). Okna są niewidoczne od pierwszej klatki (przezroczyste, bez myszy, cienia
# i ikony w Docku), a po ostatnim kroku aplikacja sama rysuje je do PNG (PELIKAN_SNAPSHOT) i kończy pracę — na ekranie
# nic się nie pojawia, nic nie steruje klawiaturą ani myszą. Połączenie z bazą testową przez portfel SEPS — bez hasła.
# --screen: dawny sposób — okna widoczne w tle i zrzuty `screencapture -l` (wymaga uprawnienia nagrywania ekranu).
#
# Użycie: scripts/screenshots.sh [--screen] [scenariusz…]   (bez scenariuszy — wszystkie z scripts/screenshots/*.json)
set -euo pipefail
SCREEN=0
if [ "${1:-}" = "--screen" ]; then SCREEN=1; shift; fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/DerivedData.noindex/Build/Products/Debug/Pelikan.app"
OUT="${SCREENSHOTS_OUT:-$ROOT/docs/screenshots}"   # SCREENSHOTS_OUT — inny katalog (próby bez zmian w docs)
WORK="${TMPDIR:-/tmp}/pelikan-shots"
mkdir -p "$OUT" "$WORK"
[ -d "$APP" ] || (cd "$ROOT" && make build)
# Kopia aplikacji z LSUIElement (D196): uruchomiona przez `open` od początku nie ma ikony w Docku ani paska menu (sama
# zmiana polityki aktywacji w kodzie przychodzi po starcie — ikona mignęłaby w Docku na pół sekundy). Klon APFS (bez
# kopiowania danych), nowy podpis ad hoc z tymi samymi uprawnieniami i Hardened Runtime; po przebiegu wyrejestrowana
# z LaunchServices i usunięta. Osobna ścieżka — instancje aplikacji Debug właściciela nie mylą się z instancjami zrzutów.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
RUN_APP="$WORK/Pelikan.app"
rm -rf "$RUN_APP"
cp -Rc "$APP" "$RUN_APP" 2>/dev/null || ditto "$APP" "$RUN_APP"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$RUN_APP/Contents/Info.plist"
codesign --force --sign - --options runtime --preserve-metadata=entitlements "$RUN_APP" >/dev/null 2>&1 \
    || { echo "Nie udało się podpisać kopii aplikacji $RUN_APP" >&2; exit 1; }
trap '"$LSREGISTER" -u "$RUN_APP" 2>/dev/null; rm -rf "$RUN_APP"' EXIT
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
    rm -f "$run.done" "$run.log"
    rm -rf "$DATA/Recovery"
    started=$(date +%s)
    # Instancje sprzed startu (np. pozostałe po przerwanym przebiegu) — tych nie wolno fotografować ani zamykać; zrzut
    # tylko z nowego procesu.
    before=" $(pgrep -f "$RUN_APP/Contents/MacOS/Pelikan" | tr '\n' ' ' || true) "
    if [ "$SCREEN" = 0 ]; then
        open -g -n --env PELIKAN_DATA_DIR="$DATA" --env PELIKAN_UI_SCRIPT="$run" --env PELIKAN_SNAPSHOT="$OUT/$name" "$RUN_APP"
        for _ in $(seq 1 120); do [ -f "$run.done" ] && break; sleep 0.5; done
        [ -f "$run.done" ] || echo "$name: przebieg nie zakończył się w 60 s" >&2
        # Zrzuty zapisała aplikacja: „zrzut plik  tytuł  rozmiar” w dzienniku skryptu.
        sed -n 's/^[^ ]* zrzut //p' "$run.log" 2>/dev/null || true
        sleep 0.5
        for p in $(pgrep -f "$RUN_APP/Contents/MacOS/Pelikan" || true); do
            [[ "$before" == *" $p "* ]] || kill "$p" 2>/dev/null || true
        done
        continue
    fi
    open -g -n --env PELIKAN_DATA_DIR="$DATA" --env PELIKAN_UI_SCRIPT="$run" --env PELIKAN_UI_SCRIPT_VISIBLE=1 "$RUN_APP"
    for _ in $(seq 1 120); do [ -f "$run.done" ] && break; sleep 0.5; done
    sleep 1.5
    pid=""
    for p in $(pgrep -f "$RUN_APP/Contents/MacOS/Pelikan" || true); do
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
