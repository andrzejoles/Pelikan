import Foundation
import PelikanDB
import PelikanSQL

/// Styl raportu z biblioteki stylów (UG 12.4): stały identyfikator (zapisywany w pliku .rep), nazwa w języku
/// interfejsu i arkusz CSS.
public struct ReportStyle: Sendable, Codable, Hashable, Identifiable {
    public var key: String
    public var name: String
    public var css: String
    /// Nazwa polska — tak zapisywały styl pliki .rep sprzed identyfikatorów.
    var legacyName: String
    public var id: String { key }
    init(key: String, name: String, legacyName: String, css: String) { self.key = key; self.name = name; self.legacyName = legacyName; self.css = css }

    /// Styl po identyfikatorze, nazwie w bieżącym języku albo nazwie polskiej (stare pliki).
    public static func named(_ s: String) -> ReportStyle? {
        library.first { $0.key == s } ?? library.first { $0.name == s || $0.legacyName == s }
    }

    /// Wbudowane style Pelikana (własne arkusze, jasne i ciemne kolory systemu przeglądarki).
    public static let library: [ReportStyle] = [
        ReportStyle(key: "standard", name: L10n.tr("Standardowy"), legacyName: "Standardowy", css: """
            body { font: 12px -apple-system, "Helvetica Neue", sans-serif; color: #1d1d1f; margin: 16px; }
            h1 { font-size: 17px; margin: 0 0 4px; } .header { color: #6e6e73; margin-bottom: 10px; }
            table { border-collapse: collapse; } th, td { padding: 3px 8px; border-bottom: 1px solid #d2d2d7; vertical-align: top; }
            th { text-align: left; background: #f5f5f7; } tr.break td { font-weight: 600; background: #eef3fb; padding-top: 8px; }
            tr.sum td { font-weight: 600; border-top: 2px solid #86868b; } .null { color: #a1a1a6; }
            table.form td.label { color: #6e6e73; } .record { margin-bottom: 14px; }
            @media (prefers-color-scheme: dark) { body { color: #f5f5f7; background: #1d1d1f; } th { background: #2c2c2e; }
              th, td { border-color: #3a3a3c; } tr.break td { background: #1c2a3d; } }
            """),
        ReportStyle(key: "green", name: L10n.tr("Zielony"), legacyName: "Zielony", css: """
            body { font: 12px Georgia, serif; color: #12301e; margin: 18px; background: #f6fbf7; }
            h1 { font-size: 18px; color: #1b6b3a; } .header { color: #4c7a5c; margin-bottom: 10px; }
            table { border-collapse: collapse; } th, td { padding: 4px 9px; border: 1px solid #b9dcc5; }
            th { background: #1b6b3a; color: #fff; } tr:nth-child(even) td { background: #e8f4ec; }
            tr.break td { background: #cfe8d7; font-weight: bold; } tr.sum td { font-weight: bold; } .null { color: #8aa896; }
            table.form td.label { font-weight: bold; } .record { margin-bottom: 14px; }
            """),
        ReportStyle(key: "compact", name: L10n.tr("Kompaktowy"), legacyName: "Kompaktowy", css: """
            body { font: 11px Menlo, monospace; margin: 8px; } h1 { font-size: 13px; margin: 0; } .header { margin-bottom: 6px; }
            table { border-collapse: collapse; } th, td { padding: 1px 6px; border-bottom: 1px dotted #999; }
            th { text-align: left; border-bottom: 1px solid #333; } tr.break td { font-weight: bold; padding-top: 6px; }
            tr.sum td { font-weight: bold; border-top: 1px solid #333; } .null { color: #999; } .record { margin-bottom: 8px; }
            """),
    ]
}

/// Format kolumny raportu (UG 12.5): nagłówek, wyrównanie, format liczby/daty, ukrycie, suma, przerwanie (Break).
public struct ReportColumnFormat: Sendable, Codable, Hashable, Identifiable {
    public enum Alignment: String, Sendable, Codable, CaseIterable { case automatic, left, center, right }
    /// Nazwa kolumny wyniku (wielkie litery jak z bazy).
    public var column: String
    public var heading: String?
    public var alignment: Alignment = .automatic
    /// Wzorzec liczby (np. `#,##0.00`) — NumberFormatter.
    public var numberFormat: String?
    /// Wzorzec daty Unicode (np. `yyyy-MM-dd HH:mm`).
    public var dateFormat: String?
    public var hidden = false
    public var sum = false
    /// Grupowanie: wartość wypisywana raz jako nagłówek grupy (master), wiersze grupy pod nią (detail).
    public var breakGroup = false
    public var id: String { column }

