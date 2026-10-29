import Foundation

/// Element grupy wstążki (PD-UI-012, D171): przycisk komendy z rejestru albo lista rozwijana komend.
public enum RibbonItem: Sendable, Hashable {
    /// Duży przycisk — ikona nad podpisem; `label` zastępuje tytuł komendy, gdy ten jest za długi.
    case large(String, label: String? = nil)
    /// Mały przycisk — ikona obok podpisu, po trzy w kolumnie.
    case small(String, label: String? = nil)
    /// Lista rozwijana: tytuł, symbol i komendy (`-` — separator, `prefiks.*` — wszystkie komendy menu z tym prefiksem,
    /// także dodane przez użytkownika, np. formaty kopiowania i raporty).
    case menu(String, symbol: String, commands: [String], large: Bool = false)

    /// Komendy elementu (bez separatorów).
    public var commands: [String] {
        switch self {
        case .large(let id, _), .small(let id, _): [id]
        case .menu(_, _, let ids, _): ids.filter { $0 != RibbonModel.separator }
        }
    }
}

public struct RibbonGroup: Sendable, Hashable {
    public let title: String
    public let items: [RibbonItem]

    public init(_ title: String, _ items: [RibbonItem]) {
        self.title = title
        self.items = items
    }
}

public struct RibbonTab: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    /// Karta kontekstowa: widoczna tylko przy aktywnym oknie jednego z tych rodzajów.
    public let context: [DocumentKind]
    public let groups: [RibbonGroup]

    public init(_ id: String, _ title: String, context: [DocumentKind] = [], _ groups: [RibbonGroup]) {
        self.id = id
        self.title = title
        self.context = context
        self.groups = groups
    }

    public var isContextual: Bool { !context.isEmpty }
    public var commands: [String] { groups.flatMap { $0.items.flatMap(\.commands) } }
}

/// Wstążka okna głównego (PD-UI-012, D171): karty z grupami komend z rejestru — każda czynność jednym kliknięciem,
/// bez szukania w menu i bez pamiętania skrótów. Karty kontekstowe pojawiają się przy oknie danego rodzaju (program,
/// wynik zapytania, diagram, raport, notatnik, plan, okno poleceń) i są wybierane same; wstążka pamięta, którą kartę
/// wybrano ostatnio przy oknie każdego rodzaju (`RibbonSelection`). Komendy rzadsze są w listach rozwijanych grup,
/// a wszystkie — w wyszukiwarce czynności (`CommandSearch`).
public enum RibbonModel {
    public static let separator = "-"

    @MainActor public static var tabs: [RibbonTab] {
        [start, edit, database, debug, tools, reports, view, result, program, command, plan, diagram, report, notebook]
    }

    /// Karty widoczne przy aktywnym oknie danego rodzaju: stałe i kontekstowe tego rodzaju.
    @MainActor public static func visibleTabs(for kind: DocumentKind?) -> [RibbonTab] {
        tabs.filter { !$0.isContextual || kind.map($0.context.contains) == true }
    }

    /// Komendy listy po rozwinięciu wzorców `prefiks.*` (komendy z menu, bez wyjątków `notOnRibbon`).
    @MainActor public static func expand(_ ids: [String], in registry: CommandRegistry) -> [String] {
        ids.flatMap { id -> [String] in
            guard id.hasSuffix(".*") else { return [id] }
            let prefix = String(id.dropLast())
            return registry.descriptors.filter { $0.inMenu && $0.id.rawValue.hasPrefix(prefix) && !notOnRibbon.contains($0.id.rawValue) }
                .map(\.id.rawValue)
        }
    }

    /// Karta wybierana przy pierwszym przejściu do okna danego rodzaju.
    public static func defaultTab(for kind: DocumentKind?) -> String {
        switch kind {
        case .program: "program"
        case .sql, .command: "start"
        case .test: "debug"
        case .explainPlan: "plan"
        case .diagram: "diagram"
        case .report: "report"
        case .notebook: "notebook"
        case nil: "start"
        }
    }

    /// Miejsce komendy na wstążce (karta i grupa) — pierwsze wystąpienie, karty stałe przed kontekstowymi.
    @MainActor public static func location(of id: String) -> (tab: RibbonTab, group: RibbonGroup)? {
        for tab in tabs {
            for group in tab.groups where group.items.contains(where: { $0.commands.contains(id) }) { return (tab, group) }
        }
        return nil
    }

    /// Komendy menu, których celowo nie ma na wstążce: wywoływane z miejsca, którego dotyczą (karta okna, lista ostatnich
    /// plików w menu Plik, przeciągnięcie obiektu), albo zastąpione na wstążce inną komendą.
    public static let notOnRibbon: Set<String> = [
        "file.closeWindow", "file.reopen", "ob.dropText", "ob.dropOnWorkspace", "tools.saveObjectSearch", "tools.deleteObjectSearch",
        "reports.predefined.run", "reports.predefined.worksheet",
    ]

    // MARK: Karty stałe

