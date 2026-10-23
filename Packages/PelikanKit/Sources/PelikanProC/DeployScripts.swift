import Foundation
import PelikanWorkspace

/// Kompresja kopii binarek na serwerze (narzędzie sprawdzane przez `whence`; brak — kopia bez kompresji).
public enum BackupCompression: String, Sendable, Codable, CaseIterable {
    case none, compress, gzip
}

/// Parametry jednego wdrożenia albo wycofania (zadanie Pro*C, „Pipeline Wdrożenie”). Znacznik czasu i tożsamość
/// użytkownika pochodzą z Maca — skrypt nie używa `date +%s` ani niczego spoza ksh88/AIX 6.1.
public struct DeployPlan: Sendable, Hashable {
    /// Identyfikator wdrożenia (nazwa skryptu `run-<id>.ksh`, wpis blokady i historii) — `[A-Za-z0-9-]`.
    public var id: String
    /// `YYYYmmddHHMMSS` (czas Maca) — przyrostek kopii binarek.
    public var timestamp: String
    /// `użytkownik@host-Maca` — zapisywane w blokadzie i historii.
    public var owner: String
    /// Ile ostatnich kopii każdej binarki zostawić w katalogu backupów.
    public var retention: Int
    public var compression: BackupCompression
    /// Katalog, w którym `make` zostawia binarki (pusty — `<baza>/src`).
    public var outputDirectory: String

    public init(id: String = DeployPlan.newID(), timestamp: String = DeployPlan.timestamp(), owner: String,
                retention: Int = 5, compression: BackupCompression = .compress, outputDirectory: String = "") {
        self.id = id; self.timestamp = timestamp; self.owner = owner; self.retention = retention
        self.compression = compression; self.outputDirectory = outputDirectory
    }

    public static func newID() -> String { String(UUID().uuidString.lowercased().prefix(13)) }

    public static func timestamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyyMMddHHmmss"
        return f.string(from: date)
    }
}

/// Źródło wycofania binarki: poprzednia wersja `<bin>/<nazwa>.prev` albo kopia z katalogu backupów.
public enum RollbackSource: Sendable, Hashable {
    case previous
    case backup(String)
}

/// Kopia binarki w katalogu backupów: `nazwa.YYYYmmddHHMMSS.<krótki-commit>[.Z|.gz]`.
public struct BackupEntry: Sendable, Hashable, Identifiable {
    public var fileName: String
    public var binary: String
    public var timestamp: String
    public var commit: String
    public var compression: BackupCompression
    public var id: String { fileName }

    /// Rozpoznanie nazwy pliku kopii dla znanych binarek (nazwa binarki może zawierać kropki).
    public static func parse(_ fileName: String, binaries: [String]) -> BackupEntry? {
        for b in binaries.sorted(by: { $0.count > $1.count }) where fileName.hasPrefix(b + ".") {
            var rest = String(fileName.dropFirst(b.count + 1))
            var comp = BackupCompression.none
            if rest.hasSuffix(".Z") { comp = .compress; rest.removeLast(2) } else if rest.hasSuffix(".gz") { comp = .gzip; rest.removeLast(3) }
            let parts = rest.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].count == 14, parts[0].allSatisfy(\.isNumber),
                  !parts[1].isEmpty, parts[1].allSatisfy({ $0.isHexDigit }) else { continue }
            return BackupEntry(fileName: fileName, binary: b, timestamp: String(parts[0]), commit: String(parts[1]), compression: comp)
        }
        return nil
    }

    /// Lista z wyjścia `ls -t` (najnowsze pierwsze), tylko pliki kopii znanych binarek.
    public static func list(_ lsOutput: String, binaries: [String]) -> [BackupEntry] {
        lsOutput.split(whereSeparator: \.isNewline).compactMap { parse(String($0).trimmingCharacters(in: .whitespaces), binaries: binaries) }
    }
}

/// Błąd przygotowania skryptu (wartości, których nie wolno podstawić).
public enum DeployScriptError: Error, Equatable, LocalizedError {
    case invalidBinaryName(String)
    case invalidIdentifier(String)
    case invalidPath(String)
    case emptyBuildCommand

