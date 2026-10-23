import Foundation

extension TemplateLibrary {
    static var programFolder: String { L10n.tr("Jednostki programów") }
    static var objectsFolder: String { L10n.tr("Obiekty") }

    /// Szablony dostarczane z Pelikanem (własne teksty; użytkownik może je zastąpić własnymi o tej samej ścieżce).
    static var builtIn: [CodeTemplate] {
        let units = programFolder
        let dml = "DML"
        let loops = L10n.tr("Pętle")
        let blocks = L10n.tr("Bloki")
        let types = L10n.tr("Typy")
        return [
            CodeTemplate(folder: units, name: L10n.tr("Procedura"), text: """
                create or replace procedure [Nazwa=nowa_procedura](
                  [Parametr=p_id] in number
                ) is
                  -- Autor: $DBUSER, $DATE
                begin
                  [#]null;
                end [Nazwa];
                /
                """, isBuiltIn: true),
            CodeTemplate(folder: units, name: L10n.tr("Funkcja"), text: """
                create or replace function [Nazwa=nowa_funkcja](
                  [Parametr=p_id] in number
                ) return [Typ zwracany=*number,varchar2,date,boolean,clob] is
                  l_wynik [Typ zwracany];
                begin
                  [#]
                  return l_wynik;
                end [Nazwa];
                /
                """, isBuiltIn: true),
            CodeTemplate(folder: units, name: L10n.tr("Pakiet"), text: """
                create or replace package [Nazwa=nowy_pakiet] as
                  -- Autor: $DBUSER, $DATE
                  procedure [Procedura=wykonaj];
                end [Nazwa];
                /
                create or replace package body [Nazwa] as
                  procedure [Procedura] is
                  begin
                    [#]null;
                  end [Procedura];
                end [Nazwa];
                /
                """, isBuiltIn: true),
            CodeTemplate(folder: units, name: L10n.tr("Typ obiektowy"), text: """
                create or replace type [Nazwa=nowy_t] as object (
                  [Atrybut=id] number,
                  member function opis return varchar2
                );
                /
                create or replace type body [Nazwa] as
                  member function opis return varchar2 is
                  begin
                    return [#]to_char([Atrybut]);
                  end opis;
                end;
                /
                """, isBuiltIn: true),
            CodeTemplate(folder: units, name: L10n.tr("Wyzwalacz"), text: """
                create or replace trigger [Nazwa=nowy_trg]
                  [Moment=*before,after] [Zdarzenie=*insert or update,insert,update,delete] on [Tabela]
                  for each row
                begin
                  [#]null;
                end [Nazwa];
                /
                """, isBuiltIn: true),
            CodeTemplate(folder: "utPLSQL", name: L10n.tr("Pakiet testowy"), text: """
                create or replace package test_[Pakiet] as
                  --%suite([Opis=Testy pakietu])

                  --%beforeall
                  procedure przygotuj;

                  --%test([Opis testu])
                  procedure [Nazwa testu=pierwszy_test];
                end;
                /
                create or replace package body test_[Pakiet] as
                  procedure przygotuj is
                  begin
                    null;
                  end;

                  procedure [Nazwa testu] is
                  begin
                    [#]ut.expect(1).to_equal(1);
                  end;
                end;
                /
                """, isBuiltIn: true),
            CodeTemplate(folder: "utPLSQL", name: L10n.tr("Test (specyfikacja)"), text: """
                --%test([Opis])
                procedure [Nazwa];[#]
                """, isBuiltIn: true),
            CodeTemplate(folder: "utPLSQL", name: L10n.tr("Test oczekujący wyjątku"), text: """
                --%test([Opis])
                --%throws([Wyjątek=no_data_found])
                procedure [Nazwa];[#]
                """, isBuiltIn: true),
            CodeTemplate(folder: "utPLSQL", name: L10n.tr("Kontekst"), text: """
                --%context([Opis])
                [#]
                --%endcontext
                """, isBuiltIn: true),
            CodeTemplate(folder: "utPLSQL", name: L10n.tr("Oczekiwanie"), text: """
                ut.expect([Wartość]).[Matcher=*to_equal,not_to_equal,to_be_null,to_be_not_null,to_be_true,to_be_false,to_be_greater_than,to_be_less_than,to_be_like,to_match,to_have_count]([Oczekiwana]);[#]
                """, isBuiltIn: true),
            CodeTemplate(folder: "utPLSQL", name: L10n.tr("Porównanie kursorów"), text: """
                open l_expected for [Zapytanie oczekiwane=select 1 x from dual];
                open l_actual for [Zapytanie badane=select 1 x from dual];
                ut.expect(l_actual).to_equal(l_expected).join_by('[Klucz=X]');[#]
                """, isBuiltIn: true),
            CodeTemplate(folder: objectsFolder, name: L10n.tr("Widok"), text: """
                create or replace view [Nazwa=nowy_widok] as
                select [#]*
                from   [Tabela] t
                where  1 = 1;
                """, isBuiltIn: true),
            CodeTemplate(folder: objectsFolder, name: L10n.tr("Domena"), text: """
                create domain if not exists [Nazwa=nowa_domena] as [Typ=varchar2(100)]
                  constraint [Nazwa]_chk check ([Warunek=value is not null])
                  display [Wyświetlanie=value]
                  annotations ([Adnotacja=opis] '[Opis]');[#]
                """, isBuiltIn: true),
            CodeTemplate(folder: dml, name: "select", text: """
                select [#]*
                from   [Tabela] t
                where  1 = 1
                """, isBuiltIn: true),
            CodeTemplate(folder: dml, name: "insert", text: """
                insert into [Tabela]
                  ([Kolumny])
                values
                  ([#]);
                """, isBuiltIn: true),
            CodeTemplate(folder: dml, name: "update", text: """
                update [Tabela] t
                set    t.[Kolumna] = [#]
                where  [Warunek=1 = 1];
                """, isBuiltIn: true),
            CodeTemplate(folder: dml, name: "delete", text: """
                delete from [Tabela] t
                where  [Warunek][#];
                """, isBuiltIn: true),
            CodeTemplate(folder: dml, name: "merge", text: """
                merge into [Tabela] t
                using ([#]select * from [Źródło]) s
                on (t.[Klucz=id] = s.[Klucz])
                when matched then
                  update set t.[Kolumna] = s.[Kolumna]
                when not matched then
                  insert ([Klucz], [Kolumna]) values (s.[Klucz], s.[Kolumna]);
                """, isBuiltIn: true),
            CodeTemplate(folder: loops, name: L10n.tr("Pętla po zapytaniu"), text: """
                for r in ([Zapytanie=select * from dual]) loop
                  [#]null;
                end loop;
                """, isBuiltIn: true),
            CodeTemplate(folder: loops, name: L10n.tr("Pętla liczbowa"), text: """
                for [Licznik=i] in [Od=1] .. [Do=10] loop
                  [#]null;
                end loop;
                """, isBuiltIn: true),
            CodeTemplate(folder: loops, name: L10n.tr("Pętla WHILE"), text: """
                while [Warunek] loop
                  [#]null;
                end loop;
                """, isBuiltIn: true),
            CodeTemplate(folder: loops, name: "bulk collect + forall", text: """
                declare
                  type t_tab is table of [Tabela]%rowtype;
                  l_tab t_tab;
                  cursor c is select * from [Tabela];
                begin
                  open c;
                  loop
                    fetch c bulk collect into l_tab limit [Rozmiar paczki=1000];
                    exit when l_tab.count = 0;
                    forall i in 1 .. l_tab.count
                      [#]null;
                  end loop;
                  close c;
                end;
                """, isBuiltIn: true),
            CodeTemplate(folder: blocks, name: L10n.tr("Blok anonimowy"), text: """
                declare
                  [#]
                begin
                  null;
                end;
                """, isBuiltIn: true),
            CodeTemplate(folder: blocks, name: L10n.tr("Obsługa wyjątków"), text: """
                begin
                  [#]null;
                exception
                  when [Wyjątek=*no_data_found,too_many_rows,dup_val_on_index,others] then
                    raise;
                end;
                """, isBuiltIn: true),
            CodeTemplate(folder: blocks, name: L10n.tr("Transakcja autonomiczna"), text: """
                procedure [Nazwa=zapisz_log](p_tekst varchar2) is
                  pragma autonomous_transaction;
                begin
                  [#]
                  commit;
                end [Nazwa];
                """, isBuiltIn: true),
            CodeTemplate(folder: types, name: L10n.tr("Rekord"), text: """
                type [Nazwa=t_rek] is record (
                  [Pole=id] number[#]
                );
                """, isBuiltIn: true),
            CodeTemplate(folder: types, name: L10n.tr("Kolekcja"), text: """
                type [Nazwa=t_tab] is table of [Typ elementu=varchar2(4000)] index by [Indeks=*pls_integer,varchar2(100)];[#]
                """, isBuiltIn: true),
        ]
    }
}