    @MainActor static var start: RibbonTab {
        RibbonTab("start", L10n.tr("Start"), [
            RibbonGroup(L10n.tr("Nowe"), [
                .large("file.new.sql", label: L10n.tr("Okno SQL")),
                .large("file.new.program", label: L10n.tr("Okno programu")),
                .small("file.new.test", label: L10n.tr("Okno testu")),
                .small("file.new.command", label: L10n.tr("Okno poleceń")),
                .menu(L10n.tr("Inne okna"), symbol: "plus.rectangle.on.rectangle", commands: [
                    "file.new.explainPlan", "file.new.report", "file.new.diagram", "file.new.notebook", separator,
                    "file.newFromTemplate", "file.pasteAsSQLWindow", "file.openWithConnection",
                ]),
            ]),
            RibbonGroup(L10n.tr("Plik"), [
                .small("file.open"), .small("file.save"), .small("file.saveAs"),
                .small("file.print"), .small("file.restoreRecovery", label: L10n.tr("Odzyskaj okna")),
                .menu(L10n.tr("Więcej"), symbol: "ellipsis.circle", commands: [
                    "file.saveAsSingleFile", "file.readOnly", "file.encoding", separator, "file.localHistory", "file.localHistoryList", "file.localHistoryCheckpoint",
                    "file.localHistoryCompare", "file.localHistoryRestore", separator, "app.openStartupParameters",
                ]),
            ]),
            RibbonGroup(L10n.tr("Wykonanie"), [
                .large("sql.execute"),
                .small("sql.break"), .small("sql.executeAlternate", label: L10n.tr("Wykonaj odwrotnie")),
                .small("window.execute"), .small("sql.toggleSubstitution"),
            ]),
            RibbonGroup(L10n.tr("Transakcja"), [
                .large("session.commit", label: L10n.tr("COMMIT")),
                .large("session.rollback", label: L10n.tr("ROLLBACK")),
            ]),
            RibbonGroup(L10n.tr("Połączenie"), [
                .large("session.logon", label: L10n.tr("Zaloguj")),
                .small("session.windowConnection", label: L10n.tr("Połączenie okna")),
                .small("window.reconnect"), .small("session.logoff", label: L10n.tr("Wyloguj")),
                .menu(L10n.tr("Połączenia"), symbol: "cylinder.split.1x2", commands: [
                    "connection.new", "connection.edit", "connection.duplicate", "connection.delete", "connection.newFolder", separator,
                    "connection.connect", "connection.connectAsMain", "connection.disconnect", "connection.setCurrentSchema", separator,
                    "connection.openWindow", "connection.showWindows", "connection.closeWindows", "connection.reconnectWindows", separator,
                    "connection.import", "connection.export", "connection.exportWithPasswords", separator, "session.console",
                ]),
            ]),
            RibbonGroup(L10n.tr("Szukaj"), [
                .large("tools.findObjects", label: L10n.tr("Znajdź obiekty")),
                .small("edit.find", label: L10n.tr("Znajdź i zamień")),
                .small("edit.searchBar", label: L10n.tr("Szukaj w plikach")),
                .small("project.find", label: L10n.tr("Szukaj w projekcie")),
                .small("edit.findNext"), .small("edit.findPrevious"),
                .small("edit.replace"), .small("edit.replaceAll"),
            ]),
            RibbonGroup(L10n.tr("Historia"), [
                .small("sql.historyBack", label: L10n.tr("Poprzednie polecenie")),
                .small("sql.historyForward", label: L10n.tr("Następne polecenie")),
                .small("edit.recallStatement", label: L10n.tr("Historia poleceń")),
            ]),
        ])
    }

