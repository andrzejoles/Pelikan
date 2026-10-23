import Foundation
import PelikanDB
import PelikanSQL

/// Element eksploratora testów (`ut_runner.get_suites_info`): suita logiczna, pakiet testowy, kontekst albo test.
public struct UtSuiteItem: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable { case logicalSuite = "UT_LOGICAL_SUITE", suite = "UT_SUITE", context = "UT_SUITE_CONTEXT", test = "UT_TEST" }
    public var owner: String
    public var object: String
    public var name: String
    public var description: String
    public var kind: Kind
    /// Linia adnotacji w specyfikacji pakietu testowego.
    public var line: Int
    public var path: String
    public var disabled: Bool
    public var disabledReason: String
    public var tags: String
    public var children: [UtSuiteItem]?
    public var id: String { path }
    public var title: String { description.isEmpty ? name.lowercased() : description }
    public var runPath: String { "\(owner.lowercased()):\(path)" }
}

@MainActor
public enum UtplsqlExplorer {
    /// Drzewo suit i testów właściciela (z hierarchii ścieżek).
    public static func load(owner: String, metadata m: MetadataProvider) async throws -> [UtSuiteItem] {
        let s = try await m.session()
        let (_, rows) = try await s.queryAll("""
            select object_owner, object_name, item_name, item_description, item_type, item_line_no, path, disabled_flag, disabled_reason, tags
            from table(ut_runner.get_suites_info(:o)) order by path
            """, binds: [BindVariable(name: "o", value: .text(owner))], limit: 100_000)
        let items = rows.compactMap { r -> UtSuiteItem? in
            guard let kind = UtSuiteItem.Kind(rawValue: r[4].displayText ?? "") else { return nil }
            return UtSuiteItem(owner: r[0].displayText ?? owner, object: r[1].displayText ?? "", name: r[2].displayText ?? "",
                               description: r[3].displayText ?? "", kind: kind, line: Int(r[5].format(.default)) ?? 0, path: r[6].displayText ?? "",
                               disabled: (r[7].displayText ?? "0") != "0", disabledReason: r[8].displayText ?? "", tags: r[9].displayText ?? "",
                               children: kind == .test ? nil : [])
        }
        return tree(items)
    }

