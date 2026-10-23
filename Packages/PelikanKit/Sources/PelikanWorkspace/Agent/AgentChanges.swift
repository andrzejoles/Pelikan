import Foundation
import PelikanDB
import PelikanSQL

/// Zmiany w bazie wykonywane przez agenta (PROMPT §7.3 p.5–6): podgląd przed zgodą, DML niezatwierdzone,
/// historia kodu obiektów przed zmianą.
public enum AgentChanges {
    /// EXPLAIN PLAN dla jednego zapytania albo DML (polecenie nie jest wykonywane); wynik DBMS_XPLAN i szacowana
    /// liczba wierszy z korzenia planu. Wiersze PLAN_TABLE są usuwane bez naruszania otwartej transakcji agenta.
    static func explain(_ sql: String, in s: any DatabaseSession) async throws -> (text: String, rows: Int64?) {
        let parts = ScriptSplitter.split(sql)
        guard parts.count == 1, let only = parts.first, [.query, .dml].contains(only.category) else {
            throw CommandError.invalidArgument("sql", L10n.tr("plan wykonania dla jednego zapytania albo polecenia DML"))
        }
        var text = only.text.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(";") { text.removeLast() }
        let id = "PLK" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20)
        let pending = try await s.scalar("select dbms_transaction.local_transaction_id from dual") != nil
        _ = try await s.execute("explain plan set statement_id = '\(id)' for \(text)")
        let b = [BindVariable(name: "id", value: .text(id))]
        let (_, rows) = try await s.queryAll("select plan_table_output from table(dbms_xplan.display('PLAN_TABLE', :id, 'TYPICAL'))", binds: b, limit: 2000)
        let card = try await s.scalar("select cardinality from plan_table where statement_id = :id and id = 0", binds: b).flatMap { Int64($0) }
        if pending { _ = try? await s.execute("delete from plan_table where statement_id = :id", binds: b) } else { try? await s.rollback() }
        return (rows.map { $0.first?.displayText ?? "" }.joined(separator: "\n"), card)
    }
}
