#!/usr/bin/env bash
# Przebieg zrzutów w tle (D30, D113, D196): aplikacja Debug uruchamiana bez aktywacji (open -g -n) z osobnym katalogiem
# danych i skryptem komend (PELIKAN_UI_SCRIPT). Okna są niewidoczne od pierwszej klatki (przezroczyste, bez myszy, cienia
# i ikony w Docku), a po ostatnim kroku aplikacja sama rysuje je do PNG (PELIKAN_SNAPSHOT) i kończy pracę — na ekranie
# nic się nie pojawia, nic nie steruje klawiaturą ani myszą. Połączenie z bazą testową przez portfel SEPS — bez hasła.
# --screen: dawny sposób — okna widoczne w tle i zrzuty `screencapture -l` (wymaga uprawnienia nagrywania ekranu).
# SCREENSHOTS_OUT — inny katalog wyników (próby bez zmian w docs/screenshots).
#
# Użycie: scripts/screenshots.sh [--screen] [scenariusz…]   (bez scenariuszy — wszystkie z scripts/screenshots/*.json)
set -euo pipefail
SCREEN=0
if [ "${1:-}" = "--screen" ]; then SCREEN=1; shift; fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/DerivedData.noindex/Build/Products/Debug/Pelikan.app"
OUT="${SCREENSHOTS_OUT:-$ROOT/docs/screenshots}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
TMP="${TMPDIR:-/tmp}"
TMP="${TMP%/}"

# Pozostałości przebiegów przerwanych bez sprzątania (SIGKILL, awaria): katalog, którego skrypt-właściciel już nie
# działa — jego niewidoczne instancje (z sesją w bazie testowej) są zamykane, katalog usuwany. Katalogi działających
# przebiegów (np. w innych worktree agentów) zostają.
for old in "$TMP"/pelikan-shots.*; do
    [ -d "$old" ] || continue
    owner=$(cat "$old/owner.pid" 2>/dev/null || true)
    if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then continue; fi
    # Katalog świeżo założony przez inny przebieg, który nie zdążył jeszcze zapisać owner.pid.
    m=$(stat -f %m "$old" 2>/dev/null) || continue
    if [ -z "$owner" ] && [ $(( $(date +%s) - m )) -lt 60 ]; then continue; fi
    pkill -f "$old/Pelikan.app/Contents/MacOS/Pelikan" 2>/dev/null || true
    "$LSREGISTER" -u "$old/Pelikan.app" 2>/dev/null || true
    rm -rf "$old"
done

# Stały katalog wersji sprzed D196 (bez sufiksu) — jednorazowo: klon wyrejestrowany, katalog usunięty; tylko gdy nic
# w nim nie zmieniło się od 10 minut (przebieg starszą wersją skryptu mógłby jeszcze trwać).
recent=""
[ -d "$TMP/pelikan-shots" ] && recent=$(/usr/bin/find "$TMP/pelikan-shots" -maxdepth 1 -mmin -10 2>/dev/null || true)
if [ -d "$TMP/pelikan-shots" ] && [ -z "$recent" ]; then
    pkill -f "$TMP/pelikan-shots/Pelikan.app/Contents/MacOS/Pelikan" 2>/dev/null || true
    "$LSREGISTER" -u "$TMP/pelikan-shots/Pelikan.app" 2>/dev/null || true
    rm -rf "$TMP/pelikan-shots"
fi

