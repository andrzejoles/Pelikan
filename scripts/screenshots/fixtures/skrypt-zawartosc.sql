-- Przegląd pensji działu
select e.empno, e.ename, e.sal
  from emp e
 where e.deptno = :dzial
 order by e.sal desc;

create table pensje_hist (empno number, sal number, data date default sysdate);

insert into pensje_hist (empno, sal)
select empno, sal from emp where deptno = :dzial;

create or replace procedure podwyzka(p_dzial number, p_proc number) is
  c_max constant number := 20;
begin
  update emp set sal = sal * (1 + least(p_proc, c_max) / 100) where deptno = p_dzial;
end;
/

declare
  l_ile pls_integer;
begin
  select count(*) into l_ile from pensje_hist;
  dbms_output.put_line('Zapisano: ' || l_ile);
end;
/

commit;
