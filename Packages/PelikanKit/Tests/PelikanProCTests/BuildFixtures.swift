// FIXTURE'Y Z FORMATU DOKUMENTOWANEGO (Pro*C/C++ Precompiler Programmer's Guide, IBM XL C/C++ for AIX V12.1
// Compiler Reference: komunikaty „1506-NNN”, opcja -qsrcmsg) — DO ZASTĄPIENIA PRÓBKAMI Z AIX WŁAŚCICIELA (D-PC2-2).
// Nazwy plików, ścieżki i treść programów są fikcyjne.

enum BuildFixtures {
    /// `make` w `/build/app/src`: proc z błędem semantycznym, błędem składni, PL/SQL i ostrzeżeniem; potem xlc.
    static let procAndXlc = """
    proc iname=orders.pc oname=orders.c sqlcheck=semantics userid=$(DBUSER)

    Pro*C/C++: Release 11.2.0.4.0 - Production on Mon Oct 19 10:15:02 2026

    System default option values taken from: /opt/oracle/precomp/admin/pcscfg.cfg

    Error at line 45, column 12 in file orders.pc
        EXEC SQL SELECT cnt INTO :v_cnt FROM ordrs;
    ...........1
    PCC-S-02322, found undefined identifier
    Syntax error at line 51, column 5, file orders.pc:
    Error at line 51, column 5 in file orders.pc
        EXEC SQL COMIT;
    ....1
    PCC-S-02201, Encountered the symbol "COMIT" when expecting one of the following:
    Semantic error at line 60, column 9, file lib/util.pc:
            v_x := f_missing(1);
    ........1
    PLS-S-00201, identifier 'F_MISSING' must be declared
    PCC-W-02340, value of DEFINE option ignored
    PCC-F-02102, Fatal error while doing C preprocessing
    xlc_r -q64 -O2 -I/opt/oracle/precomp/public -c orders.c
    "orders.c", line 120.15: 1506-045 (S) Undeclared identifier v_cnt.
    "orders.c", line 7.10: 1506-296 (S) #include file <sqlca2.h> not found.
    "/build/app/src/lib/util.c", line 33.1: 1506-1385 (W) The return type is not compatible.
    "orders.c", line 200: 1506-412 (I) Referenced variable "tmp", which is not initialized in its declaration.
    "orders.c", line 1.1: 1506-1108 (E) The external name is too long.
    "orders.c", line 2.1: 1506-005 (U) Compilation ended due to errors.
    make: 1254-004 The error code from the last command is 1.
    """

    /// `-qsrcmsg`: linia źródła, znacznik kolumn i komunikaty bez nazwy pliku (plik z polecenia kompilacji).
    static let srcmsg = """
    xlc -qsrcmsg -c report.c
      120 |     v_total = v_cnt * 2 + bad;
            ..............a...........b..
    a - 1506-045 (S) Undeclared identifier v_cnt.
    b - 1506-045 (S) Undeclared identifier bad.
        7 | #include <missing.h>
            .........a..........
    a - 1506-296 (S) #include file <missing.h> not found.
    make
    """
}
