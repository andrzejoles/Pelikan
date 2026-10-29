import Foundation
import PelikanDB
import PelikanSQL

/// Opcje eksportu obiektów użytkownika (UG 24.6, PD-TOOL-007).
public struct ObjectExportOptions: Sendable, Hashable, Codable {
    public enum Layout: String, Sendable, Codable, CaseIterable { case singleFile, filePerObject }
    public var layout: Layout = .singleFile
    /// Specyfikacja i ciało pakietu/typu w jednym pliku `.pck`/`.typ` (przy pliku na obiekt). Domyślnie osobne pliki
    /// `.pks`/`.pkb` i `.tps`/`.tpb` (D194 — konwencja repozytoriów właściciela).
    public var specAndBodyTogether = false
    /// Rozszerzenia plików specyfikacji i ciała (Preferencje › Ogólne, D194).
    public var extensions = SpecBodyExtensions()
    /// Pliki na obiekt: jednostki PL/SQL zakończone „/” w osobnej linii. Domyślnie bez „/” w osobnych plikach DDL
    /// w repozytorium („/” psuje proces wdrożenia, D192/D194); jeden plik (skrypt SQL*Plus) i pliki `.pck`/`.typ`
    /// z obiema jednostkami (konwencja PL/SQL Developera) zawsze z „/”.
    public var terminateUnits = false
    /// Uprawnienia obiektu w trybie „plik na obiekt” (D194, decyzja właściciela: „GRANT'y zawsze w osobnych plikach”):
    /// osobny plik `nazwa.grants.sql` obok plików DDL, które zawierają wyłącznie CREATE, albo pominięte. Jeden plik
    /// (skrypt) — uprawnienia zawsze za obiektem.
    public enum GrantPlacement: String, Sendable, Codable, CaseIterable { case separateFile, omit }
    public var grantPlacement: GrantPlacement = .separateFile
    /// Pliki na obiekt: komentarz „Wygenerowane przez Pelikana — data” na początku pliku. Domyślnie bez — data zmieniałaby
    /// każdy plik w repozytorium przy każdym eksporcie. Jeden plik — zawsze z nagłówkiem.
    public var dateHeader = false
    public var includePrivileges = true
    public var includeStorage = false
    /// Nazwa schematu w DDL (bez — obiekty tworzone w bieżącym schemacie docelowym).
    public var includeOwner = false
    public init() {}
}

/// Plik wyniku eksportu.
public struct ExportedFile: Sendable, Hashable {
    public var name: String
    public var content: String
    /// Plik na obiekt bez „/” (D194), w którym „/” musiał zostać (polecenie za jednostką, np. `ALTER TYPE` ewolucji
    /// typu) — ostrzeżenie w oknie eksportu.
    public var keepsSlash = false

    public init(name: String, content: String, keepsSlash: Bool = false) {
        self.name = name; self.content = content; self.keepsSlash = keepsSlash
    }
}

/// DDL jednego obiektu z eksportu: polecenia obiektu i osobno jego uprawnienia (GRANT).
struct ExportPart: Sendable {
    var object: DBObject
    var ddl: String
    var grants: String?
}

/// Eksport DDL obiektów (sekwencje pierwsze, potem tabele, widoki i kod — kolejność, w której skrypt da się wykonać).
public enum ObjectExport {
    static let order: [DBObjectType] = [.sequence, .type, .table, .index, .view, .materializedView, .synonym, .function, .procedure, .package,
                                       .typeBody, .packageBody, .trigger]

    public static func sortKey(_ t: DBObjectType) -> Int { order.firstIndex(of: t) ?? order.count }

