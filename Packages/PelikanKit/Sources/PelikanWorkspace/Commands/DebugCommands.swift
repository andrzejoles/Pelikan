import Foundation
import PelikanDB

/// Debuger (UG 5.10, ADR 0006). Agent nie ma dostępu do debugera (PROMPT §7).
enum DebugCommands {
    @MainActor
    static func testDocument(_ ws: Workspace) -> Document? {
        if let d = ws.activeDocument, d.kind == .test { return d }
        // Okno programu z bieżącą linią debugera — sterowanie debugerem okna testu, które go uruchomiło.
        return ws.debuggers.first { $0.value.state == .paused || $0.value.state == .running }.flatMap { id in ws.documents.first { $0.id == id.key } }
    }

    @MainActor
    static func step(_ id: String, _ title: String, pd: [String], mac: [String]? = nil, summary: String, _ s: DebuggerEngine.Step) -> Command {
        Command(CommandDescriptor(id: CommandID(rawValue: id), title: title, category: .debug, pd: pd, mac: mac, agent: .none, effect: .modifiesDatabase,
                                  summary: summary, feature: "PD-DBG-001"),
                validate: { ws in testDocument(ws).map { ws.debugger(for: $0).state == .paused } ?? false }) { ctx in
            guard let doc = testDocument(ctx.workspace) else { return .ok }
            let d = ctx.workspace.debugger(for: doc)
            try await d.step(s)
            ctx.workspace.showDebugLocation(d, testDocument: doc)
            return CommandResult(message: d.message)
        }
    }

    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "debug.start", title: L10n.tr("Rozpocznij debugowanie"), category: .debug, pd: ["f9"],
                                      agent: .none, effect: .modifiesDatabase,
                                      summary: L10n.tr("Uruchamia skrypt okna testu z debugerem i zatrzymuje się w pierwszej linii."), feature: "PD-DBG-001"),
                    validate: { ws in ws.activeDocument.map { $0.kind == .test && ws.debugger(for: $0).state != .paused && ws.debugger(for: $0).state != .running } ?? false }) { ctx in
                guard let doc = ctx.workspace.activeDocument, doc.kind == .test else { return .ok }
                let d = ctx.workspace.debugger(for: doc)
                ctx.ui?.showDebugger(d, document: doc)
                try await d.start()
                ctx.workspace.showDebugLocation(d, testDocument: doc)
                return .ok
            },
            step("debug.run", L10n.tr("Kontynuuj"), pd: ["ctrl+r"], summary: L10n.tr("Wykonuje do następnego punktu przerwania albo do końca."), .run),
            step("debug.stepInto", L10n.tr("Wejdź"), pd: ["ctrl+n"], summary: L10n.tr("Wchodzi do wywołania w bieżącej linii (także do wyzwalacza)."), .into),
            step("debug.stepOver", L10n.tr("Przejdź"), pd: ["ctrl+o"], summary: L10n.tr("Wykonuje bieżącą linię bez wchodzenia do wywołań."), .over),
            step("debug.stepOut", L10n.tr("Wyjdź"), pd: ["ctrl+t"], summary: L10n.tr("Wykonuje do końca bieżącej jednostki."), .out),
            step("debug.runToException", L10n.tr("Wykonaj do wyjątku"), pd: [], summary: L10n.tr("Wykonuje do wystąpienia wyjątku."), .runToException),
            Command(CommandDescriptor(id: "debug.runToCursor", title: L10n.tr("Wykonaj do kursora"), category: .debug, agent: .none, effect: .modifiesDatabase,
                                      summary: L10n.tr("Wykonuje do linii z kursorem (tymczasowy punkt przerwania)."), feature: "PD-DBG-001"),
                    validate: { ws in testDocument(ws).map { ws.debugger(for: $0).state == .paused } ?? false }) { ctx in
                guard let test = testDocument(ctx.workspace), let at = ctx.workspace.activeDocument, let bp = breakpointAtCaret(ctx.workspace, at) else { return .ok }
                ctx.workspace.breakpoints.append(bp)
                defer { ctx.workspace.breakpoints.removeAll { $0.id == bp.id } }
                let d = ctx.workspace.debugger(for: test)
                try await d.applyTemporary(bp)
                try await d.step(.run)
                ctx.workspace.showDebugLocation(d, testDocument: test)
                return .ok
            },
            Command(CommandDescriptor(id: "debug.stop", title: L10n.tr("Zatrzymaj debugowanie"), category: .debug, pd: ["shift+f9"],
                                      agent: .none, effect: .modifiesDatabase, summary: L10n.tr("Przerywa wykonywany program i kończy debugowanie."),
                                      feature: "PD-DBG-001"),
                    validate: { ws in testDocument(ws).map { [.paused, .running].contains(ws.debugger(for: $0).state) } ?? false }) { ctx in
                guard let doc = testDocument(ctx.workspace) else { return .ok }
                let d = ctx.workspace.debugger(for: doc)
                await d.stop()
                ctx.workspace.showDebugLocation(d, testDocument: doc)
                return .ok
            },
            Command(CommandDescriptor(id: "debug.breakpoints", title: L10n.tr("Punkty przerwania…"), category: .debug,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Lista punktów przerwania (włączanie, licznik przejść, usuwanie) i zatrzymanie na kodach błędów."),
                                      feature: "PD-DBG-008")) { ctx in
                ctx.ui?.showBreakpoints()
                return .ok
            },
            Command(CommandDescriptor(id: "debug.toggleBreakpoint", title: L10n.tr("Punkt przerwania"), category: .debug, pd: ["ctrl+b"],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Ustawia lub usuwa punkt przerwania w linii kursora (okno testu albo jednostka w oknie programu)."),
                                      feature: "PD-DBG-007"),
                    validate: { ws in ws.activeDocument.map { [.test, .program].contains($0.kind) } ?? false }) { ctx in
                guard let doc = ctx.workspace.activeDocument, let bp = breakpointAtCaret(ctx.workspace, doc) else {
                    throw CommandError.notAvailable(L10n.tr("Kursor nie jest w jednostce programu"))
                }
                ctx.workspace.toggleBreakpoint(bp)
                return .ok
            },
        ]
    }

    /// Punkt przerwania dla linii kursora: blok testu — linia okna; okno programu — jednostka i linia w jej źródle.
    @MainActor
    static func breakpointAtCaret(_ ws: Workspace, _ doc: Document) -> Breakpoint? {
        let line = TextEditing.line(containing: doc.selectedRange.lowerBound, in: doc.text) + 1
        return breakpoint(ws, doc, documentLine: line)
    }

    @MainActor
    static func breakpoint(_ ws: Workspace, _ doc: Document, documentLine line: Int) -> Breakpoint? {
        switch doc.kind {
        case .test: return Breakpoint(document: doc.id.raw, line: line)
        case .program:
            // Linia 1 źródła jednostki = linia nagłówka CREATE (unit.line od 0).
            guard let u = ProgramCompiler.units(in: doc.text).last(where: { $0.line < line }) else { return nil }
            return Breakpoint(owner: u.owner, unit: u.name, type: u.type, line: line - u.line)
        default: return nil
        }
    }
}

