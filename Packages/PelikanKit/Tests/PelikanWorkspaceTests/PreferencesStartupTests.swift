import Foundation
import PelikanDB
import PelikanSQL
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Zestawy preferencji, eksport i import, parametry startowe, pasek narzędzi")
struct PreferencesStartupTests {
    func connection(_ ws: Workspace, name: String, user: String, db: String) throws -> ConnectionDefinition {
        let def = ConnectionDefinition(name: name, target: ConnectionTarget(user: user, connectString: db))
        try ws.connections.upsert(def)
        return def
    }

    @Test("Pierwszeństwo: osobisty połączenia > osobisty > domyślny połączenia > domyślny; źródło wartości; wzorce")
    func precedence() throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let prod = try connection(ws, name: "Produkcja", user: "APP", db: "prod-host/svc")
        try ws.savePreferenceSet(PreferenceSet(name: "Firma", kind: .defaultGlobal, values: ["tabSize": .int(8), "editorFontSize": .int(15)]))
        try ws.savePreferenceSet(PreferenceSet(name: "Prod", kind: .defaultConnection, pattern: "app@prod*", values: ["autoCommitSQL": .bool(false), "tabSize": .int(6)]))
        try ws.savePreferenceSet(PreferenceSet(name: "Moja prod", kind: .personalConnection, pattern: "Produkcja", values: ["tabSize": .int(3)]))
        #expect(ws.settings.tabSize == 8 && ws.settings.editorFontSize == 15)
        ws.settings.editorFontSize = 12          // osobisty użytkownika
        #expect(ws.personalPreferences["editorFontSize"] == .int(12) && ws.settings.editorFontSize == 12)
        ws.sessions.setMainConnection(prod.id)
        #expect(ws.settings.tabSize == 3 && ws.settings.editorFontSize == 12)
        #expect(ws.preferenceSource(of: "tabSize")?.name == "Moja prod")
        #expect(ws.preferenceSource(of: "autoCommitSQL")?.name == "Prod")
        #expect(ws.preferenceSource(of: "highlightCurrentLine") == nil)
        try ws.inheritPreference("tabSize", in: try #require(ws.preferenceSets.first { $0.name == "Moja prod" }).id)
        #expect(ws.settings.tabSize == 6)
        ws.sessions.setMainConnection(nil)
        #expect(ws.settings.tabSize == 8)
        // Zestawy i zestaw osobisty po ponownym uruchomieniu.
        let ws2 = Workspace(dataDirectory: t.url)
        #expect(ws2.settings.editorFontSize == 12 && ws2.settings.tabSize == 8 && ws2.preferenceSets.count == 3)
        #expect(PreferenceSets.matches("app@prod*", "APP@prod-host/svc") && !PreferenceSets.matches("app@test%", "APP@prod-host/svc"))
        #expect(PreferenceSets.matches("a_c", "abc") && PreferenceSets.matches("%", "") && !PreferenceSets.matches("a?", "a"))
    }

    @Test("Edycja zestawu wybranego w Preferencjach; zmiana zapisuje tylko zmienione pola")
    func editTarget() throws {
        let ws = Workspace()
        let set = PreferenceSet(name: "Domyślny", kind: .defaultGlobal)
        try ws.savePreferenceSet(set)
        ws.preferenceEditTarget = set.id
        ws.settings.keywordCase = .upper
        #expect(ws.preferenceSets[0].values == ["keywordCase": .string("upper")] && ws.personalPreferences.isEmpty)
        ws.preferenceEditTarget = nil
        ws.settings.instantClientDirectory = "/opt/ic"
        #expect(ws.personalPreferences["instantClientDirectory"] == .string("/opt/ic"))
        ws.settings.instantClientDirectory = nil
        #expect(ws.personalPreferences["instantClientDirectory"] == .null && ws.settings.instantClientDirectory == nil)
    }

