# Solución de problemas y limitaciones

## Problemas más frecuentes

### macOS no deja abrir Pelikan

Pelikan no está notarizado por Apple. En el primer inicio, abre **Ajustes del Sistema › Privacidad y seguridad** y haz
clic en **Abrir igualmente** (consulta el capítulo *Introducción*).

### «Falta Oracle Instant Client»

- Descarga Instant Client para macOS en la versión **ARM64** (Basic o Basic Light) y descomprímelo o instálalo según las
  instrucciones de Oracle.
- Indica el directorio con el archivo `libclntsh.dylib` en **Preferencias › Oracle › Oracle Instant Client** y reinicia
  Pelikan.
- Si el cliente está en la carpeta Descargas y macOS preguntó por el acceso de Pelikan a esa carpeta y lo denegaste,
  cámbialo en **Ajustes del Sistema › Privacidad y seguridad › Archivos y carpetas** o mueve el cliente a otro lugar.
- De forma provisional, puedes cambiar la conexión al controlador *Thin* (pestaña **General** de la definición de la
  conexión).

### No puedo conectarme

- Haz clic en **Probar** en la definición de la conexión: el mensaje de la base de datos o del cliente de Oracle
  indicará la causa.
- **ORA-12154 / TNS:** no se encontró el alias; comprueba el directorio de configuración (pestaña **Avanzado** o
  **Preferencias › Oracle › Oracle Net y Oracle Wallet**) o usa una dirección `host:puerto/servicio`.
- **ORA-01017:** contraseña incorrecta; Pelikan vuelve a pedirla. Marca que se recuerde para sustituir la contraseña en
  el Llavero.
- **ORA-28001:** la contraseña ha caducado; Pelikan muestra la ventana de cambio de contraseña.
- **Oracle Wallet:** el campo **Base de datos** debe ser exactamente el alias guardado en la cartera, y la cartera debe
  tener el archivo `cwallet.sso` (inicio de sesión automático). El estado de la cartera se ve en **Preferencias ›
  Oracle**. Los cambios en esta sección surten efecto tras reiniciar.
- **Túnel SSH:** Pelikan usa el `ssh` del sistema; comprueba en el Terminal si funciona `ssh
  usuario@bastion.example.com` (clave en el agente SSH, host conocido). Indica la dirección de la base de datos tal como
  la ve el servidor SSH.
- **Touch ID:** si activaste la confirmación de las contraseñas guardadas y cancelas el diálogo del sistema, la conexión
  no se establece.

### Un atajo de teclado no funciona

- Teclas F: activa en Ajustes del Sistema su uso como teclas de función estándar o púlsalas junto con la tecla fn.
- ⌃F8, ⌃F2, ⌃F3 y otros atajos con ⌃ pueden estar ocupados por macOS (**Ajustes del Sistema › Teclado › Funciones
  rápidas de teclado**). Usa el equivalente con ⌘ (p. ej., ⇧⌘↩ en lugar de ⌃F8) o desactiva el atajo del sistema.
- ⌃Espacio cambia por omisión la fuente de entrada en macOS: invoca la sugerencia de código con ⌥⎋.
- Comprueba el atajo del comando en la paleta de comandos (⇧⌘P) o en **Preferencias › Teclado**.

### Una consulta tarda demasiado

**Interrumpir** (⌘.) interrumpe la ejecución y la obtención de filas. Si la base de datos no responde (p. ej., durante
`DBMS_SESSION.SLEEP` o con el controlador Thin, que no admite la interrupción), usa **Sesión › Finalizar la sesión de la
ventana (Kill)**: requiere el privilegio ALTER SYSTEM.

### No puedo editar un resultado en la cuadrícula

La consulta debe devolver la columna `ROWID` (p. ej., `select t.*, t.rowid from tabla t`). Lo más sencillo es usar
**Editar datos** del menú de la tabla en el Object Browser. Una conexión de solo lectura bloquea el guardado.

### El depurador no se detiene