    public init(column: String) { self.column = column.uppercased() }
}

/// Definicja raportu (Report Window, UG 12): zapytanie, układ, styl i opcje.
public struct ReportDefinition: Sendable, Codable, Hashable {
    public enum Layout: String, Sendable, Codable, CaseIterable { case table, form }
    public var title: String
    public var sql: String
    /// Nazwa stylu w języku interfejsu (wybór w oknie); w pliku zapisywany jest stały identyfikator `ReportStyle.key`.
    public var styleName: String = ReportStyle.library[0].name
    /// Własny CSS dopisywany do stylu.
    public var extraCSS = ""
    public var columns: [ReportColumnFormat] = []
    public var layout: Layout = .table
    /// Nowa strona druku po każdej grupie (Break).
    public var pageBreakOnGroup = false
    /// Nagłówek strony ze zmiennymi `#title`, `#date`, `#user`, `#connection` i wartościami zmiennych `#nazwa`.
    public var header = "#date"
    /// Kolor tła (CSS) albo pusty.
    public var background = ""
    /// Połączenie raportu (nazwa połączenia); puste — połączenie okna albo główne (UG 12.6).
    public var connection = ""
    /// Blokada definicji: zapytanie i układ są ukryte i niezmienialne, raport można tylko wykonywać (UG 12.6).
    public var locked = false
    /// Limit wierszy (ochrona przed ogromnym HTML).
    public var maxRows = 10_000

    public init(title: String, sql: String) { self.title = title; self.sql = sql }

    public func format(of column: String) -> ReportColumnFormat {
        columns.first { $0.column == column.uppercased() } ?? ReportColumnFormat(column: column)
    }

    public var style: ReportStyle { ReportStyle.named(styleName) ?? ReportStyle.library[0] }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> ReportDefinition {
        try JSONDecoder().decode(ReportDefinition.self, from: data)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(title: try c.decodeIfPresent(String.self, forKey: .title) ?? "", sql: try c.decodeIfPresent(String.self, forKey: .sql) ?? "")
        func v<T: Decodable>(_ k: CodingKeys, _ cur: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? cur }
        styleName = v(.styleName, styleName)
        if let st = ReportStyle.named(styleName) { styleName = st.name }
        extraCSS = v(.extraCSS, extraCSS); columns = v(.columns, columns)
        layout = v(.layout, layout); pageBreakOnGroup = v(.pageBreakOnGroup, pageBreakOnGroup); header = v(.header, header)
        background = v(.background, background); connection = v(.connection, connection); locked = v(.locked, locked)
        maxRows = v(.maxRows, maxRows)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title); try c.encode(sql, forKey: .sql)
        try c.encode(ReportStyle.named(styleName)?.key ?? styleName, forKey: .styleName)
        try c.encode(extraCSS, forKey: .extraCSS); try c.encode(columns, forKey: .columns); try c.encode(layout, forKey: .layout)
        try c.encode(pageBreakOnGroup, forKey: .pageBreakOnGroup); try c.encode(header, forKey: .header)
        try c.encode(background, forKey: .background); try c.encode(connection, forKey: .connection)
        try c.encode(locked, forKey: .locked); try c.encode(maxRows, forKey: .maxRows)
    }

    enum CodingKeys: String, CodingKey {
        case title, sql, styleName, extraCSS, columns, layout, pageBreakOnGroup, header, background, connection, locked, maxRows
    }
}

/// Wartość komórki raportu (typ decyduje o domyślnym wyrównaniu i formatowaniu).
public enum ReportValue: Sendable, Hashable {
    case null
    case number(Double, String)
    case date(Date)
    case text(String)

