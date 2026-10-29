import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Synchronization
import Testing

@Suite("Grupy kart: kaskada, histereza, kolejność (D200)")
struct TabGroupingTests {
    let a = UUID(), b = UUID()
    var labels: [UUID: TabGroupConnectionLabel] { [a: .init(name: "dev_test", detail: "test"), b: .init(name: "dev_alfa")] }

    func item(_ kind: DocumentKind = .sql, files: [String] = [], connection: UUID? = nil, manual: UUID? = nil) -> TabGroupItem {
        TabGroupItem(id: DocumentID(), kind: kind, files: files, connection: connection, manualGroup: manual)
    }

    @Test("Projekt, repozytorium ze zdalnym (bez zdalnego — dalej), połączenia, okna bez połączenia na końcu")
    func cascade() {
        let repo = RepositoryGroupInfo(root: "/r/pelikan", name: "pelikan", branch: "main", hasRemote: true)
        let local = RepositoryGroupInfo(root: "/r/lokalne", name: "lokalne", branch: "main", hasRemote: false)
        let wt = RepositoryGroupInfo(root: "/r/pelikan-wt", name: "pelikan", branch: "p3/grupy", hasRemote: true)
        let items = [
            item(files: ["/p/a.sql"], connection: a),           // projekt
            item(files: ["/r/pelikan/x.sql"], connection: a),   // repozytorium
            item(files: ["/r/lokalne/y.sql"], connection: b),   // repozytorium bez zdalnego → połączenie b
            item(connection: a), item(connection: b), item(connection: a),
            item(files: ["/r/pelikan-wt/z.sql"]),               // worktree z inną gałęzią — osobna grupa
            item(),                                             // bez połączenia
        ]
        let input = TabGroupInput(items: items, projectName: "Kadry", projectFiles: ["/p/a.sql"],
                                  repositories: ["/r/pelikan/x.sql": repo, "/r/lokalne/y.sql": local, "/r/pelikan-wt/z.sql": wt],
                                  connections: labels)
        var mode = TabGroupingMode.byKind
        let g = TabGrouping.groups(input, mode: &mode)
        #expect(mode == .byConnection)
        #expect(g.map(\.kind) == [.project, .repository, .repository, .connection, .connection, .noConnection])
        #expect(g.map(\.name) == ["Kadry", "pelikan", "pelikan", "dev_alfa", "dev_test", "Bez połączenia"])
        #expect(g[1].detail == "main" && g[2].detail == "p3/grupy")
        #expect(g[3].documents == [items[2].id, items[4].id] && g[4].documents == [items[3].id, items[5].id])
        #expect(g[4].caption == "test · 2" && g[5].caption == "1 okno")
        // Każde okno w dokładnie jednej grupie.
        #expect(Set(g.flatMap(\.documents)) == Set(items.map(\.id)) && g.flatMap(\.documents).count == items.count)
    }

    @Test("Jedna baza — grupy według rodzaju okna w stałej kolejności; okna bez połączenia też według rodzaju")
    func singleDatabase() {
        let items = [item(.test, connection: a), item(.sql, connection: a), item(.command, connection: a), item(.diagram), item(.program, connection: a)]
        var mode = TabGroupingMode.byKind
        let g = TabGrouping.groups(TabGroupInput(items: items, connections: labels), mode: &mode)
        #expect(mode == .byKind)
        #expect(g.map(\.name) == ["Okna SQL", "Programy", "Testy", "Konsole SQL*Plus", "Inne okna"])
    }

    @Test("Histereza: druga baza z jednym oknem nie przełącza; z dwoma — tak; powrót dopiero przy jednej bazie")
    func hysteresis() {
        #expect(TabGrouping.nextMode(.byKind, counts: [5]) == .byKind)
        #expect(TabGrouping.nextMode(.byKind, counts: [5, 1]) == .byKind)
        #expect(TabGrouping.nextMode(.byKind, counts: [5, 2]) == .byConnection)
        #expect(TabGrouping.nextMode(.byConnection, counts: [5, 1]) == .byConnection)
        #expect(TabGrouping.nextMode(.byConnection, counts: [5, 1, 1]) == .byConnection)
        #expect(TabGrouping.nextMode(.byConnection, counts: [6]) == .byKind)
        #expect(TabGrouping.nextMode(.byConnection, counts: []) == .byKind)
        // Ten sam stan wejścia — stały wynik (wyliczenie powtarzane przez kilka widoków).
        for m in [TabGroupingMode.byKind, .byConnection] {
            for counts in [[1], [3, 1], [2, 2], [1, 1, 1]] {
                let once = TabGrouping.nextMode(m, counts: counts)
                #expect(TabGrouping.nextMode(once, counts: counts) == once)
            }
        }
    }

