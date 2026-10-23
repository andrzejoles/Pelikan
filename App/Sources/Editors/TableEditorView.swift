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

    static let typeSuggestions = ["NUMBER", "NUMBER(10)", "NUMBER(10,2)", "INTEGER", "VARCHAR2(30 CHAR)", "VARCHAR2(100 CHAR)", "VARCHAR2(4000 CHAR)",
                                  "CHAR(1 CHAR)", "DATE", "TIMESTAMP", "TIMESTAMP WITH TIME ZONE", "CLOB", "BLOB", "RAW(16)", "BOOLEAN", "JSON",
                                  "VECTOR", "BINARY_DOUBLE", "INTERVAL DAY TO SECOND"]

    private var ddl: [String] { TableDDL.statements(from: original, to: definition) }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                general.tabItem { Text(L10n.tr("Ogólne")) }.tag(0)
                columns.tabItem { Text(L10n.tr("Kolumny")) }.tag(1)
                keys.tabItem { Text(L10n.tr("Klucze")) }.tag(2)
                checks.tabItem { Text(L10n.tr("Warunki")) }.tag(3)
                indexes.tabItem { Text(L10n.tr("Indeksy")) }.tag(4)
                sql.tabItem { Text("SQL") }.tag(5)
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
        }
        .formStyle(.grouped)
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
            listButtons(add: { definition.keys.append(TableDefinition.Key(name: "\(definition.name)_UK\(definition.keys.count + 1)", kind: .unique, columns: [])) },
                        remove: { if !definition.keys.isEmpty { definition.keys.removeLast() } })
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
            Button { add() } label: { Image(systemName: "plus") }.help(L10n.tr("Dodaj"))
            Button { remove() } label: { Image(systemName: "minus") }.help(L10n.tr("Usuń ostatni"))
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

    private func apply() {
        running = true
        message = ""
        Task {
            do {
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
