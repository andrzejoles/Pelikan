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

    static func literalList(_ items: [String]) -> String {
        "ut_varchar2_list(" + items.map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" }.joined(separator: ", ") + ")"
    }

    /// Uruchamia testy ze ścieżek (`schemat`, `schemat.pakiet[.procedura]`, `schemat:suitepath`); `coverage` — schematy,
    /// dla których zbierane jest pokrycie (puste — bez pokrycia). Zwraca przebieg aktualizowany na żywo.
    public static func start(paths: [String], coverageSchemes: [String] = [], in ws: Workspace, connectionID: UUID) async throws -> UtplsqlRun {
        let run = UtplsqlRun(paths: paths)
        let producer = try await ws.sessions.session(SessionKey(connectionID: connectionID, purpose: .utplsql("run")))
        let consumer = try await ws.sessions.session(SessionKey(connectionID: connectionID, purpose: .utplsql("events")))
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