    public var errorDescription: String? {
        switch self {
        case .invalidBinaryName(let n): L10n.tr("Niedozwolona nazwa binarki „\(n)” (dozwolone litery, cyfry, kropka, podkreślenie, minus, plus)")
        case .invalidIdentifier(let n): L10n.tr("Niedozwolony identyfikator wdrożenia „\(n)”")
        case .invalidPath(let p): L10n.tr("Ścieżka na serwerze musi być bezwzględna: „\(p)”")
        case .emptyBuildCommand: L10n.tr("Komenda builda jest pusta")
        }
    }
}

/// Skrypty po stronie serwera (ksh88, AIX 6.1): podstawianie wyłącznie przez `shellQuote`, kod wyjścia sprawdzany po
/// każdej komendzie (`|| fail …`), bez polegania na kodzie potoków, znaczniki `@@STEP nazwa` / `@@END nazwa kod`,
/// komendy parsowane z `LC_ALL=C`, `cd` zamiast `git -C`. Zakazane konstrukcje — `forbiddenConstructs`.
public enum DeployScripts {
    static func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// Kody wyjścia skryptów (stałe — interpretuje je `DeployProgress`).
    public enum Exit {
        public static let locked: Int32 = 10, staleLock: Int32 = 11, lockWrite: Int32 = 12
        public static let dirty: Int32 = 20, noWorkingCopy: Int32 = 21, wrongBranch: Int32 = 22, statusFailed: Int32 = 23
        public static let headFailed: Int32 = 31, fetchFailed: Int32 = 32, noFastForward: Int32 = 33
        public static let backupFailed: Int32 = 41
        public static let buildFailed: Int32 = 50, noSourceDirectory: Int32 = 51
        public static let missingBinary: Int32 = 61, installFailed: Int32 = 62
        public static let rollbackMissing: Int32 = 71, rollbackFailed: Int32 = 72
    }

    static func validate(_ t: PelikanSSHTarget, _ plan: DeployPlan) throws {
        guard plan.id.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil else { throw DeployScriptError.invalidIdentifier(plan.id) }
        for b in t.effectiveBinaries { try validateBinary(b) }
        for p in [t.baseDirectory, t.backupDirectory, t.effectiveWorkingCopy] where !p.hasPrefix("/") { throw DeployScriptError.invalidPath(p) }
        if !plan.outputDirectory.isEmpty, !plan.outputDirectory.hasPrefix("/") { throw DeployScriptError.invalidPath(plan.outputDirectory) }
    }

    static func validateBinary(_ b: String) throws {
        guard b.range(of: #"^[A-Za-z0-9_.+-]+$"#, options: .regularExpression) != nil, b != ".", b != ".." else {
            throw DeployScriptError.invalidBinaryName(b)
        }
    }

    /// Katalog blokady.
    public static func lockDirectory(_ t: PelikanSSHTarget) -> String { PelikanSSHTarget.join(t.pelikanDirectory, ".lock") }
    /// Historia wdrożeń na serwerze (linie `czas|id|właściciel|rodzaj|przed|po|krok|kod`).
    public static func historyFile(_ t: PelikanSSHTarget) -> String { PelikanSSHTarget.join(t.pelikanDirectory, "history.log") }
    /// Ścieżka skryptu uruchomieniowego.
    public static func scriptPath(_ t: PelikanSSHTarget, id: String) -> String { PelikanSSHTarget.join(t.pelikanDirectory, "run-\(id).ksh") }