- Comprueba los privilegios `DEBUG CONNECT SESSION` y `DEBUG ANY PROCEDURE` (o `DEBUG` sobre el objeto): **Depuración ›
  Privilegios del depurador…** prepara las sentencias para el administrador.
- Compila el objeto con información de depuración (**Herramientas › Objeto › Añadir información de depuración**).
- Un punto de interrupción con una marca vacía no lo aceptó la base de datos (p. ej., una línea sin código ejecutable).

### El informe AWR / SQL Monitor no funciona

Comprueba la declaración de licencia en la definición de la conexión (pestaña **Avanzado**) y el parámetro de la base de
datos `CONTROL_MANAGEMENT_PACK_ACCESS`. Las funciones del Tuning Pack requieren el valor `DIAGNOSTIC+TUNING`.

El error ORA-00904 «DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_HTML: invalid identifier» significa que falta el privilegio
EXECUTE sobre el paquete `SYS.DBMS_WORKLOAD_REPOSITORY` (informe ADDM — también `SYS.DBMS_ADDM`): en SQL, Oracle responde entonces
«invalid identifier» en lugar de indicar la falta de privilegios. El privilegio suele llegar con el rol DBA; también se
necesita la licencia de Oracle Diagnostics Pack. Pelikan comprueba el privilegio antes de los informes AWR, ASH y ADDM e
indica la sentencia GRANT para el administrador de la base de datos, p. ej.
`GRANT EXECUTE ON SYS.DBMS_WORKLOAD_REPOSITORY TO SCOTT;`.

### El agente no se inicia

- Pelikan busca el programa del agente en el `PATH` de tu shell de inicio de sesión: comprueba en el Terminal si el
  comando (p. ej., `claude`) funciona.
- El agente no ve la conexión: comprueba la pestaña **Agente de IA** de la definición de la conexión.
- El agente no puede cambiar nada: la conexión es de solo lectura, es de producción sin autorización de cambios o
  bajaste el nivel de la herramienta en la matriz de permisos de la sesión.

### Pelikan se cerró inesperadamente

En el siguiente inicio, Pelikan propondrá recuperar las ventanas sin guardar (también más tarde: **Archivo › Recuperar
ventanas…**), si en **Preferencias › Herramientas** está activada la conservación de las ventanas sin guardar. Los
cambios de los archivos también están en el historial local (**Archivo › Historial local**).

### Registro de la aplicación

Pelikan mantiene un registro de eventos: inicio, conexiones y sus errores (código ORA-), sentencias completadas (tipo,
tiempo, número de filas), tareas en segundo plano, el depurador, las pruebas, los túneles SSH, los agentes de IA y las
actualizaciones. **Ayuda › Registro de la aplicación** lo abre en la Consola de macOS; el archivo está en
`~/Library/Logs/Pelikan` y las mismas entradas van al registro del sistema (subsistema de Pelikan en la Consola). Los
archivos ocupan como máximo 2 MB y Pelikan conserva los cinco últimos.

El registro nunca contiene contraseñas, texto de sentencias SQL ni datos de la base de datos. Los nombres de
conexiones, servidores y objetos y las rutas de archivos están ocultos o sustituidos por un hash de forma
predeterminada (el mismo nombre tiene siempre el mismo hash). En **Preferencias › General › Registro de la
aplicación** eliges cuánto se registra (*Advertencias y errores*, *Eventos*, *Detalles — diagnóstico*) y puedes
mostrar los nombres, algo útil para buscar la causa de un problema en tu propio equipo.

## Limitaciones conocidas

Las siguientes funciones se comportan de forma distinta que en el programa de referencia, están incompletas o no se han
comprobado en un entorno real:

- El **controlador Thin** no admite TCPS ni carteras, autenticación externa, cambio de una contraseña caducada ni
  interrupción de la ejecución. Lee CLOB y DBMS_OUTPUT hasta 65 535 caracteres (los más largos, con marca de
  truncado), y una consulta con una columna INTERVAL YEAR TO MONTH o BFILE cierra la aplicación (error de la
  biblioteca OracleNIO): para esos datos usa el controlador Instant Client.