    @Test("Grupy ręczne mają pierwszeństwo i są pierwsze, w kolejności utworzenia; pusta grupa ręczna — bez kapsułki")
    func manual() {
        let m1 = ManualTabGroup(name: "Zadanie 2"), m2 = ManualTabGroup(name: "Awaria"), empty = ManualTabGroup(name: "Pusta")
        let items = [item(files: ["/p/a.sql"], connection: a, manual: m2.id), item(connection: a, manual: m1.id), item(connection: b),
                     item(connection: b, manual: UUID())]   // przydział do nieistniejącej grupy — kaskada
        var mode = TabGroupingMode.byKind
        let g = TabGrouping.groups(TabGroupInput(items: items, manualGroups: [m1, m2, empty], projectName: "P", projectFiles: ["/p/a.sql"],
                                                 connections: labels), mode: &mode)
        #expect(g.map(\.name) == ["Zadanie 2", "Awaria", "Okna SQL"])
        #expect(g[0].kind == .manual && g[0].manualID == m1.id && g[2].documents.count == 2)
    }

    @Test("Odmiana liczebników: polski, ukraiński, angielski")
    func plural() {
        let pl = [1, 2, 4, 5, 11, 12, 14, 21, 22, 25, 102, 112].map { L10n.pluralCategory($0, language: "pl") }
        #expect(pl == [.one, .few, .few, .many, .many, .many, .many, .many, .few, .many, .few, .many])
        #expect(L10n.pluralCategory(21, language: "uk") == .one && L10n.pluralCategory(11, language: "uk") == .many)
        #expect(L10n.pluralCategory(23, language: "uk") == .few)
        #expect(L10n.pluralCategory(1, language: "en") == .one && L10n.pluralCategory(3, language: "de") == .many)
        // Bez katalogu tekstów (testy) — polskie formy.
        #expect(TabGrouping.windowCount(1) == "1 okno" && TabGrouping.windowCount(3) == "3 okna" && TabGrouping.windowCount(5) == "5 okien")
        #expect(TabGrouping.windowCount(22) == "22 okna" && TabGrouping.windowCount(12) == "12 okien")
    }
}

@Suite("Paleta kolorów połączeń i grup (D200)")
struct TabColorPaletteTests {
    @Test("Przydział przy pierwszym oknie, trwały; zwolniony wraca do puli, najdawniej zwolniony pierwszy")
    func assignment() {
        var p = TabColorPalette()
        p.sync(["a", "b"])
        #expect(p.index(for: "a") == 0 && p.index(for: "b") == 1)
        p.sync(["b", "a", "c"])
        #expect(p.index(for: "a") == 0 && p.index(for: "b") == 1 && p.index(for: "c") == 2)
        // Zwolnienie: nowe połączenie dostaje nieużywany kolor, nie świeżo zwolniony.
        p.sync(["b", "c"])
        #expect(p.index(for: "a") == nil)
        p.sync(["b", "c", "d"])
        #expect(p.index(for: "d") == 3)
        // Gdy nieużywanych brak — najdawniej zwolniony.
        let many = (0..<10).map { "k\($0)" }
        var q = TabColorPalette()
        q.sync(many)
        q.sync(Array(many.dropFirst(2)))      // zwolnione 0, 1 (w tej kolejności nieokreślonej — oba)
        q.sync(Array(many.dropFirst(2)) + ["n1"])
        #expect([0, 1].contains(q.index(for: "n1")!))
    }

    @Test("Ponad 10 naraz — kolory się powtarzają równomiernie; kolory z workseta wracają")
    func repetitionAndWorkset() {
        var p = TabColorPalette()
        let keys = (0..<13).map { "c\($0)" }
        p.sync(keys)
        let used = keys.compactMap { p.index(for: $0) }
        #expect(used.count == 13 && Set(used).count == 10)
        var usage = [Int: Int]()
        for i in used { usage[i, default: 0] += 1 }
        #expect(usage.values.max() == 2)
        var r = TabColorPalette()
        r.prefer(["conn:X": 7, "conn:Y": 3, "zly": 42])
        r.sync(["conn:Z", "conn:Y", "conn:X"])
        #expect(r.index(for: "conn:X") == 7 && r.index(for: "conn:Y") == 3 && r.index(for: "conn:Z") == 0)
    }