    @MainActor static var edit: RibbonTab {
        RibbonTab("edit", L10n.tr("Edycja"), [
            RibbonGroup(L10n.tr("Formatowanie"), [
                .large("edit.beautify", label: L10n.tr("Formatuj kod")),
                .small("edit.uppercase"), .small("edit.lowercase"), .small("edit.commentLine"),
                .small("edit.indent"), .small("edit.outdent"), .small("edit.removeTrailingSpaces"),
            ]),
            RibbonGroup(L10n.tr("Wstawianie"), [
                .large("edit.codeAssistant"),
                .small("edit.insertSnippet"), .small("edit.insertTemplate", label: L10n.tr("Wstaw szablon")),
                .small("edit.pasteFromHistory", label: L10n.tr("Wklej z historii")),
                .small("edit.duplicateLine"),
                .menu(L10n.tr("To-Do"), symbol: "checklist", commands: ["edit.todoInsert", "edit.todoToggle", "view.todoItems"]),
                .menu(L10n.tr("Więcej"), symbol: "ellipsis.circle", commands: [
                    "edit.deleteNextWord", "edit.firstCharacterOnLine", separator, "edit.refreshCodeAssistant",
                    "edit.openInExternalEditor", "edit.webSearch",
                ]),
                .menu(L10n.tr("Kod w innym języku"), symbol: "chevron.left.forwardslash.chevron.right", commands: [
                    "edit.pasteHostLanguage", separator, "edit.specialCopy.*",
                ]),
            ]),
            RibbonGroup(L10n.tr("Nawigacja"), [
                .small("edit.gotoLine", label: L10n.tr("Przejdź do linii")), .small("edit.gotoDeclaration"), .small("edit.findUsages"),
                .small("edit.navigateBack"), .small("edit.navigateForward"),
                .menu(L10n.tr("Zakładki"), symbol: "bookmark", commands: [
                    "edit.toggleBookmark", "edit.gotoBookmark", "edit.nextBookmark", "edit.previousBookmark", separator,
                    "edit.renameBookmark", "edit.bookmarkList", "edit.clearBookmarks",
                ]),
            ]),
            RibbonGroup(L10n.tr("Zwijanie"), [
                .small("edit.fold"), .small("edit.unfold"), .small("edit.foldAll"), .small("edit.unfoldAll"),
                .menu(L10n.tr("Zawartość kodu"), symbol: "list.bullet.indent", commands: [
                    "view.codeContents", separator, "codeContents.select", "codeContents.copy", "codeContents.cut", "codeContents.test", separator,
                    "codeHierarchy.select", "codeHierarchy.goto",
                ]),
            ]),
            RibbonGroup(L10n.tr("Refaktoryzacja"), [
                .large("edit.refactorRename", label: L10n.tr("Zmień nazwę")),
                .menu(L10n.tr("Wydziel"), symbol: "rectangle.portrait.and.arrow.right", commands: [
                    "edit.extractLocalConstant", "edit.extractGlobalConstant", "edit.extractProcedure", separator,
                    "edit.replaceAssignmentWithInitialization",
                ]),
            ]),
            RibbonGroup(L10n.tr("Analiza kodu"), [
                .large("edit.analyzeCode", label: L10n.tr("Analizuj")),
                .small("edit.nextProblem"), .small("edit.previousProblem"), .small("edit.showProblems"),
                .small("edit.toggleCodeAnalysis", label: L10n.tr("Analiza w czasie pisania")),
            ]),
            RibbonGroup(L10n.tr("Kursory i makra"), [
                .menu(L10n.tr("Kursory"), symbol: "character.cursor.ibeam", commands: ["edit.addCursorAbove", "edit.addCursorBelow", "edit.singleCursor"]),
                .menu(L10n.tr("Makra"), symbol: "record.circle", commands: [
                    "edit.macroRecord", "edit.macroPlay", "edit.macroRepeat", separator, "edit.macroSave", "edit.macroLibrary",
                ]),
                .menu(L10n.tr("Znaczniki"), symbol: "highlighter", commands: ["edit.colorMark", "edit.clearColorMarks"]),
            ]),
        ])
    }

    @MainActor static var database: RibbonTab {
        RibbonTab("database", L10n.tr("Obiekty"), [
            RibbonGroup(L10n.tr("Obiekt"), [
                .large("ob.queryData", label: L10n.tr("Pokaż dane")),
                .large("ob.edit", label: L10n.tr("Edytuj")),
                .small("ob.editData"), .small("ob.ddl"), .small("ob.describe"),
                .small("ob.properties"), .small("ob.recompile"), .small("ob.test"),
                .menu(L10n.tr("Więcej"), symbol: "ellipsis.circle", commands: [
                    "ob.drop", "ob.rename", "ob.renameChild", "ob.duplicate", separator,
                    "ob.copyName", "ob.copyNames", "ob.addSourceToEditor", "ob.addToFolder", separator,
                    "ob.addDebugInfo", "ob.ccflags", "ob.standardTest", "ob.standardQuery", "ob.generateCode", "ob.viewEditor", "ob.editTable", separator,
                    "ob.enable", "ob.disable", "ob.refreshMV", "ob.testLink", "ob.runJob", "ob.startQueue", "ob.stopQueue", separator,
                    "ob.compare", "ob.compareWithConnection", "ob.utplsqlRun",
                ]),
            ]),
            RibbonGroup(L10n.tr("Zaznaczone"), [
                .small("ob.recompileSelected"), .small("ob.ddlSelected"), .small("ob.dropSelected"),
            ]),
            RibbonGroup(L10n.tr("Utwórz"), [
                .large("file.newTable", label: L10n.tr("Tabela")),
                .large("file.newView", label: L10n.tr("Widok")),
                .menu(L10n.tr("Nowy obiekt"), symbol: "plus.square.on.square", commands: [
                    "file.newViewEditor", "file.newSequence", "file.newSynonym", "file.newIndex", "file.newDomain", "file.newAssertion", separator,
                    "file.newUser", "file.newRole", "file.newProfile", separator,
                    "file.newLibrary", "file.newDirectory", "file.newDatabaseLink", "file.newJob", "file.newQueue", separator,
                    "tools.dualityViewDDL",
                ], large: true),
            ]),
            RibbonGroup(L10n.tr("Przeglądarka"), [
                .large("view.objectBrowser", label: L10n.tr("Przeglądarka obiektów")),
                .small("ob.refresh", label: L10n.tr("Odśwież")),
                .small("ob.applyFilter", label: L10n.tr("Filtr nazwany")),
                .small("tools.findObjects", label: L10n.tr("Znajdź obiekty")),
                .menu(L10n.tr("Kosz"), symbol: "trash.circle", commands: ["ob.recycleBin", "ob.restoreFromRecycleBin", "ob.purgeRecycleBin"]),
            ]),
            RibbonGroup(L10n.tr("Porównanie"), [
                .large("tools.databaseDiff"),
                .small("tools.compareUserObjects", label: L10n.tr("Porównaj obiekty")),
                .small("tools.compareTableData", label: L10n.tr("Porównaj dane")),
                .small("tools.exportUserObjects", label: L10n.tr("Eksport obiektów")),
            ]),
            RibbonGroup(L10n.tr("Schemat"), [
                .large("diagram.fromSchema", label: L10n.tr("Diagram ER")),
                .small("tools.compileInvalid", label: L10n.tr("Kompiluj niepoprawne")),
                .small("reports.invalidObjects"), .small("reports.compilationErrors"),
                .small("tools.schemaDoc", label: L10n.tr("Dokumentacja")),
            ]),
            RibbonGroup(L10n.tr("Oracle 23ai"), [
                .small("tools.dualityViews"), .small("tools.mleModules"),
                .menu(L10n.tr("MLE i REST"), symbol: "curlybraces.square", commands: [
                    "tools.importMLEModule", "tools.debugMLE", separator, "tools.ordsModules", "tools.ordsEnableSchema", "tools.ordsEnableObject",
                ]),
            ]),
        ])
    }

