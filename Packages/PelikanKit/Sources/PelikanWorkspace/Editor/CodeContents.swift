import Foundation
import PelikanSQL

/// Code Contents (UG 25.15, PD-CA-010): kolejność elementów drzewa i działania na elemencie (zaznacz, kopiuj,
/// wytnij, testuj) — wspólne dla panelu i komend.
public enum CodeContents {
    /// Kolejność elementów: jak w źródle, alfabetycznie, według rodzaju (deklaracje, potem podprogramy).
    public enum Order: String, Sendable, Codable, Hashable, CaseIterable { case source, name, kind }

    /// Zarys tekstu okna (D199): okno SQL — skrypt (polecenia SQL obok jednostek i bloków PL/SQL), okno programu
    /// i testu — PL/SQL. Ten sam zarys dla panelu i komend menu elementu.
    public static func outline(_ text: String, kind: DocumentKind) -> [OutlineNode] { analyze(text, kind: kind).nodes }

    /// Zarys z liczbą poleceń SQL pominiętych ponad limit (panel pokazuje dopisek); `isCancelled` — analiza w tle.
    public static func analyze(_ text: String, kind: DocumentKind, isCancelled: () -> Bool = { false }) -> PLSQLOutline.ScriptOutline {
        kind == .sql ? PLSQLOutline.parseScriptOutline(text, isCancelled: isCancelled) : PLSQLOutline.ScriptOutline(nodes: PLSQLOutline.parse(text))
    }

    /// Drzewo posortowane na każdym poziomie; sekcje i bloki zostają na swoich miejscach względem siebie.
    public static func sorted(_ nodes: [OutlineNode], order: Order) -> [OutlineNode] {
        let children = nodes.map { n -> OutlineNode in
            var n = n
            // Parametry zostają w kolejności nagłówka (tytuł i podpowiedź podprogramu), sortowane są tylko elementy.
            n.children = n.children.filter { $0.kind == .parameter } + sorted(n.children.filter { $0.kind != .parameter }, order: order)
            return n
        }
        switch order {
        case .source:
            return children
        case .name:
            return children.enumerated().sorted { a, b in
                let x = a.element.name.uppercased(), y = b.element.name.uppercased()
                return x == y ? a.offset < b.offset : x < y
            }.map(\.element)
        case .kind:
            return children.enumerated().sorted { a, b in
                let x = rank(a.element.kind), y = rank(b.element.kind)
                return x == y ? a.offset < b.offset : x < y
            }.map(\.element)
        }
    }

