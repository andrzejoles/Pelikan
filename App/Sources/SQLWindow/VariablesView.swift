import AppKit
import PelikanDB
import PelikanSQL
import PelikanWorkspace
import SwiftUI

/// Stan okna „Zmienne”: wartości, elementy list (także z zapytań i zależne od innych zmiennych).
@MainActor
@Observable
final class VariablesModel {
    struct Field: Identifiable {
        let id: String
        let request: VariableRequest
        var text: String
        var selected: Set<String>
        var checked: Bool
        var items: [(value: String, label: String)]
        var loading = false
        var error: String?
    }

    var fields: [Field]
    /// Numer ostatniego przeładowania listy pola — spóźniona odpowiedź starszego zapytania nie nadpisuje nowszej.
    @ObservationIgnored private var listGeneration: [Int: Int] = [:]
    private let workspace: Workspace
    private let document: PelikanWorkspace.Document

    init(requests: [VariableRequest], workspace: Workspace, document: PelikanWorkspace.Document) {
        self.workspace = workspace
        self.document = document
        fields = requests.map { r in
            let o = r.options
            var text = ""
            var selected: Set<String> = []
            switch r.value {
            case .text(let t)?: text = t
            case .list(let l)?: selected = Set(l); text = l.joined(separator: ", ")
            default: if !o.defaultIsQuery { text = o.defaultValue ?? "" }
            }
            let checked = o.checkbox.map { cb in text.lowercased() == cb.checked.lowercased() || text == "1" } ?? false
            return Field(id: r.name, request: r, text: text, selected: selected, checked: checked, items: o.listItems)
        }
    }

    /// Ładowanie list z zapytań i wartości domyślnych z zapytań (kolejno — listy zależne widzą poprzednie wartości).
    func loadQueries() async {
        for i in fields.indices {
            let o = fields[i].request.options
            if o.defaultIsQuery, fields[i].text.isEmpty, let q = o.defaultValue {
                fields[i].text = (try? await run(q, single: true).first?.value) ?? ""
            }
            if o.listIsQuery { await reloadList(i) }
        }
    }

    func reloadList(_ i: Int) async {
        guard let q = fields[i].request.options.list else { return }
        let generation = (listGeneration[i] ?? 0) + 1
        listGeneration[i] = generation
        // Pusta wartość zmiennej, od której lista zależy (`:x` albo `&x`) → pusta lista (UG 12.3, PD-VAR-004).
        guard VariableLists.prepare(q, values: dependencyValues) != nil else {
            fields[i].items = []
            fields[i].loading = false
            return
        }
        fields[i].loading = true
        let result: Result<[(value: String, label: String)], any Error>
        do { result = .success(try await run(q, single: false)) } catch { result = .failure(error) }
        guard listGeneration[i] == generation else { return }
        fields[i].loading = false
        switch result {
        case .success(let items):
            fields[i].items = items
            fields[i].error = nil
        case .failure(let error):
            fields[i].error = (error as? OracleError)?.message ?? error.localizedDescription
        }
    }

    /// Po zmianie wartości — przeładuj listy, które od niej zależą.
    func valueChanged(_ name: String) {
        let bind = fields.first { $0.id == name }?.request.options.bindName ?? name
        for i in fields.indices {
            guard let q = fields[i].request.options.list, fields[i].request.options.listIsQuery else { continue }
            if VariableLists.dependencies(of: q).contains(bind) {
                Task { await reloadList(i) }
            }
        }
    }

    /// Wartości zmiennych okna wg nazwy wiązanej (dla list zależnych).
    private var dependencyValues: [String: String] {
        Dictionary(fields.map { ($0.request.options.bindName, $0.text) }, uniquingKeysWith: { a, _ in a })
    }

    private func run(_ sql: String, single: Bool) async throws -> [(value: String, label: String)] {
        let session = try await workspace.session(for: document)
        let prepared = VariableLists.prepare(sql, values: dependencyValues) ?? Variables.Prepared(sql: sql, binds: [])
        let binds = prepared.binds.map { b in
            BindVariable(name: b.name, type: .varchar2, value: { if case .text(let t) = b.value { return .text(t) } else { return .null } }(), maxSize: 4000)
        }
        let (_, rows) = try await session.queryAll(prepared.sql, binds: binds, limit: single ? 1 : 10_000)
        return rows.map { r in
            let v = r.first?.displayText ?? ""
            return (v, r.count > 1 ? (r[1].displayText ?? v) : v)
        }
    }

