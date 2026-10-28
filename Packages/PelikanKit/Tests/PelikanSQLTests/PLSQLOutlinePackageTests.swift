import Foundation
import PelikanSQL
import Testing

/// Code Contents dla pakietu ze specyfikacją i ciałem (D192): typy, podtypy, kursory z parametrami, stałe, wyjątki,
/// pragmy, przeciążenia, podprogramy zagnieżdżone, elementy publiczne i prywatne; q'[…]' i komentarze nie mylą parsera.
@Suite("Parser strukturalny PL/SQL — pakiet ze specyfikacją i ciałem")
struct PLSQLOutlinePackageTests {
    static let source = """
    CREATE OR REPLACE PACKAGE kadry AS
      -- komentarz: PROCEDURE udawana(p number);
      c_wersja CONSTANT VARCHAR2(10) := '1.0';
      SUBTYPE t_kwota IS NUMBER(12, 2);
      TYPE r_prac IS RECORD (empno NUMBER, ename VARCHAR2(30));
      TYPE t_lista IS TABLE OF r_prac INDEX BY PLS_INTEGER;
      TYPE t_kursor IS REF CURSOR RETURN emp%ROWTYPE;
      e_brak EXCEPTION;
      PRAGMA EXCEPTION_INIT(e_brak, -20001);
      CURSOR c_dzial(p_deptno IN NUMBER) RETURN emp%ROWTYPE;
      FUNCTION pensja(p_empno IN emp.empno%TYPE) RETURN t_kwota;
      FUNCTION pensja(p_ename IN VARCHAR2, p_def IN t_kwota DEFAULT 0) RETURN t_kwota;
      PROCEDURE podwyzka(p_empno IN NUMBER, p_log OUT NOCOPY VARCHAR2);
    END kadry;
    /

    CREATE OR REPLACE PACKAGE BODY kadry AS
      c_opis CONSTANT VARCHAR2(100) := q'[tekst z 'apostrofami'; END kadry;]';
      g_ostatni NUMBER;
      /* PROCEDURE w komentarzu(p number) IS BEGIN NULL; END; */
      CURSOR c_dzial(p_deptno IN NUMBER) RETURN emp%ROWTYPE IS
        SELECT * FROM emp WHERE deptno = p_deptno;
      PROCEDURE log_zdarzenia(p_tekst IN VARCHAR2) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
      BEGIN
        COMMIT;
      END log_zdarzenia;
      FUNCTION pensja(p_empno IN emp.empno%TYPE) RETURN t_kwota IS
        l_sal t_kwota;
      BEGIN
        SELECT sal INTO l_sal FROM emp WHERE empno = p_empno;
        RETURN l_sal;
      END pensja;
      FUNCTION pensja(p_ename IN VARCHAR2, p_def IN t_kwota DEFAULT 0) RETURN t_kwota IS
      BEGIN
        RETURN p_def;
      END pensja;
      PROCEDURE podwyzka(p_empno IN NUMBER, p_log OUT NOCOPY VARCHAR2) IS
        FUNCTION oblicz(p_stara IN t_kwota) RETURN t_kwota IS
        BEGIN
          RETURN p_stara * 1.1;
        END oblicz;
      BEGIN
        p_log := q'{ok}' || oblicz(pensja(p_empno));
      END podwyzka;
    BEGIN
      g_ostatni := NULL;
    END kadry;
    /
    """

