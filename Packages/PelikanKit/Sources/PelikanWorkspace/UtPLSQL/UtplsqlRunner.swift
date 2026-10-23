import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import PelikanDB

/// Uruchamianie testów utPLSQL (PROMPT §6, docs/research/utplsql.md): sesja produkująca wykonuje `ut_runner.run`
/// z `ut_realtime_reporter`, sesja konsumująca czyta zdarzenia XML z `get_lines_cursor` na bieżąco.
@MainActor
public enum UtplsqlRunner {
    /// Wersja utPLSQL w bazie (`ut_runner.version`) albo nil, gdy nie jest zainstalowany / niedostępny.
    public static func version(_ s: any DatabaseSession) async -> String? {
        try? await s.scalar("select ut_runner.version from dual")
    }

    static func reporterID() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased() }

    /// Inicjuje bufory reporterów przed startem producenta i konsumenta: `output_buffer.init` robi MERGE do
    /// `ut_output_buffer_info_tmp`, a równoczesne pierwsze wstawienie z obu sesji kończy się ORA-00001 (wtedy konsument
    /// czeka do limitu czasu). Po tym wywołaniu kolejne `init` tylko aktualizują istniejący wiersz.
    static func initBuffers(_ reporters: [(type: String, id: String)], session s: any DatabaseSession) async throws {
        var block = "begin\n"
        var binds: [BindVariable] = []
        for (i, r) in reporters.enumerated() {
            block += "  declare r \(r.type) := \(r.type)(); begin r.set_reporter_id(:id\(i)); r.output_buffer.init(); end;\n"
            binds.append(BindVariable(name: "id\(i)", value: .text(r.id)))
        }
        _ = try await s.execute(block + "end;", binds: binds)
    }

    static func literalList(_ items: [String]) -> String {
        "ut_varchar2_list(" + items.map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" }.joined(separator: ", ") + ")"
    }

    /// Uruchamia testy ze ścieżek (`schemat`, `schemat.pakiet[.procedura]`, `schemat:suitepath`); `coverage` — schematy,
    /// dla których zbierane jest pokrycie (puste — bez pokrycia). Zwraca przebieg aktualizowany na żywo.
    /// `purposes` — sesje produkująca i konsumująca (agent uruchamia testy w swoich sesjach).
    public static func start(paths: [String], coverageSchemes: [String] = [], in ws: Workspace, connectionID: UUID,
                             purposes: (SessionPurpose, SessionPurpose) = (.utplsql("run"), .utplsql("events"))) async throws -> UtplsqlRun {
        let run = UtplsqlRun(paths: paths)
        let producer = try await ws.sessions.session(SessionKey(connectionID: connectionID, purpose: purposes.0))
        let consumer = try await ws.sessions.session(SessionKey(connectionID: connectionID, purpose: purposes.1))
        guard await version(producer) != nil else {
            throw CommandError.notAvailable(L10n.tr("utPLSQL nie jest zainstalowany albo niedostępny dla tego użytkownika (ut_runner)"))
        }
        // utPLSQL zmienia dane w transakcji testów i wycofuje je (savepointy) — strażnik jak dla bloku PL/SQL.
        try await ws.guardModification(["BEGIN ut_runner.run; END;"], connectionID: connectionID)
        let rid = reporterID(), sonarID = reporterID(), htmlID = reporterID()
        let coverage = !coverageSchemes.isEmpty
        let block = """
            declare
              r ut_realtime_reporter := ut_realtime_reporter();
              \(coverage ? "s ut_coverage_sonar_reporter := ut_coverage_sonar_reporter(); h ut_coverage_html_reporter := ut_coverage_html_reporter();" : "")
            begin
              r.set_reporter_id(:rid);
              r.output_buffer.init();
              \(coverage ? "s.set_reporter_id(:sid); s.output_buffer.init(); h.set_reporter_id(:hid); h.output_buffer.init();" : "")
              ut_runner.run(a_paths => \(literalList(paths)), a_reporters => ut_reporters(r\(coverage ? ", s, h" : ""))\(coverage ? ", a_coverage_schemes => " + literalList(coverageSchemes.map { $0.uppercased() }) : ""));
            end;
            """
        var binds = [BindVariable(name: "rid", value: .text(rid))]
        if coverage { binds += [BindVariable(name: "sid", value: .text(sonarID)), BindVariable(name: "hid", value: .text(htmlID))] }
        try await initBuffers([("ut_realtime_reporter", rid)] + (coverage ? [("ut_coverage_sonar_reporter", sonarID), ("ut_coverage_html_reporter", htmlID)] : []),
                              session: producer)
        let produce = Task.detached { try await producer.execute(block, binds: binds) }
        activeProducers[run.id] = producer
        Task {
            do {
                try await consume(reporter: "ut_realtime_reporter", id: rid, session: consumer) { xml in
                    if let e = UtEvent.parse(xml) { run.apply(e) }
                }
                _ = try await produce.value
                if coverage {
                    var sonar = ""
                    try await consume(reporter: "ut_coverage_sonar_reporter", id: sonarID, session: consumer) { sonar += $0 }
                    run.coverage = parseSonarCoverage(sonar)
                    var html = ""
                    try await consume(reporter: "ut_coverage_html_reporter", id: htmlID, session: consumer) { html += $0 }
                    run.coverageHTML = html
                }
                run.markFinished()
            } catch {
                _ = try? await produce.value
                run.markFinished(error: error.localizedDescription)
            }
            activeProducers[run.id] = nil
            ws.lastUtplsqlRun = run
        }
        ws.lastUtplsqlRun = run
        return run
    }

    /// Sesje produkujące aktywnych przebiegów (przerwanie).
    static var activeProducers: [UUID: any DatabaseSession] = [:]

    /// Przerywa przebieg (OCIBreak w sesji produkującej).
    public static func cancel(_ run: UtplsqlRun) {
        activeProducers[run.id]?.breakExecution()
    }

    /// Czyta wiersze bufora reportera po jednym (zdarzenia na bieżąco) aż do końca przebiegu.
    static func consume(reporter: String, id: String, session s: any DatabaseSession, row: (String) -> Void) async throws {
        let r = try await s.execute("""
            declare rep \(reporter) := \(reporter)(); begin rep.set_reporter_id(:id); :c := rep.get_lines_cursor(a_initial_timeout => 60); end;
            """, binds: [BindVariable(name: "id", value: .text(id)), BindVariable(name: "c", type: .refCursor, direction: .output)],
                                   options: ExecuteOptions(lobLimit: 50_000_000, fetchArraySize: 1))
        guard case .cursor(let cursor)? = r.outBinds["c"] ?? r.outBinds["C"] else { return }
        while true {
            let batch = try await s.fetch(cursor, maxRows: 1)
            for line in batch.rows { row(line.first.flatMap { lobText($0) } ?? "") }
            if !batch.hasMore { break }
        }
    }

    static func lobText(_ v: OracleValue) -> String? {
        if case .lob(let l) = v { return l.text }
        return v.displayText
    }

    /// Pokrycie z raportu `ut_coverage_sonar_reporter`: `<file path="…"><lineToCover lineNumber=".." covered="true|false"/>`.
    nonisolated static func parseSonarCoverage(_ xml: String) -> [String: CoverageLines] {
        final class D: NSObject, XMLParserDelegate {
            var out: [String: CoverageLines] = [:]
            var file = ""
            func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
                if name == "file" {
                    file = UtplsqlRunner.objectKey(fromCoveragePath: attributes["path"] ?? "")
                    if out[file] == nil { out[file] = CoverageLines(covered: [], uncovered: []) }
                } else if name == "lineToCover", let n = Int(attributes["lineNumber"] ?? "") {
                    if attributes["covered"] == "true" { out[file]?.covered.insert(n) } else { out[file]?.uncovered.insert(n) }
                }
            }
        }
        guard let data = xml.data(using: .utf8) else { return [:] }
        let d = D()
        let p = XMLParser(data: data)
        p.delegate = d
        _ = p.parse()
        return d.out
    }

    /// Klucz obiektu z atrybutu `path` raportu Sonar (np. `package body pelikan_test.emp_api` → `PELIKAN_TEST.EMP_API`
    /// z typem: `PACKAGE BODY PELIKAN_TEST.EMP_API`).
    nonisolated static func objectKey(fromCoveragePath p: String) -> String {
        p.trimmingCharacters(in: .whitespaces).uppercased()
    }
}