    /// Obiekty schematu do wyboru (bez indeksów ograniczeń, LOB-ów, partycji i obiektów kosza).
    public static func objects(owner: String, in s: any DatabaseSession) async throws -> [DBObject] {
        let (_, rows) = try await s.queryAll("""
            select owner, object_name, object_type from all_objects
             where owner = :o and object_name not like 'BIN$%' and object_name not like 'SYS\\_%' escape '\\'
               and object_type in ('SEQUENCE','TYPE','TABLE','INDEX','VIEW','MATERIALIZED VIEW','SYNONYM','FUNCTION','PROCEDURE','PACKAGE',
                                   'TYPE BODY','PACKAGE BODY','TRIGGER')
               and not (object_type = 'INDEX' and object_name in (select constraint_name from all_constraints where owner = :o and constraint_type in ('P','U')))
             order by object_type, object_name
            """, binds: [BindVariable(name: "o", value: .text(owner))], limit: 200_000)
        return rows.compactMap { r in
            guard let o = r[0].displayText, let n = r[1].displayText, let t = r[2].displayText.flatMap(DBObjectType.init(rawValue:)) else { return nil }
            return DBObject(owner: o, name: n, type: t)
        }
    }

    /// Typy bez uprawnień obiektowych (uprawnienia ma specyfikacja albo tabela).
    static let ungrantable: Set<DBObjectType> = [.index, .trigger, .packageBody, .typeBody]

    /// Obiekty schematu z uprawnieniami obiektowymi (DBA_TAB_PRIVS, bez dostępu — ALL_TAB_PRIVS); `name` — tylko ten
    /// obiekt. GET_DEPENDENT_DDL('OBJECT_GRANT') kosztuje na dużej bazie ~1,8 s także dla obiektu bez uprawnień (D164),
    /// więc pytamy o nie tylko obiekty z tej listy.
    static func grantedObjects(owner: String, name: String? = nil, in s: any DatabaseSession) async -> Set<String>? {
        var b = [BindVariable(name: "o", value: .text(owner))]
        var cond = ""
        if let name { b.append(BindVariable(name: "n", value: .text(name))); cond = " and table_name = :n" }
        let rows = try? await DictionaryQuery.queryAll(["select distinct table_name from dba_tab_privs where owner = :o\(cond)",
                                                        "select distinct table_name from all_tab_privs where table_schema = :o\(cond)"],
                                                       binds: b, limit: 1_000_000, in: s).rows
        return rows.map { Set($0.compactMap { $0.first?.displayText }) }
    }

    /// DDL jednego obiektu z ustawieniami transformacji DBMS_METADATA według opcji; `granted` — obiekty schematu
    /// z uprawnieniami (eksport wielu obiektów; `.some(nil)` — listy nie udało się pobrać, każdy obiekt traktowany
    /// jak mający uprawnienia, bez ponawiania zapytania), bez niej — sprawdzenie tego jednego obiektu.
    static func ddl(_ o: DBObject, options: ObjectExportOptions, granted: Set<String>?? = nil, in s: any DatabaseSession) async throws -> String {
        let p = try await part(o, options: options, granted: granted, in: s)
        return p.grants.map { p.ddl + "\n" + $0 } ?? p.ddl
    }

