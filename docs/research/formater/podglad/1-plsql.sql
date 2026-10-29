create or replace package body kadry_api as
c_limit constant number(12,2) := 1000; -- próg podwyżki
g_licznik pls_integer := 0; -- zmiany w sesji
cursor c_dzial(p_dzial number) is select empno, ename, sal from emp where deptno = p_dzial;


procedure podwyzka(p_dzial in number, p_procent in out nocopy number, p_data_od date default sysdate, p_tryb varchar2 := 'N') is
v_suma number(12,2);
v_opis varchar2(200) := 'brak';
begin
if v_suma > c_limit and p_tryb = 'N' and p_data_od < sysdate or p_procent is null and g_licznik < 10 then
v_opis := 'Dział ' || to_char(p_dzial) || ': suma ' || to_char(v_suma, 'FM999G990D00') || ' przekracza limit ' || c_limit;
elsif v_suma between 1 and c_limit then
v_opis := case when v_suma > 500 then 'średnia' else 'niska' end;
end if;
g_licznik := g_licznik+1;
v_suma := round(v_suma, 2);
dbms_output.put_line(v_opis);
zapisz_log(p_dzial => p_dzial, p_opis => v_opis, p_kiedy => systimestamp);
exception
when no_data_found then
v_opis := null;
raise;
end podwyzka;
function suma_dzialu(p_dzial number, p_rok number) return number is
begin
return 0;
end suma_dzialu;
end kadry_api;
/
