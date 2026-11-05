# Consola SQL*Plus

## Para qué sirve

**SQL*Plus** es la herramienta clásica de texto de Oracle para ejecutar scripts. Muchos equipos despliegan los cambios
en la base con scripts de SQL*Plus: con `SET`, `PROMPT`, `SPOOL` (escribir la salida en un archivo) o `WHENEVER SQLERROR`
(detenerse ante un error). La SQL Window no los entiende, pero la **consola SQL*Plus** de Pelikan sí.

**Cuándo usarla:** para ejecutar scripts de despliegue ya preparados (`@instalar.sql`), para scripts que escriben la
salida en un archivo y cuando quieras ver cómo se comportará un script en el SQL*Plus del administrador. Para consultas
normales y para revisar datos es más cómoda la SQL Window con su cuadrícula de resultados (capítulo 3).

La consola SQL*Plus funciona como SQL*Plus: ejecuta sentencias línea a línea y scripts, y muestra los resultados de las
consultas como texto en columnas. La abres con **Archivo › Nuevo › Consola SQL*Plus** o desde el menú de la conexión en la
lista de conexiones.

La ventana tiene dos pestañas:

- **Diálogo**: la salida y, abajo, la **línea de comandos**. Escribe un comando de SQL*Plus, una sentencia SQL o un
  bloque PL/SQL (el bloque termina con una barra `/` en una línea aparte) y pulsa ↩. Las flechas recorren el historial
  de líneas escritas.
- **Editor**: un script con resaltado de sintaxis. F8 (⌘↩) ejecuta la selección o todo el script; el resultado aparece
  en la pestaña Diálogo. **Sesión › Interrumpir** (⌘.) detiene el script.

La barra de estado muestra los ajustes actuales de `ECHO`, `TERMOUT`, `FEEDBACK`, `VERIFY`, `AUTOPRINT`, `HEADING` y
`TIMING`; un doble clic en un indicador cambia el ajuste.

> **Ejercicio: tu primer script de SQL*Plus.**
> 1. Abre **Archivo › Nuevo › Consola SQL*Plus**.
>    *Resultado:* una ventana con la letra **C** y la pestaña **Diálogo** con una línea de comandos abajo.
> 2. En la línea de comandos escribe `DESCRIBE pel_employees` y pulsa ↩.
>    *Resultado:* la lista de columnas de la tabla con sus tipos y si pueden estar vacías (NULL).
> 3. Pasa a la pestaña **Editor** y escribe el script:
>
>    ```sql
>    SET SERVEROUTPUT ON
>    SET TIMING ON
>    PROMPT Empleados del departamento Informatyka:
>    EXECUTE pel_emp_api.print_department(20)
>    COLUMN last_name HEADING 'Apellido' FORMAT A15
>    SELECT last_name, salary FROM pel_employees WHERE dept_id = 20;
>    ```
>
> 4. Pulsa **F8**.
>    *Resultado:* la pestaña Diálogo muestra el texto de PROMPT, la lista de `print_department` (DBMS_OUTPUT), una tabla de
>    texto con el encabezado «Apellido» y el tiempo de ejecución de cada sentencia (TIMING). La barra de estado muestra
>    TIMING activado.
> 5. En la línea de comandos escribe `DIR` para ver el directorio actual de la consola (lo cambias con
>    `CD directorio`). Después escribe `SPOOL empleados.txt`, `SELECT * FROM pel_departments;` y `SPOOL OFF`.
>    *Resultado:* en el directorio actual está el archivo `empleados.txt` con el resultado de la consulta.
>
> ⚠️ **Atención.** Empieza un script de despliegue con `WHENEVER SQLERROR EXIT SQL.SQLCODE`: si no, tras fallar una
> sentencia las siguientes siguen ejecutándose y la base queda «a medias». Antes de ejecutar un script ajeno, léelo y
> comprueba en qué conexión está la consola.

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
ejecutarla, ejecutar el resto del script o interrumpir. Es una forma segura de ejecutar por primera vez un script que
no conoces: ves cada sentencia antes de que llegue a la base.