    /// Nagłówek: zmienne (wartości przez `shellQuote`), funkcje znaczników, blokada z wykryciem przeterminowanej.
    static func header(_ t: PelikanSSHTarget, _ plan: DeployPlan, kind: String) -> String {
        """
        # Pelikan: \(kind) \(plan.id) (skrypt wygenerowany, ksh88; nie edytować)
        PD=\(q(t.pelikanDirectory))
        LOCK=\(q(lockDirectory(t)))
        HIST=\(q(historyFile(t)))
        WC=\(q(t.effectiveWorkingCopy))
        SRC=\(q(t.sourceDirectory))
        BIN=\(q(t.binaryDirectory))
        BK=\(q(t.backupDirectory))
        OUT=\(q(plan.outputDirectory.isEmpty ? t.sourceDirectory : plan.outputDirectory))
        BRANCH=\(q(t.branch))
        REMOTE=\(q(t.remote))
        ID=\(q(plan.id))
        TS=\(q(plan.timestamp))
        OWNER=\(q(plan.owner))
        KIND=\(q(kind))
        BEFORE=
        AFTER=
        GIT_PAGER=cat
        export GIT_PAGER
        PAGER=cat
        export PAGER
        step() {
          echo "@@STEP $1"
        }
        end() {
          echo "@@END $1 $2"
        }
        record() {
          echo "$TS|$ID|$OWNER|$KIND|$BEFORE|$AFTER|$1|$2" >> "$HIST" 2>/dev/null
        }
        fail() {
          record "$1" "$2"
          end "$1" "$2"
          exit "$2"
        }
        step lock
        if mkdir "$LOCK" 2>/dev/null; then
          :
        else
          echo "@@LOCKINFO"
          if [ -f "$LOCK/info" ]; then
            cat "$LOCK/info"
          fi
          echo "@@LOCKINFO_END"
          LPID=
          if [ -f "$LOCK/info" ]; then
            LPID=`sed -n 's/^pid=//p' "$LOCK/info"`
          fi
          if [ -n "$LPID" ]; then
            if kill -0 "$LPID" 2>/dev/null; then
              end lock \(Exit.locked)
              exit \(Exit.locked)
            fi
          fi
          end lock \(Exit.staleLock)
          exit \(Exit.staleLock)
        fi
        trap 'rm -rf "$LOCK"' 0
        trap 'rm -rf "$LOCK"; exit 129' 1 2 15
        echo "id=$ID" > "$LOCK/info" || fail lock \(Exit.lockWrite)
        echo "owner=$OWNER" >> "$LOCK/info" || fail lock \(Exit.lockWrite)
        echo "time=$TS" >> "$LOCK/info" || fail lock \(Exit.lockWrite)
        echo "pid=$$" >> "$LOCK/info" || fail lock \(Exit.lockWrite)
        end lock 0

        """
    }

    /// Pełne wdrożenie: blokada → kontrola working copy → `git pull --ff-only` → backup → build → instalacja → historia.
    public static func deploy(_ t: PelikanSSHTarget, plan: DeployPlan) throws -> String {
        try validate(t, plan)
        let build = t.buildCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !build.isEmpty else { throw DeployScriptError.emptyBuildCommand }
        let binaries = t.effectiveBinaries.map(q).joined(separator: " ")
        let short = "SHORT=`echo \"$BEFORE\" | cut -c1-8`"
        var s = header(t, plan, kind: "deploy")
        s += """
        step check
        cd "$WC" || fail check \(Exit.noWorkingCopy)
        CUR=`git symbolic-ref HEAD 2>/dev/null`
        if [ "$CUR" != "refs/heads/$BRANCH" ]; then
          echo "@@BRANCH $CUR"
          fail check \(Exit.wrongBranch)
        fi
        LC_ALL=C git status --porcelain > "$PD/status-$ID.txt" 2>&1 || fail check \(Exit.statusFailed)
        if [ -s "$PD/status-$ID.txt" ]; then
          echo "@@DIRTY_BEGIN"
          cat "$PD/status-$ID.txt"
          echo "@@DIRTY_END"
          LC_ALL=C git --no-pager diff --stat
          LC_ALL=C git --no-pager diff | head -400
          rm -f "$PD/status-$ID.txt"
          fail check \(Exit.dirty)
        fi
        rm -f "$PD/status-$ID.txt"
        end check 0

        step pull
        BEFORE=`git rev-parse HEAD` || fail pull \(Exit.headFailed)
        echo "@@HEAD_BEFORE $BEFORE"
        git fetch "$REMOTE" || fail pull \(Exit.fetchFailed)
        if git pull --ff-only "$REMOTE" "$BRANCH"; then
          :
        else
          echo "@@NO_FF"
          fail pull \(Exit.noFastForward)
        fi
        AFTER=`git rev-parse HEAD` || fail pull \(Exit.headFailed)
        echo "@@HEAD_AFTER $AFTER"
        end pull 0

        step backup
        \(short)
        for B in \(binaries); do
          if [ -f "$BIN/$B" ]; then
            F="$BK/$B.$TS.$SHORT"
            cp -p "$BIN/$B" "$F" || fail backup \(Exit.backupFailed)
        \(compressionBlock(plan.compression))
            FN=`basename "$F"`
            echo "@@BACKUP $FN"
          else
            echo "@@NOBINARY $B"
          fi
        done
        \(retentionBlock(t, keep: plan.retention))
        end backup 0

        step build
        cd "$SRC" || fail build \(Exit.noSourceDirectory)
        \(build)
        RC=$?
        if [ $RC -ne 0 ]; then
          record build $RC
          end build $RC
          exit \(Exit.buildFailed)
        fi
        end build 0

        step install
        for B in \(binaries); do
          if [ -f "$OUT/$B" ]; then
            :
          else
            echo "@@MISSING $B"
            fail install \(Exit.missingBinary)
          fi
          cp -p "$OUT/$B" "$BIN/$B.new" || fail install \(Exit.installFailed)
        done
        for B in \(binaries); do
          if [ -f "$BIN/$B" ]; then
            mv -f "$BIN/$B" "$BIN/$B.prev" || fail install \(Exit.installFailed)
          fi
          mv -f "$BIN/$B.new" "$BIN/$B" || fail install \(Exit.installFailed)
          echo "@@INSTALLED $B"
        done
        end install 0

        step history
        record done 0
        end history 0
        echo "@@DONE"
        exit 0

        """
        return s
    }

