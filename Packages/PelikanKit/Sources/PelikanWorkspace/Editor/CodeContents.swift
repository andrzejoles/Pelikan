import Foundation
import PelikanSQL

/// Code Contents (UG 25.15, PD-CA-010): kolejność elementów drzewa i działania na elemencie (zaznacz, kopiuj,
/// wytnij, testuj) — wspólne dla panelu i komend.
public enum CodeContents {
    /// Kolejność elementów: jak w źródle, alfabetycznie, według rodzaju (deklaracje, potem podprogramy).
    public enum Order: String, Sendable, Codable, Hashable, CaseIterable { case source, name, kind }

    /// Zarys tekstu okna (D199): okno SQL — skrypt (polecenia SQL obok jednostek i bloków PL/SQL), okno programu
    /// i testu — PL/SQL. Ten sam zarys dla panelu i komend menu elementu; `controlFlow` — ze strukturami sterującymi
    /// (D203, ustawienie `codeContentsControlFlow`).
    public static func outline(_ text: String, kind: DocumentKind, controlFlow: Bool = false) -> [OutlineNode] {
        analyze(text, kind: kind, controlFlow: controlFlow).nodes
    }

    /// Zarys z liczbą poleceń SQL pominiętych ponad limit (panel pokazuje dopisek); `isCancelled` — analiza w tle.
    public static func analyze(_ text: String, kind: DocumentKind, controlFlow: Bool = false,
                               isCancelled: () -> Bool = { false }) -> PLSQLOutline.ScriptOutline {
        kind == .sql ? PLSQLOutline.parseScriptOutline(text, controlFlow: controlFlow, isCancelled: isCancelled)
            : PLSQLOutline.ScriptOutline(nodes: PLSQLOutline.parse(text, controlFlow: controlFlow))
    }

    /// Najwięcej znaków nagłówka struktury sterującej w tytule węzła (pełny nagłówek w podpowiedzi).
    public static let controlTitleLimit = 60

    /// Tytuł struktury sterującej w drzewie (D203): słowo otwierające z etykietą i skróconym do jednej linii
    /// nagłówkiem — „IF warunek…”, „FOR r IN cur LOOP”, „WHILE warunek LOOP”, „CASE wybór”, „WHEN NO_DATA_FOUND”.
    public static func controlTitle(_ n: OutlineNode) -> String {
        var d = n.detail.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if d.count > controlTitleLimit || d.hasSuffix("…") {
            d = String(d.prefix(controlTitleLimit)).trimmingCharacters(in: .whitespaces)
            if !d.hasSuffix("…") { d += "…" }
        }
        let s: String
        switch n.kind {
        case .loop: s = n.name == "LOOP" ? "LOOP" : n.name + (d.isEmpty ? "" : " " + d) + " LOOP"
        case .elseBranch, .exceptionSection, .beginSection, .block: s = n.kind == .block ? "BEGIN" : n.name
        default: s = d.isEmpty ? n.name : n.name + " " + d
        }
        return (n.label.map { "<<\($0)>> " } ?? "") + s
    }

    /// Zakres zaznaczany po przejściu do elementu (klik, Enter w panelu): nazwa elementu, a w bloku — słowo
    /// otwierające (DECLARE albo BEGIN); struktura sterująca — słowo otwierające.
    public static func selection(of n: OutlineNode, in text: String) -> Range<Int> {
        guard n.kind == .block else { return n.nameOffset..<(n.nameOffset + (n.name as NSString).length) }
        let ns = text as NSString
        var e = n.nameOffset
        while e < ns.length, let u = Unicode.Scalar(ns.character(at: e)), CharacterSet.letters.contains(u) { e += 1 }
        return n.nameOffset..<e
    }

    /// Drzewo posortowane na każdym poziomie; sekcje i bloki zostają na swoich miejscach względem siebie. Struktury
    /// sterujące zawsze w kolejności źródła — za elementami sortowanymi (deklaracje, podprogramy).
    public static func sorted(_ nodes: [OutlineNode], order: Order) -> [OutlineNode] {
        let children = nodes.map { n -> OutlineNode in
            guard !n.children.isEmpty else { return n }
            var n = n
            // Parametry zostają w kolejności nagłówka (tytuł i podpowiedź podprogramu), sortowane są tylko elementy.
            n.children = n.children.filter { $0.kind == .parameter } + sorted(n.children.filter { $0.kind != .parameter }, order: order)
            return n
        }
        // Bloki jak struktury — w kolejności źródła.
        func inSourceOrder(_ n: OutlineNode) -> Bool { n.kind.isControlFlow || n.kind == .block }
        if order != .source, children.contains(where: inSourceOrder) {
            return sorted(children.filter { !inSourceOrder($0) }, order: order, sortedChildren: true) + children.filter(inSourceOrder)
        }
        return sorted(children, order: order, sortedChildren: true)
    }

