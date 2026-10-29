# Test Window, depurador y profiler

## Test Window

La Test Window ejecuta un bloque PL/SQL con variables de enlace y permite depurarlo y perfilarlo. Lo más sencillo es
abrirla desde el Object Browser: menú del procedimiento o la función › **Probar**. Pelikan prepara un bloque con la
llamada en notación nombrada (para un subprograma de paquete, con la sobrecarga correcta) y variables para los
parámetros y el resultado de la función. Abres una ventana vacía con **Archivo › Nuevo › Test Window**.

1. En la pestaña **Variables**, bajo el bloque, escribe los valores de los parámetros de entrada. Las variables
   `:nombre` del bloque se detectan automáticamente; puedes cambiar su tipo (Integer, Float, String, Date, Timestamp,
   Boolean, CLOB, BLOB, Cursor y otros).
2. Pulsa F8 (⌘↩). Tras la ejecución, los valores de salida aparecen en la tabla, y los que han cambiado se resaltan en
   amarillo. La barra de estado muestra el tiempo de ejecución.
3. Confirma o revierte los cambios: F10 / ⇧F10 (la opción **AutoCommit tras ejecutar la ventana de prueba** de
   **Ajustes › SQL Window** confirma automáticamente).

Las demás pestañas:

- **Salida**: DBMS_OUTPUT; el conmutador **Salida HTP** muestra la página generada con los paquetes HTP/OWA (tras marcar
  **Recoger HTP al ejecutar**).
- **Pila de errores**: ante un error de ejecución, la pila de llamadas con las líneas; un clic abre la unidad en la
  línea del error.
- **Resultados**: los conjuntos devueltos por `DBMS_SQL.RETURN_RESULT`.
- **Profiler**, **Estadísticas** y **Traza**: se describen más abajo.

Si tras recompilar un paquete se borra su estado (ORA-04068 y similares), la barra de estado muestra una advertencia;
volver a ejecutar funciona con normalidad.

Guardas una prueba como archivo `.tst` (el bloque, las variables y las expresiones observadas del depurador). **Archivo
› Guardar prueba como script de SQL*Plus** crea un script para ejecutarlo fuera de Pelikan. **Depuración › Guardar como
prueba estándar…** guarda la ventana como plantilla (con la marca `%CALL%` en lugar de la llamada), que después eliges
para cualquier procedimiento con **Prueba estándar…** en el menú del objeto.

Para ejecutar muchas pruebas con resultados esperados sirve **Herramientas › Test Manager** (capítulo *Herramientas*), y
para las pruebas unitarias, utPLSQL (capítulo *Pruebas utPLSQL*).

## Depurador

El depurador usa el paquete de Oracle DBMS_DEBUG y funciona en bases de datos 19c–26ai.

### Preparación

- El usuario necesita los privilegios `DEBUG CONNECT SESSION` y `DEBUG ANY PROCEDURE` o `DEBUG` sobre objetos concretos.
  **Depuración › Privilegios del depurador…** abre una SQL Window con las sentencias GRANT listas para que las ejecute
  un administrador.
- El código que quieres recorrer paso a paso debe estar compilado con información de depuración: **Herramientas › Objeto
  › Añadir información de depuración** o automáticamente al compilar en la Program Window (**Ajustes › Oracle ›
  Depurador**; ahí también están las listas de objetos y conexiones para los que la información se añade siempre o
  nunca, p. ej., `*@prod*`).

### Ejecución paso a paso

1. Establece puntos de interrupción: haz clic en el margen de números de línea de la ventana de programa o de prueba, o
   pulsa ⌃B (**Depuración › Alternar punto de interrupción**).
2. En la Test Window, elige **Depuración › Iniciar depuración** (F9). Se abre la ventana **Depurador** con la pila de
   llamadas, las variables y las expresiones observadas, y el cursor se detiene en la primera línea.
3. Avanza paso a paso:

| Acción | Atajo |
|---|---|
| Continuar (hasta el siguiente punto de interrupción) | ⌃R |
| Entrar (en un subprograma, también en un disparador) | ⌃N |
| Pasar por encima (línea siguiente) | ⌃O |
| Salir (de un subprograma) | ⌃T |
| Ejecutar hasta el cursor / hasta una excepción | menú Depuración |
| Detener depuración | ⇧F9 |

El foco se queda en la ventana principal, así que puedes avanzar con atajos mientras miras el código.

