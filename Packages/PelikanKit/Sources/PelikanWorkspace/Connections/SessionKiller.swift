import Foundation
import PelikanDB

/// Zakończenie sesji okna z innej sesji (PD-CONN-027) i SQL Trace sesji okna (PD-OPT-008).
public enum SessionKiller {
    /// `ALTER SYSTEM KILL SESSION 'sid,serial#,@instancja' IMMEDIATE`. Numer seryjny zapamiętany przy otwarciu sesji —
    /// para SID+serial# wskazuje dokładnie tę sesję (SID zakończonej sesji serwer mógł przydzielić innej; wtedy
    /// ORA-00030 „sesja nie istnieje”). Bez zapamiętanego numeru — odczyt z GV$SESSION w chwili zabicia.
    public static func kill(sid: String, serial: String? = nil, instance: String, using s: any DatabaseSession) async throws {
        guard sid.allSatisfy(\.isNumber), instance.allSatisfy(\.isNumber) else { throw CommandError.invalidArgument("sid", sid) }
        var serialNumber = serial
        if serialNumber == nil {
            serialNumber = try await s.scalar("select serial# from gv$session where sid = :s and inst_id = :i",
                                              binds: [BindVariable(name: "s", type: .number, value: .text(sid)),
                                                      BindVariable(name: "i", type: .number, value: .text(instance))])
        }
        guard let serial = serialNumber else { throw CommandError.notAvailable(L10n.tr("Sesja \(sid) już nie istnieje")) }
        guard !serial.isEmpty, serial.allSatisfy(\.isNumber) else { throw CommandError.invalidArgument("serial", serial) }
        do {
            _ = try await s.execute("alter system kill session '\(sid),\(serial),@\(instance)' immediate")
        } catch let e as OracleError where e.code == 30 {
            throw CommandError.notAvailable(L10n.tr("Sesja \(sid) już nie istnieje"))
        } catch {
            // ORA-00031 „sesja oznaczona do zakończenia” — sesja zajęta zostanie zakończona; to sukces (ODPI-C zgłasza go
            // jako zamknięcie połączenia DPI-1080, więc sesję narzędziową i tak trzeba potem zamknąć).
            guard "\(error)".contains("ORA-00031") else { throw error }
        }
    }

    /// Włącza albo wyłącza SQL Trace sesji (DBMS_SESSION); zwraca plik śladu (V$DIAG_INFO), gdy dostępny.
    public static func setSQLTrace(_ enable: Bool, in s: any DatabaseSession) async throws -> String? {
        _ = try await s.execute(enable ? "begin dbms_session.session_trace_enable(waits => true, binds => false); end;"
                                       : "begin dbms_session.session_trace_disable; end;")
        guard enable else { return nil }
        return try? await s.scalar("select value from v$diag_info where name = 'Default Trace File'")
    }
}
