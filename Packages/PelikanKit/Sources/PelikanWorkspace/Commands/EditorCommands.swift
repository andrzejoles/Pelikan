import Foundation
import PelikanDB

/// Edytory obiektów (UG 9): definicja tabeli — nowa i istniejąca; dla agenta DDL zmian bez wykonania.
enum EditorCommands {
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
