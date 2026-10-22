-- Schemat testowy Pelikana: tabele, sekwencja, widok, wyzwalacz wierszowy, LOB-y, domena 23ai/26ai.
-- Idempotentne: obiekty usuwane i tworzone od nowa przy każdym `scripts/testdb.sh seed`.
WHENEVER SQLERROR CONTINUE
DROP TABLE emp_audit PURGE;
DROP TABLE emp PURGE;
DROP TABLE dept PURGE;
DROP TABLE docs PURGE;
DROP TABLE big_rows PURGE;
DROP TABLE contacts PURGE;
DROP SEQUENCE emp_seq;
DROP DOMAIN email_d;
WHENEVER SQLERROR EXIT SQL.SQLCODE

CREATE TABLE dept (
  deptno NUMBER(2) CONSTRAINT dept_pk PRIMARY KEY,
  dname  VARCHAR2(30) NOT NULL,
  loc    VARCHAR2(30)
);
COMMENT ON TABLE dept IS 'Działy (dane przykładowe)';

CREATE TABLE emp (
  empno    NUMBER(6) CONSTRAINT emp_pk PRIMARY KEY,
  ename    VARCHAR2(40) NOT NULL,
  job      VARCHAR2(20),
  mgr      NUMBER(6) CONSTRAINT emp_mgr_fk REFERENCES emp,
  hiredate DATE DEFAULT SYSDATE,
  sal      NUMBER(9,2) CONSTRAINT emp_sal_ck CHECK (sal >= 0),
  comm     NUMBER(9,2),
  deptno   NUMBER(2) CONSTRAINT emp_dept_fk REFERENCES dept
);
CREATE INDEX emp_dept_ix ON emp(deptno);
COMMENT ON COLUMN emp.sal IS 'Pensja miesięczna';

CREATE SEQUENCE emp_seq START WITH 1000;

CREATE TABLE emp_audit (
  id       NUMBER GENERATED ALWAYS AS IDENTITY,
  empno    NUMBER(6),
  old_sal  NUMBER(9,2),
  new_sal  NUMBER(9,2),
  changed  TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE OR REPLACE TRIGGER emp_sal_trg
  BEFORE UPDATE OF sal ON emp
  FOR EACH ROW
BEGIN
  IF :new.sal <> :old.sal THEN
    INSERT INTO emp_audit (empno, old_sal, new_sal) VALUES (:old.empno, :old.sal, :new.sal);
  END IF;
END;
/

CREATE OR REPLACE VIEW emp_v AS
  SELECT e.empno, e.ename, e.job, e.sal, d.dname
    FROM emp e LEFT JOIN dept d ON d.deptno = e.deptno;

CREATE TABLE docs (
  id    NUMBER PRIMARY KEY,
  title VARCHAR2(100),
  body  CLOB,
  data  BLOB,
  meta  JSON
);

-- Duża tabela do testów siatki (dociąganie stronami); 200 000 wierszy, test 1 mln generuje własne dane.
CREATE TABLE big_rows (
  id   NUMBER PRIMARY KEY,
  txt  VARCHAR2(60),
  num  NUMBER,
  dt   DATE
);

CREATE DOMAIN email_d AS VARCHAR2(200) CONSTRAINT email_ck CHECK (REGEXP_LIKE(email_d, '^[^@]+@[^@]+$'));
CREATE TABLE contacts (
  id    NUMBER PRIMARY KEY,
  email VARCHAR2(200) DOMAIN email_d
);

INSERT INTO dept VALUES (10, 'KSIĘGOWOŚĆ', 'KRAKÓW');
INSERT INTO dept VALUES (20, 'BADANIA', 'GDAŃSK');
INSERT INTO dept VALUES (30, 'SPRZEDAŻ', 'ŁÓDŹ');
INSERT INTO dept VALUES (40, 'OPERACJE', 'WARSZAWA');
INSERT INTO emp VALUES (7839, 'KOWALSKI', 'PREZES', NULL, DATE '2001-11-17', 5000, NULL, 10);
INSERT INTO emp VALUES (7566, 'NOWAK', 'KIEROWNIK', 7839, DATE '2001-04-02', 2975, NULL, 20);
INSERT INTO emp VALUES (7698, 'WIŚNIEWSKA', 'KIEROWNIK', 7839, DATE '2001-05-01', 2850, NULL, 30);
INSERT INTO emp VALUES (7782, 'WÓJCIK', 'KIEROWNIK', 7839, DATE '2001-06-09', 2450, NULL, 10);
INSERT INTO emp VALUES (7788, 'KAMIŃSKI', 'ANALITYK', 7566, DATE '2007-04-19', 3000, NULL, 20);
INSERT INTO emp VALUES (7499, 'LEWANDOWSKA', 'SPRZEDAWCA', 7698, DATE '2001-02-20', 1600, 300, 30);
INSERT INTO emp VALUES (7521, 'ZIELIŃSKI', 'SPRZEDAWCA', 7698, DATE '2001-02-22', 1250, 500, 30);
INSERT INTO emp VALUES (7369, 'SZYMAŃSKA', 'URZĘDNIK', 7566, DATE '2000-12-17', 800, NULL, 20);
INSERT INTO docs (id, title, body, data, meta)
  VALUES (1, 'Dokument', TO_CLOB('Zażółć gęślą jaźń'), HEXTORAW('DEADBEEF'), JSON('{"a":1,"b":[1,2]}'));
INSERT INTO contacts VALUES (1, 'test@example.com');
INSERT /*+ APPEND */ INTO big_rows
  SELECT level, 'wiersz ' || level, MOD(level * 7919, 100000) / 100, DATE '2020-01-01' + MOD(level, 2000)
    FROM dual CONNECT BY level <= 200000;
COMMIT;
