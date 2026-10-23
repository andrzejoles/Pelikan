import Foundation
import PelikanDB
import PelikanSQL

/// utPLSQL (PROMPT §6): uruchamianie testów, pokrycie, wyniki. Agent uruchamia testy za zgodą (testy zmieniają dane
/// w transakcji wycofywanej przez utPLSQL) i dostaje podsumowanie z nieudanymi testami.
enum UtplsqlCommands {
    static let runParams = [
        CommandParameter("path", .string, L10n.tr("Ścieżka: schemat, schemat.pakiet[.procedura] albo schemat:suitepath (domyślnie bieżący użytkownik)")),
        CommandParameter("coverage", .boolean, L10n.tr("Zbieraj pokrycie kodu bieżącego schematu")),
    ]

    @MainActor
    static func run(_ ctx: CommandContext, paths: [String]?, coverage: Bool) async throws -> CommandResult {
        let ws = ctx.workspace
        guard let conn = ws.activeDocument.flatMap({ ws.effectiveConnection(of: $0) }) ?? ws.sessions.mainConnectionID,
              let m = ws.metadata(for: conn) else { throw CommandError.notConnected }
        let schema = try await m.currentSchema()
        let p = paths ?? [schema]
        let run = try await UtplsqlRunner.start(paths: p, coverageSchemes: coverage ? [schema] : [], in: ws, connectionID: conn)
        if ctx.invoker == .user {
            ctx.ui?.showUtplsqlResults(run)
            return CommandResult(message: L10n.tr("Uruchomiono testy: \(p.joined(separator: ", "))"))
        }
        // Agent: czeka na koniec przebiegu (do 10 min) i dostaje podsumowanie.
        for _ in 0..<6000 where !run.finished { try await Task.sleep(for: .milliseconds(100)) }
        let failed = run.tests.filter { $0.status == .failure || $0.status == .error }
        return CommandResult(message: L10n.tr("utPLSQL: sukces \(run.counter.success), niepowodzenia \(run.counter.failure), błędy \(run.counter.error), wyłączone \(run.counter.disabled)"),
                             value: .object([
                                "success": .int(Int64(run.counter.success)), "failure": .int(Int64(run.counter.failure)),
                                "error": .int(Int64(run.counter.error)), "disabled": .int(Int64(run.counter.disabled)),
                                "failed": .array(failed.map { t in
                                    .object(["path": .string(t.id), "messages": .array((t.expectations.map(\.message) + (t.errorStack.isEmpty ? [] : [t.errorStack])).map { .string($0) })])
                                }),
                                "runError": run.failure.map { .string($0) } ?? .null,
                             ]))
    }

