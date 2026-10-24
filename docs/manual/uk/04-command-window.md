# Command Window

Command Window працює як SQL*Plus: виконує команди рядок за рядком і скрипти, а результати запитів показує як текст у
стовпцях. Відкрити його можна через **Файл › Новий › Command Window** або з меню з'єднання в списку з'єднань.

Вікно має дві вкладки:

- **Діалог** — вивід і **командний рядок** унизу. Введіть команду SQL*Plus, SQL або блок PL/SQL (блок завершує скісна
  риска `/` в окремому рядку) і натисніть ↩. Стрілки прокручують історію введених рядків.
- **Редактор** — скрипт із підсвічуванням синтаксису. F8 (⌘↩) виконує виділення або весь скрипт; результат з'являється
  на вкладці «Діалог». **Сеанс › Перервати** (⌘.) зупиняє скрипт.

Рядок стану показує поточні налаштування `ECHO`, `TERMOUT`, `FEEDBACK`, `VERIFY`, `AUTOPRINT`, `HEADING` і `TIMING`;
подвійне клацання індикатора перемикає налаштування.

## Підтримувані команди SQL*Plus

- Запуск скриптів: `@файл`, `@@файл` (відносно поточного скрипту), `START`, `RUN`, `/`.
- Змінні: `DEFINE`, `UNDEFINE`, `ACCEPT`, `VARIABLE` (NUMBER, VARCHAR2, CHAR, CLOB, BLOB, REFCURSOR, DATE, BOOLEAN),
  `PRINT`, `EXECUTE`. `&&назва` запам'ятовує значення, як у SQL*Plus.
- Вивід: `PROMPT`, `PAUSE`, `SPOOL файл` (також `APPEND`, `OFF`, `OUT`), `COLUMN` (`FORMAT`, `HEADING`, `NEW_VALUE`),
  `BREAK` (`SKIP`, `DUP`/`NODUP`), `COMPUTE` (`SUM`, `AVG`, `COUNT`, `MIN`, `MAX`, `NUM` з `LABEL`), `CLEAR`.
- `SET`: зокрема `AUTOPRINT`, `COLSEP`, `CONCAT`, `DEFINE`, `ECHO`, `ESCAPE`, `FEEDBACK`, `HEADING`, `LONG`, `NUMWIDTH`,
  `PAGESIZE`, `SCAN`, `SERVEROUTPUT` (`SIZE UNLIMITED`), `TERMOUT`, `TIMING`, `VERIFY`, `EXECPAUSE`. Непідтримувані
  параметри `SET` у скриптах пропускаються без помилки.
- `SHOW` (`ERRORS`, `USER`, `RELEASE`, `SQLCODE`, `CONNECTION`, `ALL`…), `DESCRIBE`, `WHENEVER SQLERROR`, `CONNECT`,
  `DISCONNECT`, `EXIT`/`QUIT`, `REMARK`, `HELP`.
- Буфер команд: `LIST`, `APPEND`, `CHANGE`, `DEL`, `INPUT`, `SAVE`, `GET`, `STORE SET`.
- `HOST`, `!` і `$` — команда операційної системи. Pelikan завжди показує її для підтвердження й виконує без змінних
  середовища Pelikan, з лімітом 120 секунд. Агент ШІ не має доступу до Command Window.

Непідтримувана команда пропускається з повідомленням, тож скрипти, написані для SQL*Plus, виконуються до кінця. `COPY`
не підтримується.

Після `@`, `@@` і `START` підказка коду показує файли скриптів із поточного каталогу, а після `CONNECT користувач@` —
псевдоніми з `tnsnames.ora`. Команди з паролями (`CONNECT`, `ALTER USER … IDENTIFIED BY`, `CREATE DATABASE LINK`) не
потрапляють до історії команд.

## Команди SQLcl

- `INFO` і `INFO+` — опис таблиці або програми зі стовпцями, індексами й статистикою.
- `DDL об'єкт [файл]` — DDL об'єкта на екран або у файл.
- `LOAD таблиця файл.csv [NEW]` — завантаження CSV у таблицю (з `NEW` — створює таблицю).
- `FORMAT BUFFER` / `FORMAT FILE` — форматування коду.
- `HISTORY` (з часом, `CLEAR`), `ALIAS`, `REPEAT`, `CTAS`.
- `SET SQLFORMAT csv | json | xml | html | insert | loader | fixed | delimited | ansiconsole | default` — формат
  результатів запитів.

## Команди Pelikan

- `BEAUTIFY файл` — форматує файл форматувальником Pelikan.
- `EDIT об'єкт`, `VIEW об'єкт`, `BROWSE об'єкт`, `PROPERTIES об'єкт` — відкривають об'єкт у відповідному вікні.
- `QUERYDATA таблиця`, `EDITDATA таблиця` — дані таблиці в SQL Window (з можливістю редагування).
- `TEST програма`, `RECOMPILE об'єкт`, `INFO об'єкт`.
- `CD каталог`, `DIR` — поточний каталог вікна для скриптів і `SPOOL`.
- `ZIP`, `EXPORT TABLES …`, `EXPORT OBJECTS …` — експорт таблиць і об'єктів, як в інструментах експорту.
- `RUNTESTSET файл.pts` — запускає набір тестів Test Manager.

## Покрокове виконання скрипту

`SET EXECPAUSE ON` або **Сеанс › Призупинити виконання** змушує Pelikan перед кожною командою скрипту запитувати, чи
виконати її, виконати решту скрипту чи перервати.
