CREATE OR REPLACE PACKAGE BODY zamowienia_api AS
  -- Przykład do zrzutu Zawartości kodu ze strukturami sterującymi (D203).
  g_licznik PLS_INTEGER := 0;

  FUNCTION rabat(p_kwota IN NUMBER) RETURN NUMBER IS
  BEGIN
    CASE
      WHEN p_kwota > 10000 THEN RETURN 0.1;
      WHEN p_kwota > 1000 THEN RETURN 0.05;
      ELSE RETURN 0;
    END CASE;
  END rabat;

  PROCEDURE przelicz(p_klient_id IN NUMBER) IS
    l_suma NUMBER := 0;
  BEGIN
    <<pozycje>>
    FOR r IN (SELECT z.id, z.kwota, z.status FROM zamowienia z WHERE z.klient_id = p_klient_id) LOOP
      IF r.status = 'ANULOWANE' THEN
        CONTINUE pozycje;
      ELSIF r.kwota IS NULL OR r.kwota < 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Błędna kwota zamówienia ' || r.id);
      ELSE
        l_suma := l_suma + r.kwota * (1 - rabat(r.kwota));
      END IF;
    END LOOP pozycje;
    WHILE l_suma > 100000 LOOP
      l_suma := l_suma / 2;
    END LOOP;
    BEGIN
      UPDATE klienci SET obrot = l_suma WHERE id = p_klient_id;
    EXCEPTION
      WHEN DUP_VAL_ON_INDEX THEN
        NULL;
    END;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      g_licznik := g_licznik + 1;
    WHEN OTHERS THEN
      RAISE;
  END przelicz;

  PROCEDURE archiwizuj(p_ids IN SYS.ODCINUMBERLIST) IS
  BEGIN
    FORALL i IN 1 .. p_ids.COUNT
      INSERT INTO zamowienia_arch SELECT * FROM zamowienia WHERE id = p_ids(i);
  END archiwizuj;
BEGIN
  IF g_licznik IS NULL THEN
    g_licznik := 0;
  END IF;
END zamowienia_api;
