-- Przykładowy pakiet testów utPLSQL dla emp_api (eksplorator testów, uruchamianie, pokrycie).
-- Jeden test celowo nie przechodzi (widok błędu: oczekiwane/otrzymane).
WHENEVER SQLERROR EXIT SQL.SQLCODE

CREATE OR REPLACE PACKAGE test_emp_api AS
  --%suite(Testy emp_api)
  --%suitepath(pelikan.przyklady)

  --%beforeall
  PROCEDURE setup;

  --%context(get_salary)

  --%test(Zwraca pensję istniejącego pracownika)
  PROCEDURE get_salary_existing;

  --%test(Brak pracownika rzuca NO_DATA_FOUND)
  --%throws(no_data_found)
  PROCEDURE get_salary_missing;

  --%endcontext

  --%context(raise_salary)

  --%test(Podwyżka 10% zmienia pensję)
  PROCEDURE raise_salary_ten_percent;

  --%test(Ujemna podwyżka rzuca błąd -20001)
  --%throws(-20001)
  PROCEDURE raise_salary_negative;

  --%test(Celowo błędny test — porównanie oczekiwane/otrzymane)
  PROCEDURE deliberately_failing;

  --%endcontext
END test_emp_api;
/
CREATE OR REPLACE PACKAGE BODY test_emp_api AS
  PROCEDURE setup IS
  BEGIN
    NULL;
  END;

  PROCEDURE get_salary_existing IS
  BEGIN
    ut.expect(emp_api.get_salary(7839)).to_equal(5000);
  END;

  PROCEDURE get_salary_missing IS
    l_sal NUMBER;
  BEGIN
    l_sal := emp_api.get_salary(-1);
  END;

  PROCEDURE raise_salary_ten_percent IS
  BEGIN
    emp_api.raise_salary(7369, 10);
    ut.expect(emp_api.get_salary(7369)).to_equal(880);
  END;

  PROCEDURE raise_salary_negative IS
  BEGIN
    emp_api.raise_salary(7369, -5);
  END;

  PROCEDURE deliberately_failing IS
  BEGIN
    ut.expect(emp_api.get_salary(7566)).to_equal(1);
  END;
END test_emp_api;
/
