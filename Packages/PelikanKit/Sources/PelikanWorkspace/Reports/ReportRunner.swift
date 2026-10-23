import Foundation
import PelikanDB
import PelikanSQL

/// Wykonanie raportu (UG 12.2–12.6) w sesji narzędzi połączenia raportu.
@MainActor
public enum ReportRunner {
    /// Połączenie raportu: wskazane w opcjach (nazwa połączenia), potem połączenie okna, potem główne.
    public static func connection(for doc: Document, in ws: Workspace) -> UUID? {
        let name = doc.report.connection.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, let def = ws.connections.connections.first(where: { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }) {
            return def.id
        }
        return ws.effectiveConnection(of: doc) ?? ws.sessions.mainConnectionID
    }

    /// Dane raportu z zapytania (bez okna): wiersze do limitu, typy wartości do formatowania.
    public static func data(_ sql: String, binds: [BindVariable], maxRows: Int, format: ValueFormat, in s: any DatabaseSession) async throws -> ReportData {
        var text = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(";") { text.removeLast() }
        let r = try await s.execute(text, binds: binds, options: ExecuteOptions(lobLimit: 64_000))
        guard let rs = r.resultSet else { throw CommandError.notAvailable(L10n.tr("Raport wymaga zapytania SELECT")) }
        var rows: [[ReportValue]] = []
        var truncated = false
        while true {
            let batch = try await s.fetch(rs.id, maxRows: min(1000, maxRows + 1 - rows.count))
            for row in batch.rows {
                if rows.count >= maxRows { truncated = true; break }
                rows.append(row.map { ReportValue($0, format: format) })
            }
            if truncated || !batch.hasMore { break }
        }
        if truncated { await s.closeResultSet(rs.id) }
        return ReportData(columns: rs.columns.map(\.name), rows: rows, truncated: truncated)
    }

    static func binds(_ prepared: Variables.Prepared) -> [BindVariable] {
        prepared.binds.map { b -> BindVariable in
            switch b.value {
            case .null: BindVariable(name: b.name, type: .varchar2, value: .null, maxSize: 4000)
            case .text(let t): BindVariable(name: b.name, type: .varchar2, value: .text(t), maxSize: 32767)
            case .list(let l): BindVariable(name: b.name, type: .varchar2, value: .text(l.joined(separator: ",")), maxSize: 32767)
            }
        }
    }

    /// Wykonuje raport okna: pyta o zmienne (okno „Zmienne”, UG 12.3), wykonuje, renderuje HTML do `doc.reportHTML`.
    /// `values` — wartości podane z góry (testy, raporty bez pytania).
    @discardableResult
    public static func run(_ doc: Document, in ws: Workspace, values provided: [String: VariableValue]? = nil) async throws -> String {
        var def = doc.report
        def.sql = doc.text
        let requests = SQLExecutor.variableRequests(ScriptSplitter.split(def.sql), remembered: doc.variableValues)
        var values = provided ?? [:]
        if provided == nil, !requests.isEmpty {
            guard let ui = ws.ui, let answers = await ui.askVariables(requests, document: doc) else { throw CommandError.cancelledByUser }
            values = answers
        }
        for (k, v) in values { doc.variableValues[k] = v }
        guard let conn = connection(for: doc, in: ws) else { throw CommandError.notConnected }
        let session = try await ws.sessions.session(SessionKey(connectionID: conn, purpose: .tool("report")))
        let prepared = Variables.prepare(def.sql, values: values)
        doc.isExecuting = true
        defer { doc.isExecuting = false }
        do {
            let data = try await data(prepared.sql, binds: binds(prepared), maxRows: def.maxRows, format: ws.settings.valueFormat, in: session)
            var header: [String: String] = [:]
            for (k, v) in values {
                switch v {
                case .null: header[k] = ""
                case .text(let t): header[k] = t
                case .list(let l): header[k] = l.joined(separator: ", ")
                }
            }
            header["user"] = session.info.currentSchema
            header["connection"] = ws.connections.connection(conn)?.displayName ?? ""
            let html = ReportRenderer.html(def, data: data, values: header)
            doc.reportHTML = html
            doc.reportData = data
            doc.reportError = nil
            return html
        } catch {
            doc.reportError = error.localizedDescription
            throw error
        }
    }