    @MainActor static var debug: RibbonTab {
        RibbonTab("debug", L10n.tr("Debugowanie i testy"), [
            RibbonGroup(L10n.tr("Debuger"), [
                .large("debug.start", label: L10n.tr("Debuguj")),
                .small("debug.run"), .small("debug.stepInto"), .small("debug.stepOver"), .small("debug.stepOut"),
                .small("debug.runToCursor"), .small("debug.runToException"), .small("debug.stop", label: L10n.tr("Zatrzymaj")),
                .small("debug.executeInTarget", label: L10n.tr("SQL w sesji")),
            ]),
            RibbonGroup(L10n.tr("Punkty przerwania"), [
                .large("debug.toggleBreakpoint"),
                .small("debug.breakpoints", label: L10n.tr("Lista")), .small("debug.saveBreakpoints", label: L10n.tr("Zapisz")),
                .small("debug.loadBreakpoints", label: L10n.tr("Wczytaj")),
            ]),
            RibbonGroup(L10n.tr("utPLSQL"), [
                .large("utplsql.runAll", label: L10n.tr("Wszystkie testy")),
                .small("utplsql.runEditor", label: L10n.tr("Test pod kursorem")),
                .small("utplsql.rerunFailed", label: L10n.tr("Ponów nieudane")),
                .small("utplsql.coverage", label: L10n.tr("Z pokryciem kodu")),
                .small("utplsql.explorer", label: L10n.tr("Eksplorator testów")),
                .small("utplsql.cancel", label: L10n.tr("Przerwij")),
                .menu(L10n.tr("Więcej"), symbol: "ellipsis.circle", commands: [
                    "utplsql.runPath", "utplsql.runWithOptions", "utplsql.debugTest", separator,
                    "utplsql.generateTest", "utplsql.toggleTest", separator, "utplsql.export", "utplsql.cliScript", separator,
                    "utplsql.version", "utplsql.install",
                ]),
            ]),
            RibbonGroup(L10n.tr("Okno testu"), [
                .large("file.new.test", label: L10n.tr("Nowy test")),
                .small("test.saveAsStandard", label: L10n.tr("Zapisz jako standardowy")),
                .small("test.saveAsSQLPlus", label: L10n.tr("Zapisz jako SQL*Plus")),
                .small("prog.runBlock", label: L10n.tr("Blok w oknie testu")),
            ]),
            RibbonGroup(L10n.tr("Profiler i ślad"), [
                .small("test.profiler", label: L10n.tr("Profiler")), .small("test.profilerRuns"), .small("test.profilerOpenRun", label: L10n.tr("Otwórz przebieg")),
                .small("test.trace", label: L10n.tr("Ślad DBMS_TRACE")), .small("test.traceRuns", label: L10n.tr("Historia śladów")),
            ]),
            RibbonGroup(L10n.tr("Test Manager"), [
                .large("tools.testManager"),
                .small("testManager.run", label: L10n.tr("Uruchom zestaw")),
                .small("debug.grantPrivileges"),
            ]),
        ])
    }

