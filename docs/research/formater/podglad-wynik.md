# Podgląd — wynik przy ustawieniach domyślnych i pokrycie obecnych opcji

## 1-plsql.sql

```sql
CREATE OR REPLACE PACKAGE BODY kadry_api AS
  c_limit CONSTANT NUMBER(12, 2) := 1000; -- próg podwyżki
  g_licznik PLS_INTEGER := 0; -- zmiany w sesji
  CURSOR c_dzial(p_dzial NUMBER) IS SELECT empno,
                                           ename,
                                           sal
                                    FROM   emp
                                    WHERE  deptno = p_dzial;

  PROCEDURE podwyzka(p_dzial IN NUMBER,
                     p_procent IN OUT NOCOPY NUMBER,
                     p_data_od DATE DEFAULT SYSDATE,
                     p_tryb VARCHAR2 := 'N') IS
    v_suma NUMBER(12, 2);
    v_opis VARCHAR2(200) := 'brak';
  BEGIN
    IF v_suma > c_limit AND p_tryb = 'N' AND p_data_od < SYSDATE OR p_procent IS NULL AND g_licznik < 10 THEN
      v_opis := 'Dział ' || to_char(p_dzial) || ': suma ' || to_char(v_suma, 'FM999G990D00') || ' przekracza limit ' || c_limit;
    ELSIF v_suma BETWEEN 1 AND c_limit THEN
      v_opis := CASE WHEN v_suma > 500 THEN 'średnia' ELSE 'niska' END;
    END IF;
    g_licznik := g_licznik + 1;
    v_suma := round(v_suma, 2);
    dbms_output.put_line(v_opis);
    zapisz_log(p_dzial => p_dzial, p_opis => v_opis, p_kiedy => SYSTIMESTAMP);
  EXCEPTION
    WHEN no_data_found THEN
      v_opis := NULL;
    RAISE;
  END podwyzka;
  FUNCTION suma_dzialu(p_dzial NUMBER, p_rok NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN 0;
  END suma_dzialu;
END kadry_api;
/
```

## 2-zapytania.sql

```sql
WITH   dzialy AS (SELECT deptno,
                         sum(sal) suma
                  FROM   emp
                  GROUP BY deptno),
       duze AS (SELECT deptno
                FROM   dzialy
                WHERE  suma > 9000)
SELECT e.ename imie,
       d.dname dzial,
       nvl(e.comm, 0) prowizja, -- bez NULL
       CASE WHEN e.sal > 3000 THEN 'wysoka' WHEN e.sal > 1500 THEN 'średnia' ELSE 'niska' END poziom,
       rank() OVER (PARTITION BY e.deptno ORDER BY e.sal DESC) ranking
FROM   emp e
JOIN   dept d
  ON d.deptno = e.deptno
AND    d.loc IS NOT NULL
WHERE  (e.job = 'CLERK' OR e.job = 'ANALYST')
AND    e.deptno IN (SELECT deptno
                    FROM   duze)
AND    e.ename NOT IN ('SMITH',
                       'ALLEN',
                       'WARD',
                       'JONES',
                       'MARTIN',
                       'BLAKE',
                       'CLARK',
                       'SCOTT',
                       'KING',
                       'TURNER',
                       'ADAMS')
UNION ALL SELECT ename, NULL, 0, NULL, NULL
FROM   emp_hist
WHERE  sal > 0
ORDER BY 1,
         2 DESC;
```

## 3-dml.sql

```sql
UPDATE emp
SET    sal = sal * (1 + p_procent / 100),
       comm = nvl(comm, 0) + 10,
       data_zmiany = SYSDATE
WHERE  deptno = p_dzial
AND    job <> 'PRESIDENT';
INSERT INTO log_zmian(dzial, procent, kiedy, kto)
VALUES (p_dzial, p_procent, SYSDATE, USER);
INSERT INTO emp_hist(empno, ename, sal)
SELECT empno,
       ename,
       sal
FROM   emp
WHERE  deptno = p_dzial;
MERGE INTO emp t
USING  (SELECT empno,
               sal
        FROM   emp_stage) s ON (t.empno = s.empno)
WHEN MATCHED THEN UPDATE
SET    t.sal = s.sal,
       t.data_zmiany = SYSDATE
WHEN NOT MATCHED THEN INSERT (empno, sal)
VALUES (s.empno, s.sal);
DELETE
FROM   emp
WHERE  deptno = p_dzial
AND    sal IS NULL;
```

## 4-ddl.sql