    /// Filtr nazw panelu (pole nad drzewem): elementy, których nazwa zawiera tekst (bez wielkości liter), z przodkami;
    /// pasujący przodek nie pokazuje przez to wszystkich dzieci. Pusty filtr — drzewo bez zmian.
    public static func filtered(_ nodes: [OutlineNode], matching filter: String) -> [OutlineNode] {
        let f = filter.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return nodes }
        return nodes.compactMap { n in
            var n = n
            let kids = filtered(n.children.filter { $0.kind != .parameter }, matching: f)
            // Polecenie SQL — także po tekście za pierwszym słowem (nazwa tabeli, widoku).
            let matches = n.name.range(of: f, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || (n.kind == .statement && n.detail.range(of: f, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
            guard matches || !kids.isEmpty else { return nil }
            n.children = n.children.filter { $0.kind == .parameter } + kids
            return n
        }
    }

    /// Pełny opis elementu do podpowiedzi panelu: nagłówek podprogramu z parametrami (tryb i typ) i typem zwracanym,
    /// deklaracja typu, kursora, zmiennej; dopisek „publiczny”/„prywatny” dla elementów pakietu.
    public static func signature(of n: OutlineNode) -> String {
        var s: String
        switch n.kind {
        case .procedure, .function:
            let params = n.children.filter { $0.kind == .parameter }.map { ($0.name + " " + $0.detail).trimmingCharacters(in: .whitespaces) }
            s = (n.kind == .procedure ? "PROCEDURE " : "FUNCTION ") + n.name + (params.isEmpty ? "" : "(" + params.joined(separator: ", ") + ")")
            if !n.detail.isEmpty { s += " RETURN " + n.detail }
        case .package: s = "PACKAGE " + n.name
        case .packageBody: s = "PACKAGE BODY " + n.name
        case .type: s = "TYPE " + n.name
        case .typeBody: s = "TYPE BODY " + n.name
        case .trigger: s = "TRIGGER " + n.name
        case .cursor: s = "CURSOR " + n.name + (n.detail.isEmpty ? "" : (n.detail.hasPrefix("(") ? "" : " ") + n.detail)
        case .typeDeclaration:
            s = n.detail.hasPrefix("SUBTYPE ") ? "SUBTYPE " + n.name + " IS " + n.detail.dropFirst(8) : "TYPE " + n.name + (n.detail.isEmpty ? "" : " IS " + n.detail)
        case .exception: s = n.name + " EXCEPTION"
        case .constant: s = n.name + " CONSTANT " + n.detail
        case .pragma: s = "PRAGMA " + n.name + n.detail
        default: s = n.detail.isEmpty ? n.name : n.name + " " + n.detail
        }
        if let p = n.isPublic { s += " — " + (p ? L10n.tr("publiczny") : L10n.tr("prywatny")) }
        return s
    }

    static func rank(_ k: OutlineNode.Kind) -> Int {
        switch k {
        case .package, .type, .packageBody, .typeBody, .trigger: 0
        case .parameter: 1
        case .constant: 2
        case .typeDeclaration: 3
        case .variable: 4
        case .cursor: 5
        case .exception, .pragma: 6
        case .function: 7
        case .procedure: 8
        case .declareSection, .beginSection, .exceptionSection, .block, .statement: 9
        }
    }

    /// Najgłębszy element zawierający pozycję (także deklaracja).
    public static func element(at offset: Int, in nodes: [OutlineNode]) -> OutlineNode? {
        var found: OutlineNode?
        var level = nodes
        while let n = level.first(where: { $0.range.contains(offset) || $0.nameOffset == offset }) {
            found = n
            level = n.children
        }
        return found
    }

    /// Element rozszerzony do pełnych linii (z wcięciem i końcem linii) — do zaznaczenia, kopiowania i wycięcia.
    public static func lineRange(of node: OutlineNode, in text: String) -> Range<Int> {
        let ns = text as NSString
        let r = node.range.clamped(to: 0..<ns.length)
        let lines = ns.lineRange(for: NSRange(location: r.lowerBound, length: max(0, r.count)))
        // Jednostka kończy się przed „/” — tylko linie elementu, bez kolejnych niepustych znaków za nim.
        let afterEnd = ns.substring(with: NSRange(location: r.upperBound, length: lines.upperBound - r.upperBound))
        let end = afterEnd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? lines.upperBound : r.upperBound
        let before = ns.substring(with: NSRange(location: lines.location, length: r.lowerBound - lines.location))
        let start = before.trimmingCharacters(in: .whitespaces).isEmpty ? lines.location : r.lowerBound
        return start..<end
    }

    /// Argumenty komendy `ob.test` dla podprogramu: samodzielny — obiekt; w pakiecie — pakiet i element.
    public static func testTarget(for node: OutlineNode, in roots: [OutlineNode]) -> (object: String, member: String?)? {
        guard [.procedure, .function].contains(node.kind) else { return nil }
        let path = PLSQLOutline.path(at: node.nameOffset, in: roots)
        if let unit = path.first, [.package, .packageBody].contains(unit.kind), unit.range != node.range {
            return (unit.name, node.name)
        }
        if let unit = path.first, unit.range == node.range { return (node.name, nil) }
        return nil
    }
}

extension Workspace {
    /// Czy okno pokazuje panel Zawartość kodu (D199): wybór w oknie, a bez niego — ustawienie domyślne z Ustawień.
    /// Okna bez panelu (konsola SQL*Plus, plan, raport, diagram, notatnik) — false.
    public func showsCodeContents(_ doc: Document) -> Bool {
        doc.kind.hasCodeContents && (doc.codeContentsVisible ?? settings.showCodeContents)
    }
}

/// Komendy menu Code Contents (PD-CA-010) — element wskazany pozycją (`offset`, domyślnie kursor).
enum CodeContentsCommands {
    static let params = [CommandParameter("offset", .integer, L10n.tr("Pozycja elementu w tekście (domyślnie kursor)"))]

    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "codeContents.sort", title: L10n.tr("Kolejność w Zawartości kodu"), category: .edit, submenu: L10n.tr("Zawartość kodu"),
                                      parameters: [CommandParameter("order", .string, required: true, L10n.tr("Kolejność: source (jak w źródle), name (alfabetycznie), kind (według rodzaju)"),
                                                                    allowed: CodeContents.Order.allCases.map(\.rawValue))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Ustawia kolejność elementów w panelu Zawartość kodu (zapamiętana w Ustawieniach)."),
                                      inMenu: false, feature: "PD-CA-010")) { ctx in
                let raw = ctx.arguments.string("order") ?? ""
                guard let order = CodeContents.Order(rawValue: raw) else { throw CommandError.invalidArgument("order", raw) }
                ctx.workspace.settings.codeContentsOrder = order
                return .ok
            },
            Command(CommandDescriptor(id: "codeContents.select", title: L10n.tr("Zaznacz element"), category: .edit, submenu: L10n.tr("Zawartość kodu"),
                                      parameters: params, agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zaznacza w edytorze cały element Zawartości kodu (podprogram, deklarację, jednostkę)."),
                                      inMenu: false, feature: "PD-CA-010"),
                    validate: { BuiltinCommands.editable($0) != nil }) { ctx in
                let (doc, node) = try target(ctx)
                let r = CodeContents.lineRange(of: node, in: doc.text)
                doc.selectedRange = r
                return CommandResult(message: "\(node.kind.rawValue) \(node.name)")
            },
            Command(CommandDescriptor(id: "codeContents.copy", title: L10n.tr("Kopiuj element"), category: .edit, submenu: L10n.tr("Zawartość kodu"),
                                      parameters: params, agent: .none, effect: .none,
                                      summary: L10n.tr("Kopiuje do schowka tekst elementu Zawartości kodu."), inMenu: false, feature: "PD-CA-010"),
                    validate: { BuiltinCommands.editable($0) != nil }) { ctx in
                let (doc, node) = try target(ctx)
                let text = substring(doc.text, CodeContents.lineRange(of: node, in: doc.text))
                if ctx.invoker == .user { ctx.ui?.copyToClipboard(text, html: nil) }
                return CommandResult(message: text, value: .string(text))
            },
            Command(CommandDescriptor(id: "codeContents.cut", title: L10n.tr("Wytnij element"), category: .edit, submenu: L10n.tr("Zawartość kodu"),
                                      parameters: params, agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Wycina element Zawartości kodu z tekstu okna (do schowka)."), inMenu: false, feature: "PD-CA-010"),
                    validate: { BuiltinCommands.editable($0).map { !$0.isReadOnly } ?? false }) { ctx in
                let (doc, node) = try target(ctx)
                let r = CodeContents.lineRange(of: node, in: doc.text)
                let text = substring(doc.text, r)
                if ctx.invoker == .user { ctx.ui?.copyToClipboard(text, html: nil) }
                doc.text = (doc.text as NSString).replacingCharacters(in: NSRange(location: r.lowerBound, length: r.count), with: "")
                doc.selectedRange = r.lowerBound..<r.lowerBound
                return CommandResult(message: L10n.tr("Wycięto \(node.name)"), value: .string(text))
            },
            Command(CommandDescriptor(id: "codeContents.test", title: L10n.tr("Testuj podprogram"), category: .edit, submenu: L10n.tr("Zawartość kodu"),
                                      parameters: params, agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera okno testu procedury lub funkcji wskazanej w Zawartości kodu (z pakietem jako obiektem)."),
                                      inMenu: false, feature: "PD-CA-010"),
                    validate: { BuiltinCommands.editable($0) != nil }) { ctx in
                let (doc, node) = try target(ctx)
                guard let t = CodeContents.testTarget(for: node, in: PLSQLOutline.parse(doc.text)) else {
                    throw CommandError.notAvailable(L10n.tr("Element nie jest procedurą ani funkcją"))
                }
                var args: [String: JSONValue] = ["object": .string(t.object)]
                if let m = t.member { args["member"] = .string(m) }
                return try await ctx.workspace.invoke("ob.test", CommandArguments(args), invoker: ctx.invoker)
            },
            Command(CommandDescriptor(id: "codeHierarchy.select", title: L10n.tr("Zaznacz poziom hierarchii kodu"), category: .edit,
                                      submenu: L10n.tr("Zawartość kodu"),
                                      parameters: [CommandParameter("level", .integer, L10n.tr("Poziom ścieżki od jednostki (0); domyślnie najgłębszy"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zaznacza element ścieżki hierarchii kodu (jednostkę, podprogram, blok) obejmujący kursor."),
                                      inMenu: false, feature: "PD-CA-011"),
                    validate: { BuiltinCommands.editable($0) != nil }) { ctx in
                let (doc, node) = try hierarchyTarget(ctx)
                doc.selectedRange = CodeContents.lineRange(of: node, in: doc.text)
                return CommandResult(message: "\(node.kind.rawValue) \(node.name)")
            },
            Command(CommandDescriptor(id: "codeHierarchy.goto", title: L10n.tr("Przejdź do poziomu hierarchii kodu"), category: .edit,
                                      submenu: L10n.tr("Zawartość kodu"),
                                      parameters: [CommandParameter("level", .integer, L10n.tr("Poziom ścieżki od jednostki (0); domyślnie najgłębszy"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Przenosi kursor do nazwy elementu ścieżki hierarchii kodu."), inMenu: false, feature: "PD-CA-011"),
                    validate: { BuiltinCommands.editable($0) != nil }) { ctx in
                let (doc, node) = try hierarchyTarget(ctx)
                doc.selectedRange = node.nameOffset..<node.nameOffset
                return CommandResult(message: "\(node.kind.rawValue) \(node.name)")
            },
        ]
    }

    /// Element ścieżki Code Hierarchy (PD-CA-011) przy kursorze aktywnego okna: poziom od jednostki (0).
    @MainActor
    static func hierarchyTarget(_ ctx: CommandContext) throws -> (Document, OutlineNode) {
        guard let doc = BuiltinCommands.editable(ctx.workspace) else { throw CommandError.notAvailable(L10n.tr("Brak aktywnego okna z tekstem")) }
        let path = PLSQLOutline.path(at: doc.selectedRange.lowerBound, in: PLSQLOutline.parse(doc.text))
        guard !path.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak elementu w tym miejscu")) }
        let level = ctx.arguments.int("level").map(Int.init) ?? path.count - 1
        guard path.indices.contains(level) else { throw CommandError.invalidArgument("level", L10n.tr("Poziom poza ścieżką (0–\(path.count - 1))")) }
        return (doc, path[level])
    }

    @MainActor
    static func target(_ ctx: CommandContext) throws -> (Document, OutlineNode) {
        guard let doc = BuiltinCommands.editable(ctx.workspace) else { throw CommandError.notAvailable(L10n.tr("Brak aktywnego okna z tekstem")) }
        let offset = ctx.arguments.int("offset").map(Int.init) ?? doc.selectedRange.lowerBound
        guard let node = CodeContents.element(at: offset, in: CodeContents.outline(doc.text, kind: doc.kind)) else {
            throw CommandError.notAvailable(L10n.tr("Brak elementu w tym miejscu"))
        }
        return (doc, node)
    }

    static func substring(_ text: String, _ r: Range<Int>) -> String {
        (text as NSString).substring(with: NSRange(location: r.lowerBound, length: r.count))
    }
}