    /// Ścieżka utPLSQL dla pozycji kursora w oknie programu: procedura testowa pod kursorem albo cały pakiet.
    @MainActor
    static func editorPath(_ ws: Workspace) async -> String? {
        guard let doc = ws.activeDocument, doc.kind == .program else { return nil }
        let outline = PLSQLOutline.parse(doc.text)
        let path = PLSQLOutline.path(at: doc.selectedRange.lowerBound, in: outline)
        guard let unit = path.first, unit.kind == .packageBody || unit.kind == .package else { return nil }
        let owner = ProgramCompiler.units(in: doc.text).first { $0.name.uppercased() == unit.name.uppercased() }?.owner
        let schema = await (try? ws.metadata(for: ws.effectiveConnection(of: doc))?.currentSchema()) ?? ""
        let base = "\(owner ?? schema).\(unit.name)".lowercased()
        if path.count >= 2, [.procedure, .function].contains(path[1].kind) { return base + "." + path[1].name.lowercased() }
        // Kursor na deklaracji procedury w specyfikacji (bez ciała).
        if let decl = unit.children.first(where: { [.procedure, .function].contains($0.kind) && $0.range.contains(doc.selectedRange.lowerBound) }) {
            return base + "." + decl.name.lowercased()
        }
        return base
    }

    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "utplsql.runAll", title: L10n.tr("utPLSQL: uruchom wszystkie testy"), category: .tools, submenu: "utPLSQL",
                                      pd: ["ctrl+shift+u"], mac: ["cmd+shift+u"], agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Uruchamia wszystkie testy utPLSQL bieżącego użytkownika; wyniki na żywo w oknie wyników."),
                                      feature: "UT-RUN-001"),
                    validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                try await run(ctx, paths: nil, coverage: false)
            },
            Command(CommandDescriptor(id: "utplsql.runPath", title: L10n.tr("utPLSQL: uruchom testy ze ścieżki…"), category: .tools, submenu: "utPLSQL",
                                      parameters: runParams, agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Uruchamia testy ze ścieżki: schemat.pakiet.procedura albo schemat:suitepath (kilka po przecinku)."),
                                      feature: "UT-RUN-002")) { ctx in
                var path = ctx.arguments.string("path") ?? ""
                if path.isEmpty {
                    guard let p = await ctx.ui?.askText(L10n.tr("Ścieżka testów utPLSQL"), message: L10n.tr("schemat.pakiet[.procedura] albo schemat:suitepath; kilka po przecinku"),
                                                        defaultValue: await editorPath(ctx.workspace) ?? ""), !p.isEmpty else { throw CommandError.cancelledByUser }
                    path = p
                }
                let paths = path.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                return try await run(ctx, paths: paths, coverage: ctx.arguments.bool("coverage") ?? false)
            },
            Command(CommandDescriptor(id: "utplsql.coverage", title: L10n.tr("utPLSQL: testy z pokryciem kodu"), category: .tools, submenu: "utPLSQL",
                                      parameters: runParams, agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Uruchamia testy z pokryciem kodu bieżącego schematu: raport HTML i linie pokryte na marginesie edytora. Pokrycie zbiera dane profilera."),
                                      feature: "UT-COV-001")) { ctx in
                let p = ctx.arguments.string("path").map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                return try await run(ctx, paths: p, coverage: true)
            },
            Command(CommandDescriptor(id: "utplsql.runEditor", title: L10n.tr("utPLSQL: uruchom test pod kursorem"), category: .tools, submenu: "utPLSQL",
                                      pd: ["ctrl+alt+u"], mac: ["cmd+alt+u"], agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Uruchamia test (procedurę pod kursorem) albo cały pakiet testowy z okna programu."),
                                      feature: "UT-RUN-004"),
                    validate: { $0.activeDocument?.kind == .program }) { ctx in
                guard let path = await editorPath(ctx.workspace) else {
                    throw CommandError.notAvailable(L10n.tr("Kursor nie jest w pakiecie testowym"))
                }
                return try await run(ctx, paths: [path], coverage: false)
            },
            Command(CommandDescriptor(id: "utplsql.rerunFailed", title: L10n.tr("utPLSQL: uruchom ponownie nieudane"), category: .tools, submenu: "utPLSQL",
                                      agent: .approval, effect: .modifiesDatabase, summary: L10n.tr("Uruchamia ponownie testy nieudane w ostatnim przebiegu."),
                                      feature: "UT-RUN-006"),
                    validate: { ws in ws.lastUtplsqlRun.map { $0.finished && !$0.failedPaths.isEmpty } ?? false }) { ctx in
                guard let failed = ctx.workspace.lastUtplsqlRun?.failedPaths, !failed.isEmpty else { return .ok }
                return try await run(ctx, paths: failed, coverage: false)
            },
            Command(CommandDescriptor(id: "utplsql.cancel", title: L10n.tr("utPLSQL: przerwij"), category: .tools, submenu: "utPLSQL",
                                      agent: .full, effect: .uiState, summary: L10n.tr("Przerywa trwający przebieg testów."), feature: "UT-RUN-006"),
                    validate: { ws in ws.lastUtplsqlRun.map { !$0.finished } ?? false }) { ctx in
                if let r = ctx.workspace.lastUtplsqlRun { UtplsqlRunner.cancel(r) }
                return .ok
            },
            Command(CommandDescriptor(id: "utplsql.version", title: L10n.tr("utPLSQL: wersja w bazie"), category: .tools, submenu: "utPLSQL",
                                      agent: .read, effect: .none, summary: L10n.tr("Wersja utPLSQL zainstalowanego w bazie połączenia (ut_runner.version)."),
                                      feature: "UT-INS-001"),
                    validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                guard let conn = ctx.workspace.sessions.mainConnectionID else { throw CommandError.notConnected }
                let s = try await ctx.workspace.sessions.session(ctx.workspace.sessions.compileKey(connection: conn))
                let v = await UtplsqlRunner.version(s)
                return CommandResult(message: v.map { L10n.tr("utPLSQL \($0)") } ?? L10n.tr("utPLSQL nie jest zainstalowany w tej bazie"), value: v.map { .string($0) } ?? .null)
            },
            Command(CommandDescriptor(id: "ob.utplsqlRun", title: L10n.tr("Uruchom testy utPLSQL"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: ObjectCommands.objectParams + [CommandParameter("coverage", .boolean, L10n.tr("Z pokryciem kodu"))],
                                      agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Testy utPLSQL zaznaczonego pakietu, procedury albo użytkownika (opcjonalnie z pokryciem)."),
                                      feature: "UT-RUN-003"),
                    validate: { ws in ws.selectedObject.map { [.package, .packageBody, .procedure, .user].contains($0.type) } ?? false }) { ctx in
                let (o, _) = try await ObjectCommands.target(ctx)
                let path = o.type == .user ? o.name : "\(o.owner).\(o.name)"
                return try await run(ctx, paths: [path.lowercased()], coverage: ctx.arguments.bool("coverage") ?? false)
            },
        ]
    }
}

extension Workspace {
    /// Pokrycie z ostatniego przebiegu utPLSQL dla jednostek okna programu: linie dokumentu (od 1) pokryte i niepokryte.
    public func coverageLines(in doc: Document) -> (covered: Set<Int>, uncovered: Set<Int>) {
        guard doc.kind == .program, let cov = lastUtplsqlRun?.coverage, !cov.isEmpty else { return ([], []) }
        var covered = Set<Int>(), uncovered = Set<Int>()
        let schema = sessions.connectedSchema(effectiveConnection(of: doc))
        for u in ProgramCompiler.units(in: doc.text) {
            let key = "\(u.type.rawValue) \(u.owner ?? schema ?? "").\(u.name)".uppercased()
            // Klucz raportu: „TYP WŁAŚCICIEL.NAZWA” — typ porównywany dokładnie (PACKAGE ≠ PACKAGE BODY).
            let match = cov.first { k, _ in
                guard let space = k.lastIndex(of: " ") else { return false }
                return String(k[..<space]) == u.type.rawValue && k[k.index(after: space)...].hasSuffix(".\(u.name.uppercased())")
            }
            guard let lines = cov[key] ?? match?.value else { continue }
            covered.formUnion(lines.covered.map { u.line + $0 })
            uncovered.formUnion(lines.uncovered.map { u.line + $0 })
        }
        return (covered, uncovered)
    }
}