    @MainActor static var tools: RibbonTab {
        RibbonTab("tools", L10n.tr("Narzędzia"), [
            RibbonGroup(L10n.tr("Wydajność"), [
                .large("tools.explainPlan"),
                .small("tools.autotrace"), .small("session.sqlTrace"), .small("tools.instanceViewer"),
                .menu(L10n.tr("Pakiety Oracle"), symbol: "gauge.with.dots.needle.67percent", commands: [
                    "tools.awrReport", "tools.ashReport", "tools.addmReport", separator, "tools.sqlMonitor", "tools.sqlMonitorReport",
                    "tools.sqlTuningAdvisor", separator, "stats.export",
                ]),
            ]),
            RibbonGroup(L10n.tr("Sesje i baza"), [
                .large("tools.sessions"),
                .small("view.dba"), .small("tools.scheduler"), .small("tools.eventMonitor", label: L10n.tr("Monitor zdarzeń")),
                .menu(L10n.tr("Administracja"), symbol: "wrench.and.screwdriver", commands: [
                    "session.kill", "session.setPassword", separator, "dba.alterParameter", "dba.lockUser", separator, "tools.loadTester",
                ]),
            ]),
            RibbonGroup(L10n.tr("Dane"), [
                .large("tools.queryBuilder", label: L10n.tr("Query Builder")),
                .small("tools.exportTables", label: L10n.tr("Eksport tabel")), .small("tools.importTables", label: L10n.tr("Import tabel")),
                .small("tools.dataTransfer", label: L10n.tr("Przenoszenie danych")),
                .small("tools.importWizard", label: L10n.tr("Kreator importu")), .small("tools.schemaCopy", label: L10n.tr("Kopiuj schemat")),
                .menu(L10n.tr("Więcej"), symbol: "ellipsis.circle", commands: [
                    "tools.textImporter", "tools.excelImporter", "tools.dataGenerator", separator, "transfer.run",
                ]),
            ]),
            RibbonGroup(L10n.tr("Porównaj"), [
                .small("tools.compareFiles", label: L10n.tr("Pliki")), .small("tools.compareTexts", label: L10n.tr("Teksty")),
                .small("tools.databaseDiff"),
            ]),
            RibbonGroup(L10n.tr("Wdrożenie"), [
                .menu(L10n.tr("Koszyk"), symbol: "cart", commands: ["tools.cart", "cart.script"], large: true),
                .menu(L10n.tr("Git"), symbol: "arrow.triangle.branch", commands: ["vcs.status", "vcs.diff", "vcs.log", separator, "vcs.add", "vcs.commit"], large: true),
                .menu(L10n.tr("Zdalny Pro*C"), symbol: "server.rack", commands: [
                    "proc.deploy", "proc.console", "proc.stop", "proc.history", "proc.gitStatus", "proc.rollback", "proc.releaseLock", separator,
                    "ssh.manager", "ssh.test", "ssh.import", "ssh.export",
                ], large: true),
            ]),
            RibbonGroup(L10n.tr("Inne"), [
                .small("tools.configureTools", label: L10n.tr("Narzędzia użytkownika")),
                .small("tools.localTasks", label: L10n.tr("Zadania lokalne")), .small("tools.documents"),
                .menu(L10n.tr("Szablony"), symbol: "doc.text", commands: [
                    "templates.save", "templates.edit", "templates.delete", separator, "templates.newFolder", "templates.renameFolder", "templates.deleteFolder",
                ]),
                .menu(L10n.tr("Preferencje"), symbol: "gearshape", commands: ["prefs.sets", "prefs.export", "prefs.import", separator, "localTasks.runNow"]),
            ]),
            // Komendy panelu agenta rejestruje aplikacja (AgentUICommands); uruchamianie — po profilu z Preferencji › Agenci.
            RibbonGroup(L10n.tr("Agent AI"), [
                .large("agent.togglePane"),
                .menu(L10n.tr("Uruchom agenta"), symbol: "sparkles", commands: ["agent.launch.*"], large: true),
                .small("agent.undoSession", label: L10n.tr("Cofnij sesję")), .small("agent.endSession", label: L10n.tr("Zakończ sesję")),
                .small("agent.showLog", label: L10n.tr("Dziennik agentów")),
            ]),
        ])
    }

    @MainActor static var reports: RibbonTab {
        RibbonTab("reports", L10n.tr("Raporty"), [
            RibbonGroup(L10n.tr("Raporty"), [
                .large("reports.predefined", label: L10n.tr("Wszystkie raporty")),
                .large("file.new.report", label: L10n.tr("Nowy raport")),
            ]),
            RibbonGroup(L10n.tr("Obiekty"), [
                .small("reports.invalidObjects"), .small("reports.compilationErrors"), .small("reports.recentChanges"),
                .small("reports.tableSizes"), .small("reports.tableColumns"),
            ]),
            RibbonGroup(L10n.tr("Bezpieczeństwo i sesje"), [
                .small("reports.privileges"), .small("reports.sessions", label: L10n.tr("Sesje")),
            ]),
            RibbonGroup(L10n.tr("Wszystkie"), [
                .menu(L10n.tr("Raporty z menu"), symbol: "list.bullet.rectangle", commands: ["reports.*"], large: true),
            ]),
        ])
    }