/// Formaty eksportu wyników i pokrycia (UT-CI-001, UT-COV-003).
public enum UtplsqlReportFormat: String, Sendable, CaseIterable {
    case junit, sonarTests, teamcity, tap, coberturaCoverage, sonarCoverage, htmlCoverage

    var reporter: String {
        switch self {
        case .junit: "ut_junit_reporter"
        case .sonarTests: "ut_sonar_test_reporter"
        case .teamcity: "ut_teamcity_reporter"
        case .tap: "ut_tap_reporter"
        case .coberturaCoverage: "ut_coverage_cobertura_reporter"
        case .sonarCoverage: "ut_coverage_sonar_reporter"
        case .htmlCoverage: "ut_coverage_html_reporter"
        }
    }

    public var isCoverage: Bool { [.coberturaCoverage, .sonarCoverage, .htmlCoverage].contains(self) }

    public var fileExtension: String {
        switch self {
        case .teamcity, .tap: "txt"
        case .htmlCoverage: "html"
        default: "xml"
        }
    }
}

extension UtplsqlRunner {
    /// Uruchamia testy z jednym reporterem formatu i zwraca jego wyjście (eksport JUnit/Sonar/TeamCity/TAP, pokrycie).
    public static func report(paths: [String], format: UtplsqlReportFormat, coverageSchemes: [String], in ws: Workspace, connectionID: UUID) async throws -> String {
        let producer = try await ws.sessions.session(SessionKey(connectionID: connectionID, purpose: .utplsql("run")))
        let consumer = try await ws.sessions.session(SessionKey(connectionID: connectionID, purpose: .utplsql("events")))
        guard await version(producer) != nil else { throw CommandError.notAvailable(L10n.tr("utPLSQL nie jest zainstalowany albo niedostępny")) }
        try await ws.guardModification(["BEGIN ut_runner.run; END;"], connectionID: connectionID)
        let id = reporterID()
        let cov = format.isCoverage && !coverageSchemes.isEmpty ? ", a_coverage_schemes => " + literalList(coverageSchemes.map { $0.uppercased() }) : ""
        let block = """
            declare r \(format.reporter) := \(format.reporter)();
            begin r.set_reporter_id(:id); r.output_buffer.init();
              ut_runner.run(a_paths => \(literalList(paths)), a_reporters => ut_reporters(r)\(cov)); end;
            """
        try await initBuffers([(format.reporter, id)], session: producer)
        let produce = Task.detached { try await producer.execute(block, binds: [BindVariable(name: "id", value: .text(id))]) }
        var out = ""
        do {
            try await consume(reporter: format.reporter, id: id, session: consumer) { out += $0 + "\n" }
        } catch {
            // Błąd producenta jest przyczyną — zgłaszany zamiast limitu czasu konsumenta.
            _ = try await produce.value
            throw error
        }
        _ = try await produce.value
        return out
    }

