import Foundation
import PelikanDB

/// Edytory obiektów (UG 9): definicja tabeli — nowa i istniejąca; dla agenta DDL zmian bez wykonania.
enum EditorCommands {
    /// „Nowy …” dla prostego edytora; obiekty schematu w schemacie bieżącym.
    @MainActor
    static func newSimple(_ kind: SimpleObjectEditor.Kind, id: String, title: String, feature: String) -> Command {
        Command(CommandDescriptor(id: CommandID(rawValue: id), title: title, category: .file, submenu: L10n.tr("Nowy"),
                                  agent: .none, effect: .uiState, summary: L10n.tr("Otwiera edytor nowego obiektu: \(title.replacingOccurrences(of: "…", with: ""))."),
                                  feature: feature),
                validate: { $0.metadata() != nil }) { ctx in
            guard let m = ctx.workspace.metadata() else { throw CommandError.notConnected }
            var e = SimpleObjectEditor(kind: kind, owner: try await m.currentSchema())
            switch kind {
            case .sequence: e.values = ["name": "NOWA_SEKWENCJA", "start": "1", "increment": "1", "cache": "20"]
            case .user: e.values = ["name": "NOWY_UZYTKOWNIK", "roles": "CONNECT", "defaultTablespace": "USERS"]
            case .index: e.values = ["type": "NORMAL"]
            default: break
            }
            ctx.ui?.showObjectEditor(e, connectionID: m.connectionID)
            return .ok
        }
    }

    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "file.newTable", title: L10n.tr("Tabela…"), category: .file, submenu: L10n.tr("Nowy"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera edytor definicji nowej tabeli w schemacie bieżącym."), feature: "PD-OED-001"),
                    validate: { $0.metadata() != nil }) { ctx in
                guard let m = ctx.workspace.metadata() else { throw CommandError.notConnected }
                var d = TableDefinition(owner: try await m.currentSchema(), name: "NOWA_TABELA")
                d.columns = [TableDefinition.Column(name: "ID", type: "NUMBER", nullable: false)]
                d.keys = [TableDefinition.Key(name: "NOWA_TABELA_PK", kind: .primary, columns: ["ID"])]
                ctx.ui?.showTableEditor(d, original: nil, connectionID: m.connectionID)
                return .ok
            },
            newSimple(.sequence, id: "file.newSequence", title: L10n.tr("Sekwencja…"), feature: "PD-OED-008"),
            newSimple(.synonym, id: "file.newSynonym", title: L10n.tr("Synonim…"), feature: "PD-OED-008"),
            newSimple(.index, id: "file.newIndex", title: L10n.tr("Indeks…"), feature: "PD-OED-010"),
            newSimple(.user, id: "file.newUser", title: L10n.tr("Użytkownik…"), feature: "PD-OED-009"),
            newSimple(.role, id: "file.newRole", title: L10n.tr("Rola…"), feature: "PD-OED-009"),
            Command(CommandDescriptor(id: "file.newView", title: L10n.tr("Widok…"), category: .file, submenu: L10n.tr("Nowy"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera okno SQL z szablonem CREATE OR REPLACE VIEW."), feature: "PD-OED-010")) { ctx in
                try await ctx.workspace.invoke("file.newFromTemplate", CommandArguments(["template": .string(TemplateLibrary.objectsFolder + "/" + L10n.tr("Widok"))]),
                                               invoker: ctx.invoker)
            },
            Command(CommandDescriptor(id: "ob.editTable", title: L10n.tr("Edytuj definicję tabeli"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: ObjectCommands.objectParams, agent: .read, effect: .none,
                                      summary: L10n.tr("Otwiera edytor definicji tabeli (kolumny, klucze, warunki, indeksy); agent dostaje definicję jako DDL."),
                                      feature: "PD-OED-002"),
                    validate: { ws in ws.selectedObject?.type == .table }) { ctx in
                let (o, m) = try await ObjectCommands.target(ctx)
                guard o.type == .table else { throw CommandError.notAvailable(L10n.tr("To nie jest tabela")) }
                let d = try await TableDDL.load(owner: o.owner, name: o.name, metadata: m)
                if ctx.invoker == .user { ctx.ui?.showTableEditor(d, original: d, connectionID: m.connectionID) }
                return CommandResult(value: .string(TableDDL.statements(from: nil, to: d).joined(separator: ";\n") + ";"))
            },
        ]
    }
}