    @Test("Kontrast na tle kart i kapsułek: tekst i znacznik typu AA, podkreślenie i obwódka kropki ≥ 3:1; odcienie co 36°")
    func contrast() {
        let black = RGBColor(red: 0, green: 0, blue: 0), white = RGBColor(red: 1, green: 1, blue: 1)
        for i in 0..<TabColorPalette.count {
            for dark in [false, true] {
                for increased in [false, true] {
                    let accent = TabColorPalette.color(i, shade: .accent, dark: dark, increasedContrast: increased)
                    for shade in [TabColorPalette.Shade.activeBackground, .inactiveBackground] {
                        let bg = TabColorPalette.color(i, shade: shade, dark: dark, increasedContrast: increased)
                        let label = dark ? white : black
                        // Kolor etykiety 85% (labelColor); tytuł nieaktywnej karty i wiersz połączenia — przezroczystość
                        // ustawiona na 80% (`withAlphaComponent` zastępuje alfę, nie mnoży jej); przy „Zwiększ kontrast”
                        // — kolor etykiety (85%) albo pełny.
                        for alpha in increased ? [0.85] : [0.85, 0.8] {
                            let text = TabColorPalette.blend(label, alpha: alpha, over: bg)
                            #expect(TabColorPalette.contrast(text, bg) >= 4.5, "kolor \(i) dark \(dark) +kontrast \(increased) \(shade) alfa \(alpha)")
                        }
                        // Znacznik typu okna to tekst — AA.
                        for kind in DocumentKind.allCases {
                            let m = TabColorPalette.markerColor(kind, dark: dark)
                            #expect(TabColorPalette.contrast(m, bg) >= 4.5, "znacznik \(kind) kolor \(i) dark \(dark) \(shade)")
                        }
                        // Obwódka kropki środowiska (kolor etykiety 85%, 1 pt) — element nietekstowy ≥ 3:1.
                        #expect(TabColorPalette.contrast(TabColorPalette.blend(label, alpha: 0.85, over: bg), bg) >= 3)
                        // Podkreślenie aktywnej karty i obwódka bieżącej kapsułki — na mocniejszym tle ≥ 3:1.
                        if shade == .activeBackground {
                            #expect(TabColorPalette.contrast(accent, bg) >= 3, "akcent \(i) dark \(dark) +kontrast \(increased)")
                        }
                    }
                }
            }
        }
        // Znacznik typu na tle paska kart i okna bez połączenia.
        for (dark, bar) in [(false, RGBColor(red: 0.91, green: 0.91, blue: 0.92)), (true, RGBColor(red: 0.16, green: 0.16, blue: 0.17))] {
            for kind in DocumentKind.allCases { #expect(TabColorPalette.contrast(TabColorPalette.markerColor(kind, dark: dark), bar) >= 4.5) }
        }
        // Barwy wyraźnie różne: sąsiednie odcienie co najmniej 36° od siebie (10 barw równo po kole).
        let h = TabColorPalette.hues.sorted()
        for (x, y) in zip(h, h.dropFirst()) { #expect(y - x >= 36) }
        #expect(360 - h.last! + h.first! >= 36)
    }
}

@Suite("Przewijanie paska kart (D201)")
struct TabStripScrollingTests {
    @Test("Przepełnienie, przyciski na końcach, krok, kółko i aktywna karta w widoku")
    func scrolling() {
        #expect(!TabStripScrolling.overflows(content: 500, visible: 500))
        #expect(TabStripScrolling.overflows(content: 900, visible: 500))
        #expect(!TabStripScrolling.canScroll(offset: 0, content: 900, visible: 500, forward: false))
        #expect(TabStripScrolling.canScroll(offset: 0, content: 900, visible: 500, forward: true))
        #expect(!TabStripScrolling.canScroll(offset: 400, content: 900, visible: 500, forward: true))
        #expect(!TabStripScrolling.canScroll(offset: 0, content: 400, visible: 500, forward: true))
        #expect(TabStripScrolling.target(offset: 0, content: 900, visible: 500, forward: true) == 300)
        #expect(TabStripScrolling.target(offset: 300, content: 900, visible: 500, forward: true) == 400)
        #expect(TabStripScrolling.target(offset: 100, content: 900, visible: 500, forward: false) == 0)
        #expect(TabStripScrolling.wheel(offset: 100, delta: -50, content: 900, visible: 500) == 150)
        #expect(TabStripScrolling.wheel(offset: 100, delta: 500, content: 900, visible: 500) == 0)
        #expect(TabStripScrolling.reveal(offset: 0, content: 900, visible: 500, minX: 600, maxX: 700) == 208)
        #expect(TabStripScrolling.reveal(offset: 300, content: 900, visible: 500, minX: 100, maxX: 200) == 92)
        #expect(TabStripScrolling.reveal(offset: 100, content: 900, visible: 500, minX: 200, maxX: 300) == 100)
    }
}

@MainActor
@Suite("Grupy kart w obszarze roboczym: przełączanie, komendy, worksety (D200)")
struct WorkspaceTabGroupsTests {
    func workspace() throws -> (Workspace, ConnectionDefinition, ConnectionDefinition) {
        let ws = Workspace()
        let x = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: "u", connectString: "db1"), environment: .test)
        let y = ConnectionDefinition(name: "dev_druga", target: ConnectionTarget(user: "u", connectString: "db2"))
        try ws.connections.upsert(x, password: nil)
        try ws.connections.upsert(y, password: nil)
        return (ws, x, y)
    }

