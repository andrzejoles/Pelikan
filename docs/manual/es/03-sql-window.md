# SQL Window y cuadrícula de resultados

La SQL Window sirve para ejecutar consultas y scripts. El resultado de cada consulta aparece en una pestaña aparte bajo
el editor, y los mensajes de la base de datos y la salida de DBMS_OUTPUT, en la pestaña **Output**. Abres una ventana
nueva con **Archivo › Nuevo › SQL Window** (⌘N); la ventana trabaja en la conexión principal o en la conexión elegida en
la barra de estado.

## Ejecutar sentencias

| Acción | Atajo | Menú |
|---|---|---|
| Ejecutar la selección o la sentencia bajo el cursor | F8, ⌘↩ | Sesión › Ejecutar |
| Ejecutar al contrario que AutoSelect (p. ej., todo el script) | ⌃F8, ⇧⌘↩ | Sesión › Ejecutar (al contrario que AutoSelect) |
| Interrumpir la ejecución o la obtención de filas | ⇧⎋, ⌘. | Sesión › Interrumpir |
| Confirmar la transacción | F10, ⌥⌘↩ | Sesión › Confirmar (COMMIT) |
| Revertir la transacción | ⇧F10, ⌥⌘⌫ | Sesión › Revertir (ROLLBACK) |
| Sentencia anterior / siguiente de la ventana | ⌥⌘↑, ⌥⌘↓ | Sesión › Historial de la ventana |

Por omisión está activado **AutoSelect**: sin selección, F8 ejecuta solo la sentencia en la que está el cursor, así que
no ejecutarás por accidente todo el script. El texto seleccionado se ejecuta completo. Las sentencias se separan como en
SQL*Plus: el punto y coma termina una sentencia SQL, y un bloque PL/SQL o un `CREATE` con cuerpo termina con una barra
`/` en una línea aparte. Cada consulta del script obtiene su propia pestaña de resultados.

Atención: en macOS el atajo ⌃F8 lo ocupa por omisión el sistema (mover el foco a los menús de estado); usa ⇧⌘↩ o
desactiva el atajo del sistema en **Ajustes del Sistema › Teclado › Funciones rápidas de teclado**.

Durante la ejecución la ventana queda bloqueada para la edición y la barra de estado muestra «Ejecutando…». Al terminar
se ven el número de filas y el tiempo; un tiempo de más de 100 segundos tiene el formato hh:mm:ss. Tras una consulta
larga, Pelikan puede reproducir un sonido y hacer rebotar su icono en el Dock. Si **Interrumpir** no funciona (algunas
operaciones de la base de datos no responden a la interrupción), usa **Sesión › Finalizar la sesión de la ventana
(Kill)**.

Pelikan nunca confirma cambios automáticamente (la opción **AutoCommit de sentencias SQL** de **Ajustes › SQL
Window** está desactivada por omisión). La barra de estado indica una transacción abierta («● transacción abierta»).

## Contenido del código

A la izquierda del editor, el **Contenido del código** muestra la estructura de todo el script: sentencias SQL (la
primera palabra y el comienzo de la sentencia, hasta unos 1000 caracteres con saltos de línea en la ayuda emergente), procedimientos, funciones,
paquetes y disparadores de `CREATE`, y bloques anónimos con sus declaraciones. Un clic o Intro lleva el cursor a la
sentencia, el árbol sigue el cursor y el campo sobre el árbol filtra también por el texto de la sentencia (p. ej.
el nombre de una tabla). El panel se muestra u oculta en esta ventana con **Vista › Contenido del código** o con el
botón de barra lateral en el extremo izquierdo de la barra de la ventana; la elección se mantiene en la ventana, y
el valor por defecto de las ventanas nuevas está en **Ajustes › Editor › Contenido del código visible por defecto**.
La consola SQL*Plus no tiene este panel. En un script con más de 5000 sentencias SQL, el panel muestra solo las
unidades y bloques PL/SQL (con una nota con el número de sentencias).

## Variables

- **Variables de sustitución** `&nombre` y `&&nombre`: antes de ejecutar, Pelikan muestra la ventana **Variables** con
  campos para los valores. En la SQL Window, `&&` en el texto significa un carácter `&` normal (p. ej., `'R&&D'`); en la
  consola SQL*Plus, `&&` funciona como en SQL*Plus (la variable se recuerda).
- **Variables de enlace** `:nombre`: también van a la ventana de variables (`:new` y `:old` en los disparadores se
  omiten).
- **Parámetros de informes de JasperReports** `$P{…}`, `$P!{…}` y `$X{IN, columna, parámetro}`: Pelikan los reconoce y
  pide sus valores, así que ejecutas la consulta de un informe sin reescribirla.