    @Test("Eksport wybranych sekcji bez historii plików; import do zestawu edytowanego; obcy plik odrzucony")
    func exportImport() async throws {
        let t = try TempDirectory()
        let ws = Workspace()
        ws.settings.recentFiles = ["/prywatne/plik.sql"]
        ws.settings.tabSize = 5
        ws.settings.autoCommitSQL = true
        let file = t.url.appendingPathComponent("prefs.json")
        try await ws.invoke("prefs.export", CommandArguments(["file": .string(file.path), "sections": .string(L10n.tr("Edytor"))]))
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("\"tabSize\" : 5") && !text.contains("autoCommitSQL") && !text.contains("recentFiles"))
        let other = Workspace()
        try await other.invoke("prefs.import", CommandArguments(["file": .string(file.path)]))
        #expect(other.settings.tabSize == 5 && other.settings.autoCommitSQL == false)
        let all = try PreferenceSets.export(ws.settings, sections: nil)
        #expect(try PreferenceSets.importValues(all, sections: [L10n.tr("SQL Window")])["autoCommitSQL"] == .bool(true))
        #expect(throws: (any Error).self) { try PreferenceSets.importValues(Data(#"{"format":"x","version":1,"values":{}}"#.utf8), sections: nil) }
    }

    @Test("Parametry startowe: klucz=wartość, --klucz, pliki, argumenty systemu pominięte, hasło odrzucone")
    func parse() {
        let o = StartupOptions.parse(["-NSDocumentRevisionsDebugMode", "YES", "userid=app/tajne@prod", "ViewObject=PACKAGE:APP.PKG",
                                      "--edit-object", "x", "--workset=Raporty", "noloaddesktop", "readonly=prod*,uat%", "plik.sql",
                                      "commandfile=~/s.sql", "--project", "p.prj", "-psn_0_123"])
        #expect(o.connection == "app@prod" && o.viewObject == "PACKAGE:APP.PKG" && o.workset == "Raporty" && o.noLoadDesktop)
        #expect(o.readOnly == ["prod*", "uat%"] && o.files == ["plik.sql"] && o.commandFile == "~/s.sql" && o.project == "p.prj")
        #expect(o.warnings.contains { $0.contains("Hasło") } && o.warnings.contains { $0.contains("edit-object") })
        #expect(!String(describing: o).contains("tajne"))
        // EZConnect z „/” po „@” to nie hasło; hasło z „@” nie przecieka do nazwy połączenia (przegląd kodu, D168).
        let ez = StartupOptions.parse(["userid=scott@host:1521/orcl"])
        #expect(ez.connection == "scott@host:1521/orcl" && ez.warnings.isEmpty)
        let at = StartupOptions.parse(["userid=u/p@ss@db"])
        #expect(at.connection == "u@db" && !String(describing: at).contains("ss@"))
        #expect(StartupOptions.object("PACKAGE:APP.PKG") == ("PACKAGE", "APP.PKG") && StartupOptions.object("app.emp") == (nil, "app.emp"))
        #expect(StartupOptions.object("TABLE,APP.EMP") == ("TABLE", "APP.EMP"))
        let u = StartupOptions.parse(url: URL(string: "pelikan://open?connection=Dev&edit=APP.PKG&file=/tmp/a.sql&password=x")!, scheme: "pelikan")
        #expect(u.connection == "Dev" && u.editObject == "APP.PKG" && u.files == ["/tmp/a.sql"] && !u.warnings.isEmpty)
        #expect(StartupOptions.parse(url: URL(string: "https://x?connection=Dev")!, scheme: "pelikan").isEmpty)
        // Link z sieci nie uruchamia skryptu (przegląd bezpieczeństwa, D163).
        let script = StartupOptions.parse(url: URL(string: "pelikan://open?connection=Prod&commandfile=~/Downloads/x.sql&noloaddesktop=1")!, scheme: "pelikan")
        #expect(script.commandFile == nil && !script.noLoadDesktop && script.connection == "Prod")
        #expect(script.warnings.contains { $0.contains("commandfile") })
    }

    @Test("Wykonanie parametrów: połączenie po nazwie (bez łączenia w testach — brak sterownika), pliki, tylko do odczytu")
    func apply() async throws {
        let t = try TempDirectory()
        let ws = Workspace()
        let def = try connection(ws, name: "Dev", user: "APP", db: "dev/svc")
        #expect(ws.connectionDefinition(matching: "dev")?.id == def.id && ws.connectionDefinition(matching: "app@DEV/SVC")?.id == def.id)
        let f = try t.file("a.sql", "select 1 from dual;")
        var o = StartupOptions.parse([f.path, "readonly=Dev", "connection=Nieznane"])
        o.workset = nil
        let messages = await ws.applyStartup(o)
        #expect(ws.documents.contains { $0.fileURL?.lastPathComponent == "a.sql" })
        #expect(messages.contains { $0.contains("Nieznane") })
        #expect(ws.startupReadOnlyPatterns == ["Dev"])
        if case .blocked = ws.modificationCheck(["delete from emp"], connectionID: def.id) {} else { Issue.record("readonly= nie zablokował zmiany") }
    }

    @Test("WS1-23: link pelikan:// nie tworzy workseta (tylko otwiera istniejący); parametr startowy tworzy")
    func linkDoesNotCreateWorkset() async throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let link = StartupOptions.parse(url: URL(string: "pelikan://open?workset=Obcy")!, scheme: "pelikan")
        #expect(link.fromLink && link.workset == "Obcy" && !StartupOptions.parse(["workset=Obcy"]).fromLink)
        let messages = await ws.applyStartup(link)
        #expect(ws.worksets.existingName("Obcy") == nil && messages.contains { $0.contains("Obcy") })
        _ = await ws.applyStartup(StartupOptions.parse(["workset=Obcy"]))
        #expect(ws.worksets.existingName("Obcy") == "Obcy")
    }

    @Test("WS1-06: import preferencji uruchamiających programy pyta; po imporcie menu narzędzi użytkownika aktualne")
    func importRunningCodeAsks() async throws {
        let t = try TempDirectory()
        let source = Workspace()
        var tool = UserTool(name: "Obcy program")
        tool.program = "/bin/echo"
        source.settings.userTools = [tool]
        source.settings.agent.profiles[0].executable = "/tmp/nie-claude"
        source.settings.agent.queryMaxRows = 50
        source.settings.tabSize = 7
        let file = t.url.appendingPathComponent("zespol.json")
        try PreferenceSets.export(source.settings, sections: nil).write(to: file)
        let values = try PreferenceSets.importValues(try Data(contentsOf: file), sections: nil)
        let ws = Workspace()
        #expect(PreferenceSets.changesRunningCode(values, current: ws.settings) == [L10n.tr("Narzędzia użytkownika"), L10n.tr("Agenci")])
        // Same limity agenta i inne pola — bez pytania.
        #expect(PreferenceSets.changesRunningCode(["agent": values["agent"]!, "tabSize": .int(3)], current: source.settings).isEmpty)
        let ui = FakeUI()
        ws.ui = ui
        ui.answers = [1]
        await #expect(throws: CommandError.self) { try await ws.invoke("prefs.import", CommandArguments(["file": .string(file.path)])) }
        #expect(ui.asked.count == 1 && ws.settings.userTools.isEmpty && ws.settings.tabSize != 7)
        ui.answers = [0]
        try await ws.invoke("prefs.import", CommandArguments(["file": .string(file.path)]))
        #expect(ws.settings.userTools == [tool] && ws.settings.tabSize == 7)
        #expect(ws.registry.command(tool.commandID) != nil)
        // Narzędzia z zestawu preferencji połączenia głównego — komendy po zmianie połączenia.
        let def = try connection(ws, name: "Dev", user: "APP", db: "dev")
        var other = UserTool(name: "Narzędzie połączenia")
        other.program = "/bin/echo"
        try ws.savePreferenceSet(PreferenceSet(name: "Dev", kind: .personalConnection, pattern: "Dev",
                                               values: ["userTools": try JSONValue.encode([other])]))
        ws.sessions.setMainConnection(def.id)
        #expect(ws.registry.command(other.commandID) != nil && ws.registry.command(tool.commandID) == nil)
    }

    @Test("WS1-12: nieczytelne settings.json, history.json i zestawy zachowane jako .bad-…, komunikat, oryginał nienadpisany")
    func damagedPreferenceFiles() async throws {
        let t = try TempDirectory()
        try t.file("settings.json", "{ uszkodzony")
        try t.file("history.json", "[ uszkodzony")
        try t.file("Preferences/sets.json", "[ uszkodzony")
        let ws = Workspace(dataDirectory: t.url)
        #expect(ws.loadProblems.count == 3)
        ws.settings.tabSize = 9
        ws.recordHistory("select 1 from dual")
        try ws.savePreferenceSet(PreferenceSet(name: "Zespół", kind: .defaultGlobal, values: ["tabSize": .int(2)]))
        for (dir, name) in [("", "settings.json"), ("", "history.json"), ("Preferences", "sets.json")] {
            let names = try FileManager.default.contentsOfDirectory(atPath: t.url.appendingPathComponent(dir).path)
            let bad = try #require(names.first { $0.hasPrefix(name + ".bad-") }, "\(name)")
            #expect(try String(contentsOf: t.url.appendingPathComponent(dir).appendingPathComponent(bad), encoding: .utf8).contains("uszkodzony"))
        }
        // Nowe pliki zapisane obok kopii; następne uruchomienie je czyta bez komunikatów.
        let again = Workspace(dataDirectory: t.url)
        #expect(again.loadProblems.isEmpty && again.history.first?.text == "select 1 from dual" && again.preferenceSets.count == 1)
    }

    @Test("Usługi macOS: formatowanie wg reguł z Preferencji, otwarcie tekstu w nowym SQL Window")
    func services() throws {
        let ws = Workspace()
        ws.settings.beautifier.keywordCase = .upper
        let out = try MacServices.formatSQL("select a,b from t where x=1", in: ws)
        #expect(out.contains("SELECT") && out.contains("FROM"))
        let doc = MacServices.openInSQLWindow("select 1 from dual", in: ws)
        #expect(doc.kind == .sql && doc.text == "select 1 from dual" && ws.activeDocument?.id == doc.id)
    }

    @Test("Pasek narzędzi: domyślne i paleta to komendy z rejestru; szybki dostęp bez powtórzeń i nieznanych")
    func toolbar() async throws {
        let ws = Workspace()
        for id in ToolbarModel.defaultItems + ToolbarModel.paletteCommands where id != ToolbarModel.quickAccessItem && id != ToolbarModel.flexibleSpaceItem {
            #expect(ws.registry.command(CommandID(rawValue: id)) != nil, "nieznana komenda paska: \(id)")
        }
        try await ws.invoke("view.addToQuickAccess", CommandArguments(["command": "edit.beautify"]))
        try await ws.invoke("view.addToQuickAccess", CommandArguments(["command": "edit.beautify"]))
        #expect(ws.settings.quickAccessCommands == ["edit.beautify"])
        await #expect(throws: (any Error).self) { try await ws.invoke("view.addToQuickAccess", CommandArguments(["command": "nie.ma"])) }
        #expect(ToolbarModel.sanitized(["edit.beautify", "nie.ma", "edit.beautify"], in: ws) == ["edit.beautify"])
        try await ws.invoke("view.removeFromQuickAccess", CommandArguments(["command": "edit.beautify"]))
        #expect(ws.settings.quickAccessCommands.isEmpty && ToolbarModel.symbol(for: "sql.execute") == "play.fill")
    }
}