    /// DDL obiektu i jego uprawnienia osobno (plik na obiekt może je zapisać w osobnym pliku albo pominąć).
    static func part(_ o: DBObject, options: ObjectExportOptions, granted: Set<String>?? = nil, in s: any DatabaseSession) async throws -> ExportPart {
        let metaType: String = switch o.type {
        case .packageBody: "PACKAGE_BODY"
        case .package: "PACKAGE_SPEC"
        case .typeBody: "TYPE_BODY"
        case .type: "TYPE_SPEC"
        case .materializedView: "MATERIALIZED_VIEW"
        default: o.type.rawValue.replacingOccurrences(of: " ", with: "_")
        }
        let r = try await s.execute("""
            declare h number; begin
              dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'DEFAULT', true);
              dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', true);
              dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'PRETTY', true);
              begin dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SEGMENT_ATTRIBUTES', :st = 1); exception when others then null; end;
              begin dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'STORAGE', :st = 1); exception when others then null; end;
              begin dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'EMIT_SCHEMA', :ow = 1); exception when others then null; end;
              :ddl := dbms_metadata.get_ddl(:t, :n, :o);
            end;
            """, binds: [BindVariable(name: "st", type: .number, value: .text(options.includeStorage ? "1" : "0")),
                         BindVariable(name: "ow", type: .number, value: .text(options.includeOwner ? "1" : "0")),
                         BindVariable(name: "ddl", type: .clob, direction: .output), BindVariable(name: "t", value: .text(metaType)),
                         BindVariable(name: "n", value: .text(o.name)), BindVariable(name: "o", value: .text(o.owner))])
        guard case .lob(let l)? = r.outBinds["ddl"], var text = l.text else { return ExportPart(object: o, ddl: "") }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Kod PL/SQL z DBMS_METADATA kończy się „/”, pozostałe „;” (SQLTERMINATOR).
        var hasGrants = false
        if options.includePrivileges, !ungrantable.contains(o.type) {
            // Nieznana lista (błąd słownika) — pytamy DBMS_METADATA jak dawniej.
            let list = if let granted { granted } else { await grantedObjects(owner: o.owner, name: o.name, in: s) }
            hasGrants = list?.contains(o.name) ?? true
        }
        if hasGrants {
            let r2 = try? await s.execute("""
                begin :g := dbms_metadata.get_dependent_ddl('OBJECT_GRANT', :n, :o); exception when others then :g := null; end;
                """, binds: [BindVariable(name: "g", type: .clob, direction: .output), BindVariable(name: "n", value: .text(o.name)), BindVariable(name: "o", value: .text(o.owner))])
            if case .lob(let g)? = r2?.outBinds["g"], let grants = g.text?.trimmingCharacters(in: .whitespacesAndNewlines), !grants.isEmpty {
                return ExportPart(object: o, ddl: text, grants: grants)
            }
        }
        return ExportPart(object: o, ddl: text)
    }

    /// Eksport w kolejności wykonalnej; `progress` dostaje liczbę wyeksportowanych obiektów.
    public static func export(_ objects: [DBObject], options: ObjectExportOptions, in s: any DatabaseSession,
                              progress: (@MainActor (Int) -> Void)? = nil) async throws -> [ExportedFile] {
        // Właściciel w kluczu: eksport kilku schematów w stałej kolejności (pary plików nazwane tak samo przy każdym eksporcie).
        let sorted = objects.sorted { (sortKey($0.type), $0.owner, $0.name) < (sortKey($1.type), $1.owner, $1.name) }
        // Lista obiektów z uprawnieniami — raz na schemat zamiast pytania o każdy obiekt.
        var granted: [String: Set<String>?] = [:]
        if options.includePrivileges, sorted.count > 1 {
            // Także nieudane pobranie (nil) — zapamiętane, żeby każdy obiekt nie ponawiał zapytania.
            for owner in Set(sorted.map(\.owner)) { granted.updateValue(await grantedObjects(owner: owner, in: s), forKey: owner) }
        }
        var parts: [ExportPart] = []
        for (i, o) in sorted.enumerated() {
            parts.append(try await part(o, options: options, granted: granted[o.owner], in: s))
            await progress?(i + 1)
        }
        let header = "-- " + L10n.tr("Wygenerowane przez Pelikana") + " — " + ISO8601DateFormatter().string(from: Date()) + "\n"
        if options.layout == .singleFile {
            let text = parts.map { p in "\n-- \(p.object.type.rawValue) \(p.object.name)\n" + (p.grants.map { p.ddl + "\n" + $0 } ?? p.ddl) }
            return [ExportedFile(name: "\(sorted.first?.owner.lowercased() ?? "obiekty").sql", content: header + text.joined(separator: "\n") + "\n")]
        }
        return files(parts, options: options, header: options.dateHeader ? header : "")
    }