    /// Dane raportu jako dane eksportu (CSV/TSV/XML/Excel, PD-REP-001).
    public static func exportData(_ doc: Document) -> ExportData? {
        guard let d = doc.reportData else { return nil }
        let columns = d.columns.map { ColumnInfo(name: $0, type: .varchar2, typeName: "VARCHAR2") }
        let rows = d.rows.map { $0.map { v -> OracleValue in
            switch v {
            case .null: .null
            case .number(_, let raw): .number(raw)
            case .date: .text(ReportRenderer.text(v, ReportColumnFormat(column: ""), locale: Locale(identifier: "en_US_POSIX")))
            case .text(let t): .text(t)
            }
        } }
        return ExportData(title: doc.report.title, columns: columns, rows: rows, sql: doc.text)
    }
}

extension Workspace {
    /// Katalog raportów użytkownika (menu Raporty, UG 12.7).
    public var reportsDirectory: URL? { dataDirectory?.appendingPathComponent("Reports", isDirectory: true) }

    /// Nowe okno raportu z definicją.
    @discardableResult
    public func openReport(_ def: ReportDefinition) -> Document {
        let doc = newDocument(.report, text: def.sql)
        doc.report = def
        doc.customTitle = def.title
        doc.isModified = false
        return doc
    }

    /// Komendy raportów z katalogu użytkownika (`*.rep`) — odświeżane po zapisie raportu do menu.
    public func registerUserReports() {
        unregister(registry.commands.map(\.id).filter { $0.rawValue.hasPrefix("reports.user.") })
        guard let dir = reportsDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        var commands: [Command] = []
        for url in files where url.pathExtension.lowercased() == "rep" {
            let base = url.deletingPathExtension().lastPathComponent
            let slug = base.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
            commands.append(Command(CommandDescriptor(id: CommandID(rawValue: "reports.user.\(slug)"), title: base, category: .reports,
                                                      submenu: L10n.tr("Moje raporty"), agent: .none, effect: .uiState,
                                                      summary: L10n.tr("Raport użytkownika z katalogu raportów: \(base)."), feature: "PD-REP-004")) { ctx in
                let doc = try ctx.workspace.openFile(url, as: .report)
                try await ReportRunner.run(doc, in: ctx.workspace)
                return .ok
            })
        }
        register(commands)
    }
}

/// Komendy raportów (PD-REP-001..004).
@MainActor
enum ReportCommands {
    static func reportDocument(_ ws: Workspace) -> Document? {
        guard let d = ws.activeDocument, d.kind == .report else { return nil }
        return d
    }

