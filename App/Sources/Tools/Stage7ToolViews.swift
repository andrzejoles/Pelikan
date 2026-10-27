import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Okna narzędzi etapu 7 (raporty predefiniowane, Database Diff, koszyk, kopiowanie schematu, kreator importu,
/// przenoszenie danych, zadania lokalne). Logika w PelikanWorkspace; tu tylko formularze.
@MainActor
enum Stage7ToolWindows {
    static func show(_ tool: Stage7Tool, workspace: Workspace) {
        switch tool {
        case .predefinedReports:
            ToolWindowController.show(key: "predefinedReports", title: L10n.tr("Raporty predefiniowane"), size: NSSize(width: 1000, height: 640)) { PredefinedReportsView(workspace: workspace) }
        case .databaseDiff:
            ToolWindowController.show(key: "databaseDiff", title: L10n.tr("Database Diff"), size: NSSize(width: 900, height: 600)) { DatabaseDiffView(workspace: workspace) }
        case .cart:
            ToolWindowController.show(key: "cart", title: L10n.tr("Koszyk wdrożenia"), size: NSSize(width: 820, height: 520)) { CartView(workspace: workspace) }
        case .schemaCopy:
            ToolWindowController.show(key: "schemaCopy", title: L10n.tr("Kopiowanie schematu"), size: NSSize(width: 760, height: 560)) { SchemaCopyView(workspace: workspace) }
        case .importWizard:
            ToolWindowController.show(key: "importWizard", title: L10n.tr("Kreator importu danych"), size: NSSize(width: 980, height: 700)) { ImportWizardView(workspace: workspace) }
        case .dataTransfer:
            ToolWindowController.show(key: "dataTransfer2", title: L10n.tr("Przenoszenie danych"), size: NSSize(width: 900, height: 640)) { DataTransferJobView(workspace: workspace) }
        case .localTasks:
            ToolWindowController.show(key: "localTasks", title: L10n.tr("Zadania lokalne"), size: NSSize(width: 900, height: 560)) { LocalTasksView(workspace: workspace) }
        }
    }

    static let objectTypes = ["TABLE", "VIEW", "SEQUENCE", "INDEX", "SYNONYM", "PACKAGE", "PACKAGE BODY", "PROCEDURE", "FUNCTION", "TRIGGER", "TYPE", "TYPE BODY", "MATERIALIZED VIEW"]

    static func session(_ ws: Workspace, _ conn: UUID?, purpose: String) async throws -> any DatabaseSession {
        guard let conn else { throw CommandError.notConnected }
        return try await ws.sessions.session(SessionKey(connectionID: conn, purpose: .tool(purpose)))
    }
}

/// Wybór typów obiektów (pola wyboru w kolumnach).
struct ObjectTypesPicker: View {
    @Binding var types: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading) {
            ForEach(Stage7ToolWindows.objectTypes, id: \.self) { t in
                Toggle(t, isOn: Binding(get: { types.contains(t) }, set: { if $0 { types.insert(t) } else { types.remove(t) } })).toggleStyle(.checkbox)
            }
        }
        .font(.uiSecondary)
    }
}

// MARK: Raporty predefiniowane (SD-REP-001)

struct PredefinedReportsView: View {
    let workspace: Workspace
    @State private var selection: String?
    @State private var values: [String: String] = [:]
    @State private var result: PredefinedReportResult?
    @State private var detail: PredefinedReportResult?
    @State private var detailRow = 1
    @State private var message = ""
    @State private var busy = false

    private var report: PredefinedReport? { selection.flatMap(PredefinedReports.report) }

