import Foundation

/// Wyszukiwarka czynności (PD-UI-012, D171) — wspólna dla pola „Szukaj czynności” na wstążce i palety komend.
/// Dopasowanie bez wielkości liter i polskich znaków („zrodlo” znajduje „źródło”), po początkach słów tytułu, po
/// słowach kluczowych (synonimy i angielskie nazwy znane z PL/SQL Developera), po tytułach w innym języku interfejsu,
/// po menu i opisie skutków. Kolejność: najpierw trafienia w tytule, potem w słowach kluczowych, menu i opisie.
public enum CommandSearch {
    public struct Match: Sendable {
        public let descriptor: CommandDescriptor
        public let score: Int
    }

    /// Tekst do porównań: małe litery, bez znaków diakrytycznych (ł → l).
    public static func fold(_ s: String) -> String {
        s.replacingOccurrences(of: "ł", with: "l").replacingOccurrences(of: "Ł", with: "L")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
    }

    private static func words(_ s: String) -> [Substring] {
        s.split { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "$" }
    }

    /// Komendy pasujące do zapytania (wszystkie słowa zapytania muszą się znaleźć), najlepsze pierwsze.
    /// - Parameter alternateTitles: dodatkowe nazwy komendy (np. tytuł w innym języku interfejsu).
    public static func search(_ query: String, in descriptors: [CommandDescriptor], limit: Int = 50,
                              alternateTitles: (CommandDescriptor) -> [String] = { _ in [] }) -> [Match] {
        let tokens = words(fold(query)).map(String.init)
        guard !tokens.isEmpty else { return [] }
        let whole = fold(query).trimmingCharacters(in: .whitespaces)
        var matches: [Match] = []
        for d in descriptors {
            let title = fold(d.title)
            let titleWords = words(title)
            let aliases = fold(([keywords[d.id.rawValue]].compactMap { $0 } + alternateTitles(d)).joined(separator: " "))
            let aliasWords = words(aliases)
            let path = fold("\(d.category.displayName) \(d.submenu ?? "") \(d.id.rawValue)")
            let summary = fold(d.summary)
            var score = 0
            var all = true
            for t in tokens {
                if titleWords.contains(where: { $0.hasPrefix(t) }) { score += 0 }
                else if title.contains(t) || aliasWords.contains(where: { $0.hasPrefix(t) }) { score += 2 }
                else if aliases.contains(t) || path.contains(t) { score += 4 }
                else if summary.contains(t) { score += 6 }
                else { all = false; break }
            }
            guard all else { continue }
            if title.hasPrefix(whole) { score -= 3 } else if title.contains(whole) { score -= 1 }
            matches.append(Match(descriptor: d, score: score))
        }
        matches.sort { a, b in
            if a.score != b.score { return a.score < b.score }
            return a.descriptor.title.localizedStandardCompare(b.descriptor.title) == .orderedAscending
        }
        return Array(matches.prefix(limit))
    }

