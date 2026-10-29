# Agentes de IA

Pelikan te permite trabajar con un agente de IA que se ejecuta en un terminal integrado en la ventana (p. ej., Claude
Code) y que ve tus ventanas y la base de datos únicamente a través de las herramientas de Pelikan y con las reglas que
tú controlas. El agente puede leer código y datos, analizar planes, escribir y formatear código en las ventanas, y solo
hace cambios en la base de datos con tu autorización.

## Programas admitidos

| Agente | Comando | Cómo recibe el servidor MCP de Pelikan |
|---|---|---|
| Claude Code | `claude` | `--mcp-config` solo para esta sesión |
| Codex CLI | `codex` | `-c mcp_servers…` solo para esta sesión |
| Grok CLI | `grok` | la variable `GROK_CONFIG` solo para esta sesión |
| Antigravity | `agy` | registro único del servidor «pelikan», solo con tu autorización |

El programa del agente lo instalas tú y en él inicias sesión con tu cuenta del proveedor. Pelikan busca el comando en el
`PATH` de tu shell de inicio de sesión. La lista de programas se cambia en **Ajustes › Agentes** (**Añadir CLI**,
**Restaurar valores predeterminados**).

El servidor MCP de Pelikan solo está disponible para una sesión iniciada desde Pelikan: la comunicación va por un socket
Unix accesible únicamente para tu cuenta (sin puertos de red), y cada sesión tiene su propio token de un solo uso, que
se pasa al programa en el entorno y se invalida al terminar la sesión. Antigravity no permite indicar un servidor para
una sola sesión, por eso Pelikan pide autorización para un registro permanente; fuera de las sesiones iniciadas desde
Pelikan, el servidor registrado rechaza cualquier conexión.

## Iniciar un agente

1. Elige **Herramientas › Agente de IA › Ejecutar Claude Code** (u otro programa).
2. Aparece la **matriz de permisos de la sesión**: una lista de herramientas con su nivel de acceso. Puedes bajar el
   nivel de las herramientas que elijas o hacer clic en **Todo de solo lectura**. No se puede subir el nivel. Haz clic
   en **Ejecutar**.
3. En el lado derecho de la ventana se abre el **panel del agente** con el terminal del programa. Trabajas con el agente
   como en un terminal normal.

El directorio de trabajo del agente es la carpeta del archivo de la ventana activa (p. ej., de un proyecto) y, si la
ventana no tiene archivo, un directorio temporal de la sesión. El panel se muestra y se oculta con **Vista › Panel del
agente**.

![Panel del agente en el lado derecho de la ventana principal](../img/panel-agenta.png)

Bajo el terminal, el panel muestra la **actividad del agente**: cada llamada a una herramienta con su hora, estado (en
curso, aprobada, rechazada, error), parámetros y resultado, además de un contador de solicitudes pendientes de
autorización. Botones: **Deshacer sesión…**, **Finalizar** y **Registro**.

## Niveles de acceso

Cada comando de Pelikan tiene un nivel de acceso para el agente:

- **Ninguno**: el agente no ve esta función;
- **Lectura**: el agente ve el estado o el resultado y no cambia nada;
- **Con autorización**: el agente propone la operación y tú la apruebas tras ver la vista previa;
- **Completo**: el agente realiza la operación sin preguntar, pero solo si se puede deshacer (p. ej., un cambio de texto
  en una ventana), y todo queda en el registro.

Se aplica el nivel más bajo de los tres: el del comando, el de la matriz de la sesión y el de la conexión. En una
conexión de **solo lectura** o sin autorización de cambios (pestaña **Agente de IA** de la definición de la conexión),
el agente tiene como máximo **Lectura**. En las conexiones de producción, la autorización de cambios está desactivada
por omisión.

Las herramientas del agente en resumen:

- **Lectura**: lista de conexiones (solo alias), estado de las ventanas y contenido del editor, búsqueda y descripción
  de objetos, código fuente, DDL, dependencias y usos, consultas, plan de ejecución, errores de compilación,
  DBMS_OUTPUT, pruebas utPLSQL y sus resultados, cobertura, lista de sesiones;
- **Completo** (reversible): abrir un objeto o una ventana nueva, insertar y sustituir texto, formatear, ir a una línea;
- **Con autorización**: compilación, ejecución de una sentencia y de un script, COMMIT, ROLLBACK, creación y generación
  de un paquete de pruebas, ejecución de pruebas utPLSQL, instalación de utPLSQL.

El agente **no** tiene acceso a la consola SQL*Plus ni al comando HOST, al shell del sistema a través de Pelikan, al
depurador, a la ventana Sesiones (salvo leer la lista de sesiones) ni a finalizar sesiones, a SQL Trace, a los informes
AWR/ASH/ADDM, a SQL Monitor ni a SQL Tuning Advisor, al build remoto de Pro*C, a las herramientas de usuario ni a las
contraseñas, hosts, puertos y nombres de usuario de las conexiones.

## Ventana de autorización

