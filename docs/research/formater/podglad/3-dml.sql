update emp set sal = sal * (1 + p_procent / 100), comm = nvl(comm, 0) + 10, data_zmiany = sysdate where deptno = p_dzial and job <> 'PRESIDENT';
insert into log_zmian (dzial, procent, kiedy, kto) values (p_dzial, p_procent, sysdate, user);
insert into emp_hist (empno, ename, sal) select empno, ename, sal from emp where deptno = p_dzial;
merge into emp t using (select empno, sal from emp_stage) s on (t.empno = s.empno) when matched then update set t.sal = s.sal, t.data_zmiany = sysdate when not matched then insert (empno, sal) values (s.empno, s.sal);
delete from emp where deptno = p_dzial and sal is null;