    /// Hierarchia z kropkowanych ścieżek (rodzic = ścieżka bez ostatniego segmentu).
    nonisolated static func tree(_ items: [UtSuiteItem]) -> [UtSuiteItem] {
        var byPath = Dictionary(items.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        // Od najgłębszych: dziecko dołączane do rodzica.
        for path in items.map(\.path).sorted(by: { $0.split(separator: ".").count > $1.split(separator: ".").count }) {
            guard let item = byPath[path], let dot = path.lastIndex(of: ".") else { continue }
            let parent = String(path[..<dot])
            guard byPath[parent] != nil else { continue }
            byPath[parent]?.children?.append(item)
            byPath[path] = nil
        }
        func sort(_ n: inout [UtSuiteItem]) {
            n.sort { ($0.line, $0.path) < ($1.line, $1.path) }
            for i in n.indices where n[i].children != nil { sort(&n[i].children!) }
        }
        var roots = Array(byPath.values)
        sort(&roots)
        return roots
    }

    // MARK: Generator

    /// Szkielet pakietu testowego dla pakietu (UT-GEN-001): suita, po jednym teście na procedurę/funkcję specyfikacji
    /// (przeciążenia z numerem), w ciele `ut.fail` do uzupełnienia — kompiluje się bez zmian.
    public static func skeleton(for package: String, owner: String?, specification: String) -> String {
        let pkg = package.lowercased()
        let testName = "test_" + pkg
        let units = PLSQLOutline.parse(specification)
        let subprograms = units.first?.children.filter { [.procedure, .function].contains($0.kind) } ?? []
        var used: [String: Int] = [:]
        var names: [(test: String, target: OutlineNode)] = []
        for s in subprograms {
            let base = s.name.lowercased()
            used[base, default: 0] += 1
            let n = used[base]! == 1 ? base : "\(base)_\(used[base]!)"
            names.append((String(n.prefix(120)), s))
        }
        let target = (owner.map { "\($0.lowercased())." } ?? "") + pkg
        var spec = "create or replace package \(testName) as\n  --%suite(" + L10n.tr("Testy \(pkg)") + ")\n\n"
        for (n, s) in names {
            spec += "  --%test(\(s.name.lowercased()))\n  procedure \(n);\n\n"
        }
        if names.isEmpty { spec += "  --%test(" + L10n.tr("pierwszy test") + ")\n  procedure pierwszy_test;\n\n" }
        spec += "end \(testName);\n/\n"
        var body = "create or replace package body \(testName) as\n\n"
        for (n, s) in names.isEmpty ? [("pierwszy_test", OutlineNode(kind: .procedure, name: "", range: 0..<0, nameOffset: 0))] : names {
            let call = s.name.isEmpty ? "" : "\(target).\(s.name.lowercased())"
            body += "  procedure \(n) is\n  begin\n"
            body += "    -- " + L10n.tr("przygotowanie danych") + "\n"
            if !call.isEmpty { body += "    -- " + L10n.tr("wywołanie: \(call)(…)") + "\n" }
            body += "    -- " + L10n.tr("sprawdzenie: ut.expect(wynik).to_equal(oczekiwany);") + "\n"
            body += "    ut.fail('" + L10n.tr("Test do napisania") + "');\n  end \(n);\n\n"
        }
        body += "end \(testName);\n/\n"
        return spec + "\n" + body
    }

    // MARK: Nawigacja

    /// Pakiet testowy dla pakietu albo testowany pakiet dla pakietu testowego (UT-NAV-001): konwencja `test_<nazwa>`,
    /// a gdy jej brak — zależności pakietów z adnotacją `--%suite`.
    public static func counterpart(of package: String, owner: String, metadata m: MetadataProvider) async throws -> DBObject? {
        let s = try await m.session()
        let up = package.uppercased()
        let candidate = up.hasPrefix("TEST_") ? String(up.dropFirst(5)) : "TEST_" + up
        if let o = try await m.find("\"\(owner)\".\"\(candidate)\"", type: .package) { return o }
        let b = [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "n", value: .text(up))]
        let sql: String
        var isTestPackage = up.hasPrefix("TEST_")
        if !isTestPackage {
            let n = try await s.scalar("select count(*) from all_source where owner = :o and name = :n and type = 'PACKAGE' and lower(text) like '%--\\%suite%' escape '\\'", binds: b)
            isTestPackage = n != "0"
        }
        if isTestPackage {
            // Pakiet testowy → pierwszy pakiet, od którego zależy (poza utPLSQL).
            sql = "select referenced_name from all_dependencies where owner = :o and name = :n and referenced_type = 'PACKAGE' and referenced_owner = :o and referenced_name not like 'UT%' and rownum = 1"
        } else {
            sql = "select name from all_dependencies where referenced_owner = :o and referenced_name = :n and owner = :o and type = 'PACKAGE BODY' and name like 'TEST%' and rownum = 1"
        }
        guard let name = try await s.scalar(sql, binds: b) else { return nil }
        return DBObject(owner: owner, name: name, type: .package)
    }

    // MARK: Walidacja adnotacji

    nonisolated static let annotations: Set<String> = ["suite", "suitepath", "displayname", "test", "context", "endcontext", "name", "beforeall", "afterall",
                                           "beforeeach", "aftereach", "beforetest", "aftertest", "throws", "disabled", "rollback", "tags"]

    /// Nieznane adnotacje `--%` w specyfikacji pakietu (UT-CA-002): numer linii (od 1) i nazwa.
    public nonisolated static func unknownAnnotations(in text: String) -> [(line: Int, name: String)] {
        var out: [(Int, String)] = []
        for (i, line) in text.components(separatedBy: "\n").enumerated() {
            guard let r = line.range(of: #"--%([A-Za-z_]+)"#, options: .regularExpression) else { continue }
            let name = String(line[r].dropFirst(3)).lowercased()
            if !annotations.contains(name) { out.append((i + 1, name)) }
        }
        return out
    }
}