    @MainActor static var view: RibbonTab {
        RibbonTab("view", L10n.tr("Widok"), [
            RibbonGroup(L10n.tr("Panele"), [
                .small("view.objectBrowser"), .small("view.fileBrowser"), .small("view.snippets"),
                .small("view.taskMonitor"), .small("view.clipboardHistory"), .small("view.todoItems"),
                .small("grid.valuePanel"), .small("view.templateWindow"), .small("view.codeContents"),
                .small("agent.togglePane"),
            ]),
            RibbonGroup(L10n.tr("Edytor"), [
                .small("view.splitEditor"), .small("view.wordWrap"), .small("view.specialCharacters"),
                .small("view.lineStatus"), .small("view.zoomIn", label: L10n.tr("Powiększ")), .small("view.zoomOut", label: L10n.tr("Pomniejsz")),
                .small("view.zoomReset", label: L10n.tr("Domyślny rozmiar")),
            ]),
            RibbonGroup(L10n.tr("Okna"), [
                .small("window.previous"), .small("window.next"), .small("window.rename"),
                .small("file.close"), .small("file.closeAll"), .small("file.closeOthers"),
                .menu(L10n.tr("Więcej"), symbol: "ellipsis.circle", commands: ["file.closeLeft", "file.closeRight", separator, "window.listSort"]),
            ]),
            RibbonGroup(L10n.tr("Układ"), [
                .small("view.saveLayout"), .small("view.restoreLayout"), .small("view.autosaveLayout"),
                .small("view.ribbon"), .small("view.ribbonCollapse"), .small("view.customizeToolbar", label: L10n.tr("Dostosuj pasek")),
            ]),
            RibbonGroup(L10n.tr("Panele narzędzi"), [
                .small("view.toolDockRight", label: L10n.tr("Panel po prawej")), .small("view.toolDockBottom", label: L10n.tr("Panel na dole")),
                .small("view.toolDockAutoHide", label: L10n.tr("Autoukrywanie")),
                .menu(L10n.tr("Narzędzie"), symbol: "rectangle.portrait.on.rectangle.portrait", commands: [
                    "view.dockToolRight", "view.dockToolBottom", "view.floatTool", separator, "view.closeTool",
                ]),
            ]),
            RibbonGroup(L10n.tr("Projekt i workset"), [
                .menu(L10n.tr("Projekt"), symbol: "folder.badge.gearshape", commands: [
                    "project.show", "project.new", "project.open", "project.close", separator, "project.addActiveFile", "project.addSelectedObject",
                    "project.addFiles", "project.addNote", separator, "project.build", "project.make", "project.find", separator, "project.saveDesktop", "project.openDesktop",
                ], large: true),
                .menu(L10n.tr("Workset"), symbol: "square.stack.3d.up", commands: [
                    "workset.new", "workset.open", "workset.save", "workset.revert", "workset.close", separator, "workset.compare",
                    "workset.delete", "workset.toggleAutosave",
                ], large: true),
                .menu(L10n.tr("Pliki"), symbol: "folder", commands: [
                    "view.fileBrowser", separator, "fb.addLocation", "fb.removeLocation", separator, "fb.open", "fb.rename", "fb.newFolder", "fb.newFile",
                    "fb.trash", "fb.showInFinder", separator, "fb.toggleHidden", "fb.clearFilterHistory",
                ], large: true),
            ]),
            RibbonGroup(L10n.tr("Pomoc"), [
                .small("help.manual"), .small("help.context", label: L10n.tr("Pomoc kontekstowa")), .small("help.oracleManuals"),
                .small("view.commandPalette"), .small("view.ribbonSearch"), .small("help.log"), .small("help.exportLog"), .small("help.reportProblem"),
            ]),
        ])
    }

    // MARK: Karty kontekstowe

