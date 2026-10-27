#!/usr/bin/env bash
# Zapisuje wersję i numer kompilacji z gita do build/Version.xcconfig (dołączany przez Config/Brand.xcconfig).
# Uruchamiany przed budowaniem: akcja wstępna schematu w Xcode, Makefile i scripts/build-installer.sh.
# Numeru wersji nie ma nigdzie w repozytorium.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/build"
OUT="$ROOT/build/Version.xcconfig"
# Akcja wstępna schematu dziedziczy środowisko budowania Xcode: nakładka /usr/bin/git (xcrun) wypisuje wtedy przy każdym
# wywołaniu „Warning: unknown environment variable SWIFT_DEBUG_INFORMATION_*”. Numer od tych zmiennych nie zależy.
version() { env -u SWIFT_DEBUG_INFORMATION_FORMAT -u SWIFT_DEBUG_INFORMATION_VERSION "$ROOT/scripts/version.sh" "$@"; }
NEW="MARKETING_VERSION = $(version)
CURRENT_PROJECT_VERSION = $(version --build)"
# Bez zmiany pliku, gdy wersja ta sama (inaczej Xcode przebudowuje wszystko).
[ -f "$OUT" ] && [ "$(cat "$OUT")" = "$NEW" ] || printf '%s\n' "$NEW" > "$OUT"