# Własny katalog przebiegu (równoległe przebiegi nie dzielą klonu aplikacji ani danych).
WORK=$(mktemp -d "$TMP/pelikan-shots.XXXXXX")
echo $$ > "$WORK/owner.pid"
RUN_APP="$WORK/Pelikan.app"
cleanup() {
    pkill -f "$RUN_APP/Contents/MacOS/Pelikan" 2>/dev/null || true
    "$LSREGISTER" -u "$RUN_APP" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Zawsze przyrostowe budowanie — stara binarka bez haków ukrywania pokazałaby okna na ekranie.
(cd "$ROOT" && make build)
# Kopia aplikacji z LSUIElement (D196): uruchomiona przez `open` od początku nie ma ikony w Docku ani paska menu (sama
# zmiana polityki aktywacji w kodzie przychodzi po starcie — ikona mignęłaby w Docku na pół sekundy). Klon APFS (bez
# kopiowania danych), bez rozszerzeń (Quick Look nie rejestruje się drugi raz), nowy podpis ad hoc z tymi samymi
# uprawnieniami i Hardened Runtime; po przebiegu wyrejestrowana z LaunchServices i usunięta.
cp -Rc "$APP" "$RUN_APP" 2>/dev/null || ditto "$APP" "$RUN_APP"
rm -rf "$RUN_APP/Contents/PlugIns"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$RUN_APP/Contents/Info.plist"
codesign --force --sign - --options runtime --preserve-metadata=entitlements "$RUN_APP" >/dev/null 2>&1 \
    || { echo "Nie udało się podpisać kopii aplikacji $RUN_APP" >&2; exit 1; }
if [ "$SCREEN" = 0 ]; then
    syms=$(nm -m "$RUN_APP"/Contents/MacOS/* 2>/dev/null || true)
    if [ "$(grep -c PKUIScriptWindows <<< "$syms" || true)" = 0 ]; then
        echo "Aplikacja bez haków ukrywania okien (UIScriptWindows.m) — przerwane, okna byłyby widoczne" >&2
        exit 1
    fi
fi

# Instant Client poza ~/Downloads (folder chroniony — aplikacja Debug wywołałaby pytanie macOS o dostęp).
if [ ! -d "$ROOT/.testdb/instantclient" ]; then
    shopt -s nullglob
    ics=("$HOME"/Downloads/instantclient_*)
    shopt -u nullglob
    [ ${#ics[@]} -gt 0 ] || { echo "Brak Instant Client (~/Downloads/instantclient_*)" >&2; exit 1; }
    IC=$(printf '%s\n' "${ics[@]}" | sort | tail -1)
    rsync -a "$IC/" "$ROOT/.testdb/instantclient/"
fi
# Katalog danych z połączeniem portfelowym — generowany przez kod Pelikana (test ScreenshotFixtureTests).
DATA="$WORK/data"
mkdir -p "$DATA"
(cd "$ROOT/Packages/PelikanKit" && PELIKAN_SCREENSHOT_FIXTURE="$DATA" swift test --filter ScreenshotFixtureTests >/dev/null)
scenarios=("$@")
if [ ${#scenarios[@]} -eq 0 ]; then
    for f in "$ROOT"/scripts/screenshots/*.json; do scenarios+=("$(basename "$f" .json)"); done
fi
# Ścieżka jako tekst zastępujący w sed (znaki \ | & dosłownie).
sed_escape() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }
OUT_SED=$(sed_escape "$OUT")
ROOT_SED=$(sed_escape "$ROOT")
failed=0
for name in "${scenarios[@]}"; do
    script="$ROOT/scripts/screenshots/$name.json"
    [ -f "$script" ] || { echo "Brak scenariusza $name" >&2; failed=1; continue; }
    run="$WORK/$name.json"
    # @OUT@ w scenariuszu — katalog zrzutów (bez ścieżek domowych w repozytorium).
    sed -e "s|@OUT@|$OUT_SED|g" -e "s|@ROOT@|$ROOT_SED|g" "$script" > "$run"
    rm -f "$run.done" "$run.log"
    rm -rf "$DATA/Recovery"
    started=$(date +%s)
    # Klon należy tylko do tego przebiegu — instancja poprzedniego scenariusza nie może zostać.
    pkill -f "$RUN_APP/Contents/MacOS/Pelikan" 2>/dev/null || true
    if [ "$SCREEN" = 0 ]; then
        open -g -n --env PELIKAN_DATA_DIR="$DATA" --env PELIKAN_UI_SCRIPT="$run" --env PELIKAN_SNAPSHOT="$OUT/$name" "$RUN_APP"
        for _ in $(seq 1 120); do [ -f "$run.done" ] && break; sleep 0.5; done
        [ -f "$run.done" ] || echo "$name: przebieg nie zakończył się w 60 s" >&2
        # Zrzuty zapisała aplikacja: „zrzut plik  tytuł  rozmiar” w dzienniku skryptu; pominięte okna dialogowe i okna
        # modalne też są w dzienniku.
        shots=$(sed -n 's/^[^ ]* zrzut //p' "$run.log" 2>/dev/null || true)
        if [ -z "$shots" ]; then
            echo "$name: brak zrzutów (dziennik: $run.log)" >&2
            cat "$run.log" >&2 2>/dev/null || true
            failed=1
        else
            echo "$shots"
            # Błędy zrzutu i zapisu: „nieudany: tytuł”, „nieudany zapis plik: błąd”.
            if grep -q '^nieudany' <<< "$shots"; then failed=1; fi
        fi
        sed -n -E 's/^[^ ]* ((pominięto okno dialogowe|okno modalne).*)/\1/p' "$run.log" >&2 2>/dev/null || true
        sleep 0.5
        pkill -f "$RUN_APP/Contents/MacOS/Pelikan" 2>/dev/null || true
        continue
    fi
    open -g -n --env PELIKAN_DATA_DIR="$DATA" --env PELIKAN_UI_SCRIPT="$run" --env PELIKAN_UI_SCRIPT_VISIBLE=1 "$RUN_APP"
    for _ in $(seq 1 120); do [ -f "$run.done" ] && break; sleep 0.5; done
    sleep 1.5
    pid=$(pgrep -f "$RUN_APP/Contents/MacOS/Pelikan" | tail -1 || true)
    [ -n "$pid" ] || { echo "$name: instancja scenariusza nie działa (nie wystartowała albo już się zakończyła) — bez zrzutu" >&2; failed=1; continue; }
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
exit "$failed"