    /// Słowa kluczowe komend: synonimy i nazwy funkcji wzorca (PL/SQL Developer, SQL Developer), których użytkownik
    /// może szukać zamiast polskiego tytułu.
    static let keywords: [String: String] = [
        "sql.execute": "uruchom run execute kompiluj compile F8",
        "sql.break": "stop anuluj cancel break",
        "session.commit": "commit zatwierdz transakcja",
        "session.rollback": "rollback wycofaj cofnij transakcja",
        "session.logon": "login logon polacz connect",
        "session.logoff": "logoff logout rozlacz disconnect",
        "file.new.sql": "sql window nowe zapytanie query",
        "file.new.program": "program window pakiet package procedura funkcja",
        "file.new.test": "test window",
        "file.new.command": "command window sqlplus sql*plus",
        "file.new.explainPlan": "explain plan window",
        "file.new.report": "report window",
        "file.new.diagram": "diagram window erd",
        "file.new.notebook": "notebook",
        "tools.findObjects": "find database objects szukaj obiektow",
        "tools.explainPlan": "explain plan plan wykonania",
        "tools.autotrace": "autotrace statystyki",
        "tools.sessions": "sessions sesje v$session",
        "tools.queryBuilder": "query builder kreator zapytan",
        "tools.exportTables": "export tables exp expdp",
        "tools.importTables": "import tables imp impdp",
        "tools.textImporter": "text importer csv",
        "tools.excelImporter": "odbc importer excel xlsx",
        "tools.dataGenerator": "data generator dane testowe",
        "tools.compareUserObjects": "compare user objects",
        "tools.compareTableData": "compare table data",
        "tools.exportUserObjects": "export user objects ddl",
        "tools.databaseDiff": "database diff porownaj schematy",
        "tools.dataTransfer": "copy data transfer kopiuj dane",
        "tools.scheduler": "dbms_scheduler jobs zadania",
        "tools.eventMonitor": "event monitor dbms_alert dbms_pipe",
        "tools.testManager": "test manager",
        "tools.configureTools": "configure tools user tools",
        "tools.schemaDoc": "pldoc dokumentacja",
        "edit.beautify": "beautifier pl/sql beautifier formatter formatuj",
        "edit.codeAssistant": "code assistant podpowiedzi autouzupelnianie completion",
        "edit.find": "find replace szukaj zamien",
        "edit.searchBar": "search bar find in files grep",
        "edit.refactorRename": "rename refactoring",
        "edit.recallStatement": "recall statement historia",
        "edit.commentLine": "comment komentarz",
        "edit.insertTemplate": "template szablon",
        "edit.analyzeCode": "lint code analysis",
        "debug.start": "debugger debug start",
        "debug.stepInto": "step into F7",
        "debug.stepOver": "step over F8",
        "debug.stepOut": "step out",
        "debug.toggleBreakpoint": "breakpoint punkt przerwania",
        "debug.breakpoints": "breakpoints punkty przerwania",
        "test.profiler": "profiler dbms_profiler dbms_hprof",
        "test.trace": "dbms_trace trace",
        "session.sqlTrace": "sql trace tkprof",
        "ob.queryData": "query data select dane pokaz",
        "ob.editData": "edit data edytuj dane",
        "ob.ddl": "ddl view sql dbms_metadata",
        "ob.describe": "describe desc opis",
        "ob.recompile": "recompile compile kompiluj",
        "ob.recompileSelected": "compile invalid objects kompiluj niepoprawne",
        "reports.invalidObjects": "invalid objects niepoprawne kompiluj",
        "grid.export": "export results csv excel html xml json",
        "grid.copyToExcel": "copy to excel xlsx",
        "grid.queryByExample": "query by example qbe",
        "grid.graph": "chart graph wykres",
        "grid.edit": "edit data edycja wierszy",
        "grid.post": "post zapisz zmiany",
        "grid.lastPage": "fetch all pobierz wszystko",
        "view.objectBrowser": "object browser drzewo obiektow",
        "view.fileBrowser": "file browser",
        "view.commandPalette": "command palette komendy",
        "view.ribbonSearch": "tell me szukaj czynnosci",
        "view.ribbon": "ribbon wstazka",
        "view.customizeToolbar": "toolbar customize",
        "help.manual": "help manual pomoc instrukcja",
        "help.context": "oracle documentation dokumentacja F1",
        "diagram.fromSchema": "er diagram model",
        "utplsql.runAll": "utplsql unit tests testy jednostkowe",
        "utplsql.coverage": "code coverage pokrycie",
        "prog.compareWithDatabase": "compare diff porownaj",
        "window.next": "next window ctrl tab",
        "window.previous": "previous window",
        "file.print": "print drukuj",
        "file.restoreRecovery": "recovery odzyskiwanie",
        "workset.open": "workset desktop",
        "project.show": "project projekt",
    ]
}