- **Kerberos** en macOS: cuando `sqlnet.ora` activa KERBEROS5, la conexión termina con un error claro (el adaptador
  de Instant Client entra en conflicto con el Kerberos del sistema dentro de la aplicación); en Linux el inicio de
  sesión con tique funciona. **Microsoft Entra ID** y las **conexiones TCPS** están implementados según la documentación
  de Oracle, pero no se han probado con Azure ni con un listener TCPS. **LDAP** (nombres de directorio): Pelikan resuelve
  el alias por sí mismo mediante LDAPv3 anónimo, sin LDAPS ni enlace con wallet.
- **Depurador**: no hay depuración mediante DBMS_DEBUG_JDWP; en los disparadores no están disponibles los valores `:new`
  y `:old`; en una línea solo puede haber un punto de interrupción.
- La **cuadrícula** no puede inmovilizar (congelar) columnas ni filas.
- **Command Window**: los comandos `COPY` y `SET ENVVAR` no están admitidos.
- El **Event Monitor** no lee el DBMS_OUTPUT de otras sesiones (Oracle no lo ofrece).
- Las **herramientas de la columna izquierda** son pestañas de un único panel (Conexiones, Objetos, Ventanas, Templates,
  Archivos); no se pueden acoplar libremente ni ocultar automáticamente. Los documentos son pestañas de una única ventana
  principal, no pestañas nativas de macOS.
- **Quick Look** para archivos SQL (vista previa en el Finder) puede no funcionar: macOS puede rechazar una extensión
  firmada con un certificado propio.
- El **build remoto de Pro*C** se ha probado en un servidor SSH local con el shell ksh93; los analizadores de los
  mensajes de `proc` y `xlc` se escribieron a partir de la documentación. El funcionamiento en AIX 6.1 (ksh88) está
  pendiente de confirmación en un servidor real.
- **Omitidos** en esta versión: el importador ODBC (lo sustituyen los importadores de texto y de Excel y el asistente de
  importación), APEXlang y Liquibase (`lb` de SQLcl).
- **VoiceOver**: los elementos de la interfaz tienen etiquetas de accesibilidad, pero la aplicación todavía no se ha
  comprobado con VoiceOver.

## Informar de errores

Informa de errores y propuestas en la página del proyecto:
[github.com/andrzejoles/Pelikan/issues](https://github.com/andrzejoles/Pelikan/issues). No incluyas contraseñas, nombres
de servidores ni datos de bases de datos de producción: basta con describir los pasos y el mensaje de error.

Lo más sencillo es informar desde la aplicación: **Ayuda › Informar de un problema…** (también en la cinta: **Vista ›
Ayuda**), el botón **Informar de un problema…** de un mensaje de error o la pregunta tras un cierre inesperado de
Pelikan (con la descripción del fallo del informe de macOS: excepción y pila, sin rutas). En la ventana del informe
escriba un título y una descripción, elija si incluir el entorno y las últimas entradas del registro y revise la vista
previa. **Abrir incidencia en GitHub** abre la página de una nueva incidencia con el texto rellenado (hay una copia en el
portapapeles); la envía desde su propia cuenta de GitHub, Pelikan no envía nada por sí mismo. Las incidencias son
públicas: el texto pasa por el filtro de contraseñas y de la ruta personal, y el registro oculta los nombres por defecto.

Adjunta el registro al informe: **Ayuda › Exportar registro…** lo guarda junto con una descripción del entorno
(versión, sistema, controladores) en un archivo de texto. Revisa el archivo antes de enviarlo, sobre todo si se
mostraban los nombres.

## Glosario

Los nombres polacos de las ventanas y los conceptos de Pelikan y sus equivalentes en PL/SQL Developer (p. ej., *Okno
SQL*: SQL Window; *Przeglądarka obiektów*: Object Browser; *Zatwierdź zmiany (Post)*: Post changes) están en el glosario
de términos: [docs/GLOSSARY.md](https://github.com/andrzejoles/Pelikan/blob/main/docs/GLOSSARY.md).
