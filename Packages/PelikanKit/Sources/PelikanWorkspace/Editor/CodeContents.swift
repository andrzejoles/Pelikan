import Foundation
import PelikanSQL

/// Code Contents (UG 25.15, PD-CA-010): kolejność elementów drzewa i działania na elemencie (zaznacz, kopiuj,
/// wytnij, testuj) — wspólne dla panelu i komend.
public enum CodeContents {
    /// Kolejność elementów: jak w źródle, alfabetycznie, według rodzaju (deklaracje, potem podprogramy).
    public enum Order: String, Sendable, Codable, Hashable, CaseIterable { case source, name, kind }

    /// Drzewo posortowane na każdym poziomie; sekcje i bloki zostają na swoich miejscach względem siebie.
    public static func sorted(_ nodes: [OutlineNode], order: Order) -> [OutlineNode] {
        let children = nodes.map { n -> OutlineNode in
            var n = n
            n.children = sorted(n.children, order: order)
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

    static func rank(_ k: OutlineNode.Kind) -> Int {
        switch k {
        case .package, .type, .packageBody, .typeBody, .trigger: 0
        case .parameter: 1
        case .constant: 2
        case .typeDeclaration: 3
        case .variable: 4
        case .cursor: 5
        case .exception: 6
        case .function: 7
        case .procedure: 8
        case .declareSection, .beginSection, .exceptionSection, .block: 9
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

/// Komendy menu Code Contents (PD-CA-010) — element wskazany pozycją (`offset`, domyślnie kursor).
enum CodeContentsCommands {
    static let params = [CommandParameter("offset", .integer, L10n.tr("Pozycja elementu w tekście (domyślnie kursor)"))]

    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "codeContents.select", title: L10n.tr("Zaznacz element"), category: .edit, submenu: L10n.tr("Zawartość kodu"),
                                      parameters: params, agent: .full, effect: .uiState,
                                      summary: L10n.tr("Zaznacza w edytorze cały element Code Contents (podprogram, deklarację, jednostkę)."),
                                      inMenu: false, feature: "PD-CA-010"),
                    validate: { BuiltinCommands.editable($0) != nil }) { ctx in
                let (doc, node) = try target(ctx)
                let r = CodeContents.lineRange(of: node, in: doc.text)
                doc.selectedRange = r
                return CommandResult(message: "\(node.kind.rawValue) \(node.name)")
            },
            Command(CommandDescriptor(id: "codeContents.copy", title: L10n.tr("Kopiuj element"), category: .edit, submenu: L10n.tr("Zawartość kodu"),
                                      parameters: params, agent: .read, effect: .none,
                                      summary: L10n.tr("Kopiuje do schowka tekst elementu Code Contents."), inMenu: false, feature: "PD-CA-010"),
                    validate: { BuiltinCommands.editable($0) != nil }) { ctx in
                let (doc, node) = try target(ctx)
                let text = substring(doc.text, CodeContents.lineRange(of: node, in: doc.text))
                if ctx.invoker == .user { ctx.ui?.copyToClipboard(text, html: nil) }
                return CommandResult(message: text, value: .string(text))
            },
            Command(CommandDescriptor(id: "codeContents.cut", title: L10n.tr("Wytnij element"), category: .edit, submenu: L10n.tr("Zawartość kodu"),
                                      parameters: params, agent: .full, effect: .modifiesEditor,
                                      summary: L10n.tr("Wycina element Code Contents z tekstu okna (do schowka)."), inMenu: false, feature: "PD-CA-010"),
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
                                      parameters: params, agent: .full, effect: .uiState,
                                      summary: L10n.tr("Otwiera okno testu procedury lub funkcji wskazanej w Code Contents (z pakietem jako obiektem)."),
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
        ]
    }

    @MainActor
    static func target(_ ctx: CommandContext) throws -> (Document, OutlineNode) {
        guard let doc = BuiltinCommands.editable(ctx.workspace) else { throw CommandError.notAvailable(L10n.tr("Brak aktywnego okna z tekstem")) }
        let offset = ctx.arguments.int("offset").map(Int.init) ?? doc.selectedRange.lowerBound
        guard let node = CodeContents.element(at: offset, in: PLSQLOutline.parse(doc.text)) else {
            throw CommandError.notAvailable(L10n.tr("Brak elementu w tym miejscu"))
        }
        return (doc, node)
    }

    static func substring(_ text: String, _ r: Range<Int>) -> String {
        (text as NSString).substring(with: NSRange(location: r.lowerBound, length: r.count))
    }
}
