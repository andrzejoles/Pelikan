CREATE OR REPLACE PACKAGE BODY pensje_api AS
  -- Prywatna: zaokrąglenie kwoty do groszy.
  FUNCTION zaokraglij(p_kwota IN NUMBER) RETURN t_kwota IS
  BEGIN
    RETURN ROUND(p_kwota, 2);
  END zaokraglij;

  FUNCTION pensja(p_empno IN emp.empno%TYPE) RETURN t_kwota IS
    v_sal emp.sal%TYPE;
  BEGIN
    SELECT sal INTO v_sal FROM emp WHERE empno = p_empno;
    RETURN zaokraglij(v_sal);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE e_brak_pracownika;
  END pensja;

  PROCEDURE podwyzka(p_empno IN emp.empno%TYPE, p_procent IN NUMBER DEFAULT 10) IS
  BEGIN
    UPDATE emp
       SET sal = LEAST(zaokraglij(sal * (1 + p_procent / 100)), c_max_pensja)
     WHERE empno = p_empno;
  END podwyzka;
END pensje_api;