    init(_ v: OracleValue, format: ValueFormat) {
        switch v {
        case .null: self = .null
        case .number(let s): self = Double(s).map { .number($0, s) } ?? .text(s)
        case .double(let d): self = .number(d, String(d))
        case .timestamp(let t, _):
            var c = DateComponents()
            c.year = Int(t.year); c.month = Int(t.month); c.day = Int(t.day)
            c.hour = Int(t.hour); c.minute = Int(t.minute); c.second = Int(t.second)
            c.timeZone = TimeZone(identifier: "UTC")
            self = Calendar(identifier: .gregorian).date(from: c).map { .date($0) } ?? .text(v.format(format))
        case .lob(let l): self = l.text.map { .text($0) } ?? .text(v.format(format))
        default: self = .text(v.format(format))
        }
    }
}

/// Dane raportu: kolumny i wiersze.
public struct ReportData: Sendable {
    public var columns: [String]
    public var rows: [[ReportValue]]
    public var truncated = false
    public init(columns: [String], rows: [[ReportValue]], truncated: Bool = false) {
        self.columns = columns; self.rows = rows; self.truncated = truncated
    }
}

/// Renderowanie raportu do HTML (UG 12.4–12.6) — czysty Swift, bez bazy.
public enum ReportRenderer {
    nonisolated static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }

    /// Tekst komórki według formatu kolumny.
    nonisolated static func text(_ v: ReportValue, _ f: ReportColumnFormat, locale: Locale) -> String {
        switch v {
        case .null: return ""
        case .text(let s): return s
        case .number(let d, let raw):
            guard let pattern = f.numberFormat, !pattern.isEmpty else { return raw }
            let nf = NumberFormatter()
            nf.locale = locale
            nf.positiveFormat = pattern
            nf.negativeFormat = "-" + pattern
            return nf.string(from: NSNumber(value: d)) ?? raw
        case .date(let date):
            let df = DateFormatter()
            df.locale = locale
            df.timeZone = TimeZone(identifier: "UTC")
            df.dateFormat = (f.dateFormat?.isEmpty == false ? f.dateFormat : nil) ?? "yyyy-MM-dd HH:mm:ss"
            return df.string(from: date)
        }
    }

    nonisolated static func align(_ f: ReportColumnFormat, _ sample: ReportValue?) -> String {
        switch f.alignment {
        case .left: return "left"
        case .center: return "center"
        case .right: return "right"
        case .automatic:
            if case .number? = sample { return "right" }
            return "left"
        }
    }

    /// Nagłówek strony ze zmiennymi `#title`, `#date`, `#user`, `#connection` i `#<zmienna>`.
    nonisolated static func header(_ def: ReportDefinition, values: [String: String], generated: Date, locale: Locale) -> String {
        let df = DateFormatter()
        df.locale = locale
        df.dateStyle = .medium
        df.timeStyle = .short
        var vars = values.reduce(into: [String: String]()) { $0[$1.key.lowercased()] = $1.value }
        vars["title"] = def.title
        vars["date"] = df.string(from: generated)
        var out = def.header
        for (k, v) in vars.sorted(by: { $0.key.count > $1.key.count }) {
            out = out.replacingOccurrences(of: "#" + k, with: v, options: .caseInsensitive)
        }
        return out
    }

    /// Pełny dokument HTML raportu. `values` — wartości zmiennych i dane nagłówka (user, connection).
    public static func html(_ def: ReportDefinition, data: ReportData, values: [String: String] = [:], generated: Date = Date(),
                            locale: Locale = .current) -> String {
        let formats = data.columns.map { def.format(of: $0) }
        let visible = data.columns.indices.filter { !formats[$0].hidden && !formats[$0].breakGroup }
        let breaks = data.columns.indices.filter { formats[$0].breakGroup }
        let sums = visible.filter { formats[$0].sum }
        var css = def.style.css + "\n" + def.extraCSS
        if !def.background.isEmpty, def.background.range(of: #"^[#A-Za-z0-9(),. %]+$"#, options: .regularExpression) != nil {
            css += "\nbody { background: \(def.background); }"
        }
        if def.pageBreakOnGroup { css += "\n.group { break-after: page; } .group:last-child { break-after: auto; }" }
        // CSS z pliku .rep nie może zamknąć elementu <style> (np. `</style><script>`): `</` → `<\/`.
        css = css.replacingOccurrences(of: "</", with: "<\\/")
        var body = "<h1>\(escape(def.title))</h1>\n"
        let head = header(def, values: values, generated: generated, locale: locale)
        if !head.isEmpty { body += "<div class=\"header\">\(escape(head))</div>\n" }
        func cell(_ row: [ReportValue], _ i: Int) -> String {
            let v = row[i]
            if case .null = v { return "<td class=\"null\" style=\"text-align:\(align(formats[i], v))\"></td>" }
            return "<td style=\"text-align:\(align(formats[i], v))\">\(escape(text(v, formats[i], locale: locale)))</td>"
        }
        func heading(_ i: Int) -> String { escape(formats[i].heading?.isEmpty == false ? formats[i].heading! : data.columns[i]) }
        func sumRow(_ rows: [[ReportValue]], label: String) -> String {
            guard !sums.isEmpty, !rows.isEmpty else { return "" }
            var cells: [String] = []
            for (n, i) in visible.enumerated() {
                if sums.contains(i) {
                    let total = rows.reduce(0.0) { acc, r in if case .number(let d, _) = r[i] { acc + d } else { acc } }
                    cells.append(cell([ReportValue](repeating: .null, count: i) + [.number(total, String(total))], i))
                } else {
                    cells.append(n == 0 ? "<td>\(escape(label))</td>" : "<td></td>")
                }
            }
            return "<tr class=\"sum\">" + cells.joined() + "</tr>\n"
        }
        // Grupy wg kolumn Break (kolejność wierszy z zapytania — ORDER BY po stronie użytkownika).
        var groups: [(key: [ReportValue], rows: [[ReportValue]])] = []
        for r in data.rows {
            let key = breaks.map { r[$0] }
            if let last = groups.last, last.key == key { groups[groups.count - 1].rows.append(r) } else { groups.append((key, [r])) }
        }
        if groups.isEmpty { groups = [([], [])] }
        // Tabela: jedna dla wszystkich grup — wspólne szerokości kolumn, „Razem” pod tymi samymi kolumnami. Przy nowej
        // stronie po grupie tabela na grupę (blok `.group` dzielony przy druku), „Razem” w tabeli ostatniej grupy.
        let single = def.layout == .table && !def.pageBreakOnGroup
        if single { body += "<table>\n" }
        for (gi, g) in groups.enumerated() {
            if !single { body += "<div class=\"group\">\n" }
            if !breaks.isEmpty {
                let master = breaks.map { "\(heading($0)): \(escape(text(g.key[breaks.firstIndex(of: $0)!], formats[$0], locale: locale)))" }.joined(separator: " · ")
                if def.layout == .form { body += "<h2>\(master)</h2>\n" }
                else { body += (single ? "" : "<table>\n") + "<tr class=\"break\"><td colspan=\"\(max(1, visible.count))\">\(master)</td></tr>\n" }
            }
            if def.layout == .form {
                for r in g.rows {
                    body += "<table class=\"form record\">\n"
                    for i in visible { body += "<tr><td class=\"label\">\(heading(i))</td>\(cell(r, i))</tr>\n" }
                    body += "</table>\n"
                }
            } else {
                if breaks.isEmpty && !single { body += "<table>\n" }
                body += "<tr>" + visible.map { "<th style=\"text-align:\(align(formats[$0], data.rows.first?[$0]))\">\(heading($0))</th>" }.joined() + "</tr>\n"
                for r in g.rows { body += "<tr>" + visible.map { cell(r, $0) }.joined() + "</tr>\n" }
                if !breaks.isEmpty { body += sumRow(g.rows, label: L10n.tr("Suma grupy")) }
                if !single {
                    if gi == groups.count - 1 { body += sumRow(data.rows, label: L10n.tr("Razem")) }
                    body += "</table>\n"
                }
            }
            if !single { body += "</div>\n" }
        }
        if single { body += sumRow(data.rows, label: L10n.tr("Razem")) + "</table>\n" }
        if data.truncated { body += "<p class=\"header\">" + escape(L10n.tr("Pokazano pierwsze \(data.rows.count) wierszy.")) + "</p>\n" }
        // CSP: bez skryptów i zasobów zewnętrznych — tylko style z dokumentu i obrazy data:.
        return "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\">"
            + LocalHTML.contentSecurityPolicy
            + "<title>\(escape(def.title))</title>\n<style>\n\(css)\n</style></head>\n<body>\n\(body)</body></html>\n"
    }
}

