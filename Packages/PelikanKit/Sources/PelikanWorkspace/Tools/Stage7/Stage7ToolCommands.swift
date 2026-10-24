import Foundation
import PelikanDB

/// Okna narzędzi etapu 7 otwierane przez interfejs.
public enum Stage7Tool: String, Sendable, CaseIterable {
    case predefinedReports, databaseDiff, cart, schemaCopy, importWizard, dataTransfer, localTasks
}

/// Komendy narzędzi etapu 7 (notatnik, raporty predefiniowane, Database Diff/Cart, kopiowanie schematu, import,
/// diagram ER z bazy, przenoszenie danych, zadania lokalne). Agent — Brak: zmieniają dane, pliki albo harmonogram.
@MainActor
enum Stage7ToolCommands {
    static func open(_ id: CommandID, _ title: String, _ tool: Stage7Tool, category: CommandCategory = .tools, summary: String, feature: String,
                     needsConnection: Bool = true) -> Command {
        Command(CommandDescriptor(id: id, title: title, category: category, agent: .none, effect: .uiState, summary: summary, feature: feature),
                validate: { !needsConnection || DataTransferCommands.connection($0) != nil }) { ctx in
            ctx.ui?.showStage7Tool(tool)
            return .ok
        }
    }

    static func string(_ v: OracleValue) -> String { v.displayText ?? "" }

