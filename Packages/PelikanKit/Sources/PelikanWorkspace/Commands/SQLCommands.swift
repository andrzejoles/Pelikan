import Foundation
import PelikanDB

/// Komendy SQL Window: wykonanie, przerwanie, transakcje, historia okna (UG 7, 20).
public enum SQLCommands {
    @MainActor
    static func sqlDocument(_ ws: Workspace) -> Document? {
        guard let d = ws.activeDocument, [.sql, .command, .test, .program].contains(d.kind) else { return nil }
        return d
    }

    @MainActor
    static func execute(_ ctx: CommandContext, _ scope: ExecuteScope) async throws -> CommandResult {
        guard let doc = sqlDocument(ctx.workspace) else { throw CommandError.notAvailable(L10n.tr("Brak okna SQL")) }
        if doc.isExecuting { throw CommandError.notAvailable(L10n.tr("Okno już wykonuje polecenie")) }
        try await SQLExecutor.execute(doc, scope: scope, in: ctx.workspace)
        return CommandResult(message: doc.statusText)
    }

    @MainActor
    static func currentSession(_ ws: Workspace) -> (any DatabaseSession)? {
        guard let doc = ws.activeDocument, let c = ws.effectiveConnection(of: doc) else { return nil }
        return ws.sessions.existingSession(ws.sessions.key(forDocument: doc.id, connection: c))
    }

    @MainActor
    public static var all: [Command] {
        [
            Command(CommandDescriptor(id: "sql.execute", title: L10n.tr("Wykonaj"), category: .session, pd: ["f8"], mac: ["cmd+enter"],
                                      agent: .none, effect: .modifiesDatabase,
                                      summary: L10n.tr("Wykonuje zaznaczenie albo polecenie pod kursorem (AutoSelect) lub wszystkie polecenia okna."),
                                      feature: "PD-SQLW-002"),
                    validate: { ws in sqlDocument(ws).map { !$0.isExecuting } ?? false }) { ctx in
                try await execute(ctx, .standard)
            },
            Command(CommandDescriptor(id: "sql.executeAlternate", title: L10n.tr("Wykonaj (odwrotnie do AutoSelect)"), category: .session,
                                      pd: ["ctrl+f8"], mac: ["cmd+shift+enter"], agent: .none, effect: .modifiesDatabase,
                                      summary: L10n.tr("Wykonuje wszystkie polecenia albo polecenie pod kursorem — odwrotnie niż Wykonaj."),
                                      feature: "PD-SQLW-003"),
                    validate: { ws in sqlDocument(ws).map { !$0.isExecuting } ?? false }) { ctx in
                try await execute(ctx, .alternate)
            },
            Command(CommandDescriptor(id: "sql.break", title: L10n.tr("Przerwij"), category: .session, pd: ["shift+escape"], mac: ["cmd+."],
                                      agent: .none, effect: .none, summary: L10n.tr("Przerywa bieżące wykonanie (OCIBreak)."),
                                      feature: "PD-SQLW-005"),
                    validate: { $0.activeDocument?.isExecuting ?? false }) { ctx in
                currentSession(ctx.workspace)?.breakExecution()
                return .ok
            },
            Command(CommandDescriptor(id: "session.commit", title: L10n.tr("Zatwierdź (COMMIT)"), category: .session, pd: ["f10"],
                                      mac: ["cmd+alt+enter"], agent: .approval, effect: .transaction,
                                      summary: L10n.tr("Zatwierdza transakcję sesji okna."), feature: "PD-SQLW-014"),
                    validate: { $0.activeDocument?.transactionOpen ?? false }) { ctx in
                try await endTransaction(ctx, commit: true)
            },
            Command(CommandDescriptor(id: "session.rollback", title: L10n.tr("Wycofaj (ROLLBACK)"), category: .session, pd: ["shift+f10"],
                                      mac: ["cmd+alt+backspace"], agent: .approval, effect: .transaction,
                                      summary: L10n.tr("Wycofuje transakcję sesji okna."), feature: "PD-SQLW-014"),
                    validate: { $0.activeDocument?.transactionOpen ?? false }) { ctx in
                try await endTransaction(ctx, commit: false)
            },
            Command(CommandDescriptor(id: "sql.historyBack", title: L10n.tr("Poprzednie polecenie okna"), category: .session,
                                      submenu: L10n.tr("Historia okna"), mac: ["cmd+alt+up"], agent: .full, effect: .modifiesEditor,
                                      summary: L10n.tr("Wstawia poprzednie wykonane polecenie okna."), feature: "PD-SQLW-007"),
                    validate: { !($0.activeDocument?.statementHistory.isEmpty ?? true) }) { ctx in
                stepHistory(ctx.workspace, back: true)
                return .ok
            },
            Command(CommandDescriptor(id: "sql.historyForward", title: L10n.tr("Następne polecenie okna"), category: .session,
                                      submenu: L10n.tr("Historia okna"), mac: ["cmd+alt+down"], agent: .full, effect: .modifiesEditor,
                                      summary: L10n.tr("Wstawia następne polecenie z historii okna."), feature: "PD-SQLW-007"),
                    validate: { $0.activeDocument?.historyPosition != nil }) { ctx in
                stepHistory(ctx.workspace, back: false)
                return .ok
            },
            Command(CommandDescriptor(id: "sql.toggleSubstitution", title: L10n.tr("Podstawianie zmiennych"), category: .session,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Włącza lub wyłącza podstawianie zmiennych & i : w oknie."), feature: "PD-VAR-005"),
                    validate: { sqlDocument($0) != nil }) { ctx in
                guard let d = sqlDocument(ctx.workspace) else { return .ok }
                d.substitutionEnabled.toggle()
                return .ok
            },
        ]
    }

    @MainActor
    static func endTransaction(_ ctx: CommandContext, commit: Bool) async throws -> CommandResult {
        guard let doc = ctx.workspace.activeDocument else { return .ok }
        if ctx.workspace.settings.confirmCommitRollback {
            let a = await ctx.ui?.ask(commit ? L10n.tr("Zatwierdzić transakcję?") : L10n.tr("Wycofać transakcję?"),
                                      message: doc.fullTitle, buttons: [commit ? L10n.tr("Zatwierdź") : L10n.tr("Wycofaj")])
            guard a == 0 else { throw CommandError.cancelledByUser }
        }
        try await ctx.workspace.endTransactions(of: [doc], commit: commit)
        doc.statusText = commit ? L10n.tr("Transakcja zatwierdzona") : L10n.tr("Transakcja wycofana")
        return CommandResult(message: doc.statusText)
    }

    @MainActor
    static func stepHistory(_ ws: Workspace, back: Bool) {
        guard let d = ws.activeDocument, !d.statementHistory.isEmpty else { return }
        let last = d.statementHistory.count - 1
        var pos = d.historyPosition ?? (back ? last + 1 : last)
        pos += back ? -1 : 1
        if pos > last { d.historyPosition = nil; return }
        pos = max(0, pos)
        d.historyPosition = pos
        d.text = d.statementHistory[pos]
        d.selectedRange = 0..<0
    }
}