    @MainActor static var result: RibbonTab {
        RibbonTab("result", L10n.tr("Wynik"), context: [.sql], [
            RibbonGroup(L10n.tr("Wykonanie"), [
                .large("sql.execute"),
                .small("sql.break"), .small("sql.refreshResult", label: L10n.tr("Odśwież")), .small("sql.autoRefresh", label: L10n.tr("Autoodświeżanie")),
            ]),
            RibbonGroup(L10n.tr("Pobieranie"), [
                .small("grid.nextPage"), .small("grid.lastPage", label: L10n.tr("Pobierz wszystkie")),
                .small("sql.toggleEditor"),
            ]),
            RibbonGroup(L10n.tr("Edycja danych"), [
                .large("grid.edit"),
                .small("grid.insertRecord"), .small("grid.deleteRecord"), .small("grid.post", label: L10n.tr("Zatwierdź (Post)")),
                .small("grid.cancelChanges"), .small("grid.revertRowChanges"),
                .menu(L10n.tr("Zmiany"), symbol: "pencil.and.list.clipboard", commands: [
                    "grid.nextPendingChange", "grid.previousPendingChange", "grid.copyChangesSQL", separator,
                    "grid.chooseDate", "grid.largeData", "grid.upperCase", "grid.lowerCase",
                ]),
            ]),
            RibbonGroup(L10n.tr("Transakcja"), [
                .small("session.commit"), .small("session.rollback"),
            ]),
            RibbonGroup(L10n.tr("Filtr"), [
                .small("grid.filterByValue", label: L10n.tr("Według wartości")), .small("grid.filterExpression", label: L10n.tr("Wyrażenie")),
                .small("grid.clearFilter"), .small("grid.queryByExample"), .small("grid.groupBy", label: L10n.tr("Grupuj")),
                .menu(L10n.tr("Kolumny"), symbol: "tablecells", commands: [
                    "grid.columnFilter", "grid.clearColumnFilter", "grid.clearQueryByExample", separator, "grid.selectColumn", "grid.selectBlock",
                ]),
            ]),
            RibbonGroup(L10n.tr("Kopiuj i eksport"), [
                .large("grid.export", label: L10n.tr("Eksportuj")),
                .small("grid.copyWithHeader"), .small("grid.copyToExcel"), .small("grid.copyAs"),
                .menu(L10n.tr("Więcej"), symbol: "ellipsis.circle", commands: [
                    "grid.copy", "grid.copyHeader", "grid.copyExpressionList", separator, "grid.generateSQL", "sql.exportQuery", "grid.columnToFiles",
                    separator, "grid.saveAsStandardQuery",
                ]),
            ]),
            RibbonGroup(L10n.tr("Analiza"), [
                .small("grid.graph", label: L10n.tr("Wykres")), .small("grid.totals", label: L10n.tr("Sumy")), .small("grid.toggleRecordView", label: L10n.tr("Rekord")),
                .menu(L10n.tr("Więcej"), symbol: "ellipsis.circle", commands: [
                    "grid.compareRecords", "grid.compareResults", "grid.clearTotals", separator, "grid.columnInfo", "grid.valueList",
                    "grid.linkedQueries", "grid.openCursor", "grid.spatialPreview",
                ]),
            ]),
            RibbonGroup(L10n.tr("Karty wyników"), [
                .small("sql.pinResult"), .small("sql.pinAllResults"), .small("sql.clearResults"),
                .menu(L10n.tr("Wygląd"), symbol: "textformat.size", commands: [
                    "grid.align", "grid.rowHeight", "grid.saveAlignTemplate", "grid.removeAlignTemplate", separator,
                    "grid.fontLarger", "grid.fontSmaller", "grid.fontReset", separator, "grid.numberLayout", "grid.toggleRowNumbers",
                    "grid.largeDataAutoFormat",
                ]),
            ]),
        ])
    }

    @MainActor static var program: RibbonTab {
        RibbonTab("program", L10n.tr("Program"), context: [.program], [
            RibbonGroup(L10n.tr("Kompilacja"), [
                .large("sql.execute", label: L10n.tr("Kompiluj")),
                .small("prog.safeCompile"), .small("sql.break"), .small("prog.runBlock", label: L10n.tr("Uruchom w oknie testu")),
                .small("edit.beautify", label: L10n.tr("Formatuj kod")),
            ]),
            RibbonGroup(L10n.tr("Jednostki"), [
                .small("prog.selectUnit", label: L10n.tr("Pokaż jednostkę")), .small("prog.previousUnit", label: L10n.tr("Poprzednia")),
                .small("prog.nextUnit", label: L10n.tr("Następna")),
                .small("prog.addUnit", label: L10n.tr("Dodaj jednostkę")), .small("prog.removeUnit", label: L10n.tr("Usuń jednostkę")),
                .small("view.codeContents"),
            ]),
            RibbonGroup(L10n.tr("Źródło w bazie"), [
                .small("prog.reloadFromDatabase", label: L10n.tr("Wczytaj z bazy")), .small("prog.checkChanges", label: L10n.tr("Sprawdź zmiany")),
                .small("prog.revert"),
            ]),
            RibbonGroup(L10n.tr("Porównaj"), [
                .small("prog.compareWithDatabase", label: L10n.tr("Ze źródłem w bazie")), .small("prog.compareWithFile", label: L10n.tr("Z plikiem")),
                .small("prog.compareWithConnection", label: L10n.tr("Z inną bazą")),
            ]),
            RibbonGroup(L10n.tr("Testy i debuger"), [
                .large("debug.start", label: L10n.tr("Debuguj")),
                .small("debug.toggleBreakpoint"), .small("utplsql.runEditor", label: L10n.tr("Test pod kursorem")),
                .small("utplsql.toggleTest", label: L10n.tr("Test ⇄ pakiet")),
                .small("utplsql.generateTest", label: L10n.tr("Generuj test")), .small("codeContents.test", label: L10n.tr("Testuj podprogram")),
            ]),
        ])
    }

