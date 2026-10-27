import Foundation

/// Ikony rodzajów obiektów (symbole SF) — jedne w Object Browserze, Code Contents i podpowiedziach edytora.
public enum ObjectSymbols {
    /// Symbol typu obiektu bazy.
    public static func symbol(for t: DBObjectType) -> String {
        switch t {
        case .table: "tablecells"
        case .view, .materializedView: "eye"
        case .sequence: "number"
        case .synonym: "arrowshape.turn.up.right"
        case .package, .packageBody: "shippingbox"
        case .function: "f.square"
        case .procedure: "p.square"
        case .type, .typeBody: "t.square"
        case .trigger: "bolt"
        case .index: "list.number"
        case .user: "person"
        case .role: "person.2"
        case .databaseLink: "link"
        case .mleModule, .mleEnvironment: "curlybraces"
        case .domain: "checkmark.seal"
        case .annotation: "tag"
        case .assertion: "checkmark.shield"
        default: "doc"
        }
    }
}
