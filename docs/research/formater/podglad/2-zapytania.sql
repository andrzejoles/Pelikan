with dzialy as (select deptno, sum(sal) suma from emp group by deptno), duze as (select deptno from dzialy where suma > 9000)
select e.ename imie, d.dname dzial, nvl(e.comm,0) prowizja, -- bez NULL
case when e.sal > 3000 then 'wysoka' when e.sal > 1500 then 'średnia' else 'niska' end poziom,
rank() over (partition by e.deptno order by e.sal desc) ranking
from emp e join dept d on d.deptno = e.deptno and d.loc is not null
where (e.job = 'CLERK' or e.job = 'ANALYST') and e.deptno in (select deptno from duze)
and e.ename not in ('SMITH', 'ALLEN', 'WARD', 'JONES', 'MARTIN', 'BLAKE', 'CLARK', 'SCOTT', 'KING', 'TURNER', 'ADAMS')
union all
select ename, null, 0, null, null from emp_hist where sal > 0
order by 1, 2 desc;
