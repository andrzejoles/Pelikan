import Foundation

/// Komendy wbudowane. Skróty profilu PL/SQL Developer: potwierdzone w UG 17 / na forum producenta albo oznaczone
/// „do weryfikacji” w docs/research/keys.md. Komendy zapowiedziane (`.planned`) są w menu wyszarzone do swojego etapu.
public enum BuiltinCommands {
    @MainActor
    public static var all: [Command] {
        file + edit + session + debug + tools + reports + view + window + help
    }

    private static func newDocument(_ kind: DocumentKind, id: String, title: String, pd: [String] = [], mac: [String]? = nil,
                                    feature: String) -> Command {
        Command(CommandDescriptor(
            id: CommandID(rawValue: id), title: title, category: .file, submenu: L10n.tr("Nowy"), pd: pd, mac: mac,
            agent: .full, effect: .uiState, summary: L10n.tr("Otwiera nowe puste okno: \(kind.displayName)."), feature: feature
        )) { ctx in
            let doc = ctx.workspace.newDocument(kind)
            return CommandResult(message: doc.fullTitle, value: .object(["document": .string(doc.id.description)]))
        }
    }

    // MARK: Plik

    @MainActor static var file: [Command] {
        [
            newDocument(.sql, id: "file.new.sql", title: L10n.tr("Okno SQL"), mac: ["cmd+n"], feature: "PD-SQLW-002"),
            newDocument(.program, id: "file.new.program", title: L10n.tr("Okno programu"), mac: ["cmd+shift+n"], feature: "PD-PROG-001"),
            newDocument(.test, id: "file.new.test", title: L10n.tr("Okno testu"), feature: "PD-TEST-001"),
            newDocument(.command, id: "file.new.command", title: L10n.tr("Okno poleceń"), feature: "PD-CMDW-001"),
            newDocument(.explainPlan, id: "file.new.explainPlan", title: L10n.tr("Okno planu (Explain Plan)"), feature: "PD-OPT-001"),
            newDocument(.report, id: "file.new.report", title: L10n.tr("Okno raportu"), feature: "PD-REP-002"),
            newDocument(.diagram, id: "file.new.diagram", title: L10n.tr("Okno diagramu"), feature: "PD-DIAG-001"),
            newDocument(.notebook, id: "file.new.notebook", title: L10n.tr("Notatnik SQL"), feature: "SD-NB-001"),
            .planned(CommandDescriptor(id: "file.open", title: L10n.tr("Otwórz…"), category: .file, mac: ["cmd+o"],
                                       agent: .none, effect: .external, summary: L10n.tr("Otwiera plik w odpowiednim oknie."),
                                       stage: 1, feature: "PD-SQLW-012")),
            .planned(CommandDescriptor(id: "file.save", title: L10n.tr("Zapisz"), category: .file, mac: ["cmd+s"],
                                       agent: .full, effect: .external, summary: L10n.tr("Zapisuje okno do pliku."),
                                       stage: 1, feature: "PD-SQLW-012")),
            .planned(CommandDescriptor(id: "file.saveAs", title: L10n.tr("Zapisz jako…"), category: .file, mac: ["cmd+shift+s"],
                                       agent: .none, effect: .external, summary: L10n.tr("Zapisuje okno pod nową nazwą."),
                                       stage: 1, feature: "PD-SQLW-012")),
            Command(CommandDescriptor(id: "file.close", title: L10n.tr("Zamknij okno"), category: .file, mac: ["cmd+w"],
                                      agent: .full, effect: .uiState, summary: L10n.tr("Zamyka bieżące okno."), feature: "PD-UI-004"),
                    validate: { $0.activeDocument != nil }) { ctx in
                guard let doc = ctx.workspace.activeDocument else { return .ok }
                ctx.workspace.close(doc.id)
                return .ok
            },
            Command(CommandDescriptor(id: "file.closeAll", title: L10n.tr("Zamknij wszystkie okna"), category: .file,
                                      mac: ["cmd+alt+w"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zamyka wszystkie okna."), feature: "PD-UI-004"),
                    validate: { !$0.documents.isEmpty }) { ctx in
                for d in ctx.workspace.documents { ctx.workspace.close(d.id) }
                return .ok
            },
            .planned(CommandDescriptor(id: "file.print", title: L10n.tr("Drukuj…"), category: .file, mac: ["cmd+p"],
                                       agent: .none, effect: .external, summary: L10n.tr("Drukuje bieżące okno."),
                                       stage: 8, feature: "PD-SQLW-016")),
        ]
    }

    // MARK: Edycja

    @MainActor static var edit: [Command] {
        [
            .planned(CommandDescriptor(id: "edit.find", title: L10n.tr("Znajdź i zamień…"), category: .edit, pd: ["ctrl+f"], mac: ["cmd+f"],
                                       agent: .full, effect: .uiState, summary: L10n.tr("Wyszukiwanie i zamiana w edytorze."),
                                       stage: 1, feature: "PD-EDIT-008")),
            .planned(CommandDescriptor(id: "edit.gotoLine", title: L10n.tr("Przejdź do linii…"), category: .edit, pd: ["ctrl+g"], mac: ["cmd+l"],
                                       agent: .full, effect: .uiState, summary: L10n.tr("Przenosi kursor do linii."),
                                       stage: 1, feature: "PD-EDIT-010")),
            .planned(CommandDescriptor(id: "edit.recallStatement", title: L10n.tr("Historia poleceń…"), category: .edit, pd: ["ctrl+e"],
                                       mac: ["cmd+shift+h"], agent: .read, effect: .uiState,
                                       summary: L10n.tr("Wstawia wcześniej wykonane polecenie."), stage: 1, feature: "PD-EDIT-009")),
            .planned(CommandDescriptor(id: "edit.commentLine", title: L10n.tr("Komentarz linii"), category: .edit, submenu: L10n.tr("Zaznaczenie"),
                                       pd: ["ctrl+-"], mac: ["cmd+/"], agent: .full, effect: .modifiesEditor,
                                       summary: L10n.tr("Dodaje lub usuwa -- na początku linii."), stage: 1, feature: "PD-EDIT-006")),
            .planned(CommandDescriptor(id: "edit.duplicateLine", title: L10n.tr("Powiel linię"), category: .edit, submenu: L10n.tr("Zaznaczenie"),
                                       mac: ["cmd+shift+d"], agent: .full, effect: .modifiesEditor,
                                       summary: L10n.tr("Powiela bieżącą linię."), stage: 1, feature: "PD-EDIT-020")),
            .planned(CommandDescriptor(id: "edit.uppercase", title: L10n.tr("Wielkie litery"), category: .edit, submenu: L10n.tr("Zaznaczenie"),
                                       agent: .full, effect: .modifiesEditor,
                                       summary: L10n.tr("Zamienia zaznaczenie na wielkie litery (bez literałów)."), stage: 1, feature: "PD-EDIT-005")),
            .planned(CommandDescriptor(id: "edit.lowercase", title: L10n.tr("Małe litery"), category: .edit, submenu: L10n.tr("Zaznaczenie"),
                                       agent: .full, effect: .modifiesEditor,
                                       summary: L10n.tr("Zamienia zaznaczenie na małe litery (bez literałów)."), stage: 1, feature: "PD-EDIT-005")),
            .planned(CommandDescriptor(id: "edit.beautify", title: L10n.tr("Formatuj kod (PL/SQL Beautifier)"), category: .edit,
                                       mac: ["cmd+shift+f"], agent: .full, effect: .modifiesEditor,
                                       summary: L10n.tr("Formatuje kod według reguł."), stage: 2, feature: "PD-BEAU-002")),
            .planned(CommandDescriptor(id: "edit.macroRecord", title: L10n.tr("Nagrywaj makro"), category: .edit, submenu: L10n.tr("Makra"),
                                       pd: ["f11"], agent: .none, effect: .uiState,
                                       summary: L10n.tr("Rozpoczyna lub kończy nagrywanie makra."), stage: 6, feature: "PD-EDIT-015")),
            .planned(CommandDescriptor(id: "edit.macroPlay", title: L10n.tr("Odtwórz makro"), category: .edit, submenu: L10n.tr("Makra"),
                                       pd: ["f12"], agent: .none, effect: .modifiesEditor,
                                       summary: L10n.tr("Odtwarza nagrane makro."), stage: 6, feature: "PD-EDIT-015")),
        ]
    }

    // MARK: Sesja

    @MainActor static var session: [Command] {
        [
            .planned(CommandDescriptor(id: "session.logon", title: L10n.tr("Zaloguj…"), category: .session,
                                       agent: .none, effect: .settings, summary: L10n.tr("Łączy się z bazą."),
                                       stage: 1, feature: "PD-CONN-002")),
            .planned(CommandDescriptor(id: "session.logoff", title: L10n.tr("Wyloguj"), category: .session,
                                       agent: .none, effect: .settings, summary: L10n.tr("Rozłącza połączenie główne."),
                                       stage: 1, feature: "PD-CONN-018")),
            .planned(CommandDescriptor(id: "sql.execute", title: L10n.tr("Wykonaj"), category: .session, pd: ["f8"], mac: ["cmd+enter"],
                                       agent: .none, effect: .modifiesDatabase,
                                       summary: L10n.tr("Wykonuje zaznaczenie albo polecenie pod kursorem (AutoSelect) lub wszystkie polecenia okna."),
                                       stage: 1, feature: "PD-SQLW-002")),
            .planned(CommandDescriptor(id: "sql.executeAlternate", title: L10n.tr("Wykonaj (odwrotnie do AutoSelect)"), category: .session,
                                       pd: ["ctrl+f8"], mac: ["cmd+shift+enter"], agent: .none, effect: .modifiesDatabase,
                                       summary: L10n.tr("Wykonuje wszystkie polecenia albo polecenie pod kursorem — odwrotnie niż Wykonaj."),
                                       stage: 1, feature: "PD-SQLW-003")),
            .planned(CommandDescriptor(id: "sql.break", title: L10n.tr("Przerwij"), category: .session, pd: ["shift+escape"], mac: ["cmd+."],
                                       agent: .none, effect: .none, summary: L10n.tr("Przerywa bieżące wykonanie (OCIBreak)."),
                                       stage: 1, feature: "PD-SQLW-005")),
            .planned(CommandDescriptor(id: "session.commit", title: L10n.tr("Zatwierdź (COMMIT)"), category: .session, pd: ["f10"],
                                       mac: ["cmd+alt+enter"], agent: .approval, effect: .transaction,
                                       summary: L10n.tr("Zatwierdza transakcję sesji okna."), stage: 1, feature: "PD-SQLW-014")),
            .planned(CommandDescriptor(id: "session.rollback", title: L10n.tr("Wycofaj (ROLLBACK)"), category: .session, pd: ["shift+f10"],
                                       mac: ["cmd+alt+backspace"], agent: .approval, effect: .transaction,
                                       summary: L10n.tr("Wycofuje transakcję sesji okna."), stage: 1, feature: "PD-SQLW-014")),
            .planned(CommandDescriptor(id: "session.kill", title: L10n.tr("Zakończ sesję okna (Kill)"), category: .session,
                                       agent: .none, effect: .modifiesDatabase, summary: L10n.tr("Kończy sesję bazy okna, gdy Przerwij nie działa."),
                                       stage: 1, feature: "PD-CONN-027")),
            .planned(CommandDescriptor(id: "session.setPassword", title: L10n.tr("Zmień hasło…"), category: .session,
                                       agent: .none, effect: .settings, summary: L10n.tr("Zmienia hasło w bazie i w definicji połączenia."),
                                       stage: 1, feature: "PD-CONN-017")),
            .planned(CommandDescriptor(id: "session.sqlTrace", title: L10n.tr("SQL Trace"), category: .session,
                                       agent: .none, effect: .settings, summary: L10n.tr("Włącza lub wyłącza SQL Trace sesji okna."),
                                       stage: 3, feature: "PD-OPT-008")),
        ]
    }

    // MARK: Debugowanie (skróty do weryfikacji — docs/research/keys.md)

    @MainActor static var debug: [Command] {
        let d: [(String, String, [String], String)] = [
            ("debug.start", L10n.tr("Rozpocznij debugowanie"), ["f9"], L10n.tr("Uruchamia skrypt testu z debugerem.")),
            ("debug.run", L10n.tr("Kontynuuj"), ["ctrl+r"], L10n.tr("Wykonuje do następnego punktu przerwania.")),
            ("debug.stepInto", L10n.tr("Wejdź"), ["ctrl+n"], L10n.tr("Wchodzi do wywołania w bieżącej linii.")),
            ("debug.stepOver", L10n.tr("Przejdź"), ["ctrl+o"], L10n.tr("Wykonuje bieżącą linię bez wchodzenia.")),
            ("debug.stepOut", L10n.tr("Wyjdź"), ["ctrl+t"], L10n.tr("Wykonuje do końca bieżącej jednostki.")),
            ("debug.runToCursor", L10n.tr("Wykonaj do kursora"), [], L10n.tr("Wykonuje do linii z kursorem.")),
            ("debug.runToException", L10n.tr("Wykonaj do wyjątku"), [], L10n.tr("Wykonuje do wystąpienia wyjątku.")),
            ("debug.toggleBreakpoint", L10n.tr("Punkt przerwania"), ["ctrl+b"], L10n.tr("Ustawia lub usuwa punkt przerwania w linii.")),
            ("debug.breakpoints", L10n.tr("Punkty przerwania…"), [], L10n.tr("Edycja punktów przerwania, warunków i komunikatów.")),
        ]
        return d.map { id, title, pd, summary in
            .planned(CommandDescriptor(id: CommandID(rawValue: id), title: title, category: .debug, pd: pd, mac: pd.isEmpty ? [] : nil,
                                       agent: .none, effect: .modifiesDatabase, summary: summary, stage: 3, feature: "PD-DBG-001"))
        }
    }

    // MARK: Narzędzia

    @MainActor static var tools: [Command] {
        let t: [(String, String, [String], Int, String, AgentAccess)] = [
            ("tools.explainPlan", L10n.tr("Explain Plan"), ["f5"], 6, "PD-OPT-002", .read),
            ("tools.queryBuilder", L10n.tr("Query Builder…"), [], 6, "PD-QB-001", .none),
            ("tools.findObjects", L10n.tr("Znajdź obiekty bazy…"), [], 2, "PD-TOOL-001", .read),
            ("tools.compileInvalid", L10n.tr("Kompiluj niepoprawne obiekty…"), [], 2, "PD-TOOL-002", .approval),
            ("tools.sessions", L10n.tr("Sesje"), [], 6, "PD-TOOL-015", .read),
            ("tools.scheduler", L10n.tr("DBMS Scheduler"), [], 6, "PD-SCHED-001", .read),
            ("tools.exportTables", L10n.tr("Eksport tabel…"), [], 6, "PD-TOOL-003", .none),
            ("tools.importTables", L10n.tr("Import tabel…"), [], 6, "PD-TOOL-006", .none),
            ("tools.exportUserObjects", L10n.tr("Eksport obiektów użytkownika…"), [], 6, "PD-TOOL-007", .none),
            ("tools.compareUserObjects", L10n.tr("Porównaj obiekty użytkowników…"), [], 6, "PD-TOOL-012", .read),
            ("tools.compareTableData", L10n.tr("Porównaj dane tabel…"), [], 6, "PD-TOOL-013", .read),
            ("tools.textImporter", L10n.tr("Import tekstu…"), [], 6, "PD-TOOL-008", .none),
            ("tools.excelImporter", L10n.tr("Import z Excela…"), [], 6, "PD-TOOL-009", .none),
            ("tools.dataGenerator", L10n.tr("Generator danych…"), [], 6, "PD-TOOL-011", .none),
            ("tools.eventMonitor", L10n.tr("Monitor zdarzeń…"), [], 6, "PD-TOOL-014", .none),
            ("tools.testManager", L10n.tr("Menedżer testów…"), [], 6, "PD-TOOL-018", .none),
            ("tools.loadTester", L10n.tr("Test obciążenia…"), [], 6, "PD-TOOL-019", .none),
            ("utplsql.runAll", L10n.tr("utPLSQL: uruchom wszystkie testy"), [], 4, "UT-RUN-001", .approval),
            ("utplsql.runPath", L10n.tr("utPLSQL: uruchom testy ze ścieżki…"), [], 4, "UT-RUN-002", .approval),
            ("utplsql.coverage", L10n.tr("utPLSQL: pokrycie kodu…"), [], 4, "UT-COV-001", .approval),
        ]
        return t.map { id, title, pd, stage, feature, agent in
            .planned(CommandDescriptor(id: CommandID(rawValue: id), title: title, category: .tools, pd: pd, mac: pd.isEmpty ? [] : nil,
                                       agent: agent, effect: agent == .approval ? .modifiesDatabase : .none,
                                       summary: title, stage: stage, feature: feature))
        }
    }

    @MainActor static var reports: [Command] {
        [
            .planned(CommandDescriptor(id: "reports.compilationErrors", title: L10n.tr("Błędy kompilacji"), category: .reports,
                                       agent: .read, effect: .none, summary: L10n.tr("Raport błędów kompilacji obiektów."),
                                       stage: 6, feature: "PD-REP-001")),
        ]
    }

    // MARK: Widok

    @MainActor static var view: [Command] {
        [
            Command(CommandDescriptor(id: "view.commandPalette", title: L10n.tr("Paleta komend…"), category: .view,
                                      pd: ["cmd+shift+p"], mac: ["cmd+shift+p"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Wyszukuje i wykonuje komendę po nazwie."), feature: "PD-UI-007")) { ctx in
                ctx.ui?.showCommandPalette()
                return .ok
            },
            .planned(CommandDescriptor(id: "view.objectBrowser", title: L10n.tr("Przeglądarka obiektów"), category: .view,
                                       agent: .none, effect: .uiState, summary: L10n.tr("Pokazuje lub ukrywa Przeglądarkę obiektów."),
                                       stage: 2, feature: "PD-OB-001")),
            .planned(CommandDescriptor(id: "view.connectionList", title: L10n.tr("Lista połączeń"), category: .view,
                                       agent: .none, effect: .uiState, summary: L10n.tr("Pokazuje lub ukrywa Listę połączeń."),
                                       stage: 1, feature: "PD-CONN-003")),
        ]
    }

    // MARK: Okno

    @MainActor static var window: [Command] {
        [
            Command(CommandDescriptor(id: "window.next", title: L10n.tr("Następne okno"), category: .window,
                                      pd: ["ctrl+tab"], mac: ["cmd+shift+]", "ctrl+tab"], agent: .full, effect: .uiState,
                                      summary: L10n.tr("Aktywuje następne okno z Listy okien."), feature: "PD-UI-004"),
                    validate: { $0.documents.count > 1 }) { ctx in
                ctx.workspace.cycleDocuments(forward: true)
                return .ok
            },
            Command(CommandDescriptor(id: "window.previous", title: L10n.tr("Poprzednie okno"), category: .window,
                                      pd: ["ctrl+shift+tab"], mac: ["cmd+shift+[", "ctrl+shift+tab"], agent: .full, effect: .uiState,
                                      summary: L10n.tr("Aktywuje poprzednie okno z Listy okien."), feature: "PD-UI-004"),
                    validate: { $0.documents.count > 1 }) { ctx in
                ctx.workspace.cycleDocuments(forward: false)
                return .ok
            },
        ]
    }

    // MARK: Pomoc

    @MainActor static var help: [Command] {
        [
            .planned(CommandDescriptor(id: "help.context", title: L10n.tr("Pomoc kontekstowa (dokumentacja Oracle)"), category: .help,
                                       pd: ["f1"], mac: ["f1"], agent: .none, effect: .external,
                                       summary: L10n.tr("Szuka słowa pod kursorem w dokumentacji Oracle."), stage: 2, feature: "PD-EDIT-026")),
        ]
    }
}