    /// Pliki „plik na obiekt”: nazwa z bezpiecznych znaków (nazwa w cudzysłowie może mieć `/`, `..`). Nazwa bazowa jest
    /// wspólna dla obiektu (właściciel + nazwa) we wszystkich jego plikach — specyfikacja i ciało jednego pakietu dostają
    /// tę samą; przy obiektach kilku schematów z przedrostkiem schematu (`s2.pkg.pks`); różne obiekty o tej samej nazwie
    /// bazowej (np. „Foo” i „FOO”) — przyrostek `_2`, `_3`…
    /// we wszystkich swoich plikach. Specyfikacja i ciało w osobnych plikach (rozszerzenia z opcji, domyślnie
    /// `.pks`/`.pkb`, `.tps`/`.tpb`) bez „/” (chyba że `terminateUnits`), albo razem w `.pck`/`.typ` z „/”. Uprawnienia
    /// według `grantPlacement` — w osobnym pliku `nazwa.grants.sql` (polecenia z „;”) albo pominięte, nigdy w pliku DDL.
    static func files(_ parts: [ExportPart], options: ObjectExportOptions, header: String) -> [ExportedFile] {
        var contents: [String: [String]] = [:]
        var names: [String] = []
        var slashKept: Set<String> = []
        var baseOf: [String: String] = [:]
        var usedBases: Set<String> = []
        // Obiekty kilku schematów: przedrostek schematu w nazwie każdego pliku (`s2.pkg.pks`) — nazwy nie zależą od tego,
        // które obiekty wybrano; jeden schemat — bez przedrostka.
        let manyOwners = Set(parts.map(\.object.owner)).count > 1
        func safe(_ s: String) -> String { String(s.lowercased().map { $0.isLetter || $0.isNumber || "_$#".contains($0) ? $0 : "_" }) }
        func base(_ o: DBObject) -> String {
            let key = "\(o.owner)\u{1F}\(o.name)"
            if let b = baseOf[key] { return b }
            let wanted = manyOwners ? safe(o.owner) + "." + safe(o.name) : safe(o.name)
            var candidate = wanted, n = 2
            while usedBases.contains(candidate) { candidate = "\(wanted)_\(n)"; n += 1 }
            usedBases.insert(candidate)
            baseOf[key] = candidate
            return candidate
        }
        func append(_ name: String, _ text: String) {
            if contents[name] == nil { names.append(name) }
            contents[name, default: []].append(text)
        }
        for p in parts {
            let o = p.object
            let together = options.specAndBodyTogether && [.package, .packageBody, .type, .typeBody].contains(o.type)
            let pair = options.extensions.pair(for: o.type)
            let ext = together ? (o.type == .package || o.type == .packageBody ? "pck" : "typ")
                : [.package, .type].contains(o.type) ? pair?.spec ?? "spc" : [.packageBody, .typeBody].contains(o.type) ? pair?.body ?? "bdy"
                : ObjectCommands.fileExtension(o.type)
            let b = base(o)
            let name = "\(b).\(ext)"
            // Osobne pliki DDL bez „/” (D194); `.pck`/`.typ` z obiema jednostkami — z „/” jak w PL/SQL Developerze.
            let stripSlash = !options.terminateUnits && !together
            let text = stripSlash ? withoutUnitTerminator(p.ddl) : p.ddl
            if stripSlash, ProgramCompiler.header(text) != nil,
               text.components(separatedBy: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces) == "/" }) {
                slashKept.insert(name)
            }
            append(name, text)
            if let grants = p.grants, options.grantPlacement == .separateFile { append("\(b).grants.sql", grants) }
        }
        return names.map { n in
            ExportedFile(name: n, content: header + (header.isEmpty ? "" : "\n") + (contents[n] ?? []).joined(separator: "\n\n") + "\n",
                         keepsSlash: slashKept.contains(n))
        }
    }

    /// Wersja dla testów: DDL obiektów bez osobnych uprawnień.
    static func files(_ parts: [(DBObject, String)], options: ObjectExportOptions, header: String) -> [ExportedFile] {
        files(parts.map { ExportPart(object: $0.0, ddl: $0.1) }, options: options, header: header)
    }

    /// DDL z DBMS_METADATA bez „/” kończącego jednostki PL/SQL (pliki DDL w repozytorium, D194). „/” zostaje, gdy za
    /// jednostką jest polecenie, które bez niego dokleiłoby się do jej tekstu (D192) — poza GRANT/REVOKE; `ALTER TRIGGER
    /// … ENABLE` (wyzwalacz i tak powstaje włączony) jest pomijane, `… DISABLE` zostaje razem z „/”.
    static func withoutUnitTerminator(_ ddl: String) -> String {
        let ns = ddl as NSString
        let statements = ScriptSplitter.split(ddl)
        var remove: [NSRange] = []
        var inserts: [Int] = []
        for (i, st) in statements.enumerated() where st.terminator == .slash && ProgramCompiler.header(st.text) != nil {
            if i + 1 < statements.count {
                let next = statements[i + 1]
                let t = next.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    .split(whereSeparator: \.isWhitespace).joined(separator: " ")
                if t.hasPrefix("ALTER TRIGGER") {
                    // Wyłączony wyzwalacz: klauzula DISABLE w CREATE TRIGGER (11g+) zamiast ALTER, żeby plik był bez „/”;
                    // gdy nie da się jej wstawić — ALTER zostaje razem z „/”.
                    var disableAt: Int?
                    if t.hasSuffix(" DISABLE") {
                        guard let at = triggerStateClauseOffset(st.text) else { continue }
                        disableAt = st.start + at
                    } else if !t.hasSuffix(" ENABLE") {
                        continue
                    }
                    let start = ns.lineRange(for: NSRange(location: next.start, length: 0)).location
                    let end = NSMaxRange(ns.lineRange(for: NSRange(location: max(next.start, next.fullEnd - 1), length: 0)))
                    remove.append(NSRange(location: start, length: end - start))
                    if let at = disableAt { inserts.append(at) }
                } else if !(t.hasPrefix("GRANT ") || t.hasPrefix("REVOKE ")) {
                    continue
                }
            }
            // Linia z samym „/” między końcem polecenia a końcem z terminatorem.
            let slash = ns.range(of: "/", options: [], range: NSRange(location: st.end, length: max(0, st.fullEnd - st.end)))
            guard slash.location != NSNotFound else { continue }
            let line = ns.lineRange(for: slash)
            guard ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines) == "/" else { continue }
            remove.append(line)
        }
        guard !remove.isEmpty else { return ddl }
        var out = ns as String
        // Od końca: usunięcia linii „/” i ALTER oraz wstawienia „DISABLE ” (zawsze przed usuwanymi liniami).
        let edits = remove.map { ($0, "") } + inserts.map { (NSRange(location: $0, length: 0), "DISABLE ") }
        for (r, t) in edits.sorted(by: { $0.0.location > $1.0.location }) {
            out = (out as NSString).replacingCharacters(in: r, with: t)
        }
        while let c = out.last, c.isWhitespace { out.removeLast() }
        return out
    }

    /// Miejsce klauzuli `ENABLE | DISABLE` w CREATE TRIGGER (pozycja w tekście polecenia): przed `WHEN (…)` albo
    /// treścią wyzwalacza (`DECLARE`, `BEGIN`, `<<etykieta>>`, `CALL`, `COMPOUND TRIGGER`) na poziomie zerowym nawiasów. nil — nie
    /// znaleziono albo stan jest już podany.
    static func triggerStateClauseOffset(_ sql: String) -> Int? {
        let ns = sql as NSString
        var depth = 0, afterTrigger = false
        for t in Lexer(sql).tokenize() where !t.isTrivia {
            // Etykieta bloku (`<<nazwa>>`) przed DECLARE/BEGIN — początek treści wyzwalacza.
            if afterTrigger, depth == 0, t.start + 2 <= ns.length, ns.substring(with: NSRange(location: t.start, length: 2)) == "<<" {
                return t.start
            }
            switch t.kind {
            case .leftParen: depth += 1; continue
            case .rightParen: depth -= 1; continue
            default: break
            }
            guard depth == 0, [.keyword, .identifier].contains(t.kind) else { continue }
            let word = ns.substring(with: NSRange(location: t.start, length: t.length)).uppercased()
            if !afterTrigger { afterTrigger = word == "TRIGGER"; continue }
            if ["ENABLE", "DISABLE"].contains(word) { return nil }
            if ["WHEN", "DECLARE", "BEGIN", "CALL", "COMPOUND"].contains(word) { return t.start }
        }
        return nil
    }
}

