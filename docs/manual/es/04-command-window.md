# Command Window

La Command Window funciona como SQL*Plus: ejecuta sentencias línea a línea y scripts, y muestra los resultados de las
consultas como texto en columnas. La abres con **Archivo › Nuevo › Command Window** o desde el menú de la conexión en la
lista de conexiones.

La ventana tiene dos pestañas:

- **Diálogo**: la salida y, abajo, la **línea de comandos**. Escribe un comando de SQL*Plus, una sentencia SQL o un
  bloque PL/SQL (el bloque termina con una barra `/` en una línea aparte) y pulsa ↩. Las flechas recorren el historial
  de líneas escritas.
- **Editor**: un script con resaltado de sintaxis. F8 (⌘↩) ejecuta la selección o todo el script; el resultado aparece
  en la pestaña Diálogo. **Sesión › Interrumpir** (⌘.) detiene el script.

La barra de estado muestra los ajustes actuales de `ECHO`, `TERMOUT`, `FEEDBACK`, `VERIFY`, `AUTOPRINT`, `HEADING` y
`TIMING`; un doble clic en un indicador cambia el ajuste.

## Comandos de SQL*Plus admitidos

- Ejecución de scripts: `@archivo`, `@@archivo` (relativo al script actual), `START`, `RUN`, `/`.
- Variables: `DEFINE`, `UNDEFINE`, `ACCEPT`, `VARIABLE` (NUMBER, VARCHAR2, CHAR, CLOB, BLOB, REFCURSOR, DATE, BOOLEAN),
  `PRINT`, `EXECUTE`. `&&nombre` recuerda el valor como en SQL*Plus.
- Salida: `PROMPT`, `PAUSE`, `SPOOL archivo` (también `APPEND`, `OFF`, `OUT`), `COLUMN` (`FORMAT`, `HEADING`,
  `NEW_VALUE`), `BREAK` (`SKIP`, `DUP`/`NODUP`), `COMPUTE` (`SUM`, `AVG`, `COUNT`, `MIN`, `MAX`, `NUM` con `LABEL`),
  `CLEAR`.
- `SET`: entre otros, `AUTOPRINT`, `COLSEP`, `CONCAT`, `DEFINE`, `ECHO`, `ESCAPE`, `FEEDBACK`, `HEADING`, `LONG`,
  `NUMWIDTH`, `PAGESIZE`, `SCAN`, `SERVEROUTPUT` (`SIZE UNLIMITED`), `TERMOUT`, `TIMING`, `VERIFY`, `EXECPAUSE`. Las
  opciones de `SET` no admitidas se omiten en los scripts sin error.
- `SHOW` (`ERRORS`, `USER`, `RELEASE`, `SQLCODE`, `CONNECTION`, `ALL`…), `DESCRIBE`, `WHENEVER SQLERROR`, `CONNECT`,
  `DISCONNECT`, `EXIT`/`QUIT`, `REMARK`, `HELP`.
- Búfer de comandos: `LIST`, `APPEND`, `CHANGE`, `DEL`, `INPUT`, `SAVE`, `GET`, `STORE SET`.
- `HOST`, `!` y `$`: un comando del sistema operativo. Pelikan siempre lo muestra para que lo confirmes y lo ejecuta sin
  las variables de entorno de Pelikan, con un límite de 120 segundos. El agente de IA no tiene acceso a la Command
  Window.

Un comando no admitido se omite con un aviso, así que los scripts escritos para SQL*Plus se ejecutan hasta el final.
`COPY` no está admitido.

Tras `@`, `@@` y `START`, la sugerencia de código muestra los archivos de script del directorio actual, y tras `CONNECT
usuario@`, los alias de `tnsnames.ora`. Los comandos con contraseñas (`CONNECT`, `ALTER USER … IDENTIFIED BY`, `CREATE
DATABASE LINK`) no van al historial de comandos.

## Comandos de SQLcl

- `INFO` e `INFO+`: descripción de una tabla o un programa con columnas, índices y estadísticas.
- `DDL objeto [archivo]`: el DDL del objeto en pantalla o en un archivo.
- `LOAD tabla archivo.csv [NEW]`: carga de un CSV en una tabla (con `NEW`, crea la tabla).
- `FORMAT BUFFER` / `FORMAT FILE`: formato del código.
- `HISTORY` (con tiempos, `CLEAR`), `ALIAS`, `REPEAT`, `CTAS`.
- `SET SQLFORMAT csv | json | xml | html | insert | loader | fixed | delimited | ansiconsole | default`: formato de los
  resultados de las consultas.

## Comandos de Pelikan

- `BEAUTIFY archivo`: formatea un archivo con el formateador de Pelikan.
- `EDIT objeto`, `VIEW objeto`, `BROWSE objeto`, `PROPERTIES objeto`: abren el objeto en la ventana correspondiente.
- `QUERYDATA tabla`, `EDITDATA tabla`: datos de la tabla en una SQL Window (con posibilidad de edición).
- `TEST programa`, `RECOMPILE objeto`, `INFO objeto`.
- `CD directorio`, `DIR`: el directorio actual de la ventana para los scripts y `SPOOL`.
- `ZIP`, `EXPORT TABLES …`, `EXPORT OBJECTS …`: exportación de tablas y objetos como en las herramientas de exportación.
- `RUNTESTSET archivo.pts`: ejecuta un conjunto de pruebas del Test Manager.

## Ejecución paso a paso de un script

`SET EXECPAUSE ON` o **Sesión › Pausar ejecución** hacen que, antes de cada sentencia del script, Pelikan pregunte si
ejecutarla, ejecutar el resto del script o interrumpir.