    var body: some View {
        HSplitView {
            List(selection: $selection) {
                ForEach(PredefinedReports.categories, id: \.self) { cat in
                    Section(cat) {
                        ForEach(PredefinedReports.catalog.filter { $0.category == cat }) { r in Text(r.title).tag(r.id) }
                    }
                }
            }
            .frame(minWidth: 240, idealWidth: 260, maxWidth: 320)
            VStack(alignment: .leading, spacing: 8) {
                if let r = report {
                    Text(r.title).font(.uiHeadline)
                    ForEach(r.variables, id: \.name) { v in
                        TextField(v.label, text: Binding(get: { values[v.name] ?? v.defaultValue }, set: { values[v.name] = $0 }))
                    }
                    HStack {
                        Button(L10n.tr("Wykonaj")) { Task { await run(r) } }.keyboardShortcut(.return).disabled(busy)
                        Button(L10n.tr("Otwórz w oknie SQL")) { workspace.openReportInWorksheet(r) }
                        Menu(L10n.tr("Eksport")) {
                            Button("CSV…") { export(r, .csv) }
                            Button("HTML…") { export(r, .html) }
                            Button("XLSX…") { export(r, .xlsx) }
                        }
                        .fixedSize().disabled(result == nil)
                        Spacer()
                        if busy { ProgressView().controlSize(.small) }
                    }
                    if let res = result { output(r, res) }
                    if r.detailSQL != nil, let res = result, !res.rows.isEmpty {
                        HStack {
                            Text(r.detailTitle ?? L10n.tr("Szczegóły"))
                            Stepper(L10n.tr("wiersz \(detailRow)"), value: $detailRow, in: 1...max(1, res.rows.count))
                            Button(L10n.tr("Pokaż szczegóły")) { Task { await showDetail(r, res) } }
                        }
                        if let d = detail { SimpleGridView(columns: d.columns.map(\.name), rows: d.rows.map { $0.map { $0.displayText ?? "" } }).frame(minHeight: 120) }
                    }
                } else {
                    Text(L10n.tr("Wybierz raport z listy")).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(message).font(.uiSecondary).foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(minWidth: 600)
        }
        .onChange(of: selection) { result = nil; detail = nil; message = "" }
    }

    @ViewBuilder private func output(_ r: PredefinedReport, _ res: PredefinedReportResult) -> some View {
        if r.style == .dbmsOutput {
            ScrollView { Text(res.output.joined(separator: "\n")).font(.code).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        } else {
            if r.style == .chart, let data = PredefinedReports.chartData(r, res) { SimpleChartView(data: data, kind: r.chart?.kind ?? .bar).frame(minHeight: 200) }
            SimpleGridView(columns: res.columns.map(\.name), rows: res.rows.map { $0.map { $0.displayText ?? "" } })
        }
    }

    private func run(_ r: PredefinedReport) async {
        busy = true
        defer { busy = false }
        do {
            let s = try await DataTransferCommands.session(workspace)
            var v = Dictionary(uniqueKeysWithValues: r.variables.map { ($0.name, $0.defaultValue) })
            v.merge(values) { $1 }
            result = try await PredefinedReports.run(r, values: v, in: s)
            detail = nil
            message = L10n.tr("Wierszy: \(result?.rows.count ?? 0)") + (result?.truncated == true ? " " + L10n.tr("(obcięto)") : "")
        } catch { message = error.localizedDescription }
    }

    private func showDetail(_ r: PredefinedReport, _ res: PredefinedReportResult) async {
        do {
            let s = try await DataTransferCommands.session(workspace)
            detail = try await PredefinedReports.detail(r, master: res, row: detailRow - 1, values: values, in: s)
        } catch { message = error.localizedDescription }
    }

    private func export(_ r: PredefinedReport, _ f: ExportFormat) {
        guard let res = result else { return }
        let data = PredefinedReports.exportData(r, res)
        let bytes = f == .xlsx ? ResultExporter.xlsx([data]) : Data(ResultExporter.text(f, data).utf8)
        Task { _ = await workspace.ui?.saveFile(suggestedName: r.title, fileExtension: f.rawValue, data: bytes) }
    }
}

// MARK: Database Diff (SD-DIFF-001)

struct DatabaseDiffView: View {
    let workspace: Workspace
    @State private var sourceOwner = ""
    @State private var targetID: UUID?
    @State private var targetOwner = ""
    @State private var options = DatabaseDiff.Options()
    @State private var diffs: [ObjectDifference] = []
    @State private var selection: ObjectDifference.ID?
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Form {
                TextField(L10n.tr("Schemat źródłowy"), text: $sourceOwner)
                Picker(L10n.tr("Połączenie docelowe"), selection: $targetID) {
                    ForEach(workspace.connections.connections) { Text($0.displayName).tag(UUID?.some($0.id)) }
                }
                TextField(L10n.tr("Schemat docelowy"), text: $targetOwner)
                HStack {
                    Toggle(L10n.tr("Ignoruj wielkość liter"), isOn: $options.compare.ignoreCase)
                    Toggle(L10n.tr("Ignoruj odstępy"), isOn: $options.compare.ignoreWhitespace)
                    Toggle(L10n.tr("Usuń nadmiarowe obiekty"), isOn: $options.compare.dropExtra)
                    Toggle(L10n.tr("Usuń nadmiarowe kolumny"), isOn: $options.dropColumns)
                }
                .toggleStyle(.checkbox)
            }
            ObjectTypesPicker(types: $options.types)
            Table(diffs, selection: $selection) {
                TableColumn(L10n.tr("Obiekt")) { d in Text(d.name) }
                TableColumn(L10n.tr("Typ")) { d in Text(d.type.rawValue) }.width(130)
                TableColumn(L10n.tr("Różnica")) { d in Text(d.status == .onlySource ? L10n.tr("tylko w źródle") : d.status == .onlyTarget ? L10n.tr("tylko w celu") : L10n.tr("różny")) }.width(130)
            }
            HStack {
                Text(message).font(.uiSecondary).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("Porównaj")) { Task { await compare() } }.disabled(busy || targetID == nil || targetOwner.isEmpty)
                Button(L10n.tr("Pokaż różnice")) {
                    if let d = diffs.first(where: { $0.id == selection }) {
                        workspace.ui?.showDiff(left: d.sourceDDL, right: d.targetDDL, leftTitle: "\(sourceOwner).\(d.name)", rightTitle: "\(targetOwner).\(d.name)")
                    }
                }.disabled(selection == nil)
                Button(L10n.tr("Skrypt wyrównujący")) {
                    let d = workspace.newDocument(.sql, text: ObjectCompare.script(diffs))
                    d.connectionID = targetID
                }.disabled(diffs.isEmpty)
                Button(L10n.tr("Do koszyka")) {
                    var c = workspace.loadCart()
                    for i in DatabaseDiff.cart(from: diffs, sourceOwner: sourceOwner.uppercased()).items
                    where !c.items.contains(where: { $0.owner == i.owner && $0.name == i.name && $0.type == i.type }) { c.items.append(i) }
                    do { try workspace.saveCart(c); message = L10n.tr("W koszyku: \(c.items.count)") } catch { message = error.localizedDescription }
                }.disabled(diffs.isEmpty)
            }
        }
        .padding(12)
        .task {
            sourceOwner = workspace.sessions.connectedSchema(DataTransferCommands.connection(workspace)) ?? ""
            targetID = workspace.sessions.mainConnectionID
        }
    }

