#!/bin/bash
# CI: ostrzeżenia kompilatora w kodzie pakietu (Sources/Tests) z dziennika `swift test`/`swift build` kończą krok błędem.
# Zależności zdalne SwiftPM i tak wycisza; ten krok łapie regresje widoczne tylko na jednej platformie (D166).
set -u
log=${1:?dziennik budowania}
# Bez kolorów i odnośników terminala (swift na Linuksie koloruje diagnostykę także w potoku).
warnings=$(perl -pe 's/\e\[[0-9;]*m//g; s/\e\]8;;.*?\e\\//g' "$log" \
  | grep -oE 'Packages/PelikanKit/(Sources|Tests)/[^:]+:[0-9]+:[0-9]+: warning: .*' | sort -u)
if [ -n "$warnings" ]; then
  echo "$warnings" | while IFS= read -r w; do echo "::warning::$w"; done
  echo "::error::ostrzeżenia kompilatora w kodzie pakietu: $(echo "$warnings" | wc -l | tr -d ' ')"
  exit 1
fi
echo "bez ostrzeżeń kompilatora w kodzie pakietu"
