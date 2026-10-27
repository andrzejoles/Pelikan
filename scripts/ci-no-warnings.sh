#!/bin/bash
# CI: ostrzeżenia kompilatora w naszym kodzie (pakiet Sources/Tests, aplikacja App/) i ostrzeżenia linkera z dziennika
# `swift test`/`swift build`/`xcodebuild` kończą krok błędem. Zależności zdalne SwiftPM i Xcode i tak wyciszają (ich
# checkouty są dodatkowo pomijane); ten krok łapie regresje widoczne tylko na jednej platformie (D166).
set -u
log=${1:?dziennik budowania}
# Bez kolorów i odnośników terminala (swift na Linuksie koloruje diagnostykę także w potoku).
warnings=$(perl -pe 's/\e\[[0-9;]*m//g; s/\e\]8;;.*?\e\\//g' "$log" \
  | perl -ne 'next if m{/(?:SourcePackages|\.build)/checkouts/};
              if (m{(?:^|/)((?:App|Packages/PelikanKit/(?:Sources|Tests))/[^:\s]+:\d+:\d+: warning: .*)}) { print "$1\n" }
              elsif (/^(ld: warning: .*)/) { print "$1\n" }' \
  | sort -u)
if [ -n "$warnings" ]; then
  echo "$warnings" | while IFS= read -r w; do echo "::warning::$w"; done
  echo "::error::ostrzeżenia kompilatora lub linkera w naszym kodzie: $(echo "$warnings" | wc -l | tr -d ' ')"
  exit 1
fi
echo "bez ostrzeżeń kompilatora i linkera w naszym kodzie"
