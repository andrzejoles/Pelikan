import Foundation
import PelikanDB
import PelikanSQL

/// Wydruk okna (PD-SQLW-016): nagłówek (tytuł okna, połączenie, data), kod z kolorami składni i — w oknie SQL — siatka
/// wyniku (zaznaczone wiersze albo wszystkie pobrane). Układ jako HTML; okno druku i podział na strony — aplikacja.
public enum PrintLayout {
    public struct Content: Sendable {
        public var title: String
        public var connection: String?
        public var code: String?
        public var grid: ExportData?
        public var gridIsSelection = false
        public var lineNumbers = true
        public var format = ValueFormat.default

        public init(title: String, connection: String? = nil, code: String? = nil, grid: ExportData? = nil) {
            self.title = title; self.connection = connection; self.code = code; self.grid = grid
        }
    }

    public static func html(_ c: Content, printed date: Date = Date()) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm"
        var meta = [df.string(from: date)]
        if let conn = c.connection, !conn.isEmpty { meta.insert(conn, at: 0) }
        var s = "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>\(CodeHTML.escape(c.title))</title><style>"
        s += "@page{margin:15mm}body{font:11px -apple-system,system-ui,sans-serif;color:#000;background:#fff}"
        s += "h1{font-size:14px;margin:0 0 2px}p.meta{color:#555;margin:0 0 10px}h2{font-size:12px;margin:14px 0 4px}"
        s += CodeHTML.css + ResultExporter.tableCSS + "td,th{font-size:10px}</style></head><body>\n"
        s += "<h1>\(CodeHTML.escape(c.title))</h1>\n<p class=\"meta\">\(CodeHTML.escape(meta.joined(separator: " · ")))</p>\n"
        if let code = c.code, !code.isEmpty { s += CodeHTML.pre(code, lineNumbers: c.lineNumbers) + "\n" }
        if let g = c.grid, !g.columns.isEmpty {
            let what = c.gridIsSelection ? L10n.tr("Zaznaczone wiersze: \(g.rows.count)") : L10n.tr("Wiersze: \(g.rows.count)")
            s += "<h2>\(CodeHTML.escape(what))</h2>\n"
            var o = ExportOptions()
            o.format = c.format
            s += ResultExporter.htmlTable(g, options: o)
        }
        return s + "</body></html>\n"
    }

    /// Treść wydruku okna: kod (okna z edytorem) i siatka bieżącej karty wyników (okno SQL, aktywne).
    @MainActor
    public static func content(of doc: Document, in ws: Workspace) -> Content {
        var c = Content(title: doc.fullTitle, connection: ws.effectiveConnection(of: doc).flatMap { ws.connections.connection($0)?.displayName })
        if [.sql, .program, .test, .command].contains(doc.kind) { c.code = doc.text }
        if doc.kind == .sql, ws.activeDocumentID == doc.id, let (tab, grid) = GridCommands.activeGrid(ws) {
            let rows = tab.selectedRows.flatMap { $0.isEmpty ? nil : $0 }
            c.grid = grid.exportData(rows: rows, columns: tab.columnOrder, title: tab.title)
            c.gridIsSelection = rows != nil
            c.format = grid.format
        }
        return c
    }
}