- La sintaxis ampliada `&<name="…" type="…" list="…" default="…" required="…">` permite describir una variable: tipo,
  lista de valores (también de una consulta que depende de otras variables), valor predeterminado, obligatoriedad y
  otras opciones.

Los valores de las variables se recuerdan en la ventana. El botón **&** de la barra bajo el editor (**Sesión ›
Sustitución de variables**) desactiva la sustitución cuando el texto contiene los caracteres `&` y `:` con otro
significado.

## Directivas en comentarios

Un comentario justo antes de una sentencia puede controlar su resultado:

| Directiva | Efecto |
|---|---|
| `-- Tab=Empleados` | título de la pestaña de resultados; `&Count` inserta el número de filas |
| `-- Records=all` | cuántas filas obtener de inmediato: un número, `page` o `all` |
| `-- Totals=sum:SAL;count:EMPNO` | sumas y otras funciones bajo la cuadrícula |
| `-- AltRowColor=…` | color de las filas alternas |
| `-- Excel=informe_%date%.xlsx` | guardar todo el resultado en un archivo Excel |
| `-- CSV=%dbuser%_%time%.csv` | guardar todo el resultado en un archivo CSV |

En los nombres de archivo funcionan `%dbuser%`, `%dbname%`, `%date%`, `%time%` y `%&variable%`. Una ruta relativa se
cuenta desde el directorio del archivo de la ventana.

## Cuadrícula de resultados

![Edición de un resultado: fila nueva y contador de cambios pendientes](../img/siatka-edycja.png)

La cuadrícula obtiene las filas por lotes (el número se ajusta en **Ajustes › SQL Window › Filas por página**) y
carga más al desplazarte. La indicación «(más…)» junto al número de filas significa que el resultado no está completo.
**Página siguiente** (⌘⇟) y **Última página (obtener todo)** (⇧⌘⇟) están en el menú **Sesión › Resultado** y en la barra
sobre la cuadrícula. Con resultados muy grandes, Pelikan pregunta antes de superar el límite de tamaño de Ajustes.

- **Ordenar**: clic en el encabezado de la columna (ascendente, descendente, sin orden) sobre las filas obtenidas.
- **Seleccionar**: filas, columnas y bloques de celdas (clic y luego ⇧+clic).
- **NULL** tiene fondo de color; los números se muestran con la precisión completa de Oracle.
- **CLOB, BLOB, XML, textos largos**: el botón de la celda o **Edición › Resultado › Large Data Editor…** (⌥⌘L) abre el
  editor de datos grandes con vistas de texto, XML, JSON, HTML, imagen, PDF y hexadecimal, formato JSON/XML y guardado
  en archivo.
- El **Panel de valores** (**Vista › Panel de valores**, ⌥⌘V) muestra junto a la cuadrícula la celda actual como texto,
  JSON, XML, HTML, imagen o hexadecimal.
- La **Vista de registro único** muestra la fila actual en vertical con los tipos y comentarios de las columnas. La
  activa y desactiva el botón de la barra sobre la cuadrícula o **Registro** en la pestaña **Resultado** de la cinta;
  cada pestaña de resultado recuerda su estado.
- Un **cursor anidado** (`CURSOR(…)` en una consulta) se abre en una pestaña de resultados nueva.
- **Filtro de columnas…** oculta columnas por nombre, tipo, obligatoriedad y claves; las columnas ocultas se omiten al
  copiar y exportar.
- **Filtrar por el valor de la celda**, **Filtrar por expresión…** (`=`, `<>`, `<`, `>`, `LIKE`, `IS NULL`, `AND`, `OR`)
  y **Agrupar por columna** (con contadores; el doble clic filtra) funcionan localmente, sobre las filas obtenidas.
- **Totales de columna…** calculan bajo la cuadrícula la suma, el recuento, la media, el mínimo y el máximo, y los
  recuerdan tras volver a ejecutar.
- **Comparar registros** compara las filas seleccionadas columna a columna, y **Comparar resultados**, dos pestañas de
  resultados.
- **Consultas relacionadas…** abren en una ventana nueva las tablas padre e hijas de la fila actual (según las claves
  ajenas).
- **Actualizar resultado** (⇧⌘R) vuelve a ejecutar la sentencia de la pestaña, y **Actualización automática…** lo hace
  cada cierto número de segundos.
- **Fijar resultado** conserva la pestaña en la siguiente ejecución (también ⇧+clic en la pestaña).
- El tamaño de fuente de la cuadrícula se cambia en **Vista › Cuadrícula**.

La mayoría de estas acciones están en el menú contextual de la cuadrícula y en **Edición › Resultado** o **Sesión ›
Resultado**.

## Editar datos en la cuadrícula

Para editar un resultado, la consulta debe devolver la columna `ROWID`, p. ej.:

```
select t.*, t.rowid from dept t
```