    private func compare() async {
        busy = true
        defer { busy = false }
        do {
            let src = try await DataTransferCommands.session(workspace)
            let dst = try await Stage7ToolWindows.session(workspace, targetID, purpose: "diff")
            diffs = try await DatabaseDiff.run(sourceOwner: sourceOwner.uppercased(), source: src, targetOwner: targetOwner.uppercased(), target: dst, options: options) { n, all in
                message = L10n.tr("Porównano \(n) z \(all)")
            }
            message = L10n.tr("Różnice: \(diffs.count)")
        } catch { message = error.localizedDescription }
    }
}

// MARK: Koszyk (SD-DIFF-001)

struct CartView: View {
    let workspace: Workspace
    @State private var cart = DeploymentCart(name: "")
    @State private var selection: Set<UUID> = []
    @State private var objectName = ""
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(L10n.tr("Nazwa koszyka"), text: $cart.name)
                Toggle(L10n.tr("Nazwa schematu w DDL"), isOn: $cart.includeOwner).toggleStyle(.checkbox)
                Toggle(L10n.tr("Uprawnienia"), isOn: $cart.includeGrants).toggleStyle(.checkbox)
            }
            Table($cart.items, selection: $selection) {
                TableColumn(L10n.tr("Obiekt")) { $i in Text("\(i.owner).\(i.name)") }
                TableColumn(L10n.tr("Typ")) { $i in Text(i.type) }.width(110)
                TableColumn("DDL") { $i in Toggle("", isOn: $i.includeDDL).labelsHidden() }.width(40)
                TableColumn(L10n.tr("Dane")) { $i in Toggle("", isOn: $i.includeData).labelsHidden().disabled(i.type != "TABLE") }.width(44)
                TableColumn("WHERE") { $i in TextField("", text: $i.whereClause).disabled(!i.includeData) }
            }
            HStack {
                TextField(L10n.tr("Dodaj obiekt (schemat.nazwa)"), text: $objectName).frame(maxWidth: 260)
                Button(L10n.tr("Dodaj")) { Task { await add() } }.disabled(objectName.isEmpty)
                Button(L10n.tr("Usuń")) { cart.remove(selection); persist() }.disabled(selection.isEmpty)
                Spacer()
                Text(message).font(.uiSecondary).foregroundStyle(.secondary)
                Button(L10n.tr("Zapisz jako…")) { Task { await saveAs() } }
                Button(L10n.tr("Otwórz…")) { Task { await openFile() } }
                Button(L10n.tr("Skrypt wdrożenia")) { Task { await script() } }.disabled(cart.items.isEmpty)
            }
        }
        .padding(12)
        .task { cart = workspace.loadCart() }
        .onChange(of: cart) { persist() }
    }

    private func persist() {
        do { try workspace.saveCart(cart) } catch { message = error.localizedDescription }
    }

    private func add() async {
        do {
            guard let m = workspace.metadata(for: DataTransferCommands.connection(workspace)), let o = try await m.find(objectName) else {
                message = L10n.tr("Nie znaleziono obiektu \(objectName)"); return
            }
            cart.add(o)
            objectName = ""
        } catch { message = error.localizedDescription }
    }

    private func saveAs() async {
        guard let data = try? cart.encoded() else { return }
        _ = await workspace.ui?.saveFile(suggestedName: cart.name, fileExtension: "cart", data: data)
    }

    private func openFile() async {
        guard let url = await workspace.ui?.chooseFilesToOpen().first else { return }
        do { cart = try DeploymentCart.decode(Data(contentsOf: url)) } catch { message = error.localizedDescription }
    }

    private func script() async {
        do {
            let s = try await DataTransferCommands.session(workspace)
            let text = try await cart.deploymentScript(in: s) { message = L10n.tr("DDL: \($0)") }
            let d = workspace.newDocument(.sql, text: text)
            d.customTitle = cart.name
            message = ""
        } catch { message = error.localizedDescription }
    }
}

