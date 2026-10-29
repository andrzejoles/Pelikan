# Plan de ejecución, sesiones y administración

## Plan de ejecución (Explain Plan)

Coloca el cursor en una sentencia (o selecciónala) y pulsa F5 (**Herramientas › Explain Plan**). Pelikan abre una
ventana de plan con el plan de PLAN_TABLE. En el código PL/SQL, las variables se sustituyen por variables de enlace y se
omite `INTO`, así que obtienes el plan de una consulta de un procedimiento sin reescribirla. Abres una ventana de plan
vacía con **Archivo › Nuevo › Explain Plan Window**; Pelikan puede crear la tabla PLAN_TABLE si falta.

![Ventana de plan: vista Diagrama](../img/plan-diagram.png)

- **Actualizar plan** recalcula el plan del texto del editor de la ventana de plan, y **Objetivo del optimizador** (*Como en la
  sesión*, ALL_ROWS o FIRST_ROWS_n) añade una sugerencia (hint).
- Vistas: **Árbol** (operaciones con coste, número de filas, bytes, tiempo, orden de ejecución y predicados de acceso y
  de filtro), **Diagrama** (un nodo por operación con coste, cardinalidad y número de paso), **Flame graph** (el coste
  de las operaciones en proporción al padre) y **Texto** (DBMS_XPLAN).
- Los botones de navegación recorren las operaciones en orden de ejecución: primer paso, anterior, siguiente y último.
- **Comparar** compara el plan con el plan anterior de la ventana o con el plan de una segunda ventana de plan: empareja
  las operaciones y muestra las diferencias de coste, cardinalidad, orden y predicados.
- **Guardar** guarda el plan como texto, HTML o XML (DBMS_XPLAN).

El plan se calcula en una sesión de herramientas aparte, así que no afecta a la transacción de la ventana.

## Autotrace

**Herramientas › Autotrace** (o el botón **Autotrace** de la ventana de plan) ejecuta la sentencia con medición y
muestra el plan real: Starts, el número de filas estimado (E-Rows) y real (A-Rows) con las grandes discrepancias
resaltadas, tiempos, búferes y lecturas, así como la variación de las estadísticas de la sesión antes y después de la
ejecución. Las sentencias DML se revierten tras la medición. Autotrace no requiere el Tuning Pack.

Autotrace pregunta por las variables de la sentencia como la ventana SQL: las variables de enlace (`:nombre`) reciben
valores de la ventana **Variables** (recordados en la ventana) y las variables de sustitución (`&nombre`), solo con la
sustitución de la ventana activada; si está desactivada, `&` se queda en el texto sin preguntar.

## Paquetes Oracle Diagnostics y Tuning

El menú **Herramientas › Rendimiento (paquetes de Oracle)** contiene herramientas que usan paquetes de pago de Oracle:

| Comando | Paquete | Qué hace |
|---|---|---|
| Informe AWR | Diagnostics | informe HTML a partir de instantáneas AWR |
| Informe ASH | Diagnostics | informe HTML de las sesiones activas de los últimos minutos |
| Informe ADDM | Diagnostics | recomendaciones de ADDM |
| SQL Monitor | Tuning | lista de consultas monitorizadas (V$SQL_MONITOR) con informe de la elegida |
| Informe de SQL Monitor | Tuning | informe HTML de una consulta monitorizada |
| SQL Tuning Advisor | Tuning | recomendaciones para la sentencia bajo el cursor; la tarea del asesor se elimina después |

**Importante: licencias.** Usa estas funciones solo si la base de datos tiene licencia del paquete correspondiente (el
Tuning Pack requiere también el Diagnostics Pack). En el primer uso, Pelikan pregunta qué licencia tiene la base de
datos y recuerda la respuesta en la definición de la conexión (pestaña **Avanzado** › **Licencia de Diagnostics/Tuning
Pack**). Sin una licencia declarada, o si el parámetro de la base de datos `CONTROL_MANAGEMENT_PACK_ACCESS` vale `NONE`
(o `DIAGNOSTIC` para las funciones del Tuning Pack), la función no se inicia. Los agentes de IA no tienen acceso a estas
herramientas. Los informes se guardan como HTML.

## Sesiones de la base de datos

**Herramientas › Sesiones** muestra las sesiones de la base de datos (V$SESSION):

- **Filtro** elige la consulta de la lista (p. ej., *Sesiones de usuarios*); **Actualizar cada** n segundos activa la
  actualización automática.
- Pestañas de detalle de la sesión seleccionada: **SQL actual**, **Cursores abiertos**, **Bloqueos**, **Estadísticas**,
  **Espera**.
- **Finalizar** y **Finalizar inmediatamente** terminan la sesión (`ALTER SYSTEM KILL SESSION`) tras confirmación.
- **Acciones**: entre otras, activar SQL Trace para la sesión (DBMS_MONITOR).
- **Consultas…** permite definir filtros propios (condición WHERE), pestañas de detalle (con `:sid`, `:serial#`) y
  acciones.

Las sesiones de Pelikan tienen en la columna MODULE el valor «Pelikan», y las de los agentes de IA, «Pelikan agent».

## Panel DBA e Instance Viewer

**Vista › Panel DBA** reúne información de administración: tablespaces con su ocupación, archivos de datos, parámetros
de la instancia, usuarios, roles, sesiones y bloqueos. En la lista de parámetros, **Cambiar valor…** ejecuta `ALTER
SYSTEM SET … SCOPE=BOTH`, y en la lista de usuarios, **Bloquear** y **Desbloquear** cambian el estado de la cuenta,
siempre tras confirmación y con las mismas protecciones que la SQL Window. Las partes para las que no tienes privilegios
muestran un mensaje en lugar de datos.

**Herramientas › Instance Viewer** es un panel de la instancia: versión y estado de la base de datos, tiempo en
funcionamiento, número de sesiones, clases de espera (incremento por segundo), las consultas más costosas (V$SQL) y SGA
y PGA, con actualización automática.

![Instance Viewer](../img/instance-viewer.png)

## DBMS Scheduler

**Herramientas › DBMS Scheduler** muestra los objetos del planificador en un árbol: ventanas y grupos de ventanas,
clases de trabajos, programaciones, programas, cadenas, trabajos, observadores de archivos y credenciales, con una vista
previa del SQL (View SQL) del objeto seleccionado.

- **Trabajo nuevo…** crea un trabajo con una programación integrada (p. ej., `FREQ=DAILY;BYHOUR=3`) o con nombre, con
  clase, comentario y notificaciones por correo. Un trabajo existente se modifica con **Editar…** y se elimina tras
  confirmación.
- **Ejecuciones** muestra el historial de ejecuciones con informes (todas, fallidas, condiciones propias) y reglas de
  color.
- **En ejecución** muestra los trabajos en curso; **Detener** y **Detener (Force)** los interrumpen.
