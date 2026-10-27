#!/usr/bin/env bash
# Test reguły numeracji (scripts/version.sh, D184) na tymczasowym repozytorium: bety sprzed PR #BASE_PR,
# 1.0.0 po jego scaleniu, podnoszenie numeru wg prefiksu tytułu PR, numer kompilacji rosnący przy przejściu.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PR="$(awk -F= '/^BASE_PR=/{print $2}' "$ROOT/scripts/version.sh")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/scripts"
cp "$ROOT/scripts/version.sh" "$WORK/scripts/"
cd "$WORK"
# Bez globalnej i systemowej konfiguracji gita: commit.gpgsign, core.hooksPath czy szablony właściciela albo CI
# nie mogą zatrzymać testu (pytanie o klucz) ani uruchomić obcych hooków.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
git init -q -b main
git config user.email test@example.invalid
git config user.name test
git commit -q --allow-empty -m "init"

failures=0
# merge NR TYTUŁ — scalenie gałęzi z jednym commitem tak, jak robi to GitHub (temat i tytuł PR w treści).
merge() {
    git checkout -q -b "b$1"
    git commit -q --allow-empty -m "change $1"
    git checkout -q main
    git merge -q --no-ff "b$1" -m "Merge pull request #$1 from owner/b$1" -m "$2"
}
expect() {
    local got
    got="$(scripts/version.sh)"
    if [ "$got" = "$1" ]; then echo "ok   $1 — $2"; else echo "BŁĄD $2: oczekiwano $1, jest $got"; failures=$((failures + 1)); fi
}

for n in $(seq 1 $((BASE_PR - 1))); do merge "$n" "feat: beta $n"; done
git commit -q --allow-empty -m "commit po scaleniu"
expect "$((1 + (BASE_PR - 1) / 10)).$(((BASE_PR - 1) % 10)).1" "stara reguła przed PR #$BASE_PR"
build_before="$(scripts/version.sh --build)"
merge "$BASE_PR" "chore: version numbering from 1.0.0 (PL-INFRA-001)"
expect 1.0.0 "scalenie PR #$BASE_PR"
[ "$(scripts/version.sh --build)" -gt "$build_before" ] || { echo "BŁĄD numer kompilacji nie rośnie"; failures=$((failures + 1)); }
git commit -q --allow-empty -m "commit roboczy"
expect 1.0.0 "commit po scaleniu nie zmienia numeru"
merge $((BASE_PR + 1)) "fix(grid): sort order (PD-GRID-001)"
expect 1.0.1 "fix → ostatnia cyfra"
merge $((BASE_PR + 2)) "docs: manual"
expect 1.0.2 "docs → ostatnia cyfra"
merge $((BASE_PR + 3)) "feat(ob): connections in tree (PD-OB-001)"
expect 1.1.0 "feat → środkowa cyfra, ostatnia od 0"
merge $((BASE_PR + 4)) "fix: crash"
expect 1.1.1 "fix po feat"
merge $((BASE_PR + 5)) "feat!: new file format"
expect 2.0.0 "typ! → główna cyfra"
merge $((BASE_PR + 6)) "docs: explain BREAKING CHANGE policy"
expect 2.0.1 "BREAKING CHANGE w środku tytułu → ostatnia cyfra"
merge $((BASE_PR + 7)) "BREAKING CHANGE: settings format"
expect 3.0.0 "tytuł od BREAKING CHANGE: → główna cyfra"
merge $((BASE_PR + 8)) "fix(grid)!: drop old export API"
expect 4.0.0 "typ(zakres)! → główna cyfra"
merge $((BASE_PR + 9)) "feature flag cleanup"
expect 4.0.1 "tytuł bez prefiksu feat → ostatnia cyfra"
merge $((BASE_PR + 10)) ""
expect 4.0.2 "scalenie bez tytułu PR → ostatnia cyfra"

[ "$failures" = 0 ] || { echo "Błędy: $failures" >&2; exit 1; }
echo "Numeracja wersji: wszystkie przypadki poprawne"