    @Test("specyfikacja: stała, podtyp, rekord, tabela, ref cursor, wyjątek, pragma, kursor z parametrami, przeciążenia — wszystko publiczne")
    func specification() throws {
        let nodes = PLSQLOutline.parse(Self.source)
        #expect(nodes.map(\.kind) == [.package, .packageBody])
        let spec = nodes[0]
        #expect(spec.children.map { "\($0.kind.rawValue):\($0.name)" } == [
            "constant:c_wersja", "typeDeclaration:t_kwota", "typeDeclaration:r_prac", "typeDeclaration:t_lista",
            "typeDeclaration:t_kursor", "exception:e_brak", "pragma:EXCEPTION_INIT", "cursor:c_dzial",
            "function:pensja", "function:pensja", "procedure:podwyzka",
        ])
        #expect(spec.children.map(\.typeShape).filter { !$0.isEmpty } == ["SUBTYPE", "RECORD", "TABLE", "REF CURSOR"])
        #expect(spec.children[6].detail == "(e_brak, -20001)")
        #expect(spec.children[7].detail == "(p_deptno IN NUMBER) RETURN emp%ROWTYPE")
        let second = spec.children[9]
        #expect(second.children.filter { $0.kind == .parameter }.map(\.detail) == ["IN VARCHAR2", "IN t_kwota"])
        #expect(second.detail == "t_kwota")
        #expect(spec.children.filter { $0.kind != .pragma }.allSatisfy { $0.isPublic == true })
    }

    @Test("ciało: prywatne i publiczne elementy, przeciążenia rozróżnione parametrami, podprogram zagnieżdżony, pragma w procedurze")
    func body() throws {
        let body = PLSQLOutline.parse(Self.source)[1]
        let top = body.children.filter { $0.kind != .block }
        #expect(top.map { "\($0.kind.rawValue):\($0.name):\($0.isPublic.map { $0 ? "pub" : "priv" } ?? "-")" } == [
            "constant:c_opis:priv", "variable:g_ostatni:priv", "cursor:c_dzial:pub", "procedure:log_zdarzenia:priv",
            "function:pensja:pub", "function:pensja:pub", "procedure:podwyzka:pub",
        ])
        let log = top[3]
        #expect(log.children.contains { $0.kind == .pragma && $0.name == "AUTONOMOUS_TRANSACTION" })
        let podwyzka = top[6]
        #expect(podwyzka.children.contains { $0.kind == .function && $0.name == "oblicz" && $0.isPublic == nil })
        // Ciało kończy się na „END kadry;” mimo q'[…END kadry;]' w stałej.
        let ns = Self.source as NSString
        #expect(ns.substring(with: NSRange(location: body.range.lowerBound, length: body.range.count)).hasSuffix("END kadry;"))
        #expect(CodeContentsLikeSignature.text(top[5]) == "pensja(p_ename IN VARCHAR2, p_def IN t_kwota) RETURN t_kwota")
    }

    @Test("ciało bez specyfikacji w tekście — widoczność nieznana")
    func bodyWithoutSpec() throws {
        let text = Self.source.components(separatedBy: "\n/\n")[1]
        let body = try #require(PLSQLOutline.parse(text).first)
        #expect(body.kind == .packageBody)
        #expect(body.children.allSatisfy { $0.isPublic == nil })
    }

    @Test("typ obiektowy: atrybuty z typami, metody ze specyfikacji; ciało typu: MEMBER, CONSTRUCTOR … RETURN SELF AS RESULT")
    func objectType() throws {
        let text = """
        CREATE OR REPLACE TYPE punkt_t AS OBJECT (
          x NUMBER,
          y NUMBER(10, 2),
          CONSTRUCTOR FUNCTION punkt_t(p_x NUMBER) RETURN SELF AS RESULT,
          MEMBER FUNCTION odleglosc(p IN punkt_t) RETURN NUMBER DETERMINISTIC,
          MEMBER PROCEDURE przesun(p_dx NUMBER, p_dy NUMBER)
        );
        /
        CREATE OR REPLACE TYPE BODY punkt_t AS
          CONSTRUCTOR FUNCTION punkt_t(p_x NUMBER) RETURN SELF AS RESULT IS
          BEGIN
            x := p_x;
            RETURN;
          END;
          MEMBER FUNCTION odleglosc(p IN punkt_t) RETURN NUMBER DETERMINISTIC IS
          BEGIN
            RETURN SQRT(POWER(x - p.x, 2) + POWER(y - p.y, 2));
          END odleglosc;
          MEMBER PROCEDURE przesun(p_dx NUMBER, p_dy NUMBER) IS
          BEGIN
            x := x + p_dx;
          END przesun;
        END;
        /
        """
        let nodes = PLSQLOutline.parse(text)
        #expect(nodes.map(\.kind) == [.type, .typeBody])
        #expect(nodes[0].children.map { "\($0.kind.rawValue):\($0.name):\($0.detail)" } == [
            "variable:x:NUMBER", "variable:y:NUMBER(10, 2)", "function:punkt_t:SELF AS RESULT", "function:odleglosc:NUMBER",
            "procedure:przesun:",
        ])
        #expect(nodes[1].children.map { "\($0.kind.rawValue):\($0.name):\($0.detail)" } == [
            "function:punkt_t:SELF AS RESULT", "function:odleglosc:NUMBER", "procedure:przesun:",
        ])
        #expect(nodes[1].children.allSatisfy { $0.isPublic == true })
    }
}

/// Nagłówek podprogramu jak w tytule węzła panelu (nazwa, parametry z typami, typ zwracany).
enum CodeContentsLikeSignature {
    static func text(_ n: OutlineNode) -> String {
        let p = n.children.filter { $0.kind == .parameter }.map { $0.name + " " + $0.detail }
        return n.name + "(" + p.joined(separator: ", ") + ")" + (n.detail.isEmpty ? "" : " RETURN " + n.detail)
    }
}

@Suite("Parser strukturalny PL/SQL — przeciążenia prywatne i pragmy")
struct PLSQLOutlineOverloadTests {
    @Test("jedna wersja w specyfikacji i dwie w ciele — prywatne przeciążenie zostaje prywatne; pragma nie jest deklaracją nazwy")
    func privateOverload() throws {
        let text = """
        create or replace package p as
          function f(a number) return number;
        end;
        /
        create or replace package body p as
          function f(a number) return number is begin return a; end;
          function f(a varchar2, b number) return number is begin return b; end;
          procedure q is
            pragma autonomous_transaction;
          begin null; end;
        end;
        /
        """
        let nodes = PLSQLOutline.parse(text)
        let body = nodes[1]
        #expect(body.children.filter { $0.name == "f" }.map(\.isPublic) == [true, false])
        let q = try #require(body.children.first { $0.name == "q" })
        #expect(q.children.contains { $0.kind == .pragma })
        let inQ = (text as NSString).range(of: "begin null").location + 6
        #expect(PLSQLOutline.declaration(of: "autonomous_transaction", at: inQ, in: nodes) == nil)
        #expect(!CompletionContext.analyze(text, offset: inQ).declarations.contains { $0.kind == .pragma })
    }
}