    static func compressionBlock(_ c: BackupCompression) -> String {
        switch c {
        case .none: return ""
        case .compress:
            // `compress` nie zmienia pliku, gdy kompresja nic nie daje (kod 2) — wtedy kopia zostaje bez `.Z`.
            return """
                if whence compress >/dev/null 2>&1; then
                  compress -f "$F" 2>/dev/null
                  if [ -f "$F.Z" ]; then
                    F="$F.Z"
                  fi
                fi
            """
        case .gzip:
            return """
                if whence gzip >/dev/null 2>&1; then
                  gzip -f "$F" 2>/dev/null
                  if [ -f "$F.gz" ]; then
                    F="$F.gz"
                  fi
                fi
            """
        }
    }

    /// Retencja: dla każdej binarki zostaje `keep` najnowszych kopii (`ls -t`; numer linii wyliczony w Pelikanie —
    /// bez arytmetyki w skrypcie).
    static func retentionBlock(_ t: PelikanSSHTarget, keep: Int) -> String {
        let first = max(1, keep) + 1
        return t.effectiveBinaries.map { b in
            // Wyrażenie podstawowe (BRE) grep z AIX: z dozwolonych znaków nazwy tylko kropka wymaga ucieczki.
            let pattern = "^" + b.replacingOccurrences(of: ".", with: "\\.") + "\\.[0-9]\\{14\\}\\."
            return "( cd \"$BK\" && LC_ALL=C ls -t | grep \(q(pattern)) | sed -n '\(first),$p' | while read OLD; do rm -f \"$OLD\"; done )"
        }.joined(separator: "\n")
    }

    /// Wycofanie binarki z `.prev` (zamiana miejscami) albo z kopii (rozpakowanie do `.new`, prawa z bieżącej binarki).
    public static func rollback(_ t: PelikanSSHTarget, plan: DeployPlan, binary: String, source: RollbackSource) throws -> String {
        try validate(t, plan)
        try validateBinary(binary)
        var s = header(t, plan, kind: "rollback")
        s += """
        step rollback
        B=\(q(binary))

        """
        switch source {
        case .previous:
            s += """
            if [ -f "$BIN/$B.prev" ]; then
              :
            else
              fail rollback \(Exit.rollbackMissing)
            fi
            cp -p "$BIN/$B.prev" "$BIN/$B.new" || fail rollback \(Exit.rollbackFailed)

            """
        case .backup(let file):
            guard let entry = BackupEntry.parse(file, binaries: [binary]) else { throw DeployScriptError.invalidBinaryName(file) }
            let unpack = switch entry.compression {
            case .compress: "uncompress -c \"$F\" > \"$BIN/$B.new\" || fail rollback \(Exit.rollbackFailed)"
            case .gzip: "gzip -dc \"$F\" > \"$BIN/$B.new\" || fail rollback \(Exit.rollbackFailed)"
            case .none: "cp -p \"$F\" \"$BIN/$B.new\" || fail rollback \(Exit.rollbackFailed)"
            }
            s += """
            F="$BK/"\(q(entry.fileName))
            if [ -f "$F" ]; then
              :
            else
              fail rollback \(Exit.rollbackMissing)
            fi
            if [ -f "$BIN/$B" ]; then
              cp -p "$BIN/$B" "$BIN/$B.new" || fail rollback \(Exit.rollbackFailed)
            fi
            \(unpack)
            chmod u+x "$BIN/$B.new" || fail rollback \(Exit.rollbackFailed)

            """
        }
        s += """
        if [ -f "$BIN/$B" ]; then
          mv -f "$BIN/$B" "$BIN/$B.prev" || fail rollback \(Exit.rollbackFailed)
        fi
        mv -f "$BIN/$B.new" "$BIN/$B" || fail rollback \(Exit.rollbackFailed)
        echo "@@INSTALLED $B"
        end rollback 0
        record done 0
        echo "@@DONE"
        exit 0

        """
        return s
    }