    @Test("Bieżąca grupa to grupa aktywnego okna; aktywacja okna spoza grupy przełącza; nawigacja w obrębie grupy")
    func switching() async throws {
        let (ws, x, y) = try workspace()
        let a1 = ws.newDocument(.sql), a2 = ws.newDocument(.program), b1 = ws.newDocument(.sql), b2 = ws.newDocument(.test)
        for d in [a1, a2] { d.connectionID = x.id }
        for d in [b1, b2] { d.connectionID = y.id }
        let groups = ws.tabGroups
        #expect(groups.map(\.name) == ["dev_druga", "dev_test"])
        #expect(ws.currentTabGroup?.name == "dev_druga" && ws.visibleTabDocuments == [b1.id, b2.id])
        // Aktywacja z dowolnego miejsca (Przeglądarka obiektów, lista błędów, agent) — grupa przełącza się sama.
        ws.activate(a1.id)
        #expect(ws.currentTabGroup?.name == "dev_test" && ws.visibleTabDocuments == [a1.id, a2.id])
        _ = try await ws.invoke("window.next")
        #expect(ws.activeDocumentID == a2.id)
        // Za ostatnim oknem grupy — pierwsze okno następnej grupy (cyklicznie: dev_test → dev_druga); wstecz — z powrotem.
        _ = try await ws.invoke("window.next")
        #expect(ws.activeDocumentID == b1.id)
        _ = try await ws.invoke("window.previous")
        #expect(ws.activeDocumentID == a2.id)
        ws.activate(a1.id)
        // Następna grupa — ostatnio używane okno grupy (b2 było aktywne przed a1).
        ws.activate(b2.id)
        ws.activate(a1.id)
        _ = try await ws.invoke("window.nextGroup")
        #expect(ws.activeDocumentID == b2.id)
        _ = try await ws.invoke("window.previousGroup")
        #expect(ws.activeDocumentID == a1.id)
        _ = try await ws.invoke("window.showGroup", CommandArguments(["group": .string("1")]))
        #expect(ws.currentTabGroup?.name == "dev_druga")
        let shown = try await ws.invoke("window.showGroup", CommandArguments(["group": .string("dev_test")]))
        #expect(ws.activeDocumentID == a1.id)
        // Makro zapisuje „nazwa · szczegół” — wskazanie jednoznaczne także przy grupach o tej samej nazwie.
        #expect(shown.resolvedArguments?.string("group") == "dev_test · test")
        _ = try await ws.invoke("window.showGroup", CommandArguments(["group": .string("dev_test · test")]))
        #expect(ws.activeDocumentID == a1.id)
        await #expect(throws: (any Error).self) { try await ws.invoke("window.showGroup", CommandArguments(["group": .string("brak")])) }
        // Karty wszystkich grup.
        _ = try await ws.invoke("window.allTabs", CommandArguments(["visible": .bool(true)]))
        #expect(ws.visibleTabDocuments.count == 4)
        _ = try await ws.invoke("window.showGroup", CommandArguments(["group": .string("dev_druga")]))
        #expect(!ws.tabGroupState.showAll && ws.visibleTabDocuments == [b1.id, b2.id])
        // Zamknięcie aktywnego — następne okno tej samej grupy.
        ws.activate(b1.id)
        ws.close(b1.id)
        #expect(ws.activeDocumentID == b2.id)
    }

