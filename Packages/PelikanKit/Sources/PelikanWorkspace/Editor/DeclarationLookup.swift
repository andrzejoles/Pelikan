import Foundation
import PelikanSQL

/// Nawigacja hiperłączami (UG 25.19, PD-CA-012): deklaracja jednostki albo jej podprogramu najpierw w źródle
/// bieżącego okna, potem w innych otwartych oknach programu — dopiero bez trafienia obiekt z bazy w nowym oknie.
public enum DeclarationLookup {
    public struct Hit: Sendable, Equatable {
        public var documentIndex: Int
        public var range: Range<Int>
    }

    /// `parts` — nazwa `[schemat.]jednostka[.element]` (wielkimi literami); `texts` — teksty okien, bieżące pierwsze.
    public static func find(_ parts: [String], in texts: [String]) -> Hit? {
        guard !parts.isEmpty else { return nil }
        // Warianty: jednostka.element, schemat.jednostka.element, schemat.jednostka, jednostka.
        var candidates: [(unit: String, member: String?)] = []
        if parts.count >= 3 { candidates.append((parts[1], parts[2])) }
        if parts.count == 2 { candidates.append((parts[0], parts[1])); candidates.append((parts[1], nil)) }
        if parts.count == 1 { candidates.append((parts[0], nil)) }
        for (i, text) in texts.enumerated() {
            let roots = PLSQLOutline.parse(text)
            for c in candidates {
                let units = roots.filter { $0.name.uppercased() == c.unit && $0.isContainer }
                guard !units.isEmpty else { continue }
                if let member = c.member {
                    // Implementacja w ciele, a bez ciała — deklaracja w specyfikacji.
                    let ordered = units.sorted { rank($0.kind) < rank($1.kind) }
                    for u in ordered {
                        if let m = u.children.first(where: { [.procedure, .function, .variable, .constant, .cursor, .typeDeclaration, .exception].contains($0.kind)
                                                             && $0.name.uppercased() == member }) {
                            return Hit(documentIndex: i, range: m.nameOffset..<(m.nameOffset + (m.name as NSString).length))
                        }
                    }
                    continue
                }
                // Sama jednostka: specyfikacja przed ciałem.
                let u = units.sorted { rank($0.kind) > rank($1.kind) }[0]
                return Hit(documentIndex: i, range: u.nameOffset..<(u.nameOffset + (u.name as NSString).length))
            }
        }
        return nil
    }

    static func rank(_ k: OutlineNode.Kind) -> Int { [.packageBody, .typeBody].contains(k) ? 0 : 1 }

    /// Okna do przeszukania: bieżące, potem pozostałe okna programu, SQL i testu.
    @MainActor
    static func search(_ parts: [String], current: Document, in ws: Workspace) -> (Document, Range<Int>)? {
        let others = ws.documents.filter { $0.id != current.id && [.program, .sql, .test].contains($0.kind) }
        let docs = [current] + others
        guard let hit = find(parts, in: docs.map(\.text)) else { return nil }
        return (docs[hit.documentIndex], hit.range)
    }
}

/// Menu obiektu bazy na nazwie w edytorze (UG 25.9, PD-EDIT-025): działania jak w Object Browserze — komenda i tytuł;
/// każda komenda dostaje nazwę spod kursora w argumencie `object`.
public enum EditorObjectMenu {
    public static var actions: [(command: CommandID, title: String)] {
        [("ob.queryData", L10n.tr("Pokaż dane")), ("ob.editData", L10n.tr("Edytuj dane")), ("ob.describe", L10n.tr("Opis")),
         ("ob.edit", L10n.tr("Edytuj")), ("ob.ddl", L10n.tr("DDL")), ("ob.properties", L10n.tr("Właściwości")),
         ("ob.recompile", L10n.tr("Rekompiluj")), ("ob.compare", L10n.tr("Porównaj z aktywnym oknem")), ("ob.test", L10n.tr("Testuj"))]
    }

    /// Nazwa obiektu pod kursorem do menu (identyfikator spoza słów kluczowych albo nazwa kwalifikowana).
    public static func objectName(at offset: Int, in text: String) -> String? {
        guard let word = TextEditing.identifier(at: offset, in: text), !Keywords.isKeyword(word) || word.contains(".") else { return nil }
        return word
    }
}
