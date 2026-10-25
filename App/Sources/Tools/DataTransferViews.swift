import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI
import UniformTypeIdentifiers

// Okna narzędzi danych (PD-TOOL-003…013): eksport/import tabel, import tekstu i Excela, generator danych,
// porównanie danych. Logika w PelikanWorkspace (TableTransfer, DataPump, TextImport, DataGenerator, TableDataCompare).

/// Lista tabel schematu z zaznaczaniem.
struct TablePicker: View {
    let tables: [String]
    @Binding var selected: Set<String>
    @State private var filter = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(L10n.tr("Filtr nazw"), text: $filter).textFieldStyle(.roundedBorder)
                Button(L10n.tr("Wszystkie")) { selected.formUnion(visible) }
                Button(L10n.tr("Żadne")) { selected.subtract(visible) }
            }
            List(visible, id: \.self) { t in
                Toggle(t, isOn: Binding(get: { selected.contains(t) }, set: { if $0 { selected.insert(t) } else { selected.remove(t) } }))
                    .toggleStyle(.checkbox)
            }
            Text(L10n.tr("Zaznaczone: \(selected.count) z \(tables.count)")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var visible: [String] { filter.isEmpty ? tables : tables.filter { $0.localizedCaseInsensitiveContains(filter) } }
}

@MainActor
enum DataTransferUI {
    static func session(_ ws: Workspace) async throws -> any DatabaseSession { try await DataTransferCommands.session(ws) }

    static func schema(_ ws: Workspace) -> String { ws.sessions.connectedSchema(DataTransferCommands.connection(ws)) ?? "" }

    /// Zapis przez panel; nil — anulowano, błąd zapisu jest zgłaszany.
    static func save(_ data: Data, name: String, types: [UTType]) throws -> URL? {
        let p = NSSavePanel()
        p.nameFieldStringValue = name
        p.allowedContentTypes = types
        guard p.runModal() == .OK, let url = p.url else { return nil }
        try data.write(to: url)
        return url
    }

    static func open(types: [UTType]) -> URL? {
        let p = NSOpenPanel()
        p.allowedContentTypes = types
        p.allowsMultipleSelection = false
        return p.runModal() == .OK ? p.url : nil
    }

    static func sqlWindow(_ ws: Workspace, _ text: String, connection: UUID? = nil) {
        let d = ws.newDocument(.sql, text: text)
        d.connectionID = connection ?? DataTransferCommands.connection(ws)
    }

    static func summary(_ r: ImportResult) -> String {
        var s = L10n.tr("Wstawiono: \(r.inserted), zaktualizowano: \(r.updated), usunięto: \(r.deleted), pominięto: \(r.skipped), błędy: \(r.errors.count)")
        if !r.errors.isEmpty { s += "\n" + r.errors.prefix(20).joined(separator: "\n") }
        return s
    }

    /// Potwierdzenie zmian na połączeniu (produkcja: pytanie; tylko do odczytu: odmowa).
    static func guardChanges(_ ws: Workspace, connection: UUID?) async throws {
        try await ws.guardModification(["insert into x values (1)"], connectionID: connection ?? DataTransferCommands.connection(ws))
    }
}

// MARK: Eksport tabel

