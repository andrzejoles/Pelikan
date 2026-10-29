-- Pakiet przykładowy do zrzutu pary plików specyfikacji i ciała (D194): plik bez „/”.
CREATE OR REPLACE PACKAGE pensje_api AS
  c_max_pensja CONSTANT NUMBER := 99999;
  SUBTYPE t_kwota IS NUMBER(12, 2);
  e_brak_pracownika EXCEPTION;

  FUNCTION pensja(p_empno IN emp.empno%TYPE) RETURN t_kwota;
  PROCEDURE podwyzka(p_empno IN emp.empno%TYPE, p_procent IN NUMBER DEFAULT 10);
END pensje_api;
