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
        // Pusta wartość zmiennej, od której lista zależy → pusta lista (UG 12.3).
        let deps = Variables.find(in: q).filter { $0.kind == .bind }.map(\.name)
        if deps.contains(where: { d in value(forBind: d)?.isEmpty ?? true }) {
            fields[i].items = []
            return
        }
        fields[i].loading = true
        defer { fields[i].loading = false }
        do {
            fields[i].items = try await run(q, single: false)
            fields[i].error = nil
        } catch {
            fields[i].error = (error as? OracleError)?.message ?? error.localizedDescription
        }
    }

    /// Po zmianie wartości — przeładuj listy, które od niej zależą.
    func valueChanged(_ name: String) {
        let bind = fields.first { $0.id == name }?.request.options.bindName ?? name
        for i in fields.indices {
            guard let q = fields[i].request.options.list, fields[i].request.options.listIsQuery else { continue }
            if Variables.find(in: q).contains(where: { $0.kind == .bind && $0.name.lowercased() == bind }) {
                Task { await reloadList(i) }
            }
        }
    }

    private func value(forBind bind: String) -> String? {
        fields.first { $0.request.options.bindName == bind.lowercased() }.map { $0.text }
    }

    private func run(_ sql: String, single: Bool) async throws -> [(value: String, label: String)] {
        let session = try await workspace.session(for: document)
        let binds = Variables.find(in: sql).filter { $0.kind == .bind }.map { o in
            BindVariable(name: o.name, type: .varchar2, value: value(forBind: o.name).map { .text($0) } ?? .null, maxSize: 4000)
        }
        let (_, rows) = try await session.queryAll(sql, binds: binds, limit: single ? 1 : 10_000)
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
    let onDone: ([String: VariableValue]?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("Zmienne")).font(.title3.bold())
            Form {
                ForEach($model.fields) { $f in
                    if !f.request.options.hidden { row($f) }
                }
            }
            .formStyle(.grouped)
            HStack {
                Text(L10n.tr("& tekst w SQL · : zmienna wiązana · $P{} / $X{} JasperReports")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("Anuluj"), role: .cancel) { onDone(nil) }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("Wykonaj")) { onDone(model.values) }.keyboardShortcut(.defaultAction).disabled(!model.canSubmit)
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
            if let hint = o.hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
            if let e = f.wrappedValue.error { Text(e).font(.caption).foregroundStyle(.red) }
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
