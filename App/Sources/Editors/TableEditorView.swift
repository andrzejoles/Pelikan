import AppKit
import PelikanWorkspace
import SwiftUI

/// Edytor definicji tabeli (UG 9.1): karty Ogólne, Kolumny, Klucze, Warunki, Indeksy i SQL (DDL zmian);
/// Zastosuj wykonuje DDL po potwierdzeniu strażnika, Odśwież wczytuje definicję z bazy.
struct TableEditorView: View {
    let workspace: Workspace
    let connectionID: UUID
    @State var definition: TableDefinition
    @State var original: TableDefinition?
    @State private var tab = 1
    @State private var message = ""
    @State private var running = false
    @State private var fkTable = ""

    static let typeSuggestions = ["NUMBER", "NUMBER(10)", "NUMBER(10,2)", "INTEGER", "VARCHAR2(30 CHAR)", "VARCHAR2(100 CHAR)", "VARCHAR2(4000 CHAR)",
                                  "CHAR(1 CHAR)", "DATE", "TIMESTAMP", "TIMESTAMP WITH TIME ZONE", "CLOB", "BLOB", "RAW(16)", "BOOLEAN", "JSON",
                                  "VECTOR", "BINARY_DOUBLE", "INTERVAL DAY TO SECOND"]

    private var ddl: [String] { TableDDL.statements(from: original, to: definition) }

    var body: some View {
        VStack(spacing: 0) {
            // Przełącznik segmentowy zamiast TabView: przy ośmiu kartach TabView chował je pod przyciskiem przepełnienia.
            Picker("", selection: $tab) {
                Text(L10n.tr("Ogólne")).tag(0)
                Text(L10n.tr("Kolumny")).tag(1)
                Text(L10n.tr("Klucze")).tag(2)
                Text(L10n.tr("Warunki")).tag(3)
                Text(L10n.tr("Indeksy")).tag(4)
                Text(L10n.tr("Uprawnienia")).tag(6)
                Text(L10n.tr("Partycje i wyzwalacze")).tag(7)
                Text("SQL").tag(5)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 10)
            Group {
                switch tab {
                case 0: general
                case 1: columns
                case 2: keys
                case 3: checks
                case 4: indexes
                case 6: privileges
                case 7: partitionsAndTriggers
                default: sql
                }
            }
            .padding(10)
            Divider()
            HStack {
                if running { ProgressView().controlSize(.small) }
                Text(message).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button(L10n.tr("Odśwież")) { refresh() }.disabled(original == nil || running)
                Button(L10n.tr("Zastosuj")) { apply() }.keyboardShortcut(.defaultAction).disabled(ddl.isEmpty || running)
            }
            .padding(10)
        }
        .frame(minWidth: 820, minHeight: 480)
    }

    // MARK: Karty