extension Workspace {
    /// Przełącza punkt przerwania (ta sama jednostka/okno i linia — usuwa).
    public func toggleBreakpoint(_ bp: Breakpoint) {
        if let i = breakpoints.firstIndex(where: { $0.document == bp.document && $0.unit == bp.unit && $0.type == bp.type && $0.line == bp.line }) {
            breakpoints.remove(at: i)
        } else {
            breakpoints.append(bp)
        }
    }

    /// Linie dokumentu (od 1) z punktami przerwania — do znaczników w marginesie.
    public func breakpointLines(in doc: Document, onlyUnapplied: Bool = false) -> Set<Int> {
        switch doc.kind {
        case .test:
            return onlyUnapplied ? [] : Set(breakpoints.filter { $0.document == doc.id.raw }.map(\.line))
        case .program:
            var out = Set<Int>()
            for u in ProgramCompiler.units(in: doc.text) {
                for bp in breakpoints where bp.unit == u.name && bp.type == u.type && (!onlyUnapplied || unappliedBreakpoints.contains(bp.id)) {
                    out.insert(u.line + bp.line)
                }
            }
            return out
        default:
            return []
        }
    }

    /// Bieżąca linia debugera: blok testu — linia okna testu; jednostka — okno programu z jej źródłem (otwierane raz).
    public func showDebugLocation(_ d: DebuggerEngine, testDocument: Document) {
        for doc in documents { doc.executionLine = nil }
        guard d.state == .paused, let l = d.location else { return }
        if l.isTestBlock {
            testDocument.executionLine = l.line
            let o = ProgramCompiler.offset(line: l.line, column: 1, in: testDocument.text)
            testDocument.selectedRange = o..<o
            return
        }
        guard let type = l.objectType else { return }
        if let doc = documents.first(where: { $0.kind == .program && ProgramCompiler.units(in: $0.text).contains { $0.name == l.name && $0.type == type } }),
           let u = ProgramCompiler.units(in: doc.text).first(where: { $0.name == l.name && $0.type == type }) {
            doc.executionLine = u.line + l.line
            let o = ProgramCompiler.offset(line: u.line + l.line, column: 1, in: doc.text)
            doc.selectedRange = o..<o
            activate(doc.id)
            return
        }
        Task {
            try? await openObject(DBObject(owner: l.owner, name: l.name, type: type), line: l.line)
            if let doc = activeDocument, doc.kind == .program, let u = ProgramCompiler.units(in: doc.text).first(where: { $0.name == l.name && $0.type == type }) {
                doc.executionLine = u.line + l.line
            }
        }
    }
}

extension Workspace {
    /// Punkt przerwania dla linii dokumentu (klik w margines).
    public func breakpointAt(document doc: Document, line: Int) -> Breakpoint? {
        DebugCommands.breakpoint(self, doc, documentLine: line)
    }
}