@Suite("Zestawy preferencji: pola opcjonalne")
struct PreferenceOptionalKeysTests {
    @Test("Każde pole opcjonalne Settings jest wykrywane i przechodzi przez nałożenie zestawu")
    func optionalFieldsSurviveMerge() {
        #expect(PreferenceSets.optionalKeys.contains("externalEditor") && PreferenceSets.optionalKeys.contains("language"))
        var s = Settings()
        s.externalEditor = "Visual Studio Code"
        s.language = "en"
        let merged = PreferenceSets.merge([PreferenceSet(name: "", kind: .personalUser, values: PreferenceSets.difference(s, from: Settings()))])
        #expect(merged.externalEditor == "Visual Studio Code" && merged.language == "en")
    }

    @Test("Stare ustawienia i zestawy z usuniętymi polami (allowMultipleConnections, autoCommitPostedRecords) wczytują się")
    func removedFieldsIgnored() throws {
        let json = #"{"allowMultipleConnections": false, "autoCommitPostedRecords": true, "tabSize": 7}"#
        #expect(try JSONDecoder.pelikan.decode(Settings.self, from: Data(json.utf8)).tabSize == 7)
        let old = PreferenceSet(name: "", kind: .personalUser, values: ["autoCommitPostedRecords": .bool(true), "tabSize": .int(5)])
        #expect(PreferenceSets.merge([old]).tabSize == 5)
        #expect(PreferenceSets.values(of: Settings())["allowMultipleConnections"] == nil)
    }
}