    private static func sorted(_ children: [OutlineNode], order: Order, sortedChildren: Bool) -> [OutlineNode] {
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
            // Polecenie SQL i struktura sterująca — także po tekście za pierwszym słowem (nazwa tabeli, warunek,
            // zakres pętli) i po etykiecie.
            let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            let matches = n.name.range(of: f, options: opts) != nil
                || ((n.kind == .statement || n.kind.isControlFlow) && n.detail.range(of: f, options: opts) != nil)
                || (n.label?.range(of: f, options: opts) != nil)
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
        // Struktura sterująca — pełny nagłówek (do 1000 znaków) ze słowem kończącym nagłówek.
        case .ifStatement, .elsifBranch, .whenBranch, .exceptionHandler:
            s = (n.label.map { "<<\($0)>> " } ?? "") + n.name + (n.detail.isEmpty ? "" : " " + n.detail) + " THEN"
        case .loop:
            s = (n.label.map { "<<\($0)>> " } ?? "") + n.name + (n.detail.isEmpty || n.name == "LOOP" ? "" : " " + n.detail + " LOOP")
        case .block: s = (n.label.map { "<<\($0)>> " } ?? "") + n.name
        case .caseStatement, .forall, .elseBranch, .exceptionSection, .beginSection, .timingPoint:
            s = (n.label.map { "<<\($0)>> " } ?? "") + (n.detail.isEmpty ? n.name : n.name + " " + n.detail)
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
        case .ifStatement, .elsifBranch, .elseBranch, .loop, .forall, .caseStatement, .whenBranch, .exceptionHandler, .timingPoint: 9
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

    /// Argumenty `ob.test` dla najbliższej procedury albo funkcji obejmującej pozycję (także z bloku zagnieżdżonego
    /// albo struktury sterującej w jej ciele).
    public static func testTarget(at offset: Int, in text: String, kind: DocumentKind) -> (object: String, member: String?)? {
        let roots = outline(text, kind: kind)
        guard let node = PLSQLOutline.path(at: offset, in: roots).last(where: { [.procedure, .function].contains($0.kind) }) else { return nil }
        return testTarget(for: node, in: roots)
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
    /// Pozycja wskazana (menu panelu) — element w tym miejscu, także struktura sterująca (gdy pokazywane); bez niej —
    /// element pod kursorem z zarysu bez struktur: podprogram, deklaracja, blok albo jednostka (D203).
    static let params = [CommandParameter("offset", .integer, L10n.tr("Pozycja elementu w tekście — element w tym miejscu, także struktura sterująca; bez argumentu — podprogram, deklaracja, blok albo jednostka pod kursorem"))]

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
            Command(CommandDescriptor(id: "codeContents.controlFlow", title: L10n.tr("Struktury sterujące w Zawartości kodu"), category: .edit,
                                      submenu: L10n.tr("Zawartość kodu"),
                                      parameters: [CommandParameter("visible", .boolean, L10n.tr("Pokaż (true) albo ukryj (false) struktury sterujące; bez argumentu — przełącza"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Pokazuje lub ukrywa w panelu Zawartość kodu struktury sterujące (IF, pętle, CASE, obsługę wyjątków; bloki BEGIN zostają) we wszystkich oknach (zapamiętane w Ustawieniach)."),
                                      inMenu: false, feature: "PD-CA-010")) { ctx in
                let show = ctx.arguments.bool("visible") ?? !ctx.workspace.settings.codeContentsControlFlow
                ctx.workspace.settings.codeContentsControlFlow = show
                // Makro odtwarza stan, a nie przełączenie (przycisk i menu panelu wywołują bez argumentu).
                return CommandResult(value: .bool(show), resolvedArguments: CommandArguments(["visible": .bool(show)]))
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
                // Najbliższa procedura albo funkcja obejmująca pozycję (także z bloku zagnieżdżonego albo struktury).
                guard let doc = BuiltinCommands.editable(ctx.workspace) else { throw CommandError.notAvailable(L10n.tr("Brak aktywnego okna z tekstem")) }
                let offset = ctx.arguments.int("offset").map(Int.init) ?? doc.selectedRange.lowerBound
                guard let t = CodeContents.testTarget(at: offset, in: doc.text, kind: doc.kind) else {
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
        let given = ctx.arguments.int("offset").map(Int.init)
        let offset = given ?? doc.selectedRange.lowerBound
        // Z pozycją (menu panelu) — węzeł panelu, także struktura sterująca; bez niej (paleta, skrót, makro) — jak
        // dotąd podprogram, deklaracja albo jednostka pod kursorem (D203).
        let controlFlow = given != nil && ctx.workspace.settings.codeContentsControlFlow
        let outline = CodeContents.outline(doc.text, kind: doc.kind, controlFlow: controlFlow)
        guard let node = CodeContents.element(at: offset, in: outline) else {
            throw CommandError.notAvailable(L10n.tr("Brak elementu w tym miejscu"))
        }
        return (doc, node)
    }

    static func substring(_ text: String, _ r: Range<Int>) -> String {
        (text as NSString).substring(with: NSRange(location: r.lowerBound, length: r.count))
    }
}
