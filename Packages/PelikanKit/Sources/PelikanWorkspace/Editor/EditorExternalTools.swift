import Foundation

// MARK: Web Search (PD-EDIT-027)

/// Wyszukiwanie w sieci: nazwa i adres z `%s` w miejscu szukanego tekstu (UG 25.23).
public struct WebSearch: Sendable, Codable, Hashable, Identifiable {
    public var id = UUID()
    public var name: String
    public var url: String

    public init(name: String, url: String) { self.name = name; self.url = url }

    public static let defaults: [WebSearch] = [
        WebSearch(name: "Google", url: "https://www.google.com/search?q=%s"),
        WebSearch(name: L10n.tr("Dokumentacja Oracle"), url: "https://docs.oracle.com/search/?q=%s"),
        WebSearch(name: "Stack Overflow", url: "https://stackoverflow.com/search?q=%s"),
    ]

    /// Adres z tekstem zakodowanym jako parametr zapytania (`%s` — każde wystąpienie); bez `%s` tekst na końcu.
    /// Tylko http(s) — inne schematy odrzucane (adres z Preferencji nie uruchomi programu).
    public func url(for text: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#/")
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let s = url.contains("%s") ? url.replacingOccurrences(of: "%s", with: q) : url + q
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return u
    }
}

// MARK: Zewnętrzna przeglądarka różnic (PD-DIFF-002)

/// Program porównujący (UG 23.23): argumenty z dyrektywami `%1`/`%2` (pliki lewy/prawy) i `%3`/`%4` (tytuły).
public struct ExternalDiffTool: Sendable, Codable, Hashable {
    public var program: String
    public var arguments: [String]

    public init(program: String, arguments: [String] = ["%1", "%2"]) { self.program = program; self.arguments = arguments }

    /// Argumenty po podstawieniu dyrektyw (każdy argument osobno, bez powłoki).
    public func expandedArguments(left: String, right: String, leftTitle: String, rightTitle: String) -> [String] {
        arguments.map {
            $0.replacingOccurrences(of: "%1", with: left).replacingOccurrences(of: "%2", with: right)
                .replacingOccurrences(of: "%3", with: leftTitle).replacingOccurrences(of: "%4", with: rightTitle)
        }
    }

    /// Linia argumentów z Preferencji → tablica: odstępy dzielą, cudzysłowy (" albo ') grupują, `\` poprzedza znak.
    public static func split(_ line: String) -> [String] {
        var out: [String] = [], cur = "", quote: Character?, inArg = false, escape = false
        for ch in line {
            if escape { cur.append(ch); escape = false; continue }
            if ch == "\\" { escape = true; inArg = true; continue }
            if let q = quote {
                if ch == q { quote = nil } else { cur.append(ch) }
                continue
            }
            if ch == "\"" || ch == "'" { quote = ch; inArg = true; continue }
            if ch.isWhitespace {
                if inArg { out.append(cur); cur = ""; inArg = false }
                continue
            }
            cur.append(ch)
            inArg = true
        }
        if inArg { out.append(cur) }
        return out
    }

    /// Tablica → linia do edycji (argumenty z odstępami albo cudzysłowami w cudzysłowach).
    public static func join(_ args: [String]) -> String {
        args.map { a in
            a.isEmpty || a.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "'" || $0 == "\\" })
                ? "\"" + a.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" : a
        }.joined(separator: " ")
    }
}

// MARK: Dokumenty użytkownika (PD-DOC-002)

/// Dokument w menu Narzędzia › Dokumenty (UG 37.3): plik albo adres http(s).
public struct UserDocument: Sendable, Codable, Hashable, Identifiable {
    public var id = UUID()
    public var title: String
    public var location: String

    public init(title: String, location: String) { self.title = title; self.location = location }

    /// Adres do otwarcia: http(s) albo istniejący plik (z rozwinięciem `~`); inne schematy odrzucane.
    public var url: URL? {
        let s = location.trimmingCharacters(in: .whitespaces)
        if let u = URL(string: s), let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme) { return u }
        let path = (s.hasPrefix("file://") ? (URL(string: s)?.path ?? "") : (s as NSString).expandingTildeInPath)
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}