Cuando el agente quiere modificar la base de datos, Pelikan muestra la ventana **Aprobación de la operación del agente**
con una vista previa completa: las sentencias, los objetos afectados (con tablas, disparadores y objetos dependientes),
el número estimado de filas, el plan de ejecución y los argumentos. Si un cambio no se puede deshacer (COMMIT, DDL sobre
una tabla), la ventana lo dice claramente con una advertencia en rojo.

![Ventana de aprobación de una operación del agente](../img/zgoda-agenta.png)

La ventana está diseñada para que no se apruebe nada por accidente:

- no hay botón predeterminado: ↩ (p. ej., pulsada mientras escribes en el terminal del agente) no aprueba nada;
- **Permitir** se activa solo tras 0,8 segundos;
- Esc rechaza la solicitud (**Denegar**);
- las solicitudes siguientes esperan en cola hasta que resuelves la actual.

## Transacciones y deshacer

- El agente tiene **sus propias sesiones de base de datos**: no ve tu transacción sin confirmar y no puede confirmarla.
  En V$SESSION sus sesiones tienen MODULE «Pelikan agent», y en ACTION, el nombre de la herramienta.
- Las consultas del agente se ejecutan en una transacción de solo lectura, con límites de número de filas, tiempo y
  tamaño del resultado (**Ajustes › Agentes › Consultas del agente**; por omisión, 500 filas, 30 s y 1 MB) y un
  límite de llamadas por minuto. Una consulta debe ser una única sentencia SELECT/WITH, sin `FOR UPDATE` y sin funciones
  definidas en la cláusula WITH.
- **El DML del agente queda sin confirmar** hasta que autorizas por separado un COMMIT. Cerrar la sesión del agente
  revierte los cambios sin confirmar (ROLLBACK). El DDL del agente se rechaza cuando el agente tiene DML sin confirmar
  (el DDL lo confirmaría implícitamente).
- Los bloques PL/SQL y `CALL` del agente también se rechazan mientras tenga DML sin confirmar: podrían confirmarlo
  (COMMIT en el código, DDL dinámico, transacciones autónomas). La ventana de aprobación avisa de que un bloque PL/SQL
  no se puede deshacer. La consola SQL*Plus está fuera del alcance del agente: no puede leer ni cambiar su texto.
- Antes de modificar el código de un objeto (paquete, procedimiento, vista…), Pelikan guarda la versión anterior.
  **Herramientas › Agente de IA › Deshacer sesión de agente…** (o **Deshacer sesión…** en el panel) restaura el código
  de los objetos de antes de la sesión, elimina los objetos creados por el agente, deshace los cambios de texto en las
  ventanas y cierra las ventanas abiertas por el agente. Un objeto modificado después por otra persona es un conflicto:
  se omite, a menos que elijas **Deshacer forzando**. Los cambios confirmados (COMMIT) y el DDL sobre tablas no se
  pueden deshacer.
- **Herramientas › Agente de IA › Finalizar sesión del agente** termina el programa del agente, invalida el token,
  revierte los cambios sin confirmar del agente y cierra sus sesiones de base de datos.

## Ajustes de la conexión para el agente

Pestaña **Agente de IA** de la definición de la conexión:

- **El agente ve esta conexión (solo alias y entorno)**: desactívalo para ocultar la conexión al agente.
- **El agente puede modificar datos y objetos (con autorización)**: desactivado por omisión para el entorno de
  producción.
- **Usuario de base de datos independiente para el agente**: el agente se conecta a través del proxy `principal[agente]`
  como un usuario con privilegios limitados (p. ej., solo SELECT). Un administrador debe conceder `ALTER USER agente
  GRANT CONNECT THROUGH principal`; no hace falta una segunda contraseña. Recomendado para producción.
- **Columnas enmascaradas para el agente**: nombres de columnas (p. ej., `PESEL, EMAIL`) o `ESQUEMA.TABLA.COLUMNA`. Los
  valores se enmascaran en los resultados, y las consultas que hacen referencia a esas columnas se rechazan.

Recuerda: todo lo que lee el agente (código, resultados de consultas) llega al proveedor del modelo de IA. El
enmascaramiento funciona por nombre de columna y es una ayuda, no una barrera de seguridad: una columna se puede leer,
p. ej., a través de una vista con otro nombre. La verdadera barrera son los privilegios del usuario de base de datos que
usa el agente. Las funciones llamadas en las consultas pueden tener efectos secundarios (p. ej., transacciones
autónomas): también frente a eso solo protegen los privilegios.

## Modo estricto

**Ajustes › Agentes › Modo estricto** (activado por omisión) inicia el programa del agente sin su propio shell ni
edición de archivos, solo con las herramientas de Pelikan, si el programa lo permite. Si no lo permite, el panel del
agente muestra una advertencia. Un programa de agente en modo completo funciona con los permisos de tu cuenta de macOS:
Pelikan avisa, pero no lo limita.

## Registro de agentes

Cada llamada a una herramienta, también las rechazadas, va al registro (archivos JSONL en el directorio de datos de
Pelikan, sin el token ni contraseñas). **Herramientas › Agente de IA › Registro de agentes…** (o **Registro** en el
panel) abre el visor del registro con la hora, la herramienta, la decisión, los argumentos y el resultado.