    @MainActor static var command: RibbonTab {
        RibbonTab("command", L10n.tr("Okno poleceń"), context: [.command], [
            RibbonGroup(L10n.tr("Wykonanie"), [
                .large("sql.execute"), .small("cmd.executeLine"), .small("cmd.pause"), .small("sql.break"),
            ]),
            RibbonGroup(L10n.tr("Transakcja"), [
                .large("session.commit", label: L10n.tr("COMMIT")), .large("session.rollback", label: L10n.tr("ROLLBACK")),
            ]),
        ])
    }

    @MainActor static var plan: RibbonTab {
        RibbonTab("plan", L10n.tr("Plan"), context: [.explainPlan], [
            RibbonGroup(L10n.tr("Plan wykonania"), [
                .large("sql.execute", label: L10n.tr("Wyznacz plan")), .small("plan.compare", label: L10n.tr("Porównaj z poprzednim")),
                .small("plan.export", label: L10n.tr("Zapisz plan")), .small("tools.autotrace"),
            ]),
        ])
    }

    @MainActor static var diagram: RibbonTab {
        RibbonTab("diagram", L10n.tr("Diagram"), context: [.diagram], [
            RibbonGroup(L10n.tr("Elementy"), [
                .large("diagram.addObject", label: L10n.tr("Dodaj obiekt")),
                .small("diagram.addRelated", label: L10n.tr("Powiązane tabele")), .small("diagram.addReferences", label: L10n.tr("Zależności")),
                .small("diagram.addNote", label: L10n.tr("Notatka")), .small("diagram.addGroup", label: L10n.tr("Grupa")),
                .small("diagram.delete", label: L10n.tr("Usuń")), .small("diagram.updateFromDB", label: L10n.tr("Aktualizuj z bazy")),
            ]),
            RibbonGroup(L10n.tr("Widok"), [
                .small("diagram.showColumns", label: L10n.tr("Kolumny")), .small("diagram.zoom", label: L10n.tr("Powiększenie")),
                .small("diagram.toggleGrid", label: L10n.tr("Siatka")),
            ]),
            RibbonGroup(L10n.tr("Eksport"), [
                .small("diagram.export", label: L10n.tr("Jako obraz")), .small("diagram.copyImage", label: L10n.tr("Kopiuj obraz")),
                .small("diagram.print", label: L10n.tr("Drukuj")),
            ]),
        ])
    }

    @MainActor static var report: RibbonTab {
        RibbonTab("report", L10n.tr("Raport"), context: [.report], [
            RibbonGroup(L10n.tr("Raport"), [
                .large("report.execute", label: L10n.tr("Wykonaj raport")),
                .small("report.saveHTML", label: L10n.tr("Zapisz HTML")), .small("report.export", label: L10n.tr("Eksportuj dane")),
                .small("report.print", label: L10n.tr("Drukuj")),
            ]),
            RibbonGroup(L10n.tr("Definicja"), [
                .small("report.lock", label: L10n.tr("Zablokuj")), .small("report.unlock", label: L10n.tr("Odblokuj")),
                .small("report.addToMenu", label: L10n.tr("Dodaj do menu")),
            ]),
        ])
    }

    @MainActor static var notebook: RibbonTab {
        RibbonTab("notebook", L10n.tr("Notatnik"), context: [.notebook], [
            RibbonGroup(L10n.tr("Notatnik"), [
                .large("notebook.runAll", label: L10n.tr("Wykonaj wszystko")),
                .small("notebook.runCell", label: L10n.tr("Wykonaj komórkę")), .small("sql.break"),
                .small("notebook.exportMarkdown", label: L10n.tr("Eksportuj Markdown")),
            ]),
            // Usuwanie, przestawianie i wykres — przyciski w komórce (komendy z numerem komórki).
            RibbonGroup(L10n.tr("Komórki"), [
                .small("notebook.addSQLCell", label: L10n.tr("Komórka SQL")),
                .small("notebook.addMarkdownCell", label: L10n.tr("Komórka Markdown")),
            ]),
        ])
    }
}

/// Wybór karty wstążki: zapamiętana karta dla każdego rodzaju okna (pierwszy raz — karta domyślna rodzaju).
public struct RibbonSelection: Sendable, Equatable {
    private var remembered: [String: String] = [:]

    public init() {}

    private static func key(_ kind: DocumentKind?) -> String { kind?.rawValue ?? "-" }

    /// Karta dla okna danego rodzaju spośród `visible` (zapamiętana, domyślna rodzaju albo pierwsza).
    public func tab(for kind: DocumentKind?, visible: [String]) -> String? {
        if let r = remembered[Self.key(kind)], visible.contains(r) { return r }
        let d = RibbonModel.defaultTab(for: kind)
        return visible.contains(d) ? d : visible.first
    }

    /// Użytkownik wybrał kartę przy oknie danego rodzaju.
    public mutating func select(_ tab: String, for kind: DocumentKind?) {
        remembered[Self.key(kind)] = tab
    }
}