struct ExportTablesView: View {
    enum Method: String, CaseIterable { case sql, native, dataPump }
    let workspace: Workspace
    @State private var owner = ""
    @State private var tables: [String] = []
    @State private var selected: Set<String> = []
    @State private var method = Method.sql
    @State private var options = TableExportOptions()
    @State private var dumpFile = "pelikan.dmp"
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(L10n.tr("Schemat"), text: $owner).frame(maxWidth: 220).textFieldStyle(.roundedBorder).onSubmit { Task { await load() } }
                Button(L10n.tr("Wczytaj")) { Task { await load() } }
                Spacer()
                Picker(L10n.tr("Metoda"), selection: $method) {
                    Text("SQL Inserts").tag(Method.sql)
                    Text(L10n.tr("Format Pelikana")).tag(Method.native)
                    Text("Data Pump").tag(Method.dataPump)
                }
                .frame(maxWidth: 320)
            }
            HSplitView {
                TablePicker(tables: tables, selected: $selected).frame(minWidth: 260, maxHeight: .infinity, alignment: .top)
                Form {
                    switch method {
                    case .sql:
                        Toggle("DROP", isOn: $options.drop)
                        Toggle("CREATE", isOn: $options.create)
                        Toggle("TRUNCATE", isOn: $options.truncate)
                        Toggle("DELETE", isOn: $options.delete)
                        Toggle(L10n.tr("Wyłącz wyzwalacze"), isOn: $options.disableTriggers)
                        Toggle(L10n.tr("Wyłącz klucze obce"), isOn: $options.disableForeignKeys)
                        Toggle(L10n.tr("Parametry składowania"), isOn: $options.includeStorage)
                        Toggle(L10n.tr("Uprawnienia"), isOn: $options.includePrivileges)
                        Toggle(L10n.tr("LOB-y jako literały"), isOn: $options.includeLOBs)
                        Stepper(L10n.tr("COMMIT co \(options.commitEvery) wierszy"), value: $options.commitEvery, in: 0...100_000, step: 100)
                        TextField(L10n.tr("WHERE (dla wszystkich tabel)"), text: $options.whereClause)
                    case .native:
                        TextField(L10n.tr("WHERE (dla wszystkich tabel)"), text: $options.whereClause)
                        Text(L10n.tr("Opcje tworzenia i czyszczenia tabel wybiera się przy imporcie.")).font(.caption).foregroundStyle(.secondary)
                    case .dataPump:
                        TextField(L10n.tr("Plik zrzutu w DATA_PUMP_DIR"), text: $dumpFile)
                        Text(L10n.tr("Bez zaznaczonych tabel — cały schemat. Plik powstaje na serwerze bazy.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 300, maxHeight: .infinity, alignment: .top)
            }
            HStack {
                ScrollView { Text(message).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 90)
                Button(L10n.tr("Eksportuj…")) { Task { await export() } }.disabled(busy || (selected.isEmpty && method != .dataPump))
            }
        }
        .padding(12)
        .frame(minWidth: 720, minHeight: 560)
        .task { owner = DataTransferUI.schema(workspace); await load() }
    }

    private func load() async {
        do {
            tables = try await TableTransfer.tables(owner: owner.uppercased(), in: try await DataTransferUI.session(workspace))
            selected = []
            message = L10n.tr("Tabele: \(tables.count)")
        } catch { message = error.localizedDescription }
    }

    private func export() async {
        busy = true
        defer { busy = false }
        do {
            let s = try await DataTransferUI.session(workspace)
            let o = owner.uppercased()
            switch method {
            case .sql:
                let text = try await TableTransfer.sqlInserts(Array(selected), owner: o, options: options, in: s) { t in message = L10n.tr("Eksport \(t)…") }
                message = try DataTransferUI.save(Data(text.utf8), name: "\(o.lowercased()).sql", types: [.plainText]).map { L10n.tr("Zapisano \($0.lastPathComponent)") } ?? ""
            case .native:
                let data = try await TableTransfer.exportNative(Array(selected), owner: o, whereClause: options.whereClause, in: s) { t in message = L10n.tr("Eksport \(t)…") }
                message = try DataTransferUI.save(data, name: "\(o.lowercased()).pdt", types: [.data]).map { L10n.tr("Zapisano \($0.lastPathComponent)") } ?? ""
            case .dataPump:
                message = L10n.tr("Data Pump — eksport w toku…")
                let r = try await DataPump.export(schema: o, tables: selected.isEmpty ? nil : Array(selected), dumpFile: dumpFile, in: s)
                message = "\(r.state)\n\(r.log)"
            }
        } catch { message = error.localizedDescription }
    }
}

// MARK: Import tabel

struct ImportTablesView: View {
    enum Method: String, CaseIterable { case sql, native, dataPump }
    let workspace: Workspace
    @State private var method = Method.native
    @State private var file: PelikanTableFile?
    @State private var selected: Set<String> = []
    @State private var owner = ""
    @State private var options = TableImportOptions()
    @State private var dumpFile = "pelikan.dmp"
    @State private var fromSchema = ""
    @State private var dumpTables = ""
    @State private var tableExists = "APPEND"
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L10n.tr("Metoda"), selection: $method) {
                Text("SQL Inserts").tag(Method.sql)
                Text(L10n.tr("Format Pelikana")).tag(Method.native)
                Text("Data Pump").tag(Method.dataPump)
            }
            .pickerStyle(.segmented)
            switch method {
            case .sql:
                Text(L10n.tr("Skrypt wykonuje się w nowym oknie poleceń połączenia; błędy zostają w konsoli okna.")).foregroundStyle(.secondary)
                Button(L10n.tr("Wybierz skrypt i importuj…")) { Task { await importSQL() } }.disabled(busy)
            case .native:
                HStack {
                    Button(L10n.tr("Otwórz plik…")) { openNative() }
                    TextField(L10n.tr("Schemat docelowy"), text: $owner).frame(maxWidth: 220).textFieldStyle(.roundedBorder)
                }
                HSplitView {
                    TablePicker(tables: file?.tables.map(\.name) ?? [], selected: $selected).frame(minWidth: 260)
                    Form {
                        Toggle(L10n.tr("Utwórz brakujące tabele"), isOn: $options.create)
                        Toggle("TRUNCATE", isOn: $options.truncate)
                        Toggle("DELETE", isOn: $options.delete)
                        Toggle(L10n.tr("Wyłącz wyzwalacze"), isOn: $options.disableTriggers)
                        Toggle(L10n.tr("Wyłącz klucze obce"), isOn: $options.disableForeignKeys)
                        Stepper(L10n.tr("COMMIT co \(options.commitEvery) wierszy"), value: $options.commitEvery, in: 0...100_000, step: 100)
                    }
                    .frame(minWidth: 280)
                }
                Button(L10n.tr("Importuj")) { Task { await importNative() } }.disabled(busy || selected.isEmpty)
            case .dataPump:
                Form {
                    TextField(L10n.tr("Plik zrzutu w DATA_PUMP_DIR"), text: $dumpFile)
                    TextField(L10n.tr("Schemat w zrzucie"), text: $fromSchema)
                    TextField(L10n.tr("Schemat docelowy"), text: $owner)
                    TextField(L10n.tr("Tabele (po przecinku; puste — wszystkie)"), text: $dumpTables)
                    Picker(L10n.tr("Istniejące tabele"), selection: $tableExists) {
                        ForEach(["SKIP", "APPEND", "TRUNCATE", "REPLACE"], id: \.self) { Text($0).tag($0) }
                    }
                }
                Button(L10n.tr("Importuj")) { Task { await importDump() } }.disabled(busy || dumpFile.isEmpty)
            }
            ScrollView { Text(message).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .padding(12)
        .frame(minWidth: 680, minHeight: 520)
        .task { owner = DataTransferUI.schema(workspace); fromSchema = owner }
    }

    private func importSQL() async {
        guard let url = DataTransferUI.open(types: [.plainText, .data]), let conn = DataTransferCommands.connection(workspace) else { return }
        busy = true
        defer { busy = false }
        do {
            let data = try Data(contentsOf: url)
            let (_, errors) = try await TableTransfer.importSQLScript(TextImport.decode(data).text, baseDirectory: url.deletingLastPathComponent(),
                                                                      connectionID: conn, in: workspace)
            message = L10n.tr("Skrypt wykonany; błędy: \(errors)")
        } catch { message = error.localizedDescription }
    }

    private func openNative() {
        guard let url = DataTransferUI.open(types: [.data]) else { return }
        do {
            file = try TableTransfer.unpackNative(Data(contentsOf: url))
            selected = Set(file?.tables.map(\.name) ?? [])
            message = L10n.tr("Tabele w pliku: \(file?.tables.count ?? 0)")
        } catch { message = error.localizedDescription }
    }

    private func importNative() async {
        guard let file else { return }
        busy = true
        defer { busy = false }
        do {
            try await DataTransferUI.guardChanges(workspace, connection: nil)
            let r = try await TableTransfer.importNative(file, tables: selected, intoOwner: owner.uppercased(), options: options,
                                                         in: try await DataTransferUI.session(workspace)) { t in message = L10n.tr("Import \(t)…") }
            message = DataTransferUI.summary(r)
        } catch { message = error.localizedDescription }
    }

    private func importDump() async {
        busy = true
        defer { busy = false }
        do {
            try await DataTransferUI.guardChanges(workspace, connection: nil)
            message = L10n.tr("Data Pump — import w toku…")
            let list = dumpTables.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
            let r = try await DataPump.importDump(dumpFile: dumpFile, tables: list.isEmpty ? nil : list, fromSchema: fromSchema, toSchema: owner,
                                                  tableExists: tableExists, in: try await DataTransferUI.session(workspace))
            message = "\(r.state)\n\(r.log)"
        } catch { message = error.localizedDescription }
    }
}