### Variables, expresiones observadas, pila

- **Variables**: locales, parámetros, globales del paquete (privadas y públicas), registros, colecciones y objetos como
  árbol, `SELF` en los métodos de tipos. Al pasar el ratón sobre una variable en el editor se muestra su valor.
- **Establecer valor…** cambia el valor de una variable escalar (un literal PL/SQL o texto; `NULL`, valor vacío), y
  **Copiar valor** lo copia al portapapeles.
- **Observadas**: escribe una expresión (p. ej., `v`, `r.campo`, `t(3)`) y haz clic en **Observar**.
- **Pila de llamadas**: un clic en un marco muestra sus variables y su lugar en el código.
- **Ejecutar SQL en la sesión depurada…** ejecuta una consulta (las primeras 100 filas) o un bloque PL/SQL en la sesión
  que estás depurando: ve sus cambios sin confirmar.
- DBMS_OUTPUT se lee en cada parada.

En los disparadores no están disponibles los valores `:new` y `:old` (limitación de DBMS_DEBUG): el depurador muestra
entonces un aviso en lugar del valor. Por omisión, la ejecución paso a paso omite la inicialización de paquetes y los
objetos de SYS (**Ajustes › Oracle › Depurador**).

### Puntos de interrupción, condiciones y puntos de registro

**Depuración › Puntos de interrupción…** abre la lista de todos los puntos:

![Ventana Puntos de interrupción](../img/punkty-przerwania.png)

- **Activado**: un punto se puede desactivar sin eliminarlo.
- **Número de pasadas**: se detiene solo en la n-ésima pasada.
- **Condición**: una expresión, p. ej., `l_sal > 1000`; el depurador se detiene solo cuando es verdadera.
- **Mensaje**: texto que se escribe en cada pasada; `{variable}` inserta el valor de la variable.
- **No detener**: junto con un mensaje crea un **punto de registro** (logpoint): el depurador escribe el mensaje y
  sigue.
- **Detener en errores ORA-**: códigos de error en los que el depurador debe detenerse (p. ej., `1403, 20001`).
- **Activar todos**, **Desactivar todos**, **Eliminar todos**, **Guardar…** y **Cargar…** (archivo JSON).

Un punto que la base de datos no aceptó (p. ej., en una línea sin código) tiene una marca vacía en el margen. En una
línea puede haber un punto.

Las pruebas utPLSQL también se pueden depurar: **Depuración › utPLSQL: depurar la prueba bajo el cursor**.

## Profiler

1. En la pestaña **Profiler** de la Test Window, elige el tipo en el campo **Profiler durante la ejecución**: **Lineal
   (DBMS_PROFILER)** o **Jerárquico (DBMS_HPROF)**. El comando **Depuración › Profiler durante la ejecución** activa y
   desactiva el profiler lineal.
2. Ejecuta el bloque (F8).
3. La pestaña **Profiler** muestra el informe: para el profiler lineal, el tiempo, el número de ejecuciones y la
   proporción de cada línea con un gráfico de barras; para el jerárquico, las funciones con su tiempo propio y con las
   llamadas, y el árbol de llamadas. La unidad de tiempo y el umbral de proporción se ajustan en esta pestaña.

El menú **Ejecuciones** de la pestaña (y **Depuración › Ejecuciones del profiler**) abre los informes de ejecuciones
anteriores. Pelikan crea las tablas del profiler que falten en tu esquema (en una conexión de producción, tras
confirmación; en una conexión de solo lectura, nunca). Los datos de una ejecución del profiler lineal quedan en la
transacción de la ventana: confírmala si quieres conservarlos.

## Estadísticas, traza y SQL Trace

- La pestaña **Estadísticas** muestra la variación de las estadísticas de la sesión (V$MYSTAT) de la última ejecución y
  el total de la ventana, con filtro y exportación a CSV. La elección de estadísticas está en **Ajustes › SQL
  Window**. Requiere acceso a V$MYSTAT.
- **Depuración › DBMS_TRACE al ejecutar** registra la ejecución (llamadas, excepciones, SQL, líneas) en la pestaña
  **Traza**; el historial de ejecuciones está en **Historial de ejecuciones de DBMS_TRACE**. Requiere las tablas de
  traza que instala un administrador con el script `tracetab.sql`.
- **Sesión › SQL Trace** activa y desactiva SQL Trace de la sesión de la ventana; Pelikan muestra el nombre del archivo
  de traza.
