CREATE OR REPLACE PACKAGE kadry_api AS
  -- Pakiet przykładowy do zrzutów okna programu (karty jednostek, Code Contents).
  c_wersja     CONSTANT VARCHAR2(10) := '1.4.0';
  c_max_pensja CONSTANT NUMBER := 99999;
  SUBTYPE t_kwota IS NUMBER(12, 2);
  TYPE r_pracownik IS RECORD (empno emp.empno%TYPE, ename emp.ename%TYPE, sal t_kwota);
  TYPE t_pracownicy IS TABLE OF r_pracownik INDEX BY PLS_INTEGER;
  TYPE t_kursor IS REF CURSOR RETURN emp%ROWTYPE;
  e_brak_pracownika EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_brak_pracownika, -20001);
  g_licznik PLS_INTEGER := 0;

  CURSOR c_dzial(p_deptno IN NUMBER) RETURN emp%ROWTYPE;

  FUNCTION pensja(p_empno IN emp.empno%TYPE) RETURN t_kwota;
  FUNCTION pensja(p_ename IN VARCHAR2, p_domyslna IN t_kwota DEFAULT 0) RETURN t_kwota;
  PROCEDURE podwyzka(p_empno IN emp.empno%TYPE, p_procent IN NUMBER DEFAULT 10);
  PROCEDURE przenies(p_empno IN NUMBER, p_deptno IN NUMBER, p_log OUT NOCOPY VARCHAR2);
  FUNCTION lista(p_deptno IN NUMBER) RETURN t_pracownicy;
  FUNCTION otworz(p_deptno IN NUMBER) RETURN t_kursor;
  -- Raport 1: zestawienie pomocnicze nr 1.
  FUNCTION raport_01(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 2: zestawienie pomocnicze nr 2.
  FUNCTION raport_02(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 3: zestawienie pomocnicze nr 3.
  FUNCTION raport_03(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 4: zestawienie pomocnicze nr 4.
  FUNCTION raport_04(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 5: zestawienie pomocnicze nr 5.
  FUNCTION raport_05(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 6: zestawienie pomocnicze nr 6.
  FUNCTION raport_06(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 7: zestawienie pomocnicze nr 7.
  FUNCTION raport_07(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 8: zestawienie pomocnicze nr 8.
  FUNCTION raport_08(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 9: zestawienie pomocnicze nr 9.
  FUNCTION raport_09(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 10: zestawienie pomocnicze nr 10.
  FUNCTION raport_10(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 11: zestawienie pomocnicze nr 11.
  FUNCTION raport_11(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 12: zestawienie pomocnicze nr 12.
  FUNCTION raport_12(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 13: zestawienie pomocnicze nr 13.
  FUNCTION raport_13(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 14: zestawienie pomocnicze nr 14.
  FUNCTION raport_14(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 15: zestawienie pomocnicze nr 15.
  FUNCTION raport_15(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 16: zestawienie pomocnicze nr 16.
  FUNCTION raport_16(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 17: zestawienie pomocnicze nr 17.
  FUNCTION raport_17(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 18: zestawienie pomocnicze nr 18.
  FUNCTION raport_18(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 19: zestawienie pomocnicze nr 19.
  FUNCTION raport_19(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 20: zestawienie pomocnicze nr 20.
  FUNCTION raport_20(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 21: zestawienie pomocnicze nr 21.
  FUNCTION raport_21(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 22: zestawienie pomocnicze nr 22.
  FUNCTION raport_22(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 23: zestawienie pomocnicze nr 23.
  FUNCTION raport_23(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 24: zestawienie pomocnicze nr 24.
  FUNCTION raport_24(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 25: zestawienie pomocnicze nr 25.
  FUNCTION raport_25(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 26: zestawienie pomocnicze nr 26.
  FUNCTION raport_26(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 27: zestawienie pomocnicze nr 27.
  FUNCTION raport_27(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 28: zestawienie pomocnicze nr 28.
  FUNCTION raport_28(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 29: zestawienie pomocnicze nr 29.
  FUNCTION raport_29(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 30: zestawienie pomocnicze nr 30.
  FUNCTION raport_30(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 31: zestawienie pomocnicze nr 31.
  FUNCTION raport_31(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 32: zestawienie pomocnicze nr 32.
  FUNCTION raport_32(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 33: zestawienie pomocnicze nr 33.
  FUNCTION raport_33(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 34: zestawienie pomocnicze nr 34.
  FUNCTION raport_34(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 35: zestawienie pomocnicze nr 35.
  FUNCTION raport_35(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 36: zestawienie pomocnicze nr 36.
  FUNCTION raport_36(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 37: zestawienie pomocnicze nr 37.
  FUNCTION raport_37(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 38: zestawienie pomocnicze nr 38.
  FUNCTION raport_38(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 39: zestawienie pomocnicze nr 39.
  FUNCTION raport_39(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
  -- Raport 40: zestawienie pomocnicze nr 40.
  FUNCTION raport_40(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER;
END kadry_api;
/

CREATE OR REPLACE PACKAGE BODY kadry_api AS
  -- Elementy prywatne ciała: niewidoczne poza pakietem.
  c_opis CONSTANT VARCHAR2(100) := q'[Zestawienie 'kadry' — wersja ciała]';
  g_ostatni emp.empno%TYPE;

  CURSOR c_dzial(p_deptno IN NUMBER) RETURN emp%ROWTYPE IS
    SELECT * FROM emp WHERE deptno = p_deptno;

  PROCEDURE log_zdarzenia(p_tekst IN VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    dbms_output.put_line(c_opis || ': ' || p_tekst);
    COMMIT;
  END log_zdarzenia;

  FUNCTION pensja(p_empno IN emp.empno%TYPE) RETURN t_kwota IS
    l_sal t_kwota;
  BEGIN
    SELECT sal INTO l_sal FROM emp WHERE empno = p_empno;
    RETURN l_sal;
  EXCEPTION
    WHEN no_data_found THEN
      RAISE e_brak_pracownika;
  END pensja;

  FUNCTION pensja(p_ename IN VARCHAR2, p_domyslna IN t_kwota DEFAULT 0) RETURN t_kwota IS
    l_sal t_kwota;
  BEGIN
    SELECT MAX(sal) INTO l_sal FROM emp WHERE ename = UPPER(p_ename);
    RETURN NVL(l_sal, p_domyslna);
  END pensja;

  PROCEDURE podwyzka(p_empno IN emp.empno%TYPE, p_procent IN NUMBER DEFAULT 10) IS
    l_nowa t_kwota;
    FUNCTION oblicz(p_stara IN t_kwota) RETURN t_kwota IS
    BEGIN
      RETURN LEAST(p_stara * (1 + p_procent / 100), c_max_pensja);
    END oblicz;
  BEGIN
    l_nowa := oblicz(pensja(p_empno));
    UPDATE emp SET sal = l_nowa WHERE empno = p_empno;
    g_ostatni := p_empno;
    log_zdarzenia('podwyżka ' || p_empno);
  END podwyzka;

  PROCEDURE przenies(p_empno IN NUMBER, p_deptno IN NUMBER, p_log OUT NOCOPY VARCHAR2) IS
  BEGIN
    UPDATE emp SET deptno = p_deptno WHERE empno = p_empno;
    p_log := 'przeniesiono ' || p_empno;
  END przenies;

  FUNCTION lista(p_deptno IN NUMBER) RETURN t_pracownicy IS
    l_wynik t_pracownicy;
  BEGIN
    FOR r IN c_dzial(p_deptno) LOOP
      l_wynik(l_wynik.COUNT + 1).empno := r.empno;
    END LOOP;
    RETURN l_wynik;
  END lista;

  FUNCTION otworz(p_deptno IN NUMBER) RETURN t_kursor IS
    l_kursor t_kursor;
  BEGIN
    OPEN l_kursor FOR SELECT * FROM emp WHERE deptno = p_deptno;
    RETURN l_kursor;
  END otworz;

  FUNCTION raport_01(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 2) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_01;

  FUNCTION raport_02(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 3) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_02;

  FUNCTION raport_03(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 4) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_03;

  FUNCTION raport_04(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 5) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_04;

  FUNCTION raport_05(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 6) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_05;

  FUNCTION raport_06(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 7) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_06;

  FUNCTION raport_07(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 8) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_07;

  FUNCTION raport_08(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 9) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_08;

  FUNCTION raport_09(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 10) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_09;

  FUNCTION raport_10(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 11) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_10;

  FUNCTION raport_11(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 12) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_11;

  FUNCTION raport_12(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 13) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_12;

  FUNCTION raport_13(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 14) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_13;

  FUNCTION raport_14(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 15) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_14;

  FUNCTION raport_15(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 16) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_15;

  FUNCTION raport_16(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 17) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_16;

  FUNCTION raport_17(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 18) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_17;

  FUNCTION raport_18(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 19) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_18;

  FUNCTION raport_19(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 20) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_19;

  FUNCTION raport_20(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 21) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_20;

  FUNCTION raport_21(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 22) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_21;

  FUNCTION raport_22(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 23) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_22;

  FUNCTION raport_23(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 24) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_23;

  FUNCTION raport_24(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 25) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_24;

  FUNCTION raport_25(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 26) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_25;

  FUNCTION raport_26(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 27) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_26;

  FUNCTION raport_27(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 28) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_27;

  FUNCTION raport_28(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 29) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_28;

  FUNCTION raport_29(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 30) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_29;

  FUNCTION raport_30(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 31) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_30;

  FUNCTION raport_31(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 32) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_31;

  FUNCTION raport_32(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 33) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_32;

  FUNCTION raport_33(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 34) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_33;

  FUNCTION raport_34(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 35) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_34;

  FUNCTION raport_35(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 36) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_35;

  FUNCTION raport_36(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 37) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_36;

  FUNCTION raport_37(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 38) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_37;

  FUNCTION raport_38(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 39) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_38;

  FUNCTION raport_39(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 40) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_39;

  FUNCTION raport_40(p_od IN DATE, p_do IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
    l_wynik NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_wynik FROM emp
     WHERE hiredate BETWEEN p_od AND p_do
       AND MOD(empno, 41) = 0;
    g_licznik := g_licznik + 1;
    RETURN l_wynik;
  END raport_40;

BEGIN
  g_licznik := 0;
END kadry_api;
/