    private var general: some View {
        Form {
            TextField(L10n.tr("Właściciel"), text: .constant(definition.owner)).disabled(true)
            TextField(L10n.tr("Nazwa"), text: upper($definition.name))
            TextField(L10n.tr("Przestrzeń tabel"), text: upper($definition.tablespace)).disabled(definition.temporary)
            Toggle(L10n.tr("Tabela tymczasowa (GLOBAL TEMPORARY)"), isOn: $definition.temporary).disabled(original != nil)
            if definition.temporary {
                Toggle(L10n.tr("Zachowuj wiersze po zatwierdzeniu (ON COMMIT PRESERVE ROWS)"), isOn: $definition.preserveRows).disabled(original != nil)
            }
            Toggle(L10n.tr("Organizacja indeksowa (IOT)"), isOn: $definition.indexOrganized).disabled(original != nil || definition.temporary)
            TextField(L10n.tr("Komentarz"), text: $definition.comment, axis: .vertical).lineLimit(2...4)
            Toggle(L10n.tr("Archiwizacja wierszy (ROW ARCHIVAL)"), isOn: $definition.rowArchival).disabled(definition.temporary)
            TextField(L10n.tr("Adnotacje tabeli (nazwa=wartość, …; 23ai)"), text: annotations($definition.annotations))
            Section(L10n.tr("Składowanie")) {
                HStack {
                    TextField("PCTFREE", text: $definition.storage.pctFree)
                    TextField("INITRANS", text: $definition.storage.iniTrans)
                }
                HStack {
                    TextField("INITIAL", text: upper($definition.storage.initial)).disabled(original != nil && !definition.recreate)
                    TextField("NEXT", text: upper($definition.storage.next))
                }
                Toggle(L10n.tr("Logowanie zmian (LOGGING)"), isOn: $definition.storage.logging)
                Picker(L10n.tr("Kompresja"), selection: $definition.storage.compression) {
                    Text(L10n.tr("Brak")).tag(TableDefinition.Storage.Compression.none)
                    Text("BASIC").tag(TableDefinition.Storage.Compression.basic)
                    Text("ADVANCED").tag(TableDefinition.Storage.Compression.advanced)
                }
            }
            .disabled(definition.temporary || definition.external != nil || !definition.cluster.isEmpty)
            Section(L10n.tr("Organizacja")) {
                TextField(L10n.tr("Klaster"), text: upper($definition.cluster)).disabled(original != nil && !definition.recreate)
                if !definition.cluster.isEmpty {
                    TextField(L10n.tr("Kolumny klastra"), text: list($definition.clusterColumns)).disabled(original != nil && !definition.recreate)
                }
                TextField(L10n.tr("Tabela obiektowa — typ (OF …)"), text: upper($definition.objectType)).disabled(original != nil)
                Toggle(L10n.tr("Tabela zewnętrzna (ORGANIZATION EXTERNAL)"), isOn: Binding(
                    get: { definition.external != nil }, set: { definition.external = $0 ? TableDefinition.External() : nil }))
                    .disabled(original != nil)
                if definition.external != nil {
                    Picker(L10n.tr("Sterownik"), selection: Binding(get: { definition.external?.driver ?? "ORACLE_LOADER" }, set: { definition.external?.driver = $0 })) {
                        ForEach(["ORACLE_LOADER", "ORACLE_DATAPUMP", "ORACLE_BIGDATA"], id: \.self) { Text($0).tag($0) }
                    }
                    TextField(L10n.tr("Katalog (DIRECTORY)"), text: upper(Binding(get: { definition.external?.directory ?? "" }, set: { definition.external?.directory = $0 })))
                    TextField(L10n.tr("Pliki (po przecinku)"), text: list(Binding(get: { definition.external?.locations ?? [] }, set: { definition.external?.locations = $0 })))
                    TextField(L10n.tr("Parametry dostępu"), text: Binding(get: { definition.external?.accessParameters ?? "" }, set: { definition.external?.accessParameters = $0 }),
                              axis: .vertical).lineLimit(2...6).font(.system(.body, design: .monospaced))
                    TextField("REJECT LIMIT", text: upper(Binding(get: { definition.external?.rejectLimit ?? "" }, set: { definition.external?.rejectLimit = $0 })))
                }
            }
            .disabled(definition.temporary)
            if original != nil {
                Section(L10n.tr("Recreate table")) {
                    Toggle(L10n.tr("Zastosuj przez odtworzenie tabeli (kopia danych, DROP, CREATE, przeniesienie wierszy)"), isOn: $definition.recreate)
                    if definition.recreate {
                        Text(L10n.tr("Wyzwalacze, uprawnienia i klucze obce innych tabel są odtwarzane; tabela trafia do kosza (FLASHBACK TABLE … TO BEFORE DROP)."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var privileges: some View {
        VStack(alignment: .leading) {
            Table($definition.grants) {
                TableColumn(L10n.tr("Odbiorca")) { $g in TextField("", text: upper($g.grantee)) }.width(min: 140, ideal: 200)
                TableColumn(L10n.tr("Uprawnienie")) { $g in
                    Picker("", selection: $g.privilege) {
                        ForEach(["SELECT", "INSERT", "UPDATE", "DELETE", "REFERENCES", "ALTER", "INDEX", "READ", "DEBUG", "FLASHBACK"], id: \.self) { Text($0).tag($0) }
                    }.labelsHidden()
                }.width(140)
                TableColumn(L10n.tr("Z prawem nadawania")) { $g in Toggle("", isOn: $g.grantable).labelsHidden() }.width(120)
            }
            listButtons(add: { definition.grants.append(TableDefinition.Grant(grantee: "PUBLIC", privilege: "SELECT")) },
                        remove: { if !definition.grants.isEmpty { definition.grants.removeLast() } })
        }
    }

    private var partitionsAndTriggers: some View {
        Form {
            Section(L10n.tr("Partycjonowanie")) {
                if original != nil {
                    Text(definition.partitionInfo.isEmpty ? L10n.tr("Tabela nie jest partycjonowana") : L10n.tr("Partycjonowanie: \(definition.partitionInfo)"))
                        .foregroundStyle(.secondary)
                    // Partycje istniejącej tabeli (PD-OED-006): zmiana nazwy, usunięcie, nowe partycje (ADD PARTITION).
                    if let p = definition.partitioning {
                        ForEach(p.partitions.indices, id: \.self) { i in
                            HStack {
                                TextField(L10n.tr("Nazwa"), text: Binding(get: { definition.partitioning?.partitions[i].name ?? "" },
                                                                          set: { definition.partitioning?.partitions[i].name = $0.uppercased() }))
                                    .frame(width: 180)
                                if p.partitions[i].originalName != nil || p.method == .hash {
                                    Text(p.partitions[i].values).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                                } else {
                                    TextField(p.method == .range ? L10n.tr("VALUES LESS THAN") : L10n.tr("VALUES"),
                                              text: Binding(get: { definition.partitioning?.partitions[i].values ?? "" },
                                                            set: { definition.partitioning?.partitions[i].values = $0 }))
                                        .font(.system(.body, design: .monospaced))
                                }
                                Spacer()
                                Button { definition.partitioning?.partitions.remove(at: i) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless).iconLabel(L10n.tr("Usuń partycję"))
                            }
                        }
                        Button(L10n.tr("Dodaj partycję")) {
                            definition.partitioning?.partitions.append(TableDefinition.Partition(name: "P\((definition.partitioning?.partitions.count ?? 0) + 1)"))
                        }
                    }
                } else {
                    Toggle(L10n.tr("Partycjonuj tabelę"), isOn: Binding(get: { definition.partitioning != nil },
                                                                       set: { definition.partitioning = $0 ? TableDefinition.Partitioning(method: .range, columns: []) : nil }))
                    if definition.partitioning != nil {
                        Picker(L10n.tr("Metoda"), selection: Binding(get: { definition.partitioning?.method ?? .range }, set: { definition.partitioning?.method = $0 })) {
                            ForEach(TableDefinition.Partitioning.Method.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        TextField(L10n.tr("Kolumny klucza"), text: Binding(get: { definition.partitioning?.columns.joined(separator: ", ") ?? "" },
                                                                           set: { definition.partitioning?.columns = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty } }))
                        if definition.partitioning?.method == .range {
                            TextField(L10n.tr("INTERVAL (np. NUMTOYMINTERVAL(1,'MONTH'))"), text: Binding(get: { definition.partitioning?.interval ?? "" }, set: { definition.partitioning?.interval = $0 }))
                        }
                        HStack {
                            TextField(L10n.tr("Podpartycje HASH — kolumny"), text: Binding(get: { definition.partitioning?.subpartitionColumns.joined(separator: ", ") ?? "" },
                                set: { definition.partitioning?.subpartitionColumns = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty } }))
                            Stepper(L10n.tr("Liczba: \(definition.partitioning?.subpartitionCount ?? 0)"),
                                    value: Binding(get: { definition.partitioning?.subpartitionCount ?? 0 }, set: { definition.partitioning?.subpartitionCount = $0 }), in: 0...64)
                        }
                        TextField(L10n.tr("Partycje: nazwa: wartości (po jednej w linii)"), text: Binding(get: {
                            definition.partitioning?.partitions.map { $0.values.isEmpty ? $0.name : "\($0.name): \($0.values)" }.joined(separator: "\n") ?? ""
                        }, set: { text in
                            definition.partitioning?.partitions = text.split(separator: "\n").compactMap { line in
                                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                                guard let n = parts.first, !n.isEmpty else { return nil }
                                return TableDefinition.Partition(name: n.uppercased(), values: parts.count > 1 ? parts[1] : "")
                            }
                        }), axis: .vertical).lineLimit(3...8).font(.system(.body, design: .monospaced))
                    }
                }
            }
            Section(L10n.tr("Wyzwalacze")) {
                if definition.triggers.isEmpty { Text(L10n.tr("Brak wyzwalaczy")).foregroundStyle(.secondary) }
                ForEach(definition.triggers, id: \.name) { trg in
                    HStack {
                        Text(trg.name)
                        Spacer()
                        Button(trg.enabled ? L10n.tr("Wyłącz") : L10n.tr("Włącz")) {
                            Task {
                                do {
                                    // Na połączeniu edytora (jak Zastosuj), nie głównym; nazwa dokładna, bez wyszukiwania.
                                    let sql = try ObjectAdmin.setEnabled(DBObject(owner: definition.owner, name: trg.name, type: .trigger), enabled: !trg.enabled)
                                    try await workspace.guardModification([sql], connectionID: connectionID)
                                    _ = try await workspace.sessions.session(workspace.sessions.compileKey(connection: connectionID)).execute(sql)
                                    workspace.metadata(for: connectionID)?.refresh()
                                    refresh()
                                } catch CommandError.cancelledByUser {
                                    message = L10n.tr("Anulowano")
                                } catch { message = error.localizedDescription }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Adnotacje jako tekst „nazwa=wartość, nazwa2”.
    private func annotations(_ b: Binding<[TableDefinition.Annotation]>) -> Binding<String> {
        Binding(get: { b.wrappedValue.map { $0.value.isEmpty ? $0.name : "\($0.name)=\($0.value)" }.joined(separator: ", ") },
                set: { text in
                    b.wrappedValue = text.split(separator: ",").compactMap { part in
                        let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                        guard let n = kv.first, !n.isEmpty else { return nil }
                        return TableDefinition.Annotation(name: n, value: kv.count > 1 ? kv[1] : "")
                    }
                })
    }

    private var columns: some View {
        VStack(alignment: .leading) {
            Table($definition.columns) {
                TableColumn(L10n.tr("Nazwa")) { $c in TextField("", text: upper($c.name)) }.width(min: 110, ideal: 150)
                TableColumn(L10n.tr("Typ")) { $c in typeField($c.type) }.width(min: 140, ideal: 170)
                TableColumn(L10n.tr("Null")) { $c in Toggle("", isOn: $c.nullable).labelsHidden() }.width(40)
                TableColumn(L10n.tr("Domyślna")) { $c in TextField("", text: $c.defaultValue).disabled(!c.virtualExpression.isEmpty || c.identity) }
                    .width(min: 80, ideal: 110)
                TableColumn(L10n.tr("Wirtualna (wyrażenie)")) { $c in TextField("", text: $c.virtualExpression).disabled(c.originalName != nil) }
                    .width(min: 80, ideal: 120)
                TableColumn(L10n.tr("Identity")) { $c in Toggle("", isOn: $c.identity).labelsHidden().disabled(c.originalName != nil) }.width(52)
                TableColumn(L10n.tr("Niewidoczna")) { $c in Toggle("", isOn: $c.invisible).labelsHidden() }.width(70)
                TableColumn(L10n.tr("Domena")) { $c in TextField("", text: upper($c.domain)) }.width(min: 80, ideal: 110)
                TableColumn(L10n.tr("Adnotacje")) { $c in TextField("", text: annotations($c.annotations)) }.width(min: 80, ideal: 120)
                TableColumn(L10n.tr("Komentarz")) { $c in TextField("", text: $c.comment) }
            }
            listButtons(add: { definition.columns.append(TableDefinition.Column(name: "KOLUMNA\(definition.columns.count + 1)", type: "VARCHAR2(30 CHAR)")) },
                        remove: { if !definition.columns.isEmpty { definition.columns.removeLast() } })
        }
    }

    private var keys: some View {
        VStack(alignment: .leading) {
            Table($definition.keys) {
                TableColumn(L10n.tr("Nazwa")) { $k in TextField("", text: upper($k.name)) }.width(min: 120, ideal: 160)
                TableColumn(L10n.tr("Rodzaj")) { $k in
                    Picker("", selection: $k.kind) {
                        Text(L10n.tr("Główny")).tag(TableDefinition.Key.Kind.primary)
                        Text(L10n.tr("Unikalny")).tag(TableDefinition.Key.Kind.unique)
                        Text(L10n.tr("Obcy")).tag(TableDefinition.Key.Kind.foreign)
                    }.labelsHidden()
                }.width(100)
                TableColumn(L10n.tr("Kolumny")) { $k in TextField("", text: list($k.columns)) }.width(min: 100, ideal: 140)
                TableColumn(L10n.tr("Tabela wskazywana")) { $k in TextField("", text: upper($k.referencedTable)).disabled(k.kind != .foreign) }
                TableColumn(L10n.tr("Kolumny wskazywane")) { $k in TextField("", text: list($k.referencedColumns)).disabled(k.kind != .foreign) }
                TableColumn("ON DELETE") { $k in
                    Picker("", selection: $k.onDelete) { Text("—").tag(""); Text("CASCADE").tag("CASCADE"); Text("SET NULL").tag("SET NULL") }
                        .labelsHidden().disabled(k.kind != .foreign)
                }.width(100)
                TableColumn(L10n.tr("Włączony")) { $k in Toggle("", isOn: $k.enabled).labelsHidden() }.width(60)
            }
            HStack {
                listButtons(add: { definition.keys.append(TableDefinition.Key(name: "\(definition.name)_UK\(definition.keys.count + 1)", kind: .unique, columns: [])) },
                            remove: { if !definition.keys.isEmpty { definition.keys.removeLast() } })
                Spacer()
                // Add foreign key columns (PD-OED-002): kolumny klucza głównego wskazanej tabeli i klucz obcy.
                TextField(L10n.tr("Tabela wskazywana"), text: upper($fkTable)).frame(width: 180)
                Button(L10n.tr("Dodaj kolumny klucza obcego")) { addForeignKeyColumns() }.disabled(fkTable.isEmpty)
            }
        }
    }

    private var checks: some View {
        VStack(alignment: .leading) {
            Table($definition.checks) {
                TableColumn(L10n.tr("Nazwa")) { $c in TextField("", text: upper($c.name)) }.width(min: 140, ideal: 180)
                TableColumn(L10n.tr("Warunek")) { $c in TextField("", text: $c.condition).font(.system(.body, design: .monospaced)) }
                TableColumn(L10n.tr("Włączony")) { $c in Toggle("", isOn: $c.enabled).labelsHidden() }.width(60)
            }
            listButtons(add: { definition.checks.append(TableDefinition.Check(name: "\(definition.name)_CK\(definition.checks.count + 1)", condition: "")) },
                        remove: { if !definition.checks.isEmpty { definition.checks.removeLast() } })
        }
    }

    private var indexes: some View {
        VStack(alignment: .leading) {
            Table($definition.indexes) {
                TableColumn(L10n.tr("Nazwa")) { $x in TextField("", text: upper($x.name)) }.width(min: 140, ideal: 180)
                TableColumn(L10n.tr("Rodzaj")) { $x in
                    Picker("", selection: $x.kind) {
                        Text(L10n.tr("Zwykły")).tag(TableDefinition.Index.Kind.normal)
                        Text(L10n.tr("Unikalny")).tag(TableDefinition.Index.Kind.unique)
                        Text("Bitmap").tag(TableDefinition.Index.Kind.bitmap)
                    }.labelsHidden()
                }.width(110)
                TableColumn(L10n.tr("Kolumny / wyrażenia (DESC)")) { $x in TextField("", text: list($x.columns)) }
                TableColumn(L10n.tr("Przestrzeń tabel")) { $x in TextField("", text: upper($x.tablespace)) }.width(min: 90, ideal: 120)
                TableColumn(L10n.tr("Kompresja")) { $x in
                    Picker("", selection: $x.compression) {
                        Text("—").tag("")
                        ForEach(["1", "2", "3"], id: \.self) { Text("COMPRESS \($0)").tag($0) }
                        Text("ADVANCED LOW").tag("ADVANCED LOW")
                        Text("ADVANCED HIGH").tag("ADVANCED HIGH")
                        if !["", "1", "2", "3", "ADVANCED LOW", "ADVANCED HIGH"].contains(x.compression) { Text(x.compression).tag(x.compression) }
                    }.labelsHidden()
                }.width(130)
                TableColumn("PCTFREE") { $x in TextField("", text: $x.pctFree) }.width(56)
                TableColumn(L10n.tr("Odwrócony")) { $x in Toggle("", isOn: $x.reverse).labelsHidden().disabled(x.kind == .bitmap) }.width(70)
                TableColumn(L10n.tr("Lokalny")) { $x in Toggle("", isOn: $x.local).labelsHidden() }.width(56)
                TableColumn(L10n.tr("Niewidoczny")) { $x in Toggle("", isOn: $x.invisible).labelsHidden() }.width(76)
            }
            listButtons(add: { definition.indexes.append(TableDefinition.Index(name: "\(definition.name)_IX\(definition.indexes.count + 1)", columns: [])) },
                        remove: { if !definition.indexes.isEmpty { definition.indexes.removeLast() } })
        }
    }

    private var sql: some View {
        VStack(alignment: .leading) {
            ScrollView {
                Text(ddl.isEmpty ? L10n.tr("-- Brak zmian") : ddl.map { $0 + ";" }.joined(separator: "\n\n"))
                    .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading).padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            HStack {
                Button(L10n.tr("Kopiuj")) { workspace.ui?.copyToClipboard(ddl.map { $0 + ";" }.joined(separator: "\n"), html: nil) }
                Button(L10n.tr("Otwórz w oknie SQL")) {
                    let doc = workspace.newDocument(.sql, text: ddl.map { $0 + ";" }.joined(separator: "\n"))
                    workspace.activate(doc.id)
                    NSApp.mainWindow?.makeKeyAndOrderFront(nil)
                }
            }.disabled(ddl.isEmpty)
        }
    }

    // MARK: Pomocnicze

    private func typeField(_ type: Binding<String>) -> some View {
        HStack(spacing: 2) {
            TextField("", text: upper(type))
            Menu("") {
                ForEach(Self.typeSuggestions, id: \.self) { t in Button(t) { type.wrappedValue = t } }
            }
            .menuStyle(.borderlessButton).frame(width: 16)
        }
    }

    private func listButtons(add: @escaping () -> Void, remove: @escaping () -> Void) -> some View {
        HStack {
            Button { add() } label: { Image(systemName: "plus") }.iconLabel(L10n.tr("Dodaj"))
            Button { remove() } label: { Image(systemName: "minus") }.iconLabel(L10n.tr("Usuń ostatni"))
        }
    }

    /// Nazwy wpisywane wielkimi literami (jak nazwy bez cudzysłowu w Oracle).
    private func upper(_ b: Binding<String>) -> Binding<String> {
        Binding(get: { b.wrappedValue }, set: { b.wrappedValue = $0.uppercased() })
    }

    private func list(_ b: Binding<[String]>) -> Binding<String> {
        Binding(get: { b.wrappedValue.joined(separator: ", ") },
                set: { b.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })
    }

    private func addForeignKeyColumns() {
        guard let m = workspace.metadata(for: connectionID) else { return }
        Task {
            do {
                let (cols, key) = try await TableDDL.foreignKeyColumns(for: definition, referencing: fkTable, metadata: m)
                definition.columns += cols
                definition.keys.append(key)
                message = L10n.tr("Dodano kolumn: \(cols.count)")
                fkTable = ""
            } catch { message = error.localizedDescription }
        }
    }

    private func apply() {
        running = true
        message = ""
        Task {
            do {
                if definition.recreate {
                    let choice = await workspace.ui?.ask(L10n.tr("Odtworzyć tabelę \(definition.name)?"),
                                                         message: L10n.tr("Tabela zostanie usunięta (do kosza) i utworzona od nowa z przeniesieniem danych."),
                                                         buttons: [L10n.tr("Odtwórz"), L10n.tr("Anuluj")])
                    guard choice == 0 else { throw CommandError.cancelledByUser }
                }
                let r = try await TableDDL.apply(from: original, to: definition, in: workspace, connectionID: connectionID)
                if let e = r.error {
                    message = L10n.tr("Błąd w poleceniu \(r.executed.count + 1): \(e)")
                    tab = 5
                } else {
                    message = L10n.tr("Zastosowano poleceń: \(r.executed.count)")
                }
                if let m = workspace.metadata(for: connectionID) {
                    let fresh = try await TableDDL.load(owner: definition.owner, name: definition.name, metadata: m)
                    if r.error == nil { definition = fresh }
                    original = fresh
                }
            } catch CommandError.cancelledByUser {
                message = L10n.tr("Anulowano")
            } catch {
                message = error.localizedDescription
            }
            running = false
        }
    }

    private func refresh() {
        guard let o = original, let m = workspace.metadata(for: connectionID) else { return }
        Task {
            do {
                let fresh = try await TableDDL.load(owner: o.owner, name: o.name, metadata: m)
                definition = fresh
                original = fresh
                message = L10n.tr("Wczytano z bazy")
            } catch { message = error.localizedDescription }
        }
    }
}
