import Foundation

/// Operacje pomocnicze wykonywane w sesji przez zwykłe polecenia (działają z każdym sterownikiem).
public enum SessionUtilities {
    /// Włącza bufor DBMS_OUTPUT (rozmiar w bajtach; 0 = bez limitu — UG 23.5).
    public static func enableOutput(_ s: any DatabaseSession, bufferSize: Int) async throws {
        if bufferSize > 0 {
            _ = try await s.execute("BEGIN DBMS_OUTPUT.ENABLE(:n); END;", binds: [BindVariable(name: "n", type: .number, value: .number(String(bufferSize)))])
        } else {
            _ = try await s.execute("BEGIN DBMS_OUTPUT.ENABLE(NULL); END;")
        }
    }

    public static func disableOutput(_ s: any DatabaseSession) async throws {
        _ = try await s.execute("BEGIN DBMS_OUTPUT.DISABLE; END;")
    }

    /// Odczytuje cały bufor DBMS_OUTPUT jednym wywołaniem (linie sklejone w CLOB po stronie serwera).
    public static func readOutput(_ s: any DatabaseSession) async throws -> [String] {
        let r = try await s.execute("""
            DECLARE
              l_line   VARCHAR2(32767);
              l_status INTEGER;
              l_buf    CLOB;
              l_count  PLS_INTEGER := 0;
            BEGIN
              DBMS_LOB.CREATETEMPORARY(l_buf, TRUE);
              LOOP
                DBMS_OUTPUT.GET_LINE(l_line, l_status);
                EXIT WHEN l_status <> 0;
                IF l_count > 0 THEN DBMS_LOB.WRITEAPPEND(l_buf, 1, CHR(10)); END IF;
                IF l_line IS NOT NULL THEN DBMS_LOB.WRITEAPPEND(l_buf, LENGTH(l_line), l_line); END IF;
                l_count := l_count + 1;
              END LOOP;
              :cnt := l_count;
              :buf := l_buf;
            END;
            """, binds: [BindVariable(name: "cnt", type: .number, direction: .output),
                         BindVariable(name: "buf", type: .clob, direction: .output)])
        guard case .number(let n)? = r.outBinds["cnt"], let count = Int(n), count > 0 else { return [] }
        var text = ""
        if case .lob(let l)? = r.outBinds["buf"] { text = l.text ?? "" }
        let lines = text.components(separatedBy: "\n")
        return Array(lines.prefix(count))
    }

    /// Czy sesja ma otwartą transakcję (DBMS_TRANSACTION.LOCAL_TRANSACTION_ID nie jest NULL).
    public static func transactionOpen(_ s: any DatabaseSession) async throws -> Bool {
        let v = try await s.scalar("SELECT DBMS_TRANSACTION.LOCAL_TRANSACTION_ID FROM dual")
        return v != nil && v?.isEmpty == false
    }

    /// Pozycja błędu Oracle (bajty UTF-8 od początku polecenia) → przesunięcie w jednostkach UTF-16 tekstu polecenia.
    public static func utf16Offset(ofUTF8Offset offset: Int, in text: String) -> Int {
        var bytes = 0
        var utf16 = 0
        for scalar in text.unicodeScalars {
            if bytes >= offset { break }
            bytes += String(scalar).utf8.count
            utf16 += scalar.utf16.count
        }
        return utf16
    }
}
