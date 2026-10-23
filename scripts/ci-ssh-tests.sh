#!/bin/bash
# Testy SSH na lokalnym sshd w CI: każdy zestaw osobno, z limitem czasu; przy zawieszeniu — procesy i log testu.
set -u
cd "$(dirname "$0")/../Packages/PelikanKit" || exit 1
limit=${PELIKAN_SSH_TEST_LIMIT:-180}
status=0
for suite in PortedParserTests SpawnStreamTests PortedServerTests RemoteStreamTests SSHTargetTests BuildMessageParserTests SSHTargetTesterTests DeployScriptTests DeployPipelineTests; do
  grep -rqs "struct $suite\b" Tests/PelikanRemoteTests Tests/PelikanProCTests || continue
  log=$(mktemp)
  echo "::group::$suite"
  # Wyjście do pliku (nie potoku), żeby proces potomny trzymający deskryptor nie blokował końca.
  perl -e 'alarm shift; exec @ARGV' "$limit" swift test --skip-build --filter "\\.$suite/" >"$log" 2>&1
  rc=$?
  grep -E "✔|✘|↳|error|Test run with|Suite" "$log" | grep -v "Testing Library\|Target Platform" | tail -60
  echo "::endgroup::"
  if [ $rc -ne 0 ]; then
    status=1
    if [ $rc -eq 142 ]; then
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