// MARK: Kopiowanie schematu (SD-COPY-001)

struct SchemaCopyView: View {
    let workspace: Workspace
    @State private var sourceOwner = ""
    @State private var targetID: UUID?
    @State private var targetOwner = ""
    @State private var options = SchemaCopy.Options()
    @State private var log: [String] = []
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Form {
                TextField(L10n.tr("Schemat źródłowy"), text: $sourceOwner)
                Picker(L10n.tr("Połączenie docelowe"), selection: $targetID) {
                    ForEach(workspace.connections.connections) { Text($0.displayName).tag(UUID?.some($0.id)) }
                }
                TextField(L10n.tr("Schemat docelowy"), text: $targetOwner)
                Toggle(L10n.tr("Kopiuj dane"), isOn: $options.copyData).toggleStyle(.checkbox)
                TextField(L10n.tr("Warunek WHERE danych"), text: $options.whereClause).disabled(!options.copyData)
                Toggle(L10n.tr("Zastąp istniejące obiekty (DROP)"), isOn: $options.replaceExisting).toggleStyle(.checkbox)
            }
            Text(L10n.tr("Typy obiektów (puste — wszystkie)")).font(.uiSecondary)
            ObjectTypesPicker(types: $options.types)
            List(log, id: \.self) { Text($0).font(.code) }
            HStack {
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(L10n.tr("Kopiuj")) { Task { await copy() } }.disabled(busy || targetID == nil || targetOwner.isEmpty || sourceOwner.isEmpty)
            }
        }
        .padding(12)
        .task {
            sourceOwner = workspace.sessions.connectedSchema(DataTransferCommands.connection(workspace)) ?? ""
            targetID = workspace.sessions.mainConnectionID
        }
    }

    private func copy() async {
        busy = true
        defer { busy = false }
        log = []
        do {
            try await workspace.guardModification(["create table \(targetOwner).x (x number)"], connectionID: targetID)
            let src = try await DataTransferCommands.session(workspace)
            let dst = try await Stage7ToolWindows.session(workspace, targetID, purpose: "copy")
            let r = try await SchemaCopy.run(sourceOwner: sourceOwner.uppercased(), source: src, targetOwner: targetOwner.uppercased(), target: dst, options: options) { log.append($0) }
            log.append(L10n.tr("Utworzono: \(r.created.count), pominięto: \(r.skipped.count), wierszy: \(r.rows), błędy: \(r.errors.count)"))
            log += r.skipped.map { L10n.tr("pominięto (istnieje): \($0)") } + r.errors
        } catch { log.append(error.localizedDescription) }
    }
}

// MARK: Kreator importu (SD-IMP-001)