Lo más sencillo es usar **Editar datos** del menú de la tabla en el Object Browser: Pelikan prepara esa consulta por sí
mismo.

1. Haz clic en el candado sobre la cuadrícula o elige **Sesión › Resultado › Editar datos** (⌥⌘E).
2. Modifica celdas, añade filas (**Insertar registro**, ⌥⌘I) y elimínalas (**Eliminar registro**, ⇧⌘⌫). Los cambios
   pendientes se marcan en el encabezado de la fila (+, ~, −) y con color; el contador sobre la cuadrícula muestra
   cuántos hay. Las columnas con alias y las expresiones son de solo lectura. Para las columnas DATE hay un
   **Calendario…**, y para las columnas con una restricción `CHECK … IN` o una clave ajena a una tabla pequeña, una
   **Lista de valores…**.
3. **Copiar SQL de los cambios** muestra las sentencias que se ejecutarán.
4. **Confirmar cambios (Post)** (⌥⌘S) envía los cambios a la base de datos, sin COMMIT. Tras un error, el cursor pasa a
   la celda afectada. **Descartar cambios** desecha todos los cambios pendientes.
5. Confirma la transacción (F10, ⌥⌘↩) o reviértela.

En una conexión de producción, guardar requiere confirmación, y en una conexión de solo lectura está bloqueado.

## Copiar y exportar

- **Edición › Resultado › Copiar con encabezado** (⇧⌘C), **Copiar encabezado**, **Copiar como lista de expresiones**
  (para `IN (…)`), **Copiar a Excel** y, en el menú contextual de la cuadrícula, también **Copiar como** (formato
  elegido).
- **Archivo › Exportar resultado…** guarda la selección o todo el resultado obtenido como CSV, TSV, HTML, XML, SQL
  (INSERT), lista de expresiones o Excel (xlsx).
- **Sesión › Resultado › Exportar consulta a archivo…** ejecuta la sentencia bajo el cursor y guarda el resultado
  directamente en un archivo, sin mostrarlo: práctico con resultados grandes.
- **Archivo › Exportar resultado › Columna a archivos…** guarda el valor de una columna (p. ej., BLOB) en un archivo
  aparte para cada fila.
- **Generar SQL a partir de filas…** crea sentencias INSERT, UPDATE, DELETE o MERGE para las filas seleccionadas en una
  SQL Window nueva, sin ejecutarlas.
- **Archivo › Imprimir…** (⌘P) imprime el código de la ventana con colores de sintaxis y la cuadrícula (las filas
  seleccionadas o todas las obtenidas).

## Gráficos

**Sesión › Resultado › Gráfico…** abre una ventana de gráfico a partir de la pestaña de resultados actual. Elige el tipo
(barras, líneas, áreas, dispersión o circular), la columna de categoría (eje X), las series (eje Y) y una agregación
opcional; ajusta los colores, la leyenda y los valores junto a los puntos. Puedes guardar una plantilla de gráfico y
exportar el gráfico a PNG, PDF o al portapapeles. **Actualizar** vuelve a ejecutar la consulta de la SQL Window.

![Ventana de gráfico a partir del resultado de una consulta](../img/wykres.png)

## Query By Example

**Sesión › Resultado › Query By Example…** (⇧⌘E) permite acotar un resultado sin escribir WHERE: escribe criterios bajo
los nombres de las columnas (un valor, un patrón con `%`, un operador (`>`, `<>`…), `in (…)`, `between … and …` o
`null`) y Pelikan vuelve a ejecutar la consulta con las condiciones. La comparación de texto no distingue mayúsculas de
minúsculas y las fechas se comparan sin la hora. **Borrar Query By Example** restaura la consulta original.

## Estadísticas y plan

Si se activan en **Ajustes › SQL Window › Estadísticas**, la pestaña **Estadísticas** muestra la variación de las
estadísticas de la sesión (V$MYSTAT) en cada ejecución. **Herramientas › Explain Plan** (F5) muestra el plan de la
sentencia bajo el cursor, y **Herramientas › Autotrace** la ejecuta y muestra el plan real; consulta el capítulo *Plan
de ejecución, sesiones y administración*.

## Archivos e historial

- **Archivo › Guardar** (⌘S) guarda la ventana en un archivo `.sql`; los archivos conservan su codificación y sus
  finales de línea.
- **Edición › Historial de comandos…** (⇧⌘H; en el perfil PL/SQL Developer, ⌃E) muestra todas las sentencias ejecutadas
  en todas las ventanas (sin las que contienen contraseñas) con un filtro; las elegidas se insertan en el editor.
- **Archivo › Pegar como nueva SQL Window** crea una ventana con el contenido del portapapeles.
- El historial local de un archivo (**Archivo › Historial local**) se describe en el capítulo *Herramientas*.
