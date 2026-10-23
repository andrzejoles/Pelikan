import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Query Builder (UG 28, PD-QB-001): tabele na płótnie (przeciąganie, złączenia z kluczy obcych), pola z aliasem,
/// sortowaniem i grupowaniem, warunki, DISTINCT, INTO, format; podgląd SQL i wstawienie do edytora.
struct QueryBuilderView: View {
    let workspace: Workspace
    let connectionID: UUID?
    /// Okno, z którego otwarto Query Builder (wstawienie zastępuje jego zaznaczenie).
    let targetDocument: DocumentID?
    let initialSQL: String?
    @State private var model = QueryModel()
    @State private var tableName = ""
    @State private var message = ""
    @State private var dragStart: [UUID: DiagramPoint] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(L10n.tr("Tabela albo widok (NAZWA lub SCHEMAT.NAZWA)"), text: $tableName).textFieldStyle(.roundedBorder)
                    .onSubmit { add(tableName) }
                Button(L10n.tr("Dodaj")) { add(tableName) }.disabled(tableName.isEmpty)
                Button(L10n.tr("Dodaj zaznaczony obiekt")) { if let o = workspace.selectedObject { add("\"\(o.owner)\".\"\(o.name)\"") } }
                    .disabled(workspace.selectedObject == nil)
                Spacer()
                Toggle("DISTINCT", isOn: $model.distinct).toggleStyle(.checkbox)
            }
            VSplitView {
                canvas.frame(minHeight: 220)
                HSplitView {
                    fields.frame(minWidth: 380)
                    clauses.frame(minWidth: 280)
                }
                .frame(minHeight: 180)
                preview.frame(minHeight: 120)
            }
            HStack {
                Text(message).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("Kopiuj SQL")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.sql(), forType: .string)
                }
                Button(L10n.tr("Nowe okno SQL")) {
                    let d = workspace.newDocument(.sql, text: model.sql())
                    d.connectionID = connectionID
                }
                Button(L10n.tr("Wstaw do edytora")) { insert() }.disabled(model.tables.isEmpty)
            }
        }
        .padding(10)
        .frame(minWidth: 900, minHeight: 640)
        .task { await load() }
    }

    // MARK: Płótno

    private var canvas: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    for j in model.joins {
                        guard let l = model.table(j.left), let r = model.table(j.right) else { continue }
                        var p = Path()
                        p.move(to: CGPoint(x: l.position.x + 100, y: l.position.y + 14))
                        p.addLine(to: CGPoint(x: r.position.x + 100, y: r.position.y + 14))
                        ctx.stroke(p, with: .color(.secondary), lineWidth: 1.5)
                    }
                }
                .frame(width: 1400, height: 900)
                ForEach($model.tables) { $t in
                    tableCard($t)
                        .offset(x: t.position.x, y: t.position.y)
                        .gesture(DragGesture().onChanged { v in
                            let start = dragStart[t.id] ?? t.position
                            dragStart[t.id] = start
                            t.position = DiagramPoint(max(0, start.x + v.translation.width), max(0, start.y + v.translation.height))
                        }.onEnded { _ in dragStart[t.id] = nil })
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .border(Color(nsColor: .separatorColor))
    }

    private func tableCard(_ t: Binding<QBTable>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(t.wrappedValue.name.lowercased()).bold()
                TextField(L10n.tr("alias"), text: t.alias).frame(width: 50).textFieldStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button { model.removeTable(t.wrappedValue.id) } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
            .padding(.bottom, 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(t.wrappedValue.columns, id: \.name) { c in
                        Toggle(isOn: Binding(get: { model.isSelected(c.name, of: t.wrappedValue.id) },
                                             set: { _ in model.toggleColumn(c.name, of: t.wrappedValue.id) })) {
                            Text((c.primaryKey ? "🔑 " : "") + c.name.lowercased()).font(.system(size: 11))
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        .padding(6)
        .frame(width: 200, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
    }

    // MARK: Pola i klauzule

    private var fields: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.tr("Pola")).font(.headline)
                Spacer()
                Button(L10n.tr("Dodaj wyrażenie")) { model.fields.append(QBField(table: nil, expression: "count(*)")) }
            }
            List {
                ForEach($model.fields) { $f in
                    HStack {
                        if f.table == nil {
                            TextField(L10n.tr("Wyrażenie"), text: $f.expression).frame(minWidth: 120)
                        } else {
                            Text(model.table(f.table).map { "\($0.alias).\(f.expression.lowercased())" } ?? f.expression).frame(minWidth: 120, alignment: .leading)
                        }
                        TextField(L10n.tr("alias"), text: $f.alias).frame(width: 70)
                        Picker("", selection: $f.sort) {
                            Text(L10n.tr("bez sortowania")).tag(QBField.Sort.none)
                            Text(L10n.tr("rosnąco")).tag(QBField.Sort.ascending)
                            Text(L10n.tr("malejąco")).tag(QBField.Sort.descending)
                        }
                        .labelsHidden().frame(width: 120)
                        Toggle("GROUP BY", isOn: $f.groupBy).toggleStyle(.checkbox).font(.caption)
                    }
                }
                .onDelete { model.fields.remove(atOffsets: $0) }
                .onMove { model.fields.move(fromOffsets: $0, toOffset: $1) }
            }
            if !model.joins.isEmpty {
                Text(L10n.tr("Złączenia")).font(.headline)
                ForEach($model.joins) { $j in
                    HStack {
                        Text("\(model.table(j.left)?.alias ?? "?") ↔ \(model.table(j.right)?.alias ?? "?") (\(j.leftColumns.joined(separator: ", ").lowercased()))")
                            .font(.caption)
                        Picker("", selection: $j.kind) { ForEach(QBJoin.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                            .labelsHidden().frame(width: 130)
                        Button { model.joins.removeAll { $0.id == j.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var clauses: some View {
        Form {
            TextField("WHERE", text: $model.whereClause, axis: .vertical).lineLimit(2...4)
            TextField("HAVING", text: $model.having, axis: .vertical).lineLimit(1...3)
            TextField("INTO", text: $model.into)
            Toggle(L10n.tr("Słowa kluczowe wielkimi literami"), isOn: $model.format.uppercaseKeywords)
            Toggle(L10n.tr("Kolumna w osobnej linii"), isOn: $model.format.columnPerLine)
            Toggle(L10n.tr("Złączenia w FROM (ANSI)"), isOn: $model.format.ansiJoins)
            Toggle(L10n.tr("Nazwa schematu przed tabelą"), isOn: $model.format.qualifyWithOwner)
        }
        .font(.callout)
    }

    private var preview: some View {
        ScrollView {
            Text(model.sql()).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .border(Color(nsColor: .separatorColor))
    }

    // MARK: Akcje

    private func load() async {
        guard let sql = initialSQL, !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Odczyt tekstu bez słownika, potem właściciel i kolumny każdej tabeli ze słownika.
        guard var parsed = QueryModel.parse(sql, resolve: { owner, name in (owner ?? "", name, []) }) else {
            message = L10n.tr("Zaznaczone zapytanie jest zbyt złożone dla Query Buildera — zaczynam od pustego.")
            return
        }
        do {
            let source = try await workspace.schemaSource(connection: connectionID)
            for i in parsed.tables.indices {
                let t = parsed.tables[i]
                guard let o = try await source.resolve(t.owner.isEmpty ? t.name : "\"\(t.owner)\".\"\(t.name)\"") else {
                    message = L10n.tr("Nie znaleziono \(t.name)")
                    continue
                }
                parsed.tables[i].owner = o.owner
                parsed.tables[i].columns = try await source.columns(owner: o.owner, name: o.name)
            }
            model = parsed
        } catch { message = error.localizedDescription }
    }

    private func add(_ name: String) {
        let raw = name.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        Task {
            do {
                let source = try await workspace.schemaSource(connection: connectionID)
                guard let o = try await source.resolve(raw) else { message = L10n.tr("Nie znaleziono \(raw)"); return }
                let cols = try await source.columns(owner: o.owner, name: o.name)
                let fks = o.type == .table ? try await source.foreignKeys(owner: o.owner, table: o.name) : []
                model.addTable(owner: o.owner, name: o.name, columns: cols, foreignKeys: fks)
                tableName = ""
                message = L10n.tr("Tabele: \(model.tables.count), złączenia: \(model.joins.count)")
            } catch { message = error.localizedDescription }
        }
    }

    private func insert() {
        let sql = model.sql()
        if let id = targetDocument, let d = workspace.documents.first(where: { $0.id == id }) {
            let ns = d.text as NSString
            let sel = d.selectedRange
            let range = NSRange(location: min(sel.lowerBound, ns.length), length: min(sel.count, max(0, ns.length - sel.lowerBound)))
            d.text = ns.replacingCharacters(in: range, with: sql)
            d.selectedRange = range.location..<(range.location + (sql as NSString).length)
            workspace.activate(d.id)
        } else {
            let d = workspace.newDocument(.sql, text: sql)
            d.connectionID = connectionID
        }
    }
}