struct ImportWizardView: View {
    let workspace: Workspace
    @State private var fileURL: URL?
    @State private var fileData = Data()
    @State private var state = ImportWizardState()
    @State private var source: ImportSourceData?
    @State private var sheets: [String] = []
    @State private var profileName = ""
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        HSplitView {
            Form {
                Section(L10n.tr("Źródło")) {
                    HStack {
                        Text(fileURL?.lastPathComponent ?? L10n.tr("(brak pliku)")).lineLimit(1)
                        Spacer()
                        Button(L10n.tr("Wybierz plik…")) { Task { await choose() } }
                    }
                    Picker(L10n.tr("Rodzaj"), selection: $state.source) {
                        Text(L10n.tr("Rozdzielany (CSV)")).tag(ImportWizardState.SourceKind.delimited)
                        Text(L10n.tr("Stała szerokość")).tag(ImportWizardState.SourceKind.fixedWidth)
                        Text("Excel (XLSX)").tag(ImportWizardState.SourceKind.excel)
                    }
                    if state.source != .excel {
                        Picker(L10n.tr("Kodowanie"), selection: $state.encoding) { ForEach(ImportWizard.encodings, id: \.self) { Text($0).tag($0) } }
                    }
                    if state.source == .delimited {
                        TextField(L10n.tr("Separator"), text: $state.text.delimiter)
                        TextField(L10n.tr("Cudzysłów"), text: $state.text.quote)
                        Toggle(L10n.tr("Nagłówek w pierwszym wierszu"), isOn: $state.text.header)
                    } else {
                        Toggle(L10n.tr("Nagłówek w pierwszym wierszu"), isOn: $state.header)
                    }
                    if state.source == .fixedWidth {
                        TextField(L10n.tr("Początki kolumn (np. 0,4,14)"), text: Binding(get: { state.fixedStarts.map(String.init).joined(separator: ",") },
                                                                                        set: { state.fixedStarts = $0.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) } }))
                    }
                    if state.source == .excel, !sheets.isEmpty {
                        Picker(L10n.tr("Arkusz"), selection: $state.sheet) { ForEach(Array(sheets.enumerated()), id: \.offset) { i, s in Text(s).tag(i) } }
                    }
                }
                Section(L10n.tr("Cel")) {
                    TextField(L10n.tr("Schemat"), text: $state.owner)
                    TextField(L10n.tr("Tabela"), text: $state.table)
                    Toggle(L10n.tr("Nowa tabela (typy z danych)"), isOn: $state.createTable)
                    Picker(L10n.tr("Przed importem"), selection: $state.clear) {
                        Text(L10n.tr("nic")).tag(ImportTarget.Clear.none)
                        Text("DELETE").tag(ImportTarget.Clear.delete)
                        Text("TRUNCATE").tag(ImportTarget.Clear.truncate)
                    }
                    Picker(L10n.tr("Duplikaty klucza"), selection: $state.duplicates) {
                        Text(L10n.tr("błąd")).tag(ImportTarget.Duplicates.error)
                        Text(L10n.tr("pomiń")).tag(ImportTarget.Duplicates.ignore)
                        Text(L10n.tr("nadpisz")).tag(ImportTarget.Duplicates.overwrite)
                    }
                    Stepper(L10n.tr("COMMIT co \(state.commitEvery)"), value: $state.commitEvery, in: 0...100_000, step: 500)
                }
                Section(L10n.tr("Profil")) {
                    HStack {
                        TextField(L10n.tr("Nazwa profilu"), text: $profileName)
                        Button(L10n.tr("Zapisz")) { do { try ImportProfileStore.save(state, name: profileName, in: workspace.dataDirectory); message = L10n.tr("Zapisano profil") } catch { message = error.localizedDescription } }
                            .disabled(profileName.isEmpty)
                    }
                    Menu(L10n.tr("Wczytaj profil")) {
                        ForEach(ImportProfileStore.names(in: workspace.dataDirectory), id: \.self) { n in
                            Button(n) { if let s = try? ImportProfileStore.load(n, in: workspace.dataDirectory) { state = s; profileName = n; reload() } }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Podgląd")).font(.uiHeadline)
                if let s = source {
                    SimpleGridView(columns: s.fieldNames, rows: Array(s.rows.prefix(50))).frame(minHeight: 160)
                    Text(L10n.tr("Wierszy: \(s.rows.count), kodowanie: \(s.encoding)")).font(.uiSecondary).foregroundStyle(.secondary)
                }
                HStack {
                    Text(L10n.tr("Mapowanie")).font(.uiHeadline)
                    Spacer()
                    Button(L10n.tr("Mapuj automatycznie")) { Task { await mapAutomatically() } }.disabled(source == nil || state.table.isEmpty)
                }
                List {
                    ForEach($state.mappings) { $m in
                        HStack {
                            Text(m.column).frame(width: 160, alignment: .leading)
                            Picker("", selection: $m.field) {
                                Text(L10n.tr("(pomiń)")).tag(Int?.none)
                                ForEach(Array((source?.fieldNames ?? []).enumerated()), id: \.offset) { i, n in Text(n).tag(Int?.some(i)) }
                            }
                            .labelsHidden()
                            Picker("", selection: $m.type) {
                                Text(L10n.tr("tekst")).tag(ImportFieldType.string)
                                Text(L10n.tr("liczba")).tag(ImportFieldType.number)
                                Text(L10n.tr("data")).tag(ImportFieldType.date)
                            }
                            .labelsHidden().frame(width: 90)
                            if m.type == .date { TextField("", text: $m.dateFormat).frame(width: 170) }
                        }
                    }
                }
                HStack {
                    Text(message).font(.uiSecondary).foregroundStyle(.secondary)
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    Button(L10n.tr("Importuj")) { Task { await runImport() } }.disabled(busy || source == nil || state.mappings.isEmpty)
                }
            }
            .padding(10)
            .frame(minWidth: 520)
        }
        .onChange(of: state.source) { reload() }
        .onChange(of: state.encoding) { reload() }
        .onChange(of: state.text) { reload() }
        .onChange(of: state.fixedStarts) { reload() }
        .onChange(of: state.sheet) { reload() }
        .onChange(of: state.header) { reload() }
        .task { state.owner = workspace.sessions.connectedSchema(DataTransferCommands.connection(workspace)) ?? "" }
    }