// MARK: Okna „nie pokazuj więcej” (PD-PREF-008)

/// Pytania, które można wyłączyć („Nie pytaj więcej”); odpowiedź zapamiętana w Preferencjach do przywrócenia.
public enum SuppressibleDialog: String, Sendable, CaseIterable {
    case commitRollback = "confirm.commitRollback"
    case moveToTrash = "confirm.moveToTrash"
    case revertWorkset = "confirm.revertWorkset"
    case restoreRecovery = "confirm.restoreRecovery"
    case reportCrash = "ask.reportCrash"

    public var title: String {
        switch self {
        case .commitRollback: L10n.tr("Potwierdzenie zatwierdzenia albo wycofania transakcji")
        case .moveToTrash: L10n.tr("Przeniesienie pliku do Kosza")
        case .revertWorkset: L10n.tr("Przywrócenie zapisanego workseta")
        case .restoreRecovery: L10n.tr("Odzyskanie okien po nieoczekiwanym zamknięciu")
        case .reportCrash: L10n.tr("Zgłoszenie problemu po nieoczekiwanym zamknięciu")
        }
    }
}

// MARK: Kopie zapasowe i odzyskiwanie (PD-FILE-001)

public enum FileBackup {
    /// Kopia `plik.~ext` (UG 23.31), dla pliku bez rozszerzenia — `plik~`.
    public static func backupURL(for url: URL) -> URL {
        let ext = url.pathExtension
        let base = url.deletingPathExtension()
        return ext.isEmpty ? url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + "~")
            : base.appendingPathExtension("~" + ext)
    }

    /// Kopiuje dotychczasową treść pliku przed nadpisaniem (nadpisuje starszą kopię); brak pliku — nic.
    public static func backup(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let b = backupURL(for: url)
        try? FileManager.default.removeItem(at: b)
        try FileManager.default.copyItem(at: url, to: b)
    }
}

/// Odzyskiwanie po awarii (UG 23.31): znacznik działającej sesji i okresowa migawka niezapisanych okien w katalogu
/// danych (`Recovery/`, pliki 0600). Znacznik pozostały po poprzednim uruchomieniu = nieczyste zamknięcie.
public final class RecoveryStore: Sendable {
    public let directory: URL?
    var markerURL: URL? { directory?.appendingPathComponent("running") }
    var snapshotURL: URL? { directory?.appendingPathComponent("windows.json") }

    public init(directory: URL?) { self.directory = directory }

    /// Start aplikacji: zwraca migawkę z poprzedniego uruchomienia, jeśli zakończyło się nieczysto; zakłada znacznik.
    public func begin() -> Workset? {
        guard let dir = directory, let marker = markerURL, let snap = snapshotURL else { return nil }
        let crashed = FileManager.default.fileExists(atPath: marker.path)
        let previous = crashed ? (try? Data(contentsOf: snap)).flatMap { try? JSONDecoder().decode(Workset.self, from: $0) } : nil
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        _ = FileManager.default.createFile(atPath: marker.path, contents: Data(String(ProcessInfo.processInfo.processIdentifier).utf8),
                                       attributes: [.posixPermissions: 0o600])
        if !crashed { try? FileManager.default.removeItem(at: snap) }
        return previous.flatMap { $0.documents.isEmpty ? nil : $0 }
    }

    /// Zapisuje migawkę niezapisanych okien (pusta — usuwa plik).
    public func save(_ w: Workset) {
        guard let snap = snapshotURL else { return }
        guard !w.documents.isEmpty, let data = try? JSONEncoder().encode(w) else { try? FileManager.default.removeItem(at: snap); return }
        _ = FileManager.default.createFile(atPath: snap.path, contents: data, attributes: [.posixPermissions: 0o600])
    }

    /// Czyste zamknięcie: bez znacznika i migawki.
    public func end() {
        if let m = markerURL { try? FileManager.default.removeItem(at: m) }
        if let s = snapshotURL { try? FileManager.default.removeItem(at: s) }
    }

    /// Po decyzji o migawce z poprzedniego uruchomienia (przywrócona albo odrzucona).
    public func discardPrevious() {
        if let s = snapshotURL { try? FileManager.default.removeItem(at: s) }
    }
}