    @Test("Jedna baza: grupy rodzajów; druga baza z jednym oknem nie przestawia; z dwoma — grupy połączeń")
    func hysteresisInWorkspace() throws {
        let (ws, x, y) = try workspace()
        for k in [DocumentKind.sql, .sql, .program] { ws.newDocument(k).connectionID = x.id }
        #expect(ws.tabGroups.map(\.name) == ["Okna SQL", "Programy"])
        ws.newDocument(.sql).connectionID = y.id
        #expect(ws.tabGroups.map(\.name) == ["Okna SQL", "Programy"])
        ws.newDocument(.test).connectionID = y.id
        #expect(ws.tabGroups.map(\.name) == ["dev_druga", "dev_test"])
        // Kolor połączenia: grupa połączenia i karty mają ten sam kolor palety.
        let g = ws.tabGroups
        #expect(g[1].colorIndex == ws.paletteIndex(for: ws.documents[0]) && g[0].colorIndex != g[1].colorIndex)
    }

    @Test("Repozytorium ze zdalnym: grupa repozytorium · gałąź; zmiana gałęzi zmienia grupę")
    func repositories() throws {
        let (ws, x, _) = try workspace()
        ws.tabRepositoryProbe = nil
        let d = ws.newDocument(.sql, fileURL: URL(fileURLWithPath: "/repo/sql/a.sql"))
        d.connectionID = x.id
        ws.newDocument(.sql).connectionID = x.id
        ws.tabRepositoryDirectories.insert("/repo/sql")
        ws.tabRepositories["/repo/sql"] = RepositoryGroupInfo(root: "/repo", name: "kadry", branch: "main", hasRemote: true)
        #expect(ws.tabGroups.map { "\($0.name) \($0.caption)" } == ["kadry main · 1", "Okna SQL 1 okno"])
        // Identyfikator bez ścieżek (makra, agent); kolor po repozytorium, nie po gałęzi.
        let main = try #require(ws.tabGroups.first)
        #expect(!main.id.contains("/repo") && main.id.hasSuffix(":main"))
        ws.tabRepositories["/repo/sql"]?.branch = "feature"
        let feature = try #require(ws.tabGroups.first)
        #expect(feature.caption == "feature · 1" && feature.id != main.id && feature.colorIndex == main.colorIndex)
        // Nowy plik w znanym repozytorium (katalog jeszcze niesprawdzony) — od razu w grupie repozytorium.
        ws.newDocument(.sql, fileURL: URL(fileURLWithPath: "/repo/nowe/b.sql")).connectionID = x.id
        #expect(ws.tabGroups.first?.documents.count == 2)
        ws.tabRepositories["/repo/sql"]?.hasRemote = false
        #expect(ws.tabGroups.map(\.name) == ["Okna SQL"])
    }