    static var all: [Command] {
        NotebookCommands.all + [
            open("reports.predefined", L10n.tr("Raporty predefiniowane…"), .predefinedReports, category: .reports,
                 summary: L10n.tr("Raporty w kategoriach (słownik danych, obiekty, PL/SQL, bezpieczeństwo, przechowywanie): siatka, wykres albo DBMS_OUTPUT, zmienne, szczegóły wiersza, otwarcie w oknie SQL, eksport."),
                 feature: "SD-REP-001"),
            Command(CommandDescriptor(id: "reports.predefined.run", title: L10n.tr("Wykonaj raport predefiniowany"), category: .reports,
                                      parameters: [CommandParameter("report", .string, required: true, L10n.tr("Identyfikator raportu"),
                                                                    allowed: PredefinedReports.catalog.map(\.id)),
                                                   CommandParameter("owner", .string, L10n.tr("Schemat (puste — bieżący)"))],
                                      agent: .none, effect: .none, summary: L10n.tr("Wykonuje raport predefiniowany i pokazuje wynik w oknie informacji."),
                                      inMenu: false, feature: "SD-REP-001"),
                    validate: { DataTransferCommands.connection($0) != nil }) { ctx in
                guard let id = ctx.arguments.string("report"), let r = PredefinedReports.report(id) else { throw CommandError.invalidArgument("report", L10n.tr("Nieznany raport")) }
                var values = Dictionary(uniqueKeysWithValues: r.variables.map { ($0.name, $0.defaultValue) })
                if let o = ctx.arguments.string("owner") { values["OWNER"] = o }
                let s = try await DataTransferCommands.session(ctx.workspace)
                let res = try await PredefinedReports.run(r, values: values, in: s)
                if r.style == .dbmsOutput {
                    ctx.ui?.showObjectInfo(title: r.title, columns: ["OUTPUT"], rows: res.output.map { [$0] })
                } else {
                    ctx.ui?.showObjectInfo(title: r.title, columns: res.columns.map(\.name), rows: res.rows.map { $0.map(string) })
                }
                return CommandResult(message: L10n.tr("Wierszy: \(res.count(for: r))"))
            },
            Command(CommandDescriptor(id: "reports.predefined.worksheet", title: L10n.tr("Otwórz raport w oknie SQL"), category: .reports,
                                      parameters: [CommandParameter("report", .string, required: true, L10n.tr("Identyfikator raportu"),
                                                                    allowed: PredefinedReports.catalog.map(\.id))],
                                      agent: .none, effect: .uiState, summary: L10n.tr("Zapytanie raportu predefiniowanego w nowym oknie SQL (Open in Worksheet)."),
                                      inMenu: false, feature: "SD-REP-001")) { ctx in
                guard let id = ctx.arguments.string("report"), let r = PredefinedReports.report(id) else { throw CommandError.invalidArgument("report", L10n.tr("Nieznany raport")) }
                ctx.workspace.openReportInWorksheet(r)
                return .ok
            },
            open("tools.databaseDiff", L10n.tr("Database Diff…"), .databaseDiff,
                 summary: L10n.tr("Porównanie schematów (także dwóch połączeń) według typów obiektów; tabele wyrównywane przez ALTER TABLE; różnice do koszyka albo skryptu."),
                 feature: "SD-DIFF-001"),
            open("tools.cart", L10n.tr("Koszyk wdrożenia…"), .cart,
                 summary: L10n.tr("Koszyk obiektów do wdrożenia (DDL i dane z filtrem); zapis koszyka i skrypt wdrożenia w kolejności zależności."),
                 feature: "SD-DIFF-001", needsConnection: false),
            Command(CommandDescriptor(id: "cart.add", title: L10n.tr("Dodaj obiekt do koszyka"), category: .tools, submenu: L10n.tr("Koszyk"),
                                      parameters: [CommandParameter("object", .string, required: true, L10n.tr("Nazwa obiektu [schemat.]nazwa"))],
                                      agent: .none, effect: .settings, summary: L10n.tr("Dodaje obiekt bazy do koszyka wdrożenia."), inMenu: false,
                                      feature: "SD-DIFF-001")) { ctx in
                guard let name = ctx.arguments.string("object") else { throw CommandError.missingArgument("object") }
                guard let m = ctx.workspace.metadata(for: DataTransferCommands.connection(ctx.workspace)), let o = try await m.find(name) else {
                    throw CommandError.notAvailable(L10n.tr("Nie znaleziono obiektu \(name)"))
                }
                var c = ctx.workspace.loadCart()
                c.add(o)
                // Pakiet i typ razem z ciałem (skrypt ze samą specyfikacją wdrożyłby niekompletny kod).
                if o.type == .package || o.type == .type {
                    let body = DBObject(owner: o.owner, name: o.name, type: o.type == .package ? .packageBody : .typeBody)
                    if let src = try? await m.source(of: body), !src.isEmpty { c.add(body) }
                }
                try ctx.workspace.saveCart(c)
                return CommandResult(message: L10n.tr("W koszyku: \(c.items.count)"))
            },
            Command(CommandDescriptor(id: "cart.script", title: L10n.tr("Skrypt wdrożenia koszyka"), category: .tools, submenu: L10n.tr("Koszyk"),
                                      agent: .none, effect: .uiState, summary: L10n.tr("Generuje skrypt wdrożenia koszyka w nowym oknie SQL."),
                                      feature: "SD-DIFF-001"),
                    validate: { DataTransferCommands.connection($0) != nil }) { ctx in
                let c = ctx.workspace.loadCart()
                guard !c.items.isEmpty else { throw CommandError.notAvailable(L10n.tr("Koszyk jest pusty")) }
                let s = try await DataTransferCommands.session(ctx.workspace)
                let doc = ctx.workspace.newDocument(.sql, text: try await c.deploymentScript(in: s))
                doc.customTitle = c.name
                return .ok
            },
            open("tools.schemaCopy", L10n.tr("Kopiowanie schematu…"), .schemaCopy,
                 summary: L10n.tr("Kreator kopiowania obiektów i danych schematu do innego schematu lub połączenia (kolejność zależności, klucze obce i wyzwalacze na końcu)."),
                 feature: "SD-COPY-001"),
            open("tools.importWizard", L10n.tr("Kreator importu danych…"), .importWizard,
                 summary: L10n.tr("Import CSV, tekstu rozdzielanego lub o stałej szerokości i XLSX: podgląd, kodowanie, mapowanie, nowa lub istniejąca tabela, zapis profilu."),
                 feature: "SD-IMP-001"),
            Command(CommandDescriptor(id: "diagram.fromSchema", title: L10n.tr("Diagram ER ze schematu…"), category: .tools, submenu: L10n.tr("Diagram"),
                                      parameters: [CommandParameter("owner", .string, L10n.tr("Schemat (puste — bieżący)")),
                                                   CommandParameter("pattern", .string, L10n.tr("Maska nazw tabel (LIKE), domyślnie %"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Diagram ER tabel schematu z kluczami obcymi i automatycznym układem; eksport obrazu z okna diagramu."),
                                      feature: "DB-DIAG-001"),
                    validate: { DataTransferCommands.connection($0) != nil }) { ctx in
                let conn = DataTransferCommands.connection(ctx.workspace)
                var owner = ctx.arguments.string("owner") ?? ""
                var pattern = ctx.arguments.string("pattern") ?? ""
                if ctx.arguments.string("owner") == nil, let ui = ctx.ui {
                    guard let o = await ui.askText(L10n.tr("Diagram ER ze schematu"), message: L10n.tr("Schemat (puste — bieżący):"),
                                                   defaultValue: ctx.workspace.sessions.connectedSchema(conn) ?? "") else { throw CommandError.cancelledByUser }
                    owner = o
                    guard let p = await ui.askText(L10n.tr("Diagram ER ze schematu"), message: L10n.tr("Maska nazw tabel (LIKE):"), defaultValue: "%") else {
                        throw CommandError.cancelledByUser
                    }
                    pattern = p
                }
                if owner.isEmpty { owner = ctx.workspace.sessions.connectedSchema(conn) ?? "" }
                let doc = try await ctx.workspace.openERDiagram(owner: owner, pattern: pattern.isEmpty ? "%" : pattern, connection: conn)
                return CommandResult(message: L10n.tr("Tabel: \(doc.diagram.items.count), relacji: \(doc.diagram.links.count)"))
            },
            open("tools.dataTransfer", L10n.tr("Przenoszenie danych…"), .dataTransfer,
                 summary: L10n.tr("Przenoszenie danych z tabeli lub zapytania do tabeli w tym samym albo innym połączeniu z mapowaniem kolumn; zapis definicji."),
                 feature: "DB-XFER-001"),
            Command(CommandDescriptor(id: "transfer.run", title: L10n.tr("Wykonaj zapisane przeniesienie danych"), category: .tools,
                                      parameters: [CommandParameter("name", .string, required: true, L10n.tr("Nazwa definicji"))],
                                      agent: .none, effect: .modifiesDatabase, summary: L10n.tr("Wykonuje zapisaną definicję przeniesienia danych jako zadanie w tle."),
                                      inMenu: false, feature: "DB-XFER-001")) { ctx in
                guard let name = ctx.arguments.string("name") else { throw CommandError.missingArgument("name") }
                let job = try DataTransferStore.load(name, in: ctx.workspace.dataDirectory)
                let ws = ctx.workspace
                ws.tasks.run(L10n.tr("Przeniesienie danych: \(name)"), kind: "transfer") { t in
                    let r = try await ws.runDataTransfer(job) { n in t.message = L10n.tr("Wierszy: \(n)") }
                    t.message = L10n.tr("Przeniesiono: \(r.inserted), błędy: \(r.errors.count)")
                }
                return .ok
            },
            open("tools.localTasks", L10n.tr("Zadania lokalne…"), .localTasks,
                 summary: L10n.tr("Zadania uruchamiane cyklicznie przez Pelikana (skrypt, eksport, przeniesienie danych); połączenia po nazwie, hasła tylko w Pęku kluczy."),
                 feature: "DB-TASK-001", needsConnection: false),
            Command(CommandDescriptor(id: "localTasks.runNow", title: L10n.tr("Uruchom zadanie lokalne"), category: .tools,
                                      parameters: [CommandParameter("name", .string, required: true, L10n.tr("Nazwa zadania"))],
                                      agent: .none, effect: .modifiesDatabase, summary: L10n.tr("Uruchamia zadanie lokalne od razu (poza harmonogramem)."),
                                      inMenu: false, feature: "DB-TASK-001")) { ctx in
                guard let name = ctx.arguments.string("name"),
                      let d = ctx.workspace.localTasks.definitions.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                    throw CommandError.notAvailable(L10n.tr("Nie ma zadania lokalnego o tej nazwie"))
                }
                ctx.workspace.localTasks.start(ctx.workspace)
                ctx.workspace.localTasks.run(d)
                return .ok
            },
        ]
    }
}

extension PredefinedReportResult {
    func count(for r: PredefinedReport) -> Int { r.style == .dbmsOutput ? output.count : rows.count }
}
