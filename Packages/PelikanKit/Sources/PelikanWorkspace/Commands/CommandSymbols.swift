import Foundation

/// Ikony komend (symbole SF) na pasku narzędzi, wstążce i w wyszukiwarce czynności (PD-UI-006, PD-UI-012).
public enum CommandSymbols {
    /// Symbol komendy albo nil (komenda bez własnej ikony).
    public static func symbol(for id: String) -> String? { map[id] }

    static let map: [String: String] = [
        // Plik
        "file.new.sql": "doc.badge.plus", "file.new.program": "curlybraces", "file.new.test": "testtube.2", "file.new.command": "terminal",
        "file.new.explainPlan": "chart.bar.doc.horizontal", "file.new.report": "doc.richtext", "file.new.diagram": "point.3.connected.trianglepath.dotted",
        "file.new.notebook": "book.pages", "file.newFromTemplate": "doc.on.doc", "file.pasteAsSQLWindow": "doc.on.clipboard",
        "file.openWithConnection": "folder.badge.person.crop", "file.open": "folder", "file.save": "square.and.arrow.down",
        "file.saveAs": "square.and.arrow.down.on.square", "file.print": "printer", "file.restoreRecovery": "arrow.clockwise.circle",
        "file.readOnly": "lock", "file.encoding": "textformat", "file.localHistory": "clock.arrow.circlepath",
        "file.close": "xmark.square", "file.closeAll": "xmark.square.fill", "file.closeOthers": "rectangle.stack.badge.minus",
        "edit.findNext": "chevron.down.circle", "edit.findPrevious": "chevron.up.circle", "sql.toggleSubstitution": "character.textbox",
        "debug.run": "forward.frame", "prog.safeCompile": "hammer.circle", "tools.compileInvalid": "hammer",
        "tools.importWizard": "wand.and.rays", "tools.schemaCopy": "doc.on.doc.fill", "reports.tableColumns": "tablecells",
        "session.console": "apple.terminal", "tools.cart": "cart", "ob.recycleBin": "trash.circle",
        // Wykonanie, transakcja, połączenie
        "sql.execute": "play.fill", "sql.break": "stop.fill", "sql.executeAlternate": "play", "window.execute": "play.rectangle",
        "sql.historyBack": "chevron.backward", "sql.historyForward": "chevron.forward", "edit.recallStatement": "clock",
        "session.commit": "checkmark.circle", "session.rollback": "arrow.uturn.backward.circle", "session.logon": "person.badge.key",
        "session.logoff": "person.crop.circle.badge.xmark", "session.windowConnection": "cylinder", "window.reconnect": "arrow.triangle.2.circlepath",
        "session.sqlTrace": "waveform.path.ecg", "session.kill": "xmark.octagon", "session.setPassword": "key",
        "cmd.executeLine": "text.line.first.and.arrowtriangle.forward", "cmd.pause": "pause.fill",
        // Szukaj, edycja
        "tools.findObjects": "doc.text.magnifyingglass", "edit.find": "magnifyingglass", "edit.searchBar": "text.magnifyingglass",
        "project.find": "folder.badge.questionmark", "edit.beautify": "text.alignleft", "edit.uppercase": "textformat.size.larger",
        "edit.lowercase": "textformat.size.smaller", "edit.commentLine": "text.bubble", "edit.indent": "increase.indent",
        "edit.outdent": "decrease.indent", "edit.removeTrailingSpaces": "eraser", "edit.codeAssistant": "text.cursor",
        "edit.insertSnippet": "text.badge.plus", "edit.insertTemplate": "doc.text", "edit.pasteFromHistory": "list.clipboard",
        "edit.duplicateLine": "plus.square.on.square", "edit.gotoLine": "arrow.right.to.line", "edit.gotoDeclaration": "arrow.up.forward.square",
        "edit.findUsages": "link", "edit.navigateBack": "arrow.backward", "edit.navigateForward": "arrow.forward",
        "edit.fold": "chevron.up.chevron.down", "edit.unfold": "chevron.down", "edit.foldAll": "rectangle.compress.vertical",
        "edit.unfoldAll": "rectangle.expand.vertical", "edit.refactorRename": "character.cursor.ibeam", "edit.analyzeCode": "checkmark.seal",
        "edit.nextProblem": "exclamationmark.triangle", "edit.previousProblem": "exclamationmark.triangle.fill",
        "edit.showProblems": "list.bullet.rectangle", "edit.toggleCodeAnalysis": "eye", "edit.toggleBookmark": "bookmark",
        // Obiekty
        "ob.queryData": "tablecells", "ob.edit": "pencil", "ob.editData": "tablecells.badge.ellipsis", "ob.ddl": "doc.plaintext",
        "ob.describe": "info.circle", "ob.properties": "list.bullet.rectangle.portrait", "ob.recompile": "hammer", "ob.test": "testtube.2",
        "ob.recompileSelected": "hammer.fill", "ob.ddlSelected": "doc.on.doc", "ob.dropSelected": "trash", "ob.drop": "trash",
        "ob.refresh": "arrow.clockwise", "ob.applyFilter": "line.3.horizontal.decrease.circle", "file.newTable": "tablecells.badge.ellipsis",
        "file.newView": "eye", "view.objectBrowser": "sidebar.left", "tools.databaseDiff": "arrow.left.arrow.right.square",
        "tools.compareUserObjects": "rectangle.on.rectangle", "tools.compareTableData": "tablecells.fill", "tools.exportUserObjects": "shippingbox",
        "diagram.fromSchema": "point.3.connected.trianglepath.dotted", "tools.schemaDoc": "book", "reports.invalidObjects": "exclamationmark.octagon",
        "reports.compilationErrors": "xmark.circle", "tools.dualityViews": "curlybraces.square", "tools.mleModules": "chevron.left.forwardslash.chevron.right",
        // Debugowanie i testy
        "debug.start": "ladybug", "debug.stepInto": "arrow.down.to.line", "debug.stepOver": "arrow.turn.down.right", "debug.stepOut": "arrow.up.to.line",
        "debug.runToCursor": "arrow.right.to.line.compact", "debug.runToException": "bolt.trianglebadge.exclamationmark",
        "debug.stop": "stop.circle", "debug.executeInTarget": "terminal", "debug.toggleBreakpoint": "smallcircle.filled.circle", "debug.breakpoints": "list.bullet.circle",
        "debug.saveBreakpoints": "square.and.arrow.down", "debug.loadBreakpoints": "square.and.arrow.up", "debug.grantPrivileges": "lock.open",
        "utplsql.runAll": "checkmark.diamond", "utplsql.runEditor": "play.diamond", "utplsql.rerunFailed": "arrow.counterclockwise",
        "utplsql.coverage": "chart.pie", "utplsql.explorer": "list.bullet.indent", "utplsql.cancel": "stop.circle",
        "utplsql.generateTest": "wand.and.stars", "utplsql.toggleTest": "arrow.left.arrow.right", "codeContents.test": "testtube.2",
        "test.saveAsStandard": "star", "test.saveAsSQLPlus": "terminal", "prog.runBlock": "play.square", "test.profiler": "stopwatch",
        "test.profilerRuns": "list.number", "test.profilerOpenRun": "folder", "test.trace": "point.topleft.down.to.point.bottomright.curvepath",
        "test.traceRuns": "clock.arrow.circlepath", "tools.testManager": "checklist", "testManager.run": "play.circle",
        // Narzędzia
        "tools.explainPlan": "list.bullet.indent", "tools.autotrace": "speedometer", "tools.instanceViewer": "server.rack",
        "tools.sessions": "person.2", "view.dba": "cylinder.split.1x2", "tools.scheduler": "calendar.badge.clock",
        "tools.eventMonitor": "bell", "tools.queryBuilder": "square.grid.3x3.topleft.filled", "tools.exportTables": "square.and.arrow.up.on.square",
        "tools.importTables": "square.and.arrow.down.on.square", "tools.dataTransfer": "arrow.left.arrow.right",
        "tools.compareFiles": "doc.on.doc", "tools.compareTexts": "text.append", "tools.configureTools": "wrench",
        "tools.localTasks": "clock.badge.checkmark", "tools.documents": "books.vertical",
        // Raporty
        "reports.predefined": "doc.text.below.ecg", "reports.recentChanges": "clock.badge", "reports.tableSizes": "chart.bar",
        "reports.privileges": "lock.shield", "reports.sessions": "person.2",
        // Widok
        "view.fileBrowser": "folder", "view.snippets": "text.badge.plus", "view.taskMonitor": "gearshape.2", "view.clipboardHistory": "list.clipboard",
        "view.todoItems": "checklist", "grid.valuePanel": "rectangle.bottomhalf.inset.filled", "view.templateWindow": "macwindow",
        "view.codeContents": "list.bullet.indent", "view.splitEditor": "rectangle.split.1x2", "view.wordWrap": "text.word.spacing",
        "view.specialCharacters": "paragraphsign", "view.lineStatus": "line.3.horizontal", "view.zoomIn": "plus.magnifyingglass",
        "view.zoomOut": "minus.magnifyingglass", "view.zoomReset": "1.magnifyingglass", "window.previous": "chevron.left.square",
        "window.next": "chevron.right.square", "window.rename": "character.cursor.ibeam", "view.saveLayout": "rectangle.3.group",
        "view.restoreLayout": "rectangle.3.group.fill", "view.autosaveLayout": "arrow.triangle.2.circlepath", "view.ribbon": "menubar.rectangle", "view.ribbonCollapse": "rectangle.compress.vertical",
        "view.customizeToolbar": "slider.horizontal.3", "view.toolDockRight": "sidebar.right", "view.toolDockBottom": "rectangle.bottomthird.inset.filled",
        "view.toolDockAutoHide": "eye.slash", "view.dockToolRight": "rectangle.righthalf.inset.filled", "view.dockToolBottom": "dock.arrow.down.rectangle",
        "view.floatTool": "macwindow.on.rectangle", "view.closeTool": "xmark.rectangle", "help.manual": "book.closed", "help.context": "questionmark.circle",
        "help.oracleManuals": "books.vertical", "view.commandPalette": "command.square", "help.log": "doc.text.below.ecg", "help.exportLog": "square.and.arrow.up.on.square", "help.reportProblem": "exclamationmark.bubble", "view.ribbonSearch": "magnifyingglass.circle",
        // Wynik
        "sql.refreshResult": "arrow.clockwise", "sql.autoRefresh": "timer", "grid.nextPage": "arrow.down.doc", "grid.lastPage": "arrow.down.to.line",
        "sql.toggleEditor": "rectangle.tophalf.inset.filled", "grid.edit": "pencil", "grid.insertRecord": "plus.rectangle",
        "grid.deleteRecord": "minus.rectangle", "grid.post": "checkmark.rectangle", "grid.cancelChanges": "xmark.rectangle",
        "grid.revertRowChanges": "arrow.uturn.backward", "grid.filterByValue": "line.3.horizontal.decrease.circle",
        "grid.filterExpression": "function", "grid.clearFilter": "line.3.horizontal.decrease.circle.fill", "grid.queryByExample": "rectangle.and.pencil.and.ellipsis",
        "grid.groupBy": "square.stack.3d.down.right", "grid.export": "square.and.arrow.up", "grid.copyWithHeader": "doc.on.clipboard",
        "grid.copyToExcel": "tablecells", "grid.copyAs": "doc.on.doc", "grid.graph": "chart.xyaxis.line", "grid.totals": "sum",
        "grid.toggleRecordView": "list.bullet.rectangle", "sql.pinResult": "pin", "sql.pinAllResults": "pin.fill", "sql.clearResults": "xmark.bin",
        // Program
        "prog.addUnit": "plus.square", "prog.removeUnit": "minus.square", "prog.reloadFromDatabase": "arrow.down.circle",
        "prog.checkChanges": "exclamationmark.arrow.triangle.2.circlepath", "prog.revert": "arrow.uturn.backward.square",
        "prog.compareWithDatabase": "arrow.left.arrow.right.square", "prog.compareWithFile": "doc.on.doc", "prog.compareWithConnection": "cylinder.split.1x2",
        // Kontekstowe: plan, diagram, raport, notatnik
        "plan.compare": "arrow.left.arrow.right", "plan.export": "square.and.arrow.down", "diagram.addObject": "plus.app",
        "diagram.addRelated": "link", "diagram.addReferences": "arrow.triangle.branch", "diagram.addNote": "note.text", "diagram.addGroup": "square.dashed",
        "diagram.delete": "trash", "diagram.updateFromDB": "arrow.clockwise", "diagram.showColumns": "list.bullet",
        "diagram.zoom": "plus.magnifyingglass", "diagram.toggleGrid": "grid", "diagram.export": "photo", "diagram.copyImage": "doc.on.clipboard",
        "diagram.print": "printer", "report.execute": "play.fill", "report.saveHTML": "safari", "report.export": "square.and.arrow.up",
        "report.print": "printer", "report.lock": "lock", "report.unlock": "lock.open", "report.addToMenu": "text.badge.plus",
        "notebook.runAll": "forward.fill", "notebook.runCell": "play.fill", "notebook.exportMarkdown": "arrow.down.doc",
        "notebook.addSQLCell": "plus.rectangle", "notebook.addMarkdownCell": "text.badge.plus",
        // Agent AI (komendy aplikacji, AgentUICommands)
        "agent.togglePane": "sidebar.right", "agent.undoSession": "arrow.uturn.backward.circle", "agent.endSession": "stop.circle",
        "agent.showLog": "list.bullet.clipboard",
    ]
}
