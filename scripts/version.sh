#!/usr/bin/env bash
# Numer wersji z historii gita — nigdzie nie jest zapisany ręcznie. Scalony PR = commit „Merge pull request #…”
# w historii pierwszego rodzica (tak scala GitHub, dlatego PR scalaj zwykłym „Merge pull request”, nie squash);
# tytuł PR jest pierwszą niepustą linią treści tego commita.
#
# Od wydania 1.0.0 (D184) — numer semantyczny GŁÓWNY.ŚRODKOWY.OSTATNI:
# - scalenie PR #BASE_PR daje 1.0.0,
# - każdy późniejszy scalony PR podnosi numer wg prefiksu tytułu (konwencjonalne prefiksy):
#   „typ!: …” albo „BREAKING CHANGE” w tytule → GŁÓWNY (tylko na wyraźne słowo właściciela),
#   „feat…” → ŚRODKOWY (OSTATNI od 0), pozostałe (fix, docs, chore, test…) → OSTATNI.
# Commity po ostatnim scaleniu (gałąź robocza) nie zmieniają numeru.
#
# Przed scaleniem PR #BASE_PR (bety 1.0.0–10.5.0): GŁÓWNY.ŚRODKOWY.OSTATNI = 1 + PR/10 . PR mod 10 . commity od
# ostatniego scalonego PR — reguła z CantatePresentera; zostaje dla starych commitów i gałęzi sprzed 1.0.0.
#
# Numer kompilacji (CFBundleVersion) to liczba wszystkich commitów — rośnie zawsze, także przy przejściu z 10.5.0
# na 1.0.0, a po nim porównuje wersje Sparkle: scripts/version.sh --build.
# Bez gita (np. archiwum źródeł z GitHuba) używany jest plik VERSION, jeśli jest.
#
# Użycie: scripts/version.sh            wypisuje wersję
#         scripts/version.sh --build    wypisuje numer kompilacji
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PR=102

if git -C "$ROOT" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    if [ "${1:-}" = "--build" ]; then
        git -C "$ROOT" rev-list --count HEAD
        exit 0
    fi
    MERGES="$(git -C "$ROOT" log --first-parent --merges --grep='^Merge pull request #' --format=%H HEAD)"
    BASE="$(git -C "$ROOT" log --first-parent --merges --grep="^Merge pull request #$BASE_PR from " --format=%H HEAD)"
    if [ -n "$BASE" ]; then
        MAJOR=1 MINOR=0 PATCH=0
        while read -r sha; do
            [ -n "$sha" ] || continue
            title="$(git -C "$ROOT" log -1 --format=%b "$sha" | awk 'NF{print; exit}')"
            if [[ "$title" =~ ^[a-z]+(\([^\)]*\))?!: ]] || [[ "$title" == *"BREAKING CHANGE"* ]]; then
                MAJOR=$((MAJOR + 1)) MINOR=0 PATCH=0
            elif [[ "$title" =~ ^feat(\([^\)]*\))?: ]]; then
                MINOR=$((MINOR + 1)) PATCH=0
            else
                PATCH=$((PATCH + 1))
            fi
        done < <(git -C "$ROOT" log --first-parent --merges --reverse --grep='^Merge pull request #' --format=%H "$BASE..HEAD")
        VERSION="$MAJOR.$MINOR.$PATCH"
    else
        PRS="$(printf '%s' "$MERGES" | grep -c . || true)"
        # Pierwsza linia bez potoku do head (przy pipefail head potrafi przerwać printf sygnałem SIGPIPE).
        LAST="${MERGES%%$'\n'*}"
        if [ -n "$LAST" ]; then
            COMMITS="$(git -C "$ROOT" rev-list --count --first-parent "$LAST..HEAD")"
        else
            COMMITS="$(git -C "$ROOT" rev-list --count --first-parent HEAD)"
        fi
        VERSION="$((1 + PRS / 10)).$((PRS % 10)).$COMMITS"
    fi
elif [ -f "$ROOT/VERSION" ]; then
    VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
    [ "${1:-}" = "--build" ] && { echo 1; exit 0; }
else
    [ "${1:-}" = "--build" ] && { echo 1; exit 0; }
    VERSION="0.0.0"
fi
echo "$VERSION"