    private func choose() async {
        guard let url = await workspace.ui?.chooseFilesToOpen().first, let data = try? Data(contentsOf: url) else { return }
        fileURL = url
        fileData = data
        let owner = state.owner
        state = ImportWizard.suggest(fileName: url.lastPathComponent, data: data)
        state.owner = owner
        if state.source == .excel { sheets = ((try? XlsxWorkbook(data))?.sheets ?? []).map(\.name) }
        reload()
    }

    private func reload() {
        guard !fileData.isEmpty else { return }
        do { source = try ImportWizard.read(fileData, state: state); message = "" } catch { source = nil; message = error.localizedDescription }
    }

    private func mapAutomatically() async {
        guard let s = source else { return }
        do {
            let sess: (any DatabaseSession)? = state.createTable ? nil : try await DataTransferCommands.session(workspace)
            var st = state
            try await ImportWizard.prepareMappings(&st, data: s, in: sess)
            state = st
        } catch { message = error.localizedDescription }
    }

    private func runImport() async {
        guard let s = source else { return }
        busy = true
        defer { busy = false }
        do {
            try await workspace.guardModification(["insert into \(state.owner).\(state.table) values (null)"], connectionID: DataTransferCommands.connection(workspace))
            let sess = try await DataTransferCommands.session(workspace)
            let r = try await ImportWizard.execute(state, data: s, in: sess) { n in message = L10n.tr("Wierszy: \(n)") }
            message = L10n.tr("Wstawiono: \(r.inserted), zaktualizowano: \(r.updated), pominięto: \(r.skipped), błędy: \(r.errors.count)")
            if !r.errors.isEmpty { workspace.ui?.showObjectInfo(title: L10n.tr("Błędy importu"), columns: [L10n.tr("Błąd")], rows: r.errors.map { [$0] }) }
        } catch { message = error.localizedDescription }
    }
}

// MARK: Przenoszenie danych (DB-XFER-001)

struct DataTransferJobView: View {
    let workspace: Workspace
    @State private var job = DataTransferJob()
    @State private var sourceColumns: [String] = []
    @State private var name = ""
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Form {
                    Section(L10n.tr("Źródło")) {
                        connectionPicker($job.sourceConnection)
                        TextField(L10n.tr("Schemat"), text: $job.sourceOwner)
                        TextField(L10n.tr("Tabela"), text: $job.sourceTable)
                        TextField("WHERE", text: $job.whereClause)
                        TextField(L10n.tr("albo zapytanie"), text: $job.sourceQuery, axis: .vertical).lineLimit(2...5)
                    }
                }
                Form {
                    Section(L10n.tr("Cel")) {
                        connectionPicker($job.targetConnection)
                        TextField(L10n.tr("Schemat"), text: $job.targetOwner)
                        TextField(L10n.tr("Tabela"), text: $job.targetTable)
                        Picker(L10n.tr("Tryb"), selection: $job.mode) {
                            Text(L10n.tr("dopisz")).tag(DataTransferJob.Mode.append)
                            Text("TRUNCATE").tag(DataTransferJob.Mode.truncate)
                            Text("DELETE").tag(DataTransferJob.Mode.delete)
                        }
                        Stepper(L10n.tr("COMMIT co \(job.commitEvery)"), value: $job.commitEvery, in: 0...100_000, step: 500)
                        Toggle(L10n.tr("Kontynuuj po błędzie wiersza"), isOn: $job.continueOnError)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Text(L10n.tr("Mapowanie kolumn")).font(.uiHeadline)
                Spacer()
                Button(L10n.tr("Wczytaj kolumny")) { Task { await loadColumns() } }
            }
            List {
                ForEach($job.mappings) { $m in
                    HStack {
                        Text(m.target).frame(width: 180, alignment: .leading)
                        Picker("", selection: $m.source) {
                            Text(L10n.tr("(stała / pomiń)")).tag(String?.none)
                            ForEach(sourceColumns, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                        .labelsHidden()
                        TextField(L10n.tr("stała SQL"), text: $m.constant).frame(width: 180).disabled(m.source != nil)
                    }
                }
            }
            HStack {
                Text(message).font(.uiSecondary).foregroundStyle(.secondary)
                Spacer()
                TextField(L10n.tr("Nazwa definicji"), text: $name).frame(width: 180)
                Button(L10n.tr("Zapisz")) {
                    do { try DataTransferStore.save(job, name: name, in: workspace.dataDirectory); message = L10n.tr("Zapisano definicję") } catch { message = error.localizedDescription }
                }.disabled(name.isEmpty)
                Menu(L10n.tr("Wczytaj")) {
                    ForEach(DataTransferStore.names(in: workspace.dataDirectory), id: \.self) { n in
                        Button(n) { if let j = try? DataTransferStore.load(n, in: workspace.dataDirectory) { job = j; name = n } }
                    }
                }
                .fixedSize()
                if busy { ProgressView().controlSize(.small) }
                Button(L10n.tr("Przenieś")) { Task { await run() } }.disabled(busy || job.mappings.isEmpty)
            }
        }
        .padding(12)
    }

    private func connectionPicker(_ value: Binding<String>) -> some View {
        Picker(L10n.tr("Połączenie"), selection: value) {
            Text(L10n.tr("(bieżące)")).tag("")
            ForEach(workspace.connections.connections) { Text($0.displayName).tag($0.displayName) }
        }
    }

    private func loadColumns() async {
        do {
            let src = try await Stage7ToolWindows.session(workspace, workspace.connectionID(named: job.sourceConnection), purpose: "transfer-source")
            let dst = try await Stage7ToolWindows.session(workspace, workspace.connectionID(named: job.targetConnection), purpose: "transfer-target")
            sourceColumns = try await DataTransferRunner.sourceColumns(job, in: src)
            job.mappings = DataTransferRunner.defaultMappings(targetColumns: try await DataTransferRunner.targetColumns(job, in: dst), sourceColumns: sourceColumns)
            message = L10n.tr("Kolumny źródła: \(sourceColumns.count), celu: \(job.mappings.count)")
        } catch { message = error.localizedDescription }
    }

    private func run() async {
        busy = true
        defer { busy = false }
        do {
            let r = try await workspace.runDataTransfer(job) { n in message = L10n.tr("Wierszy: \(n)") }
            message = L10n.tr("Przeniesiono: \(r.inserted), błędy: \(r.errors.count)")
            if !r.errors.isEmpty { workspace.ui?.showObjectInfo(title: L10n.tr("Błędy przenoszenia"), columns: [L10n.tr("Błąd")], rows: r.errors.map { [$0] }) }
        } catch { message = error.localizedDescription }
    }
}

// MARK: Zadania lokalne (DB-TASK-001)

struct LocalTasksView: View {
    let workspace: Workspace
    @State private var selection: UUID?
    @State private var draft = LocalTasksView.empty
    @State private var message = ""