```sql
CREATE TABLE log_zmian(id NUMBER GENERATED ALWAYS AS IDENTITY,
                       dzial NUMBER(2) NOT NULL,
                       procent NUMBER(5, 2) DEFAULT 0 NOT NULL,
                       kiedy DATE DEFAULT SYSDATE,
                       kto VARCHAR2(128 CHAR),
                       CONSTRAINT log_zmian_pk PRIMARY KEY (id),
                       CONSTRAINT log_zmian_dzial_fk FOREIGN KEY (dzial) REFERENCES dept(deptno) ON DELETE CASCADE,
                       CONSTRAINT log_zmian_proc_ck CHECK (procent BETWEEN -100 AND 100)) TABLESPACE users;
COMMENT ON TABLE log_zmian IS 'Historia podwyżek';
CREATE INDEX log_zmian_ix ON log_zmian(dzial, kiedy) COMPRESS 1;
ALTER TABLE log_zmian ADD(uwagi VARCHAR2(4000), zrodlo VARCHAR2(30) DEFAULT 'APP');
CREATE OR REPLACE VIEW v_log(dzial, procent, kiedy) AS SELECT dzial,
                                                              procent,
                                                              kiedy
                                                       FROM   log_zmian
                                                       WHERE  procent <> 0 WITH read ONLY;
CREATE OR REPLACE TRIGGER log_zmian_bi BEFORE INSERT OR UPDATE OF procent ON log_zmian FOR EACH ROW WHEN (new.procent > 50)
BEGIN
  :new.kto := USER;
END;
/
CREATE OR REPLACE TYPE t_zmiana AS OBJECT (dzial NUMBER(2),
                                           procent NUMBER(5, 2),
                                           kiedy DATE,
                                           MEMBER FUNCTION opis RETURN VARCHAR2);
/
GRANT SELECT, INSERT ON log_zmian TO kadry_role, raport_user;
```

## Pokrycie: opcja (wartość po zmianie z domyślnej) → przykłady, w których zmienia wynik, liczba zmienionych linii

- `indent`: 1-plsql.sql (33), 2-zapytania.sql (1), 4-ddl.sql (1)
- `useTabs`: 1-plsql.sql (32), 2-zapytania.sql (23), 3-dml.sql (7), 4-ddl.sql (15)
- `rightMargin`: 1-plsql.sql (7), 2-zapytania.sql (7), 3-dml.sql (17), 4-ddl.sql (15)
- `listLayout`: 1-plsql.sql (1), 2-zapytania.sql (6), 3-dml.sql (4), 4-ddl.sql (1)
- `parameterDeclarations`: 1-plsql.sql (2)
- `callParameters`: 1-plsql.sql (11), 4-ddl.sql (11)
- `insertLists`: 3-dml.sql (13)
- `commaBefore`: 1-plsql.sql (7), 2-zapytania.sql (23), 3-dml.sql (10), 4-ddl.sql (15)
- `keepBlankLines`: 1-plsql.sql (0)
- `maxBlankLines`: 1-plsql.sql (1)
- `blankLineBetweenSubprograms`: 1-plsql.sql (1)
- `clauseLayout`: 1-plsql.sql (2), 2-zapytania.sql (13), 3-dml.sql (11), 4-ddl.sql (2)
- `andOrPosition`: 2-zapytania.sql (6), 3-dml.sql (4)
- `joinConditionOnNewLine`: 2-zapytania.sql (1)
- `thenOnNewLine`: 1-plsql.sql (4)
- `caseLayout`: 1-plsql.sql (4), 2-zapytania.sql (5)
- `spaceAroundOperators`: 1-plsql.sql (5), 2-zapytania.sql (5), 3-dml.sql (10), 4-ddl.sql (2)
- `spaceAfterComma`: 1-plsql.sql (6), 2-zapytania.sql (2), 3-dml.sql (6), 4-ddl.sql (10)
- `spaceInsideParentheses`: 1-plsql.sql (17), 2-zapytania.sql (21), 3-dml.sql (10), 4-ddl.sql (20)
- `alignDeclarations`: 1-plsql.sql (2)
- `alignParameters`: 1-plsql.sql (5)
- `alignNamedArguments`: 1-plsql.sql (11), 4-ddl.sql (11)
- `alignAssignments`: 1-plsql.sql (1)
- `alignAliases`: 2-zapytania.sql (4)
- `alignSetValues`: 3-dml.sql (3)
- `alignTrailingComments`: 1-plsql.sql (1)
- `keywordCase`: 1-plsql.sql (28), 2-zapytania.sql (22), 3-dml.sql (23), 4-ddl.sql (23)
- `identifierCase`: 1-plsql.sql (28), 2-zapytania.sql (23), 3-dml.sql (25), 4-ddl.sql (23)
- `dataTypeCase`: 1-plsql.sql (10), 4-ddl.sql (10)
- `functionCase`: 1-plsql.sql (2), 2-zapytania.sql (3), 3-dml.sql (1)
- `packageCase`: 1-plsql.sql (1)
- `specialCase`: 1-plsql.sql (1)
