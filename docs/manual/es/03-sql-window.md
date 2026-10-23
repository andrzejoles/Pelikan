# SQL Window

La SQL Window sirve para ejecutar consultas y scripts. El resultado de la consulta aparece en la cuadrícula bajo el
editor, los mensajes en la pestaña *Output* y la salida de DBMS_OUTPUT en una pestaña aparte.

## Ejecución

- **F8 / ⌘↩**: ejecuta la selección o la sentencia bajo el cursor (según el ajuste *AutoSelect*).
- **⌃F8 / ⇧⌘↩**: ejecuta al contrario que *AutoSelect* (p. ej., todas las sentencias de la ventana en lugar de la
  sentencia bajo el cursor).
- **Interrumpir** (⌘.): interrumpe una consulta larga.
- Pelikan detecta por sí mismo las variables de sustitución `&` y `&&` y las variables de enlace `:nazwa`, y pide sus
  valores. También reconoce los parámetros de informes de JasperReports `$P{…}`, `$P!{…}` y `$X{…}`.

## Cuadrícula de resultados

La cuadrícula obtiene las filas por lotes y carga más al desplazarte. Al hacer clic en un encabezado se ordena, y el
filtro actúa localmente sobre las filas obtenidas. Las celdas se pueden editar cuando la consulta obtiene `ROWID` o
procede de una sola tabla con clave: los cambios se aplican con un botón y se hacen definitivos al confirmar la transacción.
Los valores grandes (CLOB, BLOB, XML, JSON) se abren en el **Large Data Editor**.

Puedes exportar el resultado a CSV, TSV, HTML, XML, XLSX, sentencias INSERT o al portapapeles. El
**Panel de valores** (⌥⌘V) muestra la celda actual como texto, JSON, XML, HTML, imagen o hexadecimal.

## Transacciones

La barra de estado muestra si hay una transacción abierta. **Commit** (F10, ⌥⌘↩) y **Rollback** están en el menú Sesión
y en la barra de herramientas. En el modo *Multi session* cada ventana tiene su propia sesión; en el modo
*Dual session* las ventanas comparten una sesión.

## Explain Plan y Autotrace

**Explain Plan** (F5) muestra el plan de ejecución de la sentencia bajo el cursor en forma de árbol con el coste, el
número de filas y los predicados. Los planes se pueden comparar, y **Autotrace** ejecuta la sentencia y muestra el plan
real con estadísticas.
