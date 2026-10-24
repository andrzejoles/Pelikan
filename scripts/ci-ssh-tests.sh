#!/bin/bash
# Testy SSH na lokalnym sshd w CI: każdy zestaw osobno, z limitem czasu; przy zawieszeniu — procesy i log testu.
set -u
cd "$(dirname "$0")/../Packages/PelikanKit" || exit 1
limit=${PELIKAN_SSH_TEST_LIMIT:-180}
status=0
# Wszystkie zestawy z celów testowych SSH (krok testów jednostkowych je pomija) — nowy zestaw nie wypadnie z CI.
suites=$(grep -hoE '^(final class|struct) [A-Za-z0-9_]+Tests\b' Tests/PelikanRemoteTests/*.swift Tests/PelikanProCTests/*.swift | awk '{print $NF}' | sort -u)
[ -n "$suites" ] || { echo "::error::brak zestawów testów SSH"; exit 1; }
for suite in $suites; do
  log=$(mktemp)
  echo "::group::$suite"
  # Wyjście do pliku (nie potoku), żeby proces potomny trzymający deskryptor nie blokował końca; przez `script`
  # (pseudoterminal — buforowanie wierszami), żeby po przerwaniu w dzienniku zostały linie „started” zawieszonego testu.
  script -q "$log" perl -e 'alarm shift; exec @ARGV' "$limit" swift test --skip-build --filter "\\.$suite/" >/dev/null 2>&1 </dev/null
  rc=$?
  grep -E "✔|✘|↳|error|Test run with|Suite" "$log" | grep -v "Testing Library\|Target Platform" | tail -60
  echo "::endgroup::"
  if [ $rc -ne 0 ]; then
    status=1
    if [ $rc -eq 142 ] || [ $rc -eq 14 ]; then   # SIGALRM: 128+14, a przez `script` sam numer sygnału
      echo "::error::$suite przekroczył ${limit}s — rozpoczęte, niezakończone testy:"
      grep -o 'Test "[^"]*" started' "$log" | sed 's/ started$//' | sort -u > "$log.s"
      grep -oE 'Test "[^"]*" (passed|failed|skipped)' "$log" | sed -E 's/ (passed|failed|skipped)$//' | sort -u > "$log.f"
      comm -23 "$log.s" "$log.f"
      echo "--- procesy ssh/sshd ---"; ps -Ao pid,ppid,etime,command | grep -E "ssh|swiftpm|xctest" | grep -v grep | cut -c1-200
      for f in "${TMPDIR:-/tmp}"/pelikan-sshd-*/sshd.log; do [ -f "$f" ] && { echo "--- $f"; tail -20 "$f"; }; done
      pkill -f swiftpm-testing-helper || true
    else
      echo "::error::$suite zakończony kodem $rc"
    fi
  fi
  rm -f "$log" "$log.s" "$log.f"
done
exit $status