    var canSubmit: Bool {
        fields.allSatisfy { f in
            !f.request.options.required || !(f.request.options.multiSelect ? f.selected.isEmpty : f.text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    var values: [String: VariableValue] {
        var out: [String: VariableValue] = [:]
        for f in fields {
            let o = f.request.options
            if let cb = o.checkbox { out[f.id] = .text(f.checked ? cb.checked : (cb.unchecked.isEmpty ? "0" : cb.unchecked)); continue }
            if o.multiSelect { out[f.id] = .list(f.items.map(\.value).filter { f.selected.contains($0) }); continue }
            if f.request.kind == .jasperClause, f.text.contains(",") {
                out[f.id] = .list(f.text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                continue
            }
            out[f.id] = f.text.isEmpty ? (f.request.kind == .bind || f.request.kind == .jasperValue ? .null : .text("")) : .text(f.text)
        }
        return out
    }
}

struct VariablesView: View {
    @Bindable var model: VariablesModel
    var title = L10n.tr("Zmienne")
    var submitTitle = L10n.tr("Wykonaj")
    var showLegend = true
    let onDone: ([String: VariableValue]?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            Form {
                ForEach($model.fields) { $f in
                    if !f.request.options.hidden { row($f) }
                }
            }
            .formStyle(.grouped)
            HStack {
                if showLegend {
                    Text(L10n.tr("& tekst w SQL · : zmienna wiązana · $P{} / $X{} JasperReports")).font(.uiSecondary).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.tr("Anuluj"), role: .cancel) { onDone(nil) }.keyboardShortcut(.cancelAction)
                Button(submitTitle) { onDone(model.values) }.keyboardShortcut(.defaultAction).disabled(!model.canSubmit)
            }
        }
        .padding(18)
        .frame(width: 560, height: min(620, CGFloat(160 + model.fields.count * 64)))
        .task { await model.loadQueries() }
    }

    @ViewBuilder
    private func row(_ f: Binding<VariablesModel.Field>) -> some View {
        let o = f.wrappedValue.request.options
        let label = o.name + (o.required ? " *" : "") + kindSuffix(f.wrappedValue.request.kind)
        VStack(alignment: .leading, spacing: 2) {
            if let cb = o.checkbox {
                Toggle(label, isOn: f.checked).help(cb.checked)
            } else if o.multiSelect {
                Text(label)
                List(f.wrappedValue.items, id: \.value) { item in
                    Toggle(item.label, isOn: Binding(get: { f.wrappedValue.selected.contains(item.value) },
                                                     set: { on in if on { f.wrappedValue.selected.insert(item.value) } else { f.wrappedValue.selected.remove(item.value) } }))
                }
                .frame(height: 110)
            } else if !f.wrappedValue.items.isEmpty || o.list != nil {
                HStack {
                    if o.restricted {
                        Picker(label, selection: f.text) {
                            Text("").tag("")
                            ForEach(f.wrappedValue.items, id: \.value) { Text($0.label).tag($0.value) }
                        }
                    } else {
                        TextField(label, text: f.text)
                        Menu("▾") {
                            ForEach(f.wrappedValue.items, id: \.value) { item in
                                Button(item.label == item.value ? item.value : "\(item.label)  (\(item.value))") {
                                    f.wrappedValue.text = item.value
                                    model.valueChanged(o.name)
                                }
                            }
                        }.fixedSize()
                    }
                    if f.wrappedValue.loading { ProgressView().controlSize(.small) }
                }
            } else if o.lines > 1 {
                Text(label)
                TextEditor(text: f.text).font(.system(.body, design: o.editor == "sql" ? .monospaced : .default))
                    .frame(height: CGFloat(o.lines) * 18)
            } else {
                TextField(label, text: f.text).disabled(o.readOnly)
                    .onSubmit { if model.canSubmit { onDone(model.values) } }   // Enter wykonuje (jak w PL/SQL Developer)
            }
            if let hint = o.hint { Text(hint).font(.uiSecondary).foregroundStyle(.secondary) }
            if let e = f.wrappedValue.error { Text(e).font(.uiSecondary).foregroundStyle(.red) }
        }
        .onChange(of: f.wrappedValue.text) { _, _ in model.valueChanged(o.name) }
    }

    private func kindSuffix(_ k: VariableKind) -> String {
        switch k {
        case .bind: "  (:)"
        case .jasperValue: "  ($P)"
        case .jasperText: "  ($P!)"
        case .jasperClause: "  ($X)"
        default: ""
        }
    }
}