    static var all: [Command] {
        var list: [Command] = StandardReports.all.map { entry in
            Command(CommandDescriptor(id: CommandID(rawValue: entry.id), title: entry.definition.title, category: .reports,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Raport standardowy „\(entry.definition.title)” w oknie raportu (HTML, druk, zapis, eksport)."),
                                      feature: "PD-REP-001"),
                    validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                let doc = ctx.workspace.openReport(entry.definition)
                try await ReportRunner.run(doc, in: ctx.workspace)
                return .ok
            }
        }
        list += [
            Command(CommandDescriptor(id: "report.execute", title: L10n.tr("Wykonaj raport"), category: .reports, submenu: L10n.tr("Raport"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Wykonuje zapytanie okna raportu (z pytaniem o zmienne) i pokazuje wynik HTML; w oknie raportu także Wykonaj (F8)."),
                                      feature: "PD-REP-002"),
                    validate: { ws in reportDocument(ws).map { !$0.isExecuting } ?? false }) { ctx in
                guard let doc = reportDocument(ctx.workspace) else { return .ok }
                try await ReportRunner.run(doc, in: ctx.workspace)
                return .ok
            },
            Command(CommandDescriptor(id: "report.saveHTML", title: L10n.tr("Zapisz raport jako HTML…"), category: .reports, submenu: L10n.tr("Raport"),
                                      agent: .none, effect: .external, summary: L10n.tr("Zapisuje wynik raportu do pliku HTML."), feature: "PD-REP-001"),
                    validate: { reportDocument($0)?.reportHTML != nil }) { ctx in
                guard let doc = reportDocument(ctx.workspace), let html = doc.reportHTML else { return .ok }
                _ = await ctx.ui?.saveFile(suggestedName: doc.report.title.isEmpty ? "raport" : doc.report.title, fileExtension: "html", data: Data(html.utf8))
                return .ok
            },
            Command(CommandDescriptor(id: "report.export", title: L10n.tr("Eksportuj dane raportu…"), category: .reports, submenu: L10n.tr("Raport"),
                                      parameters: [CommandParameter("format", .string, L10n.tr("Format"), allowed: ["csv", "tsv", "xml", "xlsx"])],
                                      agent: .none, effect: .external, summary: L10n.tr("Zapisuje dane wyniku raportu jako CSV, TSV, XML albo Excel."), feature: "PD-REP-001"),
                    validate: { reportDocument($0)?.reportData != nil }) { ctx in
                guard let doc = reportDocument(ctx.workspace), let data = ReportRunner.exportData(doc) else { return .ok }
                let format = ExportFormat(rawValue: ctx.arguments.string("format") ?? "csv") ?? .csv
                let bytes = format == .xlsx ? ResultExporter.xlsx([data]) : Data(ResultExporter.text(format, data).utf8)
                _ = await ctx.ui?.saveFile(suggestedName: doc.report.title.isEmpty ? "raport" : doc.report.title, fileExtension: format.fileExtension, data: bytes)
                return .ok
            },
            Command(CommandDescriptor(id: "report.print", title: L10n.tr("Drukuj raport…"), category: .reports, submenu: L10n.tr("Raport"),
                                      agent: .none, effect: .external, summary: L10n.tr("Drukuje wynik raportu (także do PDF z okna druku)."), feature: "PD-REP-001"),
                    validate: { reportDocument($0)?.reportHTML != nil }) { ctx in
                guard let doc = reportDocument(ctx.workspace), let html = doc.reportHTML else { return .ok }
                ctx.ui?.printHTML(html, title: doc.report.title)
                return .ok
            },
            Command(CommandDescriptor(id: "report.lock", title: L10n.tr("Zablokuj definicję raportu"), category: .reports, submenu: L10n.tr("Raport"),
                                      agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Ukrywa zapytanie i układ raportu; raport można tylko wykonywać (do odblokowania)."), feature: "PD-REP-004"),
                    validate: { reportDocument($0).map { !$0.report.locked } ?? false }) { ctx in
                guard let doc = reportDocument(ctx.workspace) else { return .ok }
                doc.report.locked = true
                doc.isModified = true
                return .ok
            },
            Command(CommandDescriptor(id: "report.unlock", title: L10n.tr("Odblokuj definicję raportu"), category: .reports, submenu: L10n.tr("Raport"),
                                      agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Przywraca edycję zapytania i układu raportu (po potwierdzeniu)."), feature: "PD-REP-004"),
                    validate: { reportDocument($0)?.report.locked ?? false }) { ctx in
                guard let doc = reportDocument(ctx.workspace) else { return .ok }
                if let ui = ctx.ui {
                    guard await ui.ask(L10n.tr("Odblokować definicję raportu?"), message: L10n.tr("Zapytanie i układ raportu będą widoczne i edytowalne."),
                                       buttons: [L10n.tr("Odblokuj"), L10n.tr("Anuluj")]) == 0 else { throw CommandError.cancelledByUser }
                }
                doc.report.locked = false
                doc.isModified = true
                return .ok
            },
            Command(CommandDescriptor(id: "report.addToMenu", title: L10n.tr("Dodaj raport do menu Raporty"), category: .reports, submenu: L10n.tr("Raport"),
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Zapisuje raport w katalogu raportów użytkownika — pojawia się w menu Raporty › Moje raporty."), feature: "PD-REP-004"),
                    validate: { reportDocument($0) != nil && $0.reportsDirectory != nil }) { ctx in
                let ws = ctx.workspace
                guard let doc = reportDocument(ws), let dir = ws.reportsDirectory else { return .ok }
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let name = (doc.report.title.isEmpty ? "raport" : doc.report.title).replacingOccurrences(of: "/", with: "-")
                try ws.save(doc, to: dir.appendingPathComponent(name + ".rep"))
                ws.registerUserReports()
                return CommandResult(message: L10n.tr("Raport dodany do menu"))
            },
        ]
        return list
    }
}