// MARK: Edytor zewnętrzny (PD-EDIT-028)

/// Okno edytowane programem zewnętrznym: plik i data modyfikacji przy przekazaniu.
public struct ExternalDocumentEdit: Sendable, Hashable {
    public var url: URL
    public var modified: Date?
    /// Plik tymczasowy (okno bez pliku) — po wczytaniu okno zostaje zmienione, bez pliku.
    public var temporary: Bool
}

extension Workspace {
    /// Tekst do wyszukania: zaznaczenie albo identyfikator pod kursorem.
    public func searchText(in doc: Document) -> String {
        let ns = doc.text as NSString
        let r = doc.selectedRange
        if !r.isEmpty, r.upperBound <= ns.length {
            return ns.substring(with: NSRange(location: r.lowerBound, length: r.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return TextEditing.identifier(at: min(r.lowerBound, ns.length), in: doc.text) ?? ""
    }

    static func modificationDate(_ u: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date
    }

    /// Przygotowuje okno do edycji zewnętrznej: zapisuje plik (gdy zmieniony) albo tworzy plik tymczasowy 0600
    /// w `External/` katalogu danych; zapamiętuje datę modyfikacji do wykrycia zmian po powrocie.
    public func prepareExternalEdit(_ doc: Document) throws -> URL {
        let edit: ExternalDocumentEdit
        if let url = doc.fileURL {
            if doc.isModified { try save(doc, to: url) }
            edit = ExternalDocumentEdit(url: url, modified: Self.modificationDate(url), temporary: false)
        } else {
            let base = dataDirectory ?? FileManager.default.temporaryDirectory
            let dir = base.appendingPathComponent("External", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let ext = switch doc.kind {
            case .program: "sql"
            case .test: "tst"
            default: "sql"
            }
            let name = doc.title.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
            let url = dir.appendingPathComponent("\(name.isEmpty ? "okno" : name)-\(doc.id.raw.uuidString.prefix(8)).\(ext)")
            guard let data = TextFileCodec.encode(doc.text, format: doc.fileFormat) ?? doc.text.data(using: .utf8) else {
                throw CommandError.notAvailable(L10n.tr("Nie można zapisać tekstu okna"))
            }
            _ = FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
            edit = ExternalDocumentEdit(url: url, modified: Self.modificationDate(url), temporary: true)
        }
        externalEdits[doc.id] = edit
        return edit.url
    }

    /// Po powrocie do Pelikana: okna, których pliki zmienił program zewnętrzny, dostają nową treść.
    /// Zwraca liczbę przeładowanych okien.
    @discardableResult
    public func checkExternalEdits() -> Int {
        var reloaded = 0
        for (id, e) in externalEdits {
            guard let doc = documents.first(where: { $0.id == id }) else {
                if e.temporary { try? FileManager.default.removeItem(at: e.url) }
                externalEdits[id] = nil
                continue
            }
            guard let m = Self.modificationDate(e.url), m != e.modified, let data = try? Data(contentsOf: e.url) else { continue }
            let decoded = TextFileCodec.decode(data)
            if decoded.text != doc.text {
                doc.text = decoded.text
                let len = (doc.text as NSString).length
                doc.selectedRange = min(doc.selectedRange.lowerBound, len)..<min(doc.selectedRange.lowerBound, len)
                doc.isModified = e.temporary
                if !e.temporary { doc.fileFormat = decoded.format }
                reloaded += 1
            }
            externalEdits[id]?.modified = m
        }
        return reloaded
    }

    /// Zapis z kopią zapasową `plik.~ext`, gdy włączona w Preferencjach (PD-FILE-001).
    func backupBeforeSave(_ url: URL) {
        guard settings.backupOnSave else { return }
        try? FileBackup.backup(url)
    }

    /// Migawka do odzyskiwania: okna z niezapisanymi zmianami (z plikiem albo bez, z niepustym tekstem albo z modelem
    /// diagramu lub notatnika — ich tekst jest pusty, R3-15).
    public func recoverySnapshot() -> Workset {
        var w = worksetSnapshot(name: "recovery")
        w.documents = w.documents.filter {
            $0.modified && (!($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.diagram != nil || $0.notebook != nil)
        }
        w.activeIndex = nil
        return w
    }

    /// Okresowy zapis migawki (wywołuje aplikacja co interwał z Preferencji).
    public func saveRecoverySnapshot() {
        guard settings.recoveryEnabled else { return }
        recovery.save(recoverySnapshot())
    }

    /// Migawka przed wykonaniem (PD-FILE-001, opcja „przy każdym wykonaniu”): awaria w trakcie długiego polecenia nie
    /// traci niezapisanych okien. Najwyżej jedna migawka na `minimumInterval` sekund — seria F8 nie spowalnia pracy.
    @discardableResult
    public func saveRecoverySnapshotBeforeExecute(now: Date = Date(), minimumInterval: TimeInterval = 5) -> Bool {
        guard settings.recoveryEnabled, settings.recoveryOnExecute else { return false }
        if let last = lastExecuteSnapshot, now.timeIntervalSince(last) < minimumInterval { return false }
        lastExecuteSnapshot = now
        recovery.save(recoverySnapshot())
        return true
    }

    /// Pytanie z opcją „Nie pytaj więcej” (PD-PREF-008): zapamiętana odpowiedź zastępuje pytanie, dopóki użytkownik
    /// nie przywróci okna w Preferencjach. Anulowanie nie jest zapamiętywane.
    public func askSuppressible(_ dialog: SuppressibleDialog, title: String, message: String, buttons: [String]) async -> Int? {
        if let saved = settings.suppressedDialogs[dialog.rawValue], saved < buttons.count { return saved }
        guard let ui else { return nil }
        let (answer, suppress) = await ui.askWithSuppression(title, message: message, buttons: buttons)
        if suppress, let answer { settings.suppressedDialogs[dialog.rawValue] = answer }
        return answer
    }
}

// MARK: Komendy

@MainActor
enum EditorExternalCommands {
    static func editorDocument(_ ws: Workspace) -> Document? {
        ws.activeDocument.flatMap { [.sql, .program, .test, .command].contains($0.kind) ? $0 : nil }
    }

    static var all: [Command] {
        [
            Command(CommandDescriptor(id: "edit.webSearch", title: L10n.tr("Szukaj w sieci"), category: .edit, submenu: nil,
                                      parameters: [CommandParameter("engine", .string, L10n.tr("Nazwa wyszukiwania z Preferencji (domyślnie pierwsze)")),
                                                   CommandParameter("text", .string, L10n.tr("Tekst (domyślnie zaznaczenie albo słowo pod kursorem)"))],
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Otwiera w przeglądarce wyszukiwanie zaznaczonego tekstu albo słowa pod kursorem (wyszukiwania z %s w Preferencjach)."),
                                      feature: "PD-EDIT-027")) { ctx in
                let ws = ctx.workspace
                let text = ctx.arguments.string("text") ?? editorDocument(ws).map { ws.searchText(in: $0) } ?? ""
                guard !text.isEmpty else { throw CommandError.notAvailable(L10n.tr("Zaznacz tekst albo ustaw kursor na słowie")) }
                let searches = ws.settings.webSearches
                guard !searches.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak wyszukiwań — dodaj je w Preferencjach › Narzędzia")) }
                var search = searches[0]
                if let name = ctx.arguments.string("engine") {
                    guard let s = searches.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                        throw CommandError.invalidArgument("engine", name)
                    }
                    search = s
                } else if searches.count > 1, let ui = ctx.ui {
                    guard let i = await ui.ask(L10n.tr("Szukaj w sieci: „\(text)”"), message: L10n.tr("Wybierz wyszukiwanie."),
                                               buttons: searches.prefix(6).map(\.name)) else { throw CommandError.cancelledByUser }
                    search = searches[i]
                }
                guard let url = search.url(for: text) else {
                    throw CommandError.notAvailable(L10n.tr("Adres wyszukiwania „\(search.name)” nie jest adresem http(s)"))
                }
                ctx.ui?.openURL(url)
                return CommandResult(value: .string(url.absoluteString))
            },
            Command(CommandDescriptor(id: "edit.openInExternalEditor", title: L10n.tr("Otwórz w zewnętrznym edytorze"), category: .edit,
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Otwiera tekst okna w programie z Preferencji (np. Visual Studio Code); po powrocie do Pelikana zmiany są wczytywane."),
                                      feature: "PD-EDIT-028"),
                    validate: { editorDocument($0) != nil }) { ctx in
                guard let doc = editorDocument(ctx.workspace) else { return .ok }
                let url = try ctx.workspace.prepareExternalEdit(doc)
                let app = ctx.workspace.settings.externalEditor?.trimmingCharacters(in: .whitespaces)
                ctx.ui?.openInApplication(url, application: app?.isEmpty == false ? app : nil)
                return CommandResult(value: .string(url.lastPathComponent))
            },
            Command(CommandDescriptor(id: "tools.documents", title: L10n.tr("Dokumenty…"), category: .tools,
                                      parameters: [CommandParameter("title", .string, L10n.tr("Tytuł dokumentu (domyślnie wybór z listy)"))],
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Otwiera dokument użytkownika z listy w Preferencjach (plik albo adres http/https)."),
                                      feature: "PD-DOC-002"),
                    validate: { !$0.settings.userDocuments.isEmpty }) { ctx in
                let docs = ctx.workspace.settings.userDocuments
                var chosen: UserDocument?
                if let t = ctx.arguments.string("title") {
                    chosen = docs.first { $0.title.caseInsensitiveCompare(t) == .orderedSame }
                    if chosen == nil { throw CommandError.invalidArgument("title", t) }
                } else if docs.count == 1 {
                    chosen = docs[0]
                } else if let ui = ctx.ui {
                    guard let i = await ui.ask(L10n.tr("Dokumenty"), message: L10n.tr("Wybierz dokument."), buttons: docs.prefix(8).map(\.title)) else {
                        throw CommandError.cancelledByUser
                    }
                    chosen = docs[i]
                }
                guard let d = chosen else { return .ok }
                guard let url = d.url else { throw CommandError.notAvailable(L10n.tr("Nie można otworzyć „\(d.location)”")) }
                ctx.ui?.openURL(url)
                return CommandResult(value: .string(d.title))
            },
            Command(CommandDescriptor(id: "file.restoreRecovery", title: L10n.tr("Odzyskaj okna…"), category: .file,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera okna z niezapisanymi zmianami zachowane przed nieoczekiwanym zamknięciem Pelikana."),
                                      feature: "PD-FILE-001"),
                    validate: { $0.pendingRecovery != nil }) { ctx in
                guard let w = ctx.workspace.pendingRecovery else { return .ok }
                let before = ctx.workspace.documents.count
                ctx.workspace.appendWorksetDocuments(w)
                ctx.workspace.pendingRecovery = nil
                ctx.workspace.recovery.discardPrevious()
                return CommandResult(message: L10n.tr("Odzyskano okien: \(ctx.workspace.documents.count - before)"))
            },
        ]
    }
}

extension Workspace {
    /// Zewnętrzne porównanie: teksty w plikach 0600 w `Diff/` katalogu danych, program z dyrektywami `%1…%4`.
    public func openExternalDiff(_ tool: ExternalDiffTool, left: String, right: String, leftTitle: String, rightTitle: String) throws {
        guard let exe = UserTools.resolve(tool.program) else {
            throw CommandError.notAvailable(L10n.tr("Nie znaleziono programu porównującego „\(tool.program)”"))
        }
        let base = dataDirectory ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Diff", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Pliki poprzednich porównań — sprzątane po dobie.
        if let old = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for f in old where (Self.modificationDate(f) ?? Date()) < Date().addingTimeInterval(-86_400) { try? FileManager.default.removeItem(at: f) }
        }
        func file(_ title: String, _ text: String, _ side: String) -> URL {
            let safe = title.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }.prefix(40)
            let u = dir.appendingPathComponent("\(UUID().uuidString.prefix(8))-\(side)-\(safe.isEmpty ? "tekst" : String(safe)).txt")
            _ = FileManager.default.createFile(atPath: u.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600])
            return u
        }
        let l = file(leftTitle, left, "1"), r = file(rightTitle, right, "2")
        try launchProgram(exe, tool.expandedArguments(left: l.path, right: r.path, leftTitle: leftTitle, rightTitle: rightTitle))
    }
}
