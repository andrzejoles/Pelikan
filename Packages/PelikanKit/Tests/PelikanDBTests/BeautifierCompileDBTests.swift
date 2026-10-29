import Foundation
import PelikanDB
import PelikanODPI
import PelikanSQL
import Testing

/// Formater nie zmienia znaczenia kodu: jednostki z korpusu rozpoznania (docs/research/formater/korpus.txt —
/// kompilacja warunkowa, operatory wektorów, wyzwalacz złożony, typ obiektowy z ciałem, pakiet z kursorami, FORALL,
/// obsługą wyjątków, etykietami i długimi wyrażeniami, widok) kompilują się do VALID przed i po formatowaniu,
/// przy ustawieniach domyślnych i „ciężkich” (wszystkie wyrównania, przecinek na początku, element w linii).
@Suite("Formater — kompilacja na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct BeautifierCompileDBTests {
    static let units: [(type: String, name: String, ddl: String)] = [
        ("TABLE", "PELIKAN_FMT_T", """
            create table pelikan_fmt_t (id number(10) not null, qty number(10,3) default 1 not null, price number(14,2), \
            note varchar2(400 char), modified date, constraint pelikan_fmt_t_pk primary key (id), \
            constraint pelikan_fmt_t_ck check (qty > 0 and (price is null or price >= 0))) pctfree 10 storage (initial 64k next 1m)
            """),
        ("FUNCTION", "PELIKAN_FMT_CC", """
            create or replace function pelikan_fmt_cc return varchar2 is v varchar2(200); begin
            $if dbms_db_version.ver_le_12 $then v := 'stara';
              $else v := 'nowa:' || $$plsql_unit;
            $end
            if v is null then raise program_error; end if; return v; end;
            """),
        ("FUNCTION", "PELIKAN_FMT_VEC", """
            create or replace function pelikan_fmt_vec return number is r number; begin select (to_vector('[1,2]')<->to_vector('[2,3]')) \
            + (to_vector('[1,2]')<=>to_vector('[2,3]')) + (to_vector('[1,2]')<#>to_vector('[2,3]')) into r from dual; return r; end;
            """),
        ("TRIGGER", "PELIKAN_FMT_TRG", """
            create or replace trigger pelikan_fmt_trg for insert or update on pelikan_fmt_t compound trigger \
            type t_ids is table of number index by pls_integer; g_ids t_ids; before statement is begin g_ids.delete; end before statement; \
            after each row is begin g_ids(g_ids.count + 1) := :new.id; end after each row; after statement is begin \
            forall i in 1 .. g_ids.count update pelikan_fmt_t set modified = sysdate where id = g_ids(i) and modified is null; \
            end after statement; end pelikan_fmt_trg;
            """),
        ("TRIGGER", "PELIKAN_FMT_BIU", """
            create or replace trigger pelikan_fmt_biu before insert or update of qty, price on pelikan_fmt_t referencing old as o new as n \
            for each row when (n.qty > 0 or o.qty is not null) begin if inserting then :n.note := nvl(:n.note, 'nowy'); \
            elsif updating ('QTY') then :n.qty := round(:n.qty, 3); end if; end;
            """),
        ("TYPE", "PELIKAN_FMT_MONEY", """
            create or replace type pelikan_fmt_money force as object (amount number(14,2), currency varchar2(3), \
            constructor function pelikan_fmt_money(p_amount number) return self as result, member function to_string return varchar2, \
            map member function sort_key return number, static function zero return pelikan_fmt_money) not final;
            """),
        ("TYPE BODY", "PELIKAN_FMT_MONEY", """
            create or replace type body pelikan_fmt_money as constructor function pelikan_fmt_money(p_amount number) return self as result is \
            begin self.amount := p_amount; self.currency := 'PLN'; return; end; member function to_string return varchar2 is begin \
            return to_char(amount, 'FM999G990D00') || ' ' || currency; end; map member function sort_key return number is begin return amount; end; \
            static function zero return pelikan_fmt_money is begin return pelikan_fmt_money(0); end; end;
            """),
        ("PACKAGE", "PELIKAN_FMT_PKG", """
            create or replace package pelikan_fmt_pkg as c_max constant pls_integer := 999; \
            cursor c_items(p_id number) return pelikan_fmt_t%rowtype; type t_cur is ref cursor return pelikan_fmt_t%rowtype; \
            e_too_many exception; pragma exception_init(e_too_many, -20100); \
            function total(p_id number) return number result_cache deterministic; \
            procedure add_item(p_id in number, p_qty in number default 1, p_price in number default null, p_note out varchar2); end pelikan_fmt_pkg;
            """),
        ("PACKAGE BODY", "PELIKAN_FMT_PKG", """
            create or replace package body pelikan_fmt_pkg as
            cursor c_items(p_id number) return pelikan_fmt_t%rowtype is select * from pelikan_fmt_t where id = p_id union all select * from pelikan_fmt_t where id = -p_id;
            function total(p_id number) return number result_cache deterministic is v number; begin
            select sum(qty * price) into v from pelikan_fmt_t t where t.id = p_id and t.qty between 1 and 100 and (t.price > 0 or t.price is null);
            return v; end total;
            procedure add_item(p_id in number, p_qty in number default 1, p_price in number default null, p_note out varchar2) is
            type t_ids is table of number; l_ids t_ids := t_ids(p_id); v_text varchar2(4000);
            begin
            <<outer>> for i in 1 .. 2 loop exit outer when i > 1; end loop outer;
            forall i in 1 .. l_ids.count insert into pelikan_fmt_t (id, qty, price) values (l_ids(i), p_qty, p_price);
            merge into pelikan_fmt_t t using (select p_id id, p_qty qty from dual) s on (t.id = s.id) when matched then update set t.qty = s.qty, t.modified = sysdate where t.qty <> s.qty delete where s.qty is null when not matched then insert (id, qty) values (s.id, s.qty);
            update pelikan_fmt_t set note = 'Pozycja ' || to_char(p_id) || ', ilość ' || to_char(p_qty) || ', cena ' || nvl(to_char(p_price), 'brak') || ', kontrola ' || to_char(sysdate, 'YYYY-MM-DD') where id = p_id returning note into p_note;
            case when p_qty > 10 then v_text := 'duża'; v_text := v_text || '!'; else v_text := 'mała'; end case;
            exception when dup_val_on_index then p_note := 'duplikat'; raise e_too_many; when others then p_note := sqlerrm; raise;
            end add_item;
            end pelikan_fmt_pkg;
            """),
        ("VIEW", "PELIKAN_FMT_V", """
            create or replace force view pelikan_fmt_v (id, total) as select id, qty * price from pelikan_fmt_t where qty > 0 with read only
            """),
    ]

    static var heavy: BeautifierOptions {
        var o = BeautifierOptions()
        o.alignDeclarations = true; o.alignParameters = true; o.alignNamedArguments = true; o.alignAssignments = true
        o.alignAliases = true; o.alignSetValues = true; o.alignTrailingComments = true; o.commaBefore = true
        o.parameterDeclarations = .onePerLine; o.callParameters = .onePerLine; o.insertLists = .onePerLine
        o.caseLayout = .multiline; o.thenOnNewLine = true; o.clauseLayout = .rightAligned; o.rightMargin = 60
        return o
    }

    func compile(_ s: ODPISession, _ ddl: String) async throws {
        _ = try await s.execute(ddl.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func status(_ s: ODPISession, _ type: String, _ name: String) async throws -> String? {
        try await s.scalar("select status from user_objects where object_type = '\(type)' and object_name = '\(name)'")
    }

    @Test("jednostki z korpusu kompilują się do VALID przed i po formatowaniu (ustawienia domyślne i ciężkie)")
    func formattedUnitsCompile() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        func dropAll() async {
            for drop in ["view pelikan_fmt_v", "package pelikan_fmt_pkg", "type pelikan_fmt_money force", "function pelikan_fmt_vec",
                         "function pelikan_fmt_cc", "table pelikan_fmt_t purge"] {
                _ = try? await s.execute("drop \(drop)")
            }
        }
        /// Wyniki wywołań: odległości wektorów i gałąź kompilacji warunkowej.
        func results() async throws -> [String?] {
            [try await s.scalar("select to_char(round(pelikan_fmt_vec, 9)) from dual"), try await s.scalar("select pelikan_fmt_cc from dual")]
        }
        await dropAll()
        do {
            // Wyniki wywołań funkcji skompilowanych z oryginalnego źródła.
            for u in Self.units where u.type == "FUNCTION" { try await compile(s, u.ddl) }
            let expected = try await results()
            for options in [BeautifierOptions(), Self.heavy] {
                for u in Self.units {
                    if u.type == "TABLE" { _ = try? await s.execute("drop table pelikan_fmt_t purge") }
                    try await compile(s, u.ddl)
                    #expect(try await status(s, u.type, u.name) == "VALID", "przed: \(u.type) \(u.name)")
                    if u.type == "TABLE" { continue }
                    let formatted = try Beautifier.format(u.ddl, options: options)
                    try await compile(s, formatted)
                    #expect(try await status(s, u.type, u.name) == "VALID", "po formatowaniu: \(u.type) \(u.name)\n\(formatted)")
                }
                // Te same wyniki wywołań po formatowaniu (funkcje skompilowane ze sformatowanego źródła).
                let after = try await results()
                #expect(after == expected && after.allSatisfy { $0 != nil }, "\(after) ≠ \(expected)")
                // Tabela — sformatowana tworzona od nowa (po usunięciu zależnych), potem całość jeszcze raz poprawna.
                _ = try await s.execute("drop table pelikan_fmt_t purge")
                try await compile(s, try Beautifier.format(Self.units[0].ddl, options: options))
                #expect(try await status(s, "TABLE", "PELIKAN_FMT_T") == "VALID")
                for u in Self.units where ["TRIGGER", "VIEW", "PACKAGE BODY"].contains(u.type) {
                    try await compile(s, try Beautifier.format(u.ddl, options: options))
                    #expect(try await status(s, u.type, u.name) == "VALID", "po odtworzeniu tabeli: \(u.type) \(u.name)")
                }
            }
        } catch {
            await dropAll()
            throw error
        }
        await dropAll()
    }
}