/// Raporty standardowe (UG 12.1) — menu Raporty.
public enum StandardReports {
    public struct Entry: Sendable {
        public var id: String
        public var definition: ReportDefinition
    }

    public static var all: [Entry] {
        func def(_ title: String, _ sql: String, _ configure: (inout ReportDefinition) -> Void = { _ in }) -> ReportDefinition {
            var d = ReportDefinition(title: title, sql: sql)
            configure(&d)
            return d
        }
        return [
            Entry(id: "reports.compilationErrors", definition: def(L10n.tr("Błędy kompilacji"), """
                select type || ' ' || name obiekt, line linia, position kolumna, attribute rodzaj, text tekst
                  from user_errors order by type, name, sequence
                """) { d in
                var b = ReportColumnFormat(column: "OBIEKT"); b.breakGroup = true
                d.columns = [b]
            }),
            Entry(id: "reports.invalidObjects", definition: def(L10n.tr("Niepoprawne obiekty"), """
                select object_type typ, object_name nazwa, to_char(last_ddl_time, 'YYYY-MM-DD HH24:MI') zmieniony
                  from user_objects where status <> 'VALID' order by object_type, object_name
                """)),
            Entry(id: "reports.recentChanges", definition: def(L10n.tr("Ostatnio zmienione obiekty"), """
                select object_type typ, object_name nazwa, last_ddl_time zmieniony, status
                  from user_objects where last_ddl_time > sysdate - &<name="Dni" type="integer" default="7" required="yes">
                 order by last_ddl_time desc
                """) { d in
                var c = ReportColumnFormat(column: "ZMIENIONY"); c.dateFormat = "yyyy-MM-dd HH:mm"
                d.columns = [c]
                d.header = "#date · " + L10n.tr("ostatnie dni: #Dni")
            }),
            Entry(id: "reports.tableSizes", definition: def(L10n.tr("Rozmiary tabel"), """
                select segment_name tabela, round(sum(bytes) / 1024 / 1024, 2) mb, sum(blocks) bloki
                  from user_segments where segment_type like 'TABLE%' group by segment_name order by 2 desc
                """) { d in
                var mb = ReportColumnFormat(column: "MB"); mb.numberFormat = "#,##0.00"; mb.sum = true
                var bl = ReportColumnFormat(column: "BLOKI"); bl.sum = true
                d.columns = [mb, bl]
            }),
            Entry(id: "reports.tableColumns", definition: def(L10n.tr("Kolumny tabel"), """
                select table_name tabela, column_name kolumna, data_type || case when data_type like '%CHAR%' then '(' || char_length || ')'
                       when data_precision is not null then '(' || data_precision || ',' || data_scale || ')' end typ, nullable pusta
                  from user_tab_columns where table_name like upper('&<name="Tabela" default="%">') order by table_name, column_id
                """) { d in
                var t = ReportColumnFormat(column: "TABELA"); t.breakGroup = true
                d.columns = [t]
            }),
            Entry(id: "reports.privileges", definition: def(L10n.tr("Uprawnienia użytkownika"), """
                select 'systemowe' rodzaj, privilege uprawnienie, null obiekt from user_sys_privs
                union all
                select 'obiektowe', privilege, owner || '.' || table_name from user_tab_privs where grantee = user
                union all
                select 'rola', granted_role, null from user_role_privs
                order by 1, 2, 3
                """) { d in
                var r = ReportColumnFormat(column: "RODZAJ"); r.breakGroup = true
                d.columns = [r]
            }),
            Entry(id: "reports.sessions", definition: def(L10n.tr("Sesje"), """
                select username uzytkownik, count(*) sesje, sum(case when status = 'ACTIVE' then 1 else 0 end) aktywne
                  from v$session where type = 'USER' group by username order by 2 desc
                """) { d in
                var s = ReportColumnFormat(column: "SESJE"); s.sum = true
                var a = ReportColumnFormat(column: "AKTYWNE"); a.sum = true
                d.columns = [s, a]
            }),
        ]
    }
}