    @Test("Grupy ręczne: nowa, przeniesienie, usunięcie z grupy, zmiana nazwy, rozgrupowanie, zamknięcie ostatniego okna")
    func manualCommands() async throws {
        let (ws, x, _) = try workspace()
        let a = ws.newDocument(.sql), b = ws.newDocument(.sql), c = ws.newDocument(.program)
        for d in [a, b, c] { d.connectionID = x.id }
        _ = try await ws.invoke("window.moveToGroup", CommandArguments(["document": .string(a.id.description), "name": .string("Awaria")]))
        _ = try await ws.invoke("window.moveToGroup", CommandArguments(["document": .string(c.id.description), "group": .string("awaria")]))
        #expect(ws.tabGroups.map(\.name) == ["Awaria", "Okna SQL"])
        #expect(ws.tabGroups[0].documents == [a.id, c.id])
        _ = try await ws.invoke("window.renameGroup", CommandArguments(["group": .string("Awaria"), "name": .string("Incydent")]))
        #expect(ws.tabGroups[0].name == "Incydent")
        _ = try await ws.invoke("window.removeFromGroup", CommandArguments(["document": .string(c.id.description)]))
        #expect(ws.tabGroups.map(\.name) == ["Incydent", "Okna SQL", "Programy"])
        await #expect(throws: (any Error).self) {
            try await ws.invoke("window.removeFromGroup", CommandArguments(["document": .string(c.id.description)]))
        }
        _ = try await ws.invoke("window.ungroup", CommandArguments(["group": .string("Incydent")]))
        #expect(ws.tabGroupState.manualGroups.isEmpty && ws.tabGroups.map(\.name) == ["Okna SQL", "Programy"])
        // Zamknięcie ostatniego okna grupy ręcznej — grupa znika.
        ws.moveToNewTabGroup(b.id, name: "Tymczasowa")
        ws.close(b.id)
        #expect(ws.tabGroupState.manualGroups.isEmpty && ws.tabGroupState.assignments.isEmpty)
    }

    @Test("Workset: grupy ręczne i kolory zapisane i odtworzone; starszy workset bez pól")
    func workset() throws {
        let (ws, x, y) = try workspace()
        let a = ws.newDocument(.sql, text: "select 1 from dual"), b = ws.newDocument(.sql, text: "select 2 from dual")
        a.connectionID = x.id; a.connectionPinned = true
        b.connectionID = y.id; b.connectionPinned = true
        ws.moveToNewTabGroup(a.id, name: "Zadanie")
        let colorY = ws.paletteIndex(for: b)
        let snap = ws.worksetSnapshot(name: "t")
        #expect(snap.tabGroups?.map(\.name) == ["Zadanie"] && snap.documents[0].group == snap.tabGroups?.first?.id)
        #expect(snap.tabColors?[TabColorPalette.connectionKey(y.id)] == colorY)
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(Workset.self, from: data)
        let (ws2, x2, y2) = (Workspace(), x, y)
        try ws2.connections.upsert(x2, password: nil)
        try ws2.connections.upsert(y2, password: nil)
        // Inne połączenie otwarte wcześniej — kolor y z workseta i tak wraca.
        ws2.appendWorksetDocuments(back)
        #expect(ws2.tabGroups.first?.name == "Zadanie" && ws2.tabGroups.first?.documents.count == 1)
        #expect(ws2.paletteIndex(for: ws2.documents[1]) == colorY)
        // Starszy workset (bez pól grup i kolorów).
        let old = #"{"name":"stary","documents":[{"kind":"sql","modified":true,"text":"select 1","selectionStart":0,"selectionEnd":0}],"saved":"2026-01-01T00:00:00Z"}"#
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let w = try dec.decode(Workset.self, from: Data(old.utf8))
        #expect(w.tabGroups == nil && w.tabColors == nil && w.documents[0].group == nil)
        let ws3 = Workspace()
        ws3.appendWorksetDocuments(w)
        #expect(ws3.tabGroupState.manualGroups.isEmpty && ws3.tabGroups.count == 1)
    }
}