/// Różnica obiektu między schematami (UG 24.11, PD-TOOL-012).
public struct ObjectDifference: Sendable, Hashable, Identifiable {
    public enum Status: String, Sendable, Hashable { case onlySource, onlyTarget, different }
    public var name: String
    public var type: DBObjectType
    public var status: Status
    public var sourceDDL: String
    public var targetDDL: String
    /// SQL wyrównujący obiekt w schemacie docelowym (pusty, gdy wymaga ręcznej zmiany, np. tabela).
    public var sync: String
    public var id: String { "\(type.rawValue) \(name)" }
}

public struct CompareOptions: Sendable, Hashable, Codable {
    public var ignoreCase = false
    public var ignoreWhitespace = true
    public var includeStorage = false
    /// Obiekty istniejące tylko w schemacie docelowym: DROP w skrypcie wyrównującym.
    public var dropExtra = false
    public init() {}
}

/// Porównanie obiektów dwóch schematów (także różnych połączeń) po DDL bez nazwy schematu.
public enum ObjectCompare {
    nonisolated static func normalize(_ ddl: String, _ o: CompareOptions) -> String {
        var t = ddl.replacingOccurrences(of: "\r\n", with: "\n")
        if o.ignoreWhitespace { t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
        if o.ignoreCase { t = t.uppercased() }
        return t
    }

    public static func compare(_ objects: [DBObject], source: any DatabaseSession, targetOwner: String, target: any DatabaseSession,
                               options: CompareOptions, progress: (@MainActor (Int) -> Void)? = nil) async throws -> [ObjectDifference] {
        var exportOptions = ObjectExportOptions()
        exportOptions.includeOwner = false
        exportOptions.includePrivileges = false
        exportOptions.includeStorage = options.includeStorage
        let targetObjects = try await ObjectExport.objects(owner: targetOwner, in: target)
        let targetKeys = Set(targetObjects.map { "\($0.type.rawValue) \($0.name)" })
        var out: [ObjectDifference] = []
        let sorted = objects.sorted { (ObjectExport.sortKey($0.type), $0.name) < (ObjectExport.sortKey($1.type), $1.name) }
        for (i, o) in sorted.enumerated() {
            let src = try await ObjectExport.ddl(o, options: exportOptions, in: source)
            if targetKeys.contains("\(o.type.rawValue) \(o.name)") {
                let dst = try await ObjectExport.ddl(DBObject(owner: targetOwner, name: o.name, type: o.type), options: exportOptions, in: target)
                if normalize(src, options) != normalize(dst, options) {
                    let manual = [.table, .index, .materializedView].contains(o.type)
                    let sync = manual ? "-- " + L10n.tr("\(o.type.rawValue) \(o.name) różni się — zmiana wymaga ALTER; porównaj definicje.") : src
                    out.append(ObjectDifference(name: o.name, type: o.type, status: .different, sourceDDL: src, targetDDL: dst, sync: sync))
                }
            } else {
                out.append(ObjectDifference(name: o.name, type: o.type, status: .onlySource, sourceDDL: src, targetDDL: "", sync: src))
            }
            await progress?(i + 1)
        }
        let sourceKeys = Set(objects.map { "\($0.type.rawValue) \($0.name)" })
        let selectedTypes = Set(objects.map(\.type))
        for o in targetObjects where selectedTypes.contains(o.type) && !sourceKeys.contains("\(o.type.rawValue) \(o.name)") && ![.packageBody, .typeBody].contains(o.type) {
            let drop = options.dropExtra ? "drop \(o.type.rawValue.lowercased()) \"\(o.name)\";" : ""
            out.append(ObjectDifference(name: o.name, type: o.type, status: .onlyTarget, sourceDDL: "", targetDDL: "", sync: drop))
        }
        return out
    }

    /// Skrypt wyrównujący w kolejności zależności.
    public static func script(_ diffs: [ObjectDifference]) -> String {
        diffs.filter { !$0.sync.isEmpty }.map { "-- \($0.type.rawValue) \($0.name) (\($0.status.rawValue))\n\($0.sync)" }.joined(separator: "\n\n") + "\n"
    }
}