    /// Zdjęcie własnej blokady (po Stop albo zerwaniu połączenia): tylko gdy w `info` jest identyfikator tego wdrożenia.
    public static func releaseOwnLockCommand(_ t: PelikanSSHTarget, id: String) -> String {
        let lock = q(lockDirectory(t))
        return "if [ -f \(lock)/info ]; then if grep \(q("^id=\(id)$")) \(lock)/info >/dev/null 2>&1; then rm -rf \(lock); echo released; fi; fi; exit 0"
    }

    /// Ręczne zdjęcie cudzej albo przeterminowanej blokady (tylko po potwierdzeniu użytkownika).
    public static func forceReleaseLockCommand(_ t: PelikanSSHTarget) -> String {
        "rm -rf \(q(lockDirectory(t))) && echo released"
    }

    /// Lista kopii w katalogu backupów (najnowsze pierwsze).
    public static func listBackupsCommand(_ t: PelikanSSHTarget) -> String {
        "cd \(q(t.backupDirectory)) && LC_ALL=C ls -t"
    }

    /// Ostatnie wpisy historii na serwerze.
    public static func serverHistoryCommand(_ t: PelikanSSHTarget, lines: Int = 200) -> String {
        "if [ -f \(q(historyFile(t))) ]; then tail -\(max(1, lines)) \(q(historyFile(t))); fi; exit 0"
    }

    /// Commit working copy na serwerze.
    public static func serverHeadCommand(_ t: PelikanSSHTarget) -> String {
        "cd \(q(t.effectiveWorkingCopy)) && git rev-parse HEAD"
    }

    /// Przygotowanie katalogu roboczego Pelikana przed wysłaniem skryptu.
    public static func prepareCommand(_ t: PelikanSSHTarget) -> String {
        "mkdir -p \(q(t.pelikanDirectory))"
    }

    /// Usunięcie skryptu po zakończeniu.
    public static func cleanupCommand(_ t: PelikanSSHTarget, id: String) -> String {
        "rm -f \(q(scriptPath(t, id: id))); exit 0"
    }

    /// Konstrukcje spoza ksh88/AIX 6.1 (lista z zadania Pro*C) znalezione w skrypcie — testy pilnują, żeby była pusta.
    public static func forbiddenConstructs(_ script: String) -> [String] {
        let rules: [(String, String)] = [
            ("set -o pipefail", #"set\s+-o\s+pipefail"#),
            ("local", #"(^|[;\s])local\s"#),
            ("typeset -A", #"typeset\s+-A"#),
            ("${v//a/b}", #"\$\{[^}]*//"#),
            ("sed -i", #"sed\s+-i"#),
            ("stat", #"(^|[;\s|])stat\s"#),
            ("mktemp", #"mktemp"#),
            ("md5sum/sha256sum", #"md5sum|sha256sum"#),
            ("date +%s", #"date\s+\+%s"#),
            ("tar -z", #"tar\s+-?[a-y]*z"#),
            ("xargs -0", #"xargs\s+-0"#),
            ("[[ ]]", #"\[\["#),
            ("$(< plik)", #"\$\(<"#),
            ("git -C", #"git\s+-C"#),
            ("find -maxdepth/-printf", #"-maxdepth|-printf"#),
            ("echo -e", #"echo\s+-e"#),
        ]
        let lines = script.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        let body = lines.joined(separator: "\n")
        return rules.compactMap { name, pattern in
            body.range(of: pattern, options: [.regularExpression]) != nil ? name : nil
        }
    }
}
