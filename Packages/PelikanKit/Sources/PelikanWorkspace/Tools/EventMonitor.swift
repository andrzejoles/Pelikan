import Foundation
import Observation
import PelikanDB

/// Monitor zdarzeń (UG 24.13, PD-TOOL-014): alerty DBMS_ALERT i wiadomości DBMS_PIPE odbierane w osobnej sesji.
@MainActor
@Observable
public final class EventMonitor: Identifiable {
    public enum Kind: String, Sendable, CaseIterable { case alert, pipe }

    public struct Event: Sendable, Hashable, Identifiable {
        public let id = UUID()
        public var time: Date
        public var name: String
        public var message: String
    }

    public let id = UUID()
    public let kind: Kind
    public let names: [String]
    public private(set) var events: [Event] = []
    public private(set) var running = false
    public private(set) var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let workspace: Workspace
    @ObservationIgnored private let connectionID: UUID

    public init(kind: Kind, names: [String], connectionID: UUID, in ws: Workspace) {
        self.kind = kind
        self.names = names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        self.connectionID = connectionID
        workspace = ws
    }

    private var key: SessionKey { SessionKey(connectionID: connectionID, purpose: .tool("events-\(id.uuidString.prefix(8))")) }

    public func start() async throws {
        guard !running else { return }
        let s = try await workspace.sessions.session(key)
        if kind == .alert {
            for n in names { _ = try await s.execute("begin dbms_alert.register(:n); end;", binds: [BindVariable(name: "n", value: .text(n))]) }
        }
        running = true
        error = nil
        task = Task { [weak self] in
            while let self, self.running, !Task.isCancelled {
                do {
                    try await self.poll(s)
                } catch {
                    self.error = error.localizedDescription
                    self.running = false
                }
            }
        }
    }

    /// Jedno oczekiwanie (do 1 s) — alert z dowolnej zarejestrowanej nazwy albo wiadomość z każdej rury.
    private func poll(_ s: any DatabaseSession) async throws {
        switch kind {
        case .alert:
            let r = try await s.execute("begin dbms_alert.waitany(:n, :m, :st, 1); end;",
                                        binds: [BindVariable(name: "n", direction: .output, maxSize: 128), BindVariable(name: "m", direction: .output, maxSize: 1800),
                                                BindVariable(name: "st", type: .number, direction: .output)])
            if r.outBinds["st"]?.displayText == "0" {
                append(r.outBinds["n"]?.displayText ?? "", r.outBinds["m"]?.displayText ?? "")
            }
        case .pipe:
            for n in names {
                let r = try await s.execute("""
                    declare st integer; t integer; v varchar2(32767); nv number; dv date; msg varchar2(32767);
                    begin
                      st := dbms_pipe.receive_message(:p, 0);
                      if st = 0 then
                        loop
                          t := dbms_pipe.next_item_type;
                          exit when t = 0;
                          if t = 6 then dbms_pipe.unpack_message(nv); v := to_char(nv);
                          elsif t = 12 then dbms_pipe.unpack_message(dv); v := to_char(dv, 'YYYY-MM-DD HH24:MI:SS');
                          else dbms_pipe.unpack_message(v); end if;
                          msg := msg || case when msg is not null then ' | ' end || v;
                        end loop;
                      end if;
                      :st := st; :m := msg;
                    end;
                    """, binds: [BindVariable(name: "p", value: .text(n)), BindVariable(name: "st", type: .number, direction: .output),
                                 BindVariable(name: "m", direction: .output, maxSize: 32767)])
                if r.outBinds["st"]?.displayText == "0" { append(n, r.outBinds["m"]?.displayText ?? "") }
            }
            try await Task.sleep(for: .milliseconds(300))
        }
    }

    private func append(_ name: String, _ message: String) {
        events.append(Event(time: Date(), name: name, message: message))
        if events.count > 10_000 { events.removeFirst(events.count - 10_000) }
    }

    public func clear() { events.removeAll() }

    public func stop() async {
        running = false
        task?.cancel()
        _ = await task?.value
        if kind == .alert, let s = workspace.sessions.existingSession(key) { _ = try? await s.execute("begin dbms_alert.removeall; end;") }
        await workspace.sessions.close(key)
    }
}