    static var empty: LocalTaskDefinition {
        LocalTaskDefinition(name: "", connection: "", action: .script(file: nil, text: "", commit: false), schedule: .daily(hour: 6, minute: 0))
    }

    private var scheduler: LocalTaskScheduler { workspace.localTasks }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                Table(scheduler.definitions, selection: $selection) {
                    TableColumn(L10n.tr("Zadanie")) { d in Text(d.name) }
                    TableColumn(L10n.tr("Harmonogram")) { d in Text(d.schedule.displayText) }
                    TableColumn(L10n.tr("Ostatnio")) { d in Text(scheduler.state[d.id]?.lastStatus ?? "—").lineLimit(1) }
                    TableColumn(L10n.tr("Następne")) { d in Text(scheduler.state[d.id]?.nextRun?.formatted(date: .abbreviated, time: .shortened) ?? "—") }
                }
                HStack {
                    Button(L10n.tr("Nowe")) { selection = nil; draft = Self.empty }
                    Button(L10n.tr("Usuń")) { if let id = selection { try? scheduler.remove(id); selection = nil } }.disabled(selection == nil)
                    Button(L10n.tr("Uruchom teraz")) {
                        if let d = scheduler.definitions.first(where: { $0.id == selection }) { scheduler.start(workspace); scheduler.run(d) }
                    }.disabled(selection == nil)
                }
            }
            .frame(minWidth: 380)
            Form {
                TextField(L10n.tr("Nazwa"), text: $draft.name)
                Picker(L10n.tr("Połączenie"), selection: $draft.connection) {
                    Text(L10n.tr("(główne)")).tag("")
                    ForEach(workspace.connections.connections) { Text($0.displayName).tag($0.displayName) }
                }
                Toggle(L10n.tr("Włączone"), isOn: $draft.enabled)
                actionEditor
                scheduleEditor
                HStack {
                    Text(message).font(.uiSecondary).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.tr("Zapisz zadanie")) {
                        do { try scheduler.upsert(draft); selection = draft.id; message = L10n.tr("Zapisano") } catch { message = error.localizedDescription }
                    }.disabled(draft.name.isEmpty)
                }
                Text(L10n.tr("Zadania działają, gdy Pelikan jest uruchomiony. Definicje zawierają tylko nazwę połączenia — hasło pochodzi z Pęku kluczy.")).font(.uiSecondary).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .frame(minWidth: 420)
        }
        .onChange(of: selection) { if let d = scheduler.definitions.first(where: { $0.id == selection }) { draft = d } }
        .task { scheduler.start(workspace) }
    }

    private enum ActionKind: String, CaseIterable { case script, export, transfer }

    private var actionKind: Binding<ActionKind> {
        Binding(get: {
            switch draft.action { case .script: .script; case .export: .export; case .transfer: .transfer }
        }, set: { k in
            switch k {
            case .script: draft.action = .script(file: nil, text: "", commit: false)
            case .export: draft.action = .export(query: "", directory: "~/Documents", fileName: "eksport-{date}.csv", format: .csv)
            case .transfer: draft.action = .transfer(name: DataTransferStore.names(in: workspace.dataDirectory).first ?? "")
            }
        })
    }

    @ViewBuilder private var actionEditor: some View {
        Picker(L10n.tr("Czynność"), selection: actionKind) {
            Text(L10n.tr("Skrypt SQL")).tag(ActionKind.script)
            Text(L10n.tr("Eksport zapytania")).tag(ActionKind.export)
            Text(L10n.tr("Przeniesienie danych")).tag(ActionKind.transfer)
        }
        switch draft.action {
        case .script(let file, let text, let commit):
            TextField(L10n.tr("Plik skryptu (puste — tekst poniżej)"), text: Binding(get: { file ?? "" }, set: { draft.action = .script(file: $0.isEmpty ? nil : $0, text: text, commit: commit) }))
            TextField(L10n.tr("Skrypt"), text: Binding(get: { text }, set: { draft.action = .script(file: file, text: $0, commit: commit) }), axis: .vertical).lineLimit(3...8)
                .font(.code)
            Toggle(L10n.tr("Zatwierdź (COMMIT) na końcu"), isOn: Binding(get: { commit }, set: { draft.action = .script(file: file, text: text, commit: $0) }))
        case .export(let query, let directory, let fileName, let format):
            TextField(L10n.tr("Zapytanie"), text: Binding(get: { query }, set: { draft.action = .export(query: $0, directory: directory, fileName: fileName, format: format) }), axis: .vertical).lineLimit(2...6)
            TextField(L10n.tr("Katalog"), text: Binding(get: { directory }, set: { draft.action = .export(query: query, directory: $0, fileName: fileName, format: format) }))
            TextField(L10n.tr("Plik ({date}, {time})"), text: Binding(get: { fileName }, set: { draft.action = .export(query: query, directory: directory, fileName: $0, format: format) }))
            Picker(L10n.tr("Format"), selection: Binding(get: { format }, set: { draft.action = .export(query: query, directory: directory, fileName: fileName, format: $0) })) {
                ForEach([ExportFormat.csv, .tsv, .html, .xml, .sql, .xlsx], id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
            }
        case .transfer(let name):
            Picker(L10n.tr("Definicja"), selection: Binding(get: { name }, set: { draft.action = .transfer(name: $0) })) {
                ForEach(DataTransferStore.names(in: workspace.dataDirectory), id: \.self) { Text($0).tag($0) }
            }
        }
    }

    private enum ScheduleKind: String { case interval, daily, weekly }

    @ViewBuilder private var scheduleEditor: some View {
        let kind = Binding<ScheduleKind>(get: {
            switch draft.schedule { case .interval: .interval; case .daily: .daily; case .weekly: .weekly }
        }, set: { k in
            switch k {
            case .interval: draft.schedule = .interval(minutes: 60)
            case .daily: draft.schedule = .daily(hour: 6, minute: 0)
            case .weekly: draft.schedule = .weekly(weekdays: [2], hour: 6, minute: 0)
            }
        })
        Picker(L10n.tr("Harmonogram"), selection: kind) {
            Text(L10n.tr("co n minut")).tag(ScheduleKind.interval)
            Text(L10n.tr("codziennie")).tag(ScheduleKind.daily)
            Text(L10n.tr("w dni tygodnia")).tag(ScheduleKind.weekly)
        }
        switch draft.schedule {
        case .interval(let m):
            Stepper(L10n.tr("co \(m) min"), value: Binding(get: { m }, set: { draft.schedule = .interval(minutes: $0) }), in: 1...10_080)
        case .daily(let h, let m):
            timeFields(h, m) { draft.schedule = .daily(hour: $0, minute: $1) }
        case .weekly(let days, let h, let m):
            HStack {
                ForEach(1...7, id: \.self) { d in
                    Toggle(Calendar.current.shortWeekdaySymbols[d - 1], isOn: Binding(get: { days.contains(d) }, set: { on in
                        let nd = on ? (days + [d]).sorted() : days.filter { $0 != d }
                        draft.schedule = .weekly(weekdays: nd, hour: h, minute: m)
                    })).toggleStyle(.checkbox)
                }
            }
            timeFields(h, m) { draft.schedule = .weekly(weekdays: days, hour: $0, minute: $1) }
        }
    }

    private func timeFields(_ h: Int, _ m: Int, _ set: @escaping (Int, Int) -> Void) -> some View {
        HStack {
            Stepper(L10n.tr("godzina \(h)"), value: Binding(get: { h }, set: { set($0, m) }), in: 0...23)
            Stepper(L10n.tr("minuta \(m)"), value: Binding(get: { m }, set: { set(h, $0) }), in: 0...59, step: 5)
        }
    }
}
