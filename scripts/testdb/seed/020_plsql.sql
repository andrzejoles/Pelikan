-- Kod PL/SQL do testów: pakiet poprawny, pakiet z błędem kompilacji, typy obiektowe i kolekcje,
-- funkcja z ostrzeżeniem PLSQL_WARNINGS, moduł MLE (JavaScript, 23ai/26ai).
-- Idempotentne: typy z zależnościami trzeba usunąć (FORCE), bo CREATE OR REPLACE rzuca ORA-02303.
WHENEVER SQLERROR CONTINUE
DROP TYPE address_list_t FORCE;
DROP TYPE number_list_t FORCE;
DROP TYPE address_t FORCE;
WHENEVER SQLERROR EXIT SQL.SQLCODE

CREATE OR REPLACE TYPE address_t AS OBJECT (
  street VARCHAR2(60),
  city   VARCHAR2(40),
  MEMBER FUNCTION label RETURN VARCHAR2
);
/
CREATE OR REPLACE TYPE BODY address_t AS
  MEMBER FUNCTION label RETURN VARCHAR2 IS
  BEGIN
    RETURN street || ', ' || city;
  END;
END;
/
CREATE OR REPLACE TYPE number_list_t AS TABLE OF NUMBER;
/
CREATE OR REPLACE TYPE address_list_t AS VARRAY(10) OF address_t;
/

CREATE OR REPLACE PACKAGE emp_api AS
  -- Prosty pakiet do testów Program Window, debugera i utPLSQL.
  TYPE emp_rec_t IS RECORD (empno emp.empno%TYPE, ename emp.ename%TYPE, sal emp.sal%TYPE);
  TYPE emp_tab_t IS TABLE OF emp_rec_t INDEX BY PLS_INTEGER;
  g_calls PLS_INTEGER := 0;

  FUNCTION get_salary(p_empno IN emp.empno%TYPE) RETURN emp.sal%TYPE;
  PROCEDURE raise_salary(p_empno IN emp.empno%TYPE, p_pct IN NUMBER);
  FUNCTION dept_employees(p_deptno IN dept.deptno%TYPE) RETURN emp_tab_t;
  FUNCTION employees_cursor(p_deptno IN dept.deptno%TYPE) RETURN SYS_REFCURSOR;
  FUNCTION total_salary(p_ids IN number_list_t) RETURN NUMBER;
END emp_api;
/
CREATE OR REPLACE PACKAGE BODY emp_api AS
  FUNCTION get_salary(p_empno IN emp.empno%TYPE) RETURN emp.sal%TYPE IS
    l_sal emp.sal%TYPE;
  BEGIN
    g_calls := g_calls + 1;
    SELECT sal INTO l_sal FROM emp WHERE empno = p_empno;
    RETURN l_sal;
  END get_salary;

  PROCEDURE raise_salary(p_empno IN emp.empno%TYPE, p_pct IN NUMBER) IS
  BEGIN
    IF p_pct < 0 THEN
      raise_application_error(-20001, 'Podwyżka nie może być ujemna');
    END IF;
    UPDATE emp SET sal = ROUND(sal * (1 + p_pct / 100), 2) WHERE empno = p_empno;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE NO_DATA_FOUND;
    END IF;
    dbms_output.put_line('Podwyżka dla ' || p_empno || ': ' || p_pct || '%');
  END raise_salary;

  FUNCTION dept_employees(p_deptno IN dept.deptno%TYPE) RETURN emp_tab_t IS
    l_result emp_tab_t;
  BEGIN
    SELECT empno, ename, sal BULK COLLECT INTO l_result FROM emp WHERE deptno = p_deptno ORDER BY empno;
    RETURN l_result;
  END dept_employees;

  FUNCTION employees_cursor(p_deptno IN dept.deptno%TYPE) RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR SELECT empno, ename, sal FROM emp WHERE deptno = p_deptno ORDER BY empno;
    RETURN c;
  END employees_cursor;

  FUNCTION total_salary(p_ids IN number_list_t) RETURN NUMBER IS
    l_total NUMBER := 0;
  BEGIN
    FOR i IN 1 .. p_ids.COUNT LOOP
      l_total := l_total + NVL(get_salary(p_ids(i)), 0);
    END LOOP;
    RETURN l_total;
  END total_salary;
END emp_api;
/

-- Pakiet celowo z błędem kompilacji (lista błędów, przejście do błędu, obiekty niepoprawne).
WHENEVER SQLERROR CONTINUE
CREATE OR REPLACE PACKAGE broken_pkg AS
  PROCEDURE do_it;
END broken_pkg;
/
CREATE OR REPLACE PACKAGE BODY broken_pkg AS
  PROCEDURE do_it IS
    l_x NUMBER;
  BEGIN
    l_x := undefined_function(1);
    SELECT no_such_column INTO l_x FROM dual;
  END do_it;
END broken_pkg;
/
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- Funkcja z ostrzeżeniem kompilatora (PLW-06002: kod nieosiągalny) przy PLSQL_WARNINGS='ENABLE:ALL'.
ALTER SESSION SET PLSQL_WARNINGS = 'ENABLE:ALL';
CREATE OR REPLACE FUNCTION warn_fn(p IN NUMBER) RETURN NUMBER IS
  l NUMBER := p;
BEGIN
  RETURN l;
  l := l + 1;
END warn_fn;
/
ALTER SESSION SET PLSQL_WARNINGS = 'DISABLE:ALL';

-- Moduł MLE (JavaScript) — Oracle 23ai/26ai.
WHENEVER SQLERROR CONTINUE
CREATE OR REPLACE MLE MODULE greet_mod LANGUAGE JAVASCRIPT AS
export function greet(name) {
  return "Cześć, " + name + "!";
}
/
CREATE OR REPLACE FUNCTION greet(p_name IN VARCHAR2) RETURN VARCHAR2
  AS MLE MODULE greet_mod SIGNATURE 'greet(string)';
/
WHENEVER SQLERROR EXIT SQL.SQLCODE