@Suite("Git: repozytorium dla grup kart (D200)", .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")), .serialized)
struct TabGroupRepositoryTests {
    func git(_ args: [String], _ dir: URL) throws { try GitRepository.run(args, in: dir) }

    func repo(_ t: TempDirectory) throws -> URL {
        let dir = t.url.appendingPathComponent("kadry")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for args in [["init", "-q", "-b", "main"], ["config", "user.name", "Test"], ["config", "user.email", "test@example.invalid"],
                     ["config", "commit.gpgsign", "false"]] { try git(args, dir) }
        return dir
    }

    @Test("groupInfo: nazwa, gałąź, zdalne; worktree z inną gałęzią; gałąź z pliku HEAD")
    func groupInfo() throws {
        let t = try TempDirectory()
        let dir = try repo(t)
        try t.file("kadry/a.sql", "select 1 from dual;\n")
        try git(["add", "."], dir)
        try git(["commit", "-q", "-m", "start"], dir)
        var info = try #require(GitRepository.groupInfo(for: dir))
        #expect(info.name == "kadry" && info.branch == "main" && !info.hasRemote)
        let bare = t.url.appendingPathComponent("zdalne.git")
        try git(["init", "-q", "--bare", bare.path], t.url)
        try git(["remote", "add", "origin", bare.path], dir)
        info = try #require(GitRepository.groupInfo(for: dir))
        #expect(info.hasRemote)
        let wt = t.url.appendingPathComponent("kadry-wt")
        try git(["worktree", "add", "-q", "-b", "zadanie", wt.path], dir)
        let w = try #require(GitRepository.groupInfo(for: wt))
        #expect(w.name == "kadry" && w.branch == "zadanie" && w.hasRemote && w.root != info.root)
        try git(["checkout", "-q", "-b", "inna"], dir)
        #expect(GitRepository.headBranch(gitDirectory: try #require(info.gitDirectory)) == "inna")
        #expect(GitRepository.groupInfo(for: t.url) == nil)
    }
}

@MainActor
@Suite("Grupy kart: menu karty, kapsułki przy braku miejsca, sprawdzanie repozytoriów (przegląd D200)")
struct TabGroupReviewTests {
    @Test("Menu karty: każda pozycja wywołuje swoją komendę — Usuń z grupy ręcznej to window.removeFromGroup")
    func tabMenu() async throws {
        let ws = Workspace()
        let a = ws.newDocument(.sql), b = ws.newDocument(.sql)
        ws.moveToNewTabGroup(a.id, name: "Awaria")
        let entries = ws.tabMenuEntries(for: a)
        let remove = try #require(entries.first { $0.title == "Usuń z grupy ręcznej" })
        #expect(remove.command == "window.removeFromGroup" && remove.arguments["document"] == .string(a.id.description))
        _ = try await ws.invoke(try #require(remove.command), CommandArguments(remove.arguments))
        #expect(ws.documents.count == 2 && ws.tabGroupState.assignments[a.id] == nil)
        // Bez grupy ręcznej — bez pozycji „Usuń z grupy ręcznej”; „Przenieś do grupy” zawiera nową grupę i istniejące.
        ws.moveToNewTabGroup(b.id, name: "Zadanie")
        let menu = ws.tabMenuEntries(for: a)
        #expect(!menu.contains { $0.command == "window.removeFromGroup" })
        let move = try #require(menu.first { $0.submenu != nil }?.submenu)
        #expect(move.first?.arguments["new"] == .bool(true) && move.contains { $0.title == "Zadanie" && $0.command == "window.moveToGroup" })
        let close = try #require(menu.first)
        #expect(close.command == "file.closeWindow" && close.arguments["document"] == .string(a.id.description))
        // Nazwy grup ręcznych są unikalne.
        await #expect(throws: (any Error).self) {
            try await ws.invoke("window.moveToGroup", CommandArguments(["document": .string(a.id.description), "name": .string("zadanie")]))
        }
    }

    @Test("Kapsułki: przy braku miejsca bieżąca zawsze widoczna — widoczne usuwane od końca, aż zmieszczą się bieżąca i „»”")
    func capsuleLayout() {
        let w: [Double] = [100, 100, 100, 100, 150]
        let all = TabCapsuleLayout.fit(widths: w, available: 600, spacing: 6, overflowWidth: 28, current: 1)
        #expect(all.visible == [0, 1, 2, 3, 4] && !all.overflow)
        // 330 pt: mieszczą się 0, 1 (+ „»”); bieżąca 4 (150) — od końca usunięta 1, bo 28 + 106 + 156 = 290 ≤ 330.
        let r = TabCapsuleLayout.fit(widths: w, available: 330, spacing: 6, overflowWidth: 28, current: 4)
        #expect(r.overflow && r.visible == [0, 4] && r.widths[4] == 150)
        // Bieżąca w środku mieszczących się — bez zmian.
        let m = TabCapsuleLayout.fit(widths: w, available: 330, spacing: 6, overflowWidth: 28, current: 1)
        #expect(m.visible == [0, 1])
        // Bardzo wąsko — sama bieżąca, zwężona najwyżej do minimum.
        let n = TabCapsuleLayout.fit(widths: w, available: 120, spacing: 6, overflowWidth: 28, current: 4)
        #expect(n.visible == [4] && n.widths[4] == 86)
        #expect(TabCapsuleLayout.fit(widths: w, available: 60, spacing: 6, overflowWidth: 28, current: 4).widths[4] == 60)
    }

    @Test("Repozytoria: remote i gałąź raz na repozytorium, znane katalogi tylko HEAD, pełne sprawdzenie od nowa najwyżej co 30 s")
    func probe() async throws {
        let calls = CallCounter()
        let probe = TabRepositoryProbe(
            locate: { dir in
                calls.add("locate")
                // „Usunięty worktree”: po przełączeniu flagi /repo/b przestaje być repozytorium.
                if dir == "/repo/b", calls.count("removed") > 0 { return nil }
                return dir.hasPrefix("/repo") ? RepositoryGroupInfo(root: "/repo", name: "kadry", branch: "main", hasRemote: false, gitDirectory: "/repo/.git") : nil
            },
            hasRemote: { _ in calls.add("remote"); return true },
            branch: { _, _, allowProcess in
                calls.add(allowProcess ? "branchProcess" : "branch")
                // HEAD w formacie reftable: bez zgody na proces — nieznana (gałąź zapamiętana), z nią — z gita.
                return allowProcess ? .branch("main") : .unknown
            })
        let ws = Workspace()
        ws.tabRepositoryProbe = probe
        for p in ["/repo/a/x.sql", "/repo/b/y.sql", "/inne/z.sql"] { ws.newDocument(.sql, fileURL: URL(fileURLWithPath: p)) }
        ws.scheduleTabRepositoryRefresh(full: false)
        await ws.tabRepositoryRefresh?.value
        // Położenie każdego katalogu, git remote i gałąź raz na repozytorium.
        #expect(calls.count("locate") == 3 && calls.count("remote") == 1 && calls.count("branch") == 1)
        #expect(ws.tabRepositories.count == 2 && ws.tabRepositories["/repo/a"]?.hasRemote == true)
        // Zwykła aktywacja: znane katalogi — tylko gałąź (reftable: zapamiętana, bez procesu gita), bez remote i locate.
        calls.reset()
        ws.activate(ws.documents[0].id)
        ws.scheduleTabRepositoryRefresh(full: false)
        await ws.tabRepositoryRefresh?.value
        #expect(calls.count("remote") == 0 && calls.count("locate") == 0 && calls.count("branch") == 1 && calls.count("branchProcess") == 0)
        #expect(ws.tabRepositories["/repo/a"]?.branch == "main")
        // Aktywacja aplikacji: pełne sprawdzenie — położenie wszystkich katalogów od nowa (usunięty worktree znika),
        // remote i gałąź z gita raz na repozytorium.
        calls.reset()
        calls.add("removed")
        ws.scheduleTabRepositoryRefresh(full: true)
        await ws.tabRepositoryRefresh?.value
        #expect(calls.count("locate") == 3 && calls.count("remote") == 1 && calls.count("branchProcess") == 1)
        #expect(ws.tabRepositories["/repo/b"] == nil && ws.tabRepositories["/repo/a"] != nil)
        // Drugie pełne w ciągu 30 s — tylko gałęzie.
        calls.reset()
        ws.scheduleTabRepositoryRefresh(full: true)
        await ws.tabRepositoryRefresh?.value
        #expect(calls.count("remote") == 0 && calls.count("locate") == 0 && calls.count("branch") == 1)
        // Obszar roboczy bez katalogu danych (testy) — sprawdzanie domyślnie wyłączone.
        let off = Workspace()
        #expect(off.tabRepositoryProbe == nil)
        off.newDocument(.sql, fileURL: URL(fileURLWithPath: "/repo/a/x.sql"))
        off.scheduleTabRepositoryRefresh(full: true)
        #expect(off.tabRepositoryRefresh == nil)
    }

    @Test("Identyfikator grupy repozytorium z solą: inna sól — inny identyfikator; ścieżki brak")
    func salt() {
        let item = TabGroupItem(id: DocumentID(), kind: .sql, files: ["/repo/a.sql"])
        let repo = RepositoryGroupInfo(root: "/repo", name: "kadry", branch: "main", hasRemote: true)
        func id(_ salt: String) -> String {
            var input = TabGroupInput(items: [item], repositories: ["/repo/a.sql": repo])
            input.salt = salt
            var mode = TabGroupingMode.byKind
            return TabGrouping.groups(input, mode: &mode)[0].id
        }
        #expect(id("a") == id("a") && id("a") != id("b") && !id("a").contains("repo/"))
    }

    @Test("Gałąź z HEAD: zwykła, reftable (.invalid — nieznana), rebase (head-name), odłączony")
    func head() throws {
        let t = try TempDirectory()
        let g = t.url.path
        try t.file("HEAD", "ref: refs/heads/feature/pensje\n")
        #expect(GitRepository.headReference(gitDirectory: g) == .branch("feature/pensje"))
        try t.file("HEAD", "ref: refs/heads/.invalid\n")
        #expect(GitRepository.headReference(gitDirectory: g) == .unknown && GitRepository.headBranch(gitDirectory: g) == nil)
        try t.file("HEAD", "0123456789abcdef0123456789abcdef01234567\n")
        #expect(GitRepository.headReference(gitDirectory: g) == .detached)
        #expect(GitRepository.currentBranch(gitDirectory: g, root: g) == nil)
        try t.file("rebase-merge/head-name", "refs/heads/zadanie\n")
        #expect(GitRepository.currentBranch(gitDirectory: g, root: g) == "zadanie")
    }
}

/// Licznik wywołań zaślepki (wywołania z zadania w tle).
final class CallCounter: Sendable {
    private let calls = Mutex<[String: Int]>([:])
    func add(_ k: String) { calls.withLock { $0[k, default: 0] += 1 } }
    func count(_ k: String) -> Int { calls.withLock { $0[k] ?? 0 } }
    func reset() { calls.withLock { $0 = [:] } }
}