// MARK: Import tekstu i Excela

struct ImporterView: View {
    let workspace: Workspace
    let excel: Bool
    @State private var text = ""
    @State private var format = TextFormat()
    @State private var workbook: XlsxWorkbook?
    @State private var sheet = 0
    @State private var headerLine = 1
    @State private var lastLine = 0
    @State private var header: [String] = []
    @State private var rows: [[String]] = []
    @State private var owner = ""
    @State private var table = ""
    @State private var target: ImportTarget?
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(excel ? L10n.tr("Otwórz plik xlsx…") : L10n.tr("Otwórz plik…")) { openFile() }
                Button(L10n.tr("Wklej ze schowka")) { paste() }
                Spacer()
                if excel, let wb = workbook {
                    Picker(L10n.tr("Arkusz"), selection: $sheet) { ForEach(wb.sheets.indices, id: \.self) { Text(wb.sheets[$0].name).tag($0) } }
                        .frame(maxWidth: 220)
                        .onChange(of: sheet) { reparse() }
                }
            }
            formatControls
            Table(rows.prefix(100).indices.map { PreviewRow(id: $0, values: rows[$0]) }) {
                TableColumnForEach(header.indices.map { $0 }, id: \.self) { i in
                    TableColumn(header[i]) { (r: PreviewRow) in Text(i < r.values.count ? r.values[i] : "").lineLimit(1) }
                }
            }
            .frame(minHeight: 140)
            HStack {
                TextField(L10n.tr("Schemat"), text: $owner).frame(maxWidth: 160).textFieldStyle(.roundedBorder)
                TextField(L10n.tr("Tabela docelowa"), text: $table).frame(maxWidth: 220).textFieldStyle(.roundedBorder)
                Button(L10n.tr("Mapuj kolumny")) { Task { await loadMapping() } }.disabled(table.isEmpty || header.isEmpty)
                Button(L10n.tr("SQL tworzenia tabeli")) { createTable() }.disabled(table.isEmpty || header.isEmpty)
            }
            if target != nil { mappingEditor }
            HStack {
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                Spacer()
                Button(L10n.tr("Do skryptu")) { if let t = target { DataTransferUI.sqlWindow(workspace, TextImport.script(rows, fieldNames: header, target: t)) } }
                    .disabled(target == nil)
                Button(L10n.tr("Importuj")) { Task { await runImport() } }.disabled(target == nil || busy)
            }
        }
        .padding(12)
        .frame(minWidth: 860, minHeight: 640)
        .task { owner = DataTransferUI.schema(workspace) }
    }

    @ViewBuilder private var formatControls: some View {
        HStack {
            if excel {
                Stepper(L10n.tr("Linia nagłówka: \(headerLine)"), value: $headerLine, in: 0...1000).onChange(of: headerLine) { reparse() }
                Stepper(L10n.tr("Ostatnia linia: \(lastLine == 0 ? L10n.tr("koniec") : String(lastLine))"), value: $lastLine, in: 0...1_000_000).onChange(of: lastLine) { reparse() }
            } else {
                Picker(L10n.tr("Separator"), selection: $format.delimiter) {
                    Text(",").tag(","); Text(";").tag(";"); Text(L10n.tr("tabulator")).tag("\t"); Text("|").tag("|")
                }
                .frame(maxWidth: 200)
                Picker(L10n.tr("Cudzysłów"), selection: $format.quote) { Text("\"").tag("\""); Text("'").tag("'"); Text(L10n.tr("brak")).tag("") }
                    .frame(maxWidth: 180)
                Toggle(L10n.tr("Nagłówek"), isOn: $format.header).toggleStyle(.checkbox)
                TextField(L10n.tr("Komentarz"), text: $format.commentPrefix).frame(width: 70)
                Stepper(L10n.tr("Od \(format.firstLine)"), value: $format.firstLine, in: 0...1_000_000).fixedSize()
                Stepper(L10n.tr("Do \(format.lastLine)"), value: $format.lastLine, in: 0...1_000_000).fixedSize()
            }
        }
        .onChange(of: format) { reparse() }
    }

    @ViewBuilder private var mappingEditor: some View {
        let binding = Binding(get: { target! }, set: { target = $0 })
        VStack(alignment: .leading, spacing: 4) {
            List {
                ForEach(binding.mappings) { $m in
                    HStack {
                        Text(m.column).frame(width: 160, alignment: .leading)
                        Picker("", selection: $m.field) {
                            Text(L10n.tr("(pomiń)")).tag(Int?.none)
                            ForEach(header.indices, id: \.self) { Text(header[$0]).tag(Int?.some($0)) }
                        }
                        .frame(width: 180)
                        Picker("", selection: $m.type) {
                            Text(L10n.tr("tekst")).tag(ImportFieldType.string); Text(L10n.tr("liczba")).tag(ImportFieldType.number); Text(L10n.tr("data")).tag(ImportFieldType.date)
                        }
                        .frame(width: 110)
                        if m.type == .date { TextField(L10n.tr("Format daty"), text: $m.dateFormat).frame(width: 170) }
                        TextField(L10n.tr("Funkcja, np. upper(#)"), text: $m.function)
                    }
                }
            }
            .frame(minHeight: 140)
            HStack {
                Picker(L10n.tr("Przed importem"), selection: binding.clear) {
                    Text(L10n.tr("nic")).tag(ImportTarget.Clear.none); Text("DELETE").tag(ImportTarget.Clear.delete); Text("TRUNCATE").tag(ImportTarget.Clear.truncate)
                }
                .frame(maxWidth: 240)
                Picker(L10n.tr("Duplikaty klucza"), selection: binding.duplicates) {
                    Text(L10n.tr("błąd")).tag(ImportTarget.Duplicates.error); Text(L10n.tr("pomiń")).tag(ImportTarget.Duplicates.ignore); Text(L10n.tr("nadpisz")).tag(ImportTarget.Duplicates.overwrite)
                }
                .frame(maxWidth: 260)
                Stepper(L10n.tr("COMMIT co \(target!.commitEvery)"), value: binding.commitEvery, in: 0...100_000, step: 100).fixedSize()
            }
            TextField(L10n.tr("Filtr SQL, np. :KWOTA > 0"), text: binding.filter).textFieldStyle(.roundedBorder)
            Text(L10n.tr("Pola w filtrze: \(header.indices.map { ":" + TextImport.bindName(header[$0], index: $0) }.joined(separator: ", "))"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func openFile() {
        guard let url = DataTransferUI.open(types: excel ? [UTType(filenameExtension: "xlsx") ?? .data] : [.plainText, .commaSeparatedText, .tabSeparatedText, .data]) else { return }
        do {
            let data = try Data(contentsOf: url)
            if excel {
                workbook = try XlsxWorkbook(data)
                sheet = 0
                table = url.deletingPathExtension().lastPathComponent.uppercased()
            } else {
                text = TextImport.decode(data).text
                format = TextImport.detect(String(text.prefix(200_000)))
                table = url.deletingPathExtension().lastPathComponent.uppercased()
            }
            reparse()
        } catch { message = error.localizedDescription }
    }

    /// Wklejenie z Excela (tekst z tabulatorami) albo dowolnego tekstu rozdzielanego.
    private func paste() {
        guard let s = NSPasteboard.general.string(forType: .string) else { return }
        workbook = nil
        text = s
        format = TextImport.detect(s)
        reparse()
    }

    private func reparse() {
        if excel, let wb = workbook {
            do {
                var all = try wb.rows(sheet: sheet)
                if lastLine > 0, lastLine < all.count { all = Array(all.prefix(lastLine)) }
                if headerLine > 0, headerLine <= all.count {
                    header = all[headerLine - 1].enumerated().map { $1.isEmpty ? "POLE\($0 + 1)" : $1 }
                    rows = Array(all.dropFirst(headerLine))
                } else {
                    rows = all
                    header = (0..<(all.map(\.count).max() ?? 0)).map { "POLE\($0 + 1)" }
                }
                message = L10n.tr("Wiersze: \(rows.count)")
            } catch { message = error.localizedDescription }
        } else {
            (header, rows) = TextImport.parse(text, format)
            message = L10n.tr("Wiersze: \(rows.count)")
        }
    }

    private func loadMapping() async {
        do {
            let maps = try await TextImport.defaultMappings(owner: owner, table: table, fieldNames: header, in: try await DataTransferUI.session(workspace))
            guard !maps.isEmpty else { message = L10n.tr("Brak tabeli \(owner).\(table)"); return }
            target = ImportTarget(owner: owner.uppercased(), table: table.uppercased(), mappings: maps)
        } catch { message = error.localizedDescription }
    }

    private func createTable() {
        let (sql, maps) = TextImport.createTable(owner: owner.uppercased(), table: table.uppercased(), fieldNames: header, rows: Array(rows.prefix(1000)))
        DataTransferUI.sqlWindow(workspace, sql + ";")
        target = ImportTarget(owner: owner.uppercased(), table: table.uppercased(), mappings: maps)
        message = L10n.tr("Wykonaj CREATE TABLE w oknie SQL, potem Importuj.")
    }

    private func runImport() async {
        guard let t = target else { return }
        busy = true
        defer { busy = false }
        do {
            try await DataTransferUI.guardChanges(workspace, connection: nil)
            let r = try await TextImport.run(rows, fieldNames: header, target: t, in: try await DataTransferUI.session(workspace)) { n in message = L10n.tr("Zaimportowano \(n)…") }
            message = DataTransferUI.summary(r)
        } catch { message = error.localizedDescription }
    }
}

struct PreviewRow: Identifiable {
    let id: Int
    let values: [String]
}

// MARK: Generator danych

struct DataGeneratorView: View {
    let workspace: Workspace
    @State private var owner = ""
    @State private var newTable = ""
    @State private var tables: [GeneratorTable] = []
    @State private var current: String?
    @State private var preview: [[String: String]] = []
    @State private var commitEvery = 100
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(L10n.tr("Schemat"), text: $owner).frame(maxWidth: 160).textFieldStyle(.roundedBorder)
                TextField(L10n.tr("Tabela"), text: $newTable).frame(maxWidth: 220).textFieldStyle(.roundedBorder).onSubmit { Task { await add() } }
                Button(L10n.tr("Dodaj tabelę")) { Task { await add() } }.disabled(newTable.isEmpty)
                Spacer()
                Stepper(L10n.tr("COMMIT co \(commitEvery)"), value: $commitEvery, in: 0...100_000, step: 100).fixedSize()
            }
            HSplitView {
                List(selection: $current) {
                    ForEach($tables) { $t in
                        VStack(alignment: .leading) {
                            Text(t.name).bold()
                            HStack {
                                Stepper(L10n.tr("od \(t.minRecords)"), value: $t.minRecords, in: 0...1_000_000).fixedSize()
                                Stepper(L10n.tr("do \(t.maxRecords)"), value: $t.maxRecords, in: 0...1_000_000).fixedSize()
                            }
                            Picker(L10n.tr("Nadrzędna"), selection: $t.parent) {
                                Text(L10n.tr("(brak)")).tag(String?.none)
                                ForEach(tables.filter { $0.name != t.name }) { Text($0.name).tag(String?.some($0.name)) }
                            }
                        }
                        .tag(t.name)
                    }
                    .onDelete { tables.remove(atOffsets: $0) }
                }
                .frame(minWidth: 260)
                if let i = tables.firstIndex(where: { $0.name == current }) {
                    List {
                        ForEach($tables[i].fields) { $f in
                            HStack {
                                Text(f.name).frame(width: 150, alignment: .leading)
                                Text(f.type).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                                TextField(L10n.tr("Definicja"), text: $f.definition).font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                    .frame(minWidth: 420)
                } else {
                    Text(L10n.tr("Wybierz tabelę")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let t = tables.first(where: { $0.name == current }), !preview.isEmpty {
                Table(preview.indices.map { i in PreviewRow(id: i, values: t.fields.map { f in preview[i][f.name.uppercased()] ?? "" }) }) {
                    TableColumnForEach(t.fields.indices.map { $0 }, id: \.self) { i in
                        TableColumn(t.fields[i].name) { (r: PreviewRow) in Text(i < r.values.count ? r.values[i] : "").lineLimit(1) }
                    }
                }
                .frame(minHeight: 120)
            }
            HStack {
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                Spacer()
                Button(L10n.tr("Próbny przebieg")) { Task { await run(.preview) } }.disabled(tables.isEmpty || busy)
                Button(L10n.tr("Jako SQL")) { Task { await run(.script) } }.disabled(tables.isEmpty || busy)
                Button(L10n.tr("Do bazy")) { Task { await run(.database) } }.disabled(tables.isEmpty || busy)
            }
        }
        .padding(12)
        .frame(minWidth: 860, minHeight: 600)
        .task { owner = DataTransferUI.schema(workspace) }
    }

    enum Mode { case preview, script, database }

    private func add() async {
        do {
            let t = try await DataGenerator.defaultTable(owner: owner, table: newTable, in: try await DataTransferUI.session(workspace))
            guard !t.fields.isEmpty else { message = L10n.tr("Brak tabeli \(owner).\(newTable)"); return }
            tables.removeAll { $0.name == t.name }
            tables.append(t)
            current = t.name
            newTable = ""
        } catch { message = error.localizedDescription }
    }

    private func run(_ mode: Mode) async {
        busy = true
        defer { busy = false }
        do {
            let s = try await DataTransferUI.session(workspace)
            var g = DataGenerator(seed: mode == .preview ? 1 : UInt64.random(in: 1...UInt64.max), session: s)
            var defs = tables
            if mode == .preview { defs = defs.map { var t = $0; t.minRecords = min(t.minRecords, 20); t.maxRecords = min(t.maxRecords, 20); return t } }
            let data = try await g.generate(defs)
            switch mode {
            case .preview:
                preview = data[current ?? ""] ?? []
                message = L10n.tr("Podgląd: \(preview.count) rekordów")
            case .script:
                DataTransferUI.sqlWindow(workspace, DataGenerator.script(data, tables: tables, owner: owner.uppercased(), commitEvery: commitEvery))
            case .database:
                try await DataTransferUI.guardChanges(workspace, connection: nil)
                let r = try await DataGenerator.insert(data, tables: tables, owner: owner.uppercased(), commitEvery: commitEvery, in: s)
                message = DataTransferUI.summary(r)
            }
        } catch { message = error.localizedDescription }
    }
}

// MARK: Porównanie danych

struct CompareTableDataView: View {
    let workspace: Workspace
    @State private var owner = ""
    @State private var tables: [String] = []
    @State private var selected: Set<String> = []
    @State private var targetID: UUID?
    @State private var targetOwner = ""
    @State private var options = DataCompareOptions()
    @State private var diffs: [TableDataDiff] = []
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(L10n.tr("Schemat źródłowy"), text: $owner).frame(maxWidth: 180).textFieldStyle(.roundedBorder).onSubmit { Task { await load() } }
                Button(L10n.tr("Wczytaj")) { Task { await load() } }
                Spacer()
                Picker(L10n.tr("Połączenie docelowe"), selection: $targetID) {
                    ForEach(workspace.connections.connections) { Text($0.displayName).tag(UUID?.some($0.id)) }
                }
                .frame(maxWidth: 300)
                TextField(L10n.tr("Schemat docelowy"), text: $targetOwner).frame(maxWidth: 180).textFieldStyle(.roundedBorder)
            }
            HSplitView {
                TablePicker(tables: tables, selected: $selected).frame(minWidth: 260)
                VStack(alignment: .leading) {
                    // Dwa wiersze opcji — w jednym przy węższym oknie etykiety łamały się w środku słów.
                    HStack {
                        Toggle("INSERT", isOn: $options.insert)
                        Toggle("UPDATE", isOn: $options.update)
                        Toggle("DELETE", isOn: $options.delete)
                    }
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    HStack {
                        Toggle(L10n.tr("Schemat w SQL"), isOn: $options.ownerInScript).toggleStyle(.checkbox)
                        Stepper(L10n.tr("COMMIT co \(options.commitEvery)"), value: $options.commitEvery, in: 0...100_000, step: 100)
                    }
                    .fixedSize()
                    Table(diffs, columns: {
                        TableColumn(L10n.tr("Tabela"), value: \.table)
                        TableColumn(L10n.tr("Nowe")) { d in Text("\(d.inserts.count)") }.width(60)
                        TableColumn(L10n.tr("Różne")) { d in Text("\(d.updates.count)") }.width(60)
                        TableColumn(L10n.tr("Nadmiarowe")) { d in Text("\(d.deletes.count)") }.width(90)
                    })
                }
                .frame(minWidth: 380)
            }
            HStack {
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(5).textSelection(.enabled)
                Spacer()
                Button(L10n.tr("Porównaj")) { Task { await compare() } }.disabled(selected.isEmpty || targetID == nil || targetOwner.isEmpty || busy)
                Button(L10n.tr("Skrypt")) { DataTransferUI.sqlWindow(workspace, TableDataCompare.script(diffs, targetOwner: targetOwner.uppercased(), options: options), connection: targetID) }
                    .disabled(diffs.isEmpty)
                Button(L10n.tr("Aktualizuj cel")) { Task { await apply() } }.disabled(diffs.isEmpty || busy)
            }
        }
        .padding(12)
        .frame(minWidth: 860, minHeight: 540)
        .task {
            owner = DataTransferUI.schema(workspace)
            targetID = DataTransferCommands.connection(workspace)
            await load()
        }
    }

    private func load() async {
        do {
            tables = try await TableTransfer.tables(owner: owner.uppercased(), in: try await DataTransferUI.session(workspace))
            selected = []
        } catch { message = error.localizedDescription }
    }

    private func target() async throws -> any DatabaseSession {
        try await DataTransferCommands.session(workspace, connection: targetID)
    }

    private func compare() async {
        busy = true
        defer { busy = false }
        do {
            let s = try await DataTransferUI.session(workspace)
            let t = try await target()
            var out: [TableDataDiff] = []
            var errors: [String] = []
            for name in selected.sorted() {
                message = L10n.tr("Porównanie \(name)…")
                do { out.append(try await TableDataCompare.compare(table: name, sourceOwner: owner.uppercased(), source: s, targetOwner: targetOwner.uppercased(), target: t)) } catch {
                    errors.append("\(name): \(error.localizedDescription)")
                }
            }
            diffs = out.filter { !$0.isEmpty }
            message = L10n.tr("Tabele z różnicami: \(diffs.count) z \(out.count)") + (errors.isEmpty ? "" : "\n" + errors.joined(separator: "\n"))
        } catch { message = error.localizedDescription }
    }

    private func apply() async {
        busy = true
        defer { busy = false }
        do {
            try await DataTransferUI.guardChanges(workspace, connection: targetID)
            guard await workspace.ui?.ask(L10n.tr("Zaktualizować dane w \(targetOwner.uppercased())?"),
                                          message: L10n.tr("Polecenia wyrównujące zostaną wykonane i zatwierdzone w schemacie docelowym."),
                                          buttons: [L10n.tr("Aktualizuj"), L10n.tr("Anuluj")]) == 0 else { return }
            let r = try await TableDataCompare.apply(diffs, targetOwner: targetOwner.uppercased(), options: options, in: try await target())
            message = DataTransferUI.summary(r)
            diffs = []
        } catch { message = error.localizedDescription }
    }
}