    /// Skrypt SQL*Plus / SQLcl uruchamiający te same testy z reporterem JUnit (CI) — bez hasła: łączenie z wiersza
    /// poleceń (pytanie o hasło albo wallet).
    public static func cliScript(paths: [String], user: String, connectString: String) -> (sql: String, shell: String) {
        let sql = """
            -- \(L10n.tr("Testy utPLSQL z wiersza poleceń (wygenerowane przez Pelikana)"))
            set serveroutput on size unlimited format truncated
            set feedback off heading off pagesize 0 linesize 32767 trimspool on verify off
            spool utplsql-junit.xml
            exec ut.run(\(literalList(paths)), ut_junit_reporter());
            spool off
            exit
            """
        let shell = """
            #!/bin/sh
            # \(L10n.tr("Uruchamia testy utPLSQL; wynik JUnit w utplsql-junit.xml. Hasło: pytanie SQLcl/SQL*Plus albo wallet — nigdy w skrypcie."))
            set -e
            CONNECT="${PELIKAN_UT_CONNECT:-\(user)@\(connectString)}"
            if command -v sql >/dev/null 2>&1; then sql -S -L "$CONNECT" @utplsql-run.sql; else sqlplus -S -L "$CONNECT" @utplsql-run.sql; fi
            """
        return (sql, shell)
    }
}
