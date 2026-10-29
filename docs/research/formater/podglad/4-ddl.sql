create table log_zmian (id number generated always as identity, dzial number(2) not null, procent number(5,2) default 0 not null, kiedy date default sysdate, kto varchar2(128 char), constraint log_zmian_pk primary key (id), constraint log_zmian_dzial_fk foreign key (dzial) references dept (deptno) on delete cascade, constraint log_zmian_proc_ck check (procent between -100 and 100)) tablespace users;
comment on table log_zmian is 'Historia podwyżek';
create index log_zmian_ix on log_zmian (dzial, kiedy) compress 1;
alter table log_zmian add (uwagi varchar2(4000), zrodlo varchar2(30) default 'APP');
create or replace view v_log (dzial, procent, kiedy) as select dzial, procent, kiedy from log_zmian where procent <> 0 with read only;
create or replace trigger log_zmian_bi before insert or update of procent on log_zmian for each row when (new.procent > 50) begin :new.kto := user; end;
/
create or replace type t_zmiana as object (dzial number(2), procent number(5,2), kiedy date, member function opis return varchar2);
/
grant select, insert on log_zmian to kadry_role, raport_user;
