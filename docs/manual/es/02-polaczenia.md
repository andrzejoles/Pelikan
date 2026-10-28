# Conexiones

Una conexión es una definición guardada: adónde conectarse, como quién y con qué reglas de seguridad. Las definiciones
se guardan sin contraseñas: las contraseñas van únicamente al Llavero de macOS.

## Lista de conexiones

La pestaña **Conexiones** de la columna izquierda muestra las definiciones en carpetas, y la carpeta **Recientes**, las
usadas recientemente. Bajo cada conexión se ven sus ventanas abiertas.

- Un doble clic en una conexión la conecta como **conexión principal** (en negrita en la lista). Las ventanas nuevas se
  abren en la conexión principal.
- Menú contextual de la conexión: **Conectar como principal**, **Conectar** (sin cambiar la principal),
  **Desconectar**, **Ventana nueva** (SQL, de programa, de prueba o de comandos en esta conexión), **Mostrar ventanas
  de la conexión**, **Cerrar ventanas de la conexión**, **Reconectar ventanas de la conexión**, **Establecer esquema
  actual…**, **Editar…**, **Copiar con otro nombre…** (copia en la misma carpeta, con las contraseñas guardadas),
  **Mover a la carpeta** y **Eliminar…**.
- Las carpetas y las conexiones se ordenan alfabéticamente. Arrastra una conexión con el ratón a una carpeta para
  moverla allí, o a un espacio libre de la lista para llevarla al nivel superior.
- Los botones sobre la lista crean una conexión nueva (**+**) y una carpeta, y actualizan la lista.

También puedes usar la ventana de inicio de sesión: **Sesión › Iniciar sesión…** (⇧⌘L). Muestra todas las definiciones
con un buscador y permite crear una conexión nueva o editar una existente. **Sesión › Cerrar sesión de la conexión
principal** finaliza las sesiones de la conexión principal.

## Conexión nueva

Elige **Sesión › Conexiones › Conexión nueva…** o haz clic en **+** en la lista de conexiones. La ventana de definición
tiene cuatro pestañas.

### Pestaña General

- **Nombre**: el nombre en la lista (vacío significa `usuario@base`). Para bases de datos de prueba locales van bien los
  nombres con prefijo, p. ej., `dev_test`.
- **Carpeta** y **Entorno**: *De desarrollo*, *De pruebas*, *De producción* u *Otros*. El entorno determina el color del
  indicador (pruebas: naranja; producción: rojo), la confirmación de los cambios y lo que puede hacer el agente de IA.
  **Color propio del indicador** sustituye al color del entorno.
- **Usuario**, **Contraseña** y **Recordar la contraseña en el Llavero**. Si no la recuerda, Pelikan pide la contraseña
  en la primera conexión y la mantiene solo en memoria hasta cerrar la aplicación. Cuando una contraseña guardada deja
  de coincidir (ORA-01017), Pelikan vuelve a pedirla.
- **Base de datos**: una dirección EZConnect `host:puerto/servicio` (p. ej., `db.example.com:1521/FREEPDB1`), un alias
  de `tnsnames.ora` (el botón **TNS** junto al campo sugiere alias de la configuración), un descriptor completo o una
  dirección `tcps://…` para conexiones cifradas.
- **Conectar como**: Normal, SYSDBA, SYSOPER, SYSBACKUP, SYSDG, SYSKM o SYSASM.
- **Autenticación**: *Contraseña*, *Oracle Wallet (almacén de contraseñas)*, *Externa (Kerberos, sistema)*, *Microsoft
  Entra ID (navegador)* o *Token OAuth2 desde archivo* (se describen más abajo).
- **Controlador**: *Instant Client (recomendado)* o *Thin (sin Instant Client)*. Thin no admite TCPS ni carteras,
  autenticación externa, cambio de una contraseña caducada ni interrupción de la ejecución.

Haz clic en **Probar** para comprobar la conexión y después en **Guardar**.

### Pestaña Avanzado

- **Proxy: esquema de destino**: inicio de sesión con un usuario intermediario en otro esquema (`usuario[esquema]`).
- **Directorio de configuración (tnsnames.ora)**: un directorio TNS propio de esta conexión.
- **Cartera TLS (mTLS, p. ej., Autonomous Database)**: un directorio con `cwallet.sso`. El botón **Importar ZIP…**
  descomprime junto al archivo ZIP el archivo de cartera descargado de la consola de la nube y establece también el
  directorio de configuración.
- **Edition (EBR)** y **Workspace (DBMS_WM)**: la edición y el espacio de trabajo que se establecen tras iniciar sesión.
- **Licencia de Diagnostics/Tuning Pack**: consulta *Licencias de los paquetes de Oracle* más abajo.
- **Esquema actual**: `ALTER SESSION SET CURRENT_SCHEMA` en cada sesión.
- **Solo lectura (bloqueo de cambios de datos y objetos)**: consulta más abajo.
- **Conectar al iniciar la aplicación**.
- **Script de inicialización de la sesión**: sentencias que se ejecutan en cada sesión nueva de esta conexión (separadas
  por `;`, bloques PL/SQL terminados con `/`).
- **Mensaje al iniciar sesión**: texto que se muestra tras conectarse, p. ej., un recordatorio de que es una base de
  datos compartida.

### Pestaña Túnel SSH

Cuando la base de datos solo es accesible a través de un servidor intermedio, marca **Conectar mediante túnel SSH** e
indica:

- **Servidor SSH (bastión)**, p. ej., `bastion.example.com`, **Puerto** y **Usuario SSH**;
- **Archivo de clave privada**: un campo vacío significa el agente SSH y los ajustes de `~/.ssh/config`;
- opcionalmente, un **Host intermedio (ProxyJump)**;
- o bien **Inicio de sesión SSH con contraseña (en lugar de clave)** y **Contraseña SSH**.

El túnel usa el `ssh` del sistema, así que funcionan tu configuración `~/.ssh/config`, el agente SSH (claves añadidas
con `ssh-add --apple-use-keychain`) y el archivo de hosts conocidos. Indica el host y el puerto de la base de datos en
el campo **Base de datos** tal como los ve el servidor SSH (p. ej., `db.internal.example.com:1521/SERVICIO`). La
contraseña SSH se guarda solo en el Llavero y llega a `ssh` a través de una canalización de un solo uso, nunca mediante
argumentos de comandos, variables de entorno ni archivos. Un túnel sirve a todas las sesiones de la conexión y se cierra
junto con la última de ellas.

### Pestaña Agente de IA

Ajustes del acceso de los agentes de IA a la conexión: si el agente la ve, si puede modificar datos y objetos (con tu
autorización), un usuario de base de datos independiente para el agente y columnas enmascaradas. Se describen en el
capítulo *Agentes de IA*.

## Entornos y protección contra errores

- El color de la conexión se ve en la lista de conexiones, en la pestaña de la ventana, en la lista de ventanas y en la
  barra de estado. La opción **Fondo del editor con el color de la conexión** (**Preferencias › General**) colorea
  también el fondo del editor. En la misma pestaña puedes añadir reglas de color según el patrón `usuario@base` (p. ej.,
  `sys@*`); tienen prioridad sobre el color del entorno.
- En una conexión de **producción**, las sentencias que modifican datos u objetos (DML, DDL, bloques PL/SQL) requieren
  confirmación en la ventana «Cambios en la conexión de producción».
- Una conexión de **solo lectura** rechaza, antes de enviarlo a la base de datos, todo lo que no sean consultas y
  control de la sesión, incluidos `SELECT … FOR UPDATE` y los bloques PL/SQL. En la barra de estado de la ventana se ve
  entonces «solo lectura».
- Pelikan nunca confirma una transacción por sí mismo. Al cerrar una ventana o la aplicación con una transacción
  abierta, pregunta si confirmar (COMMIT) o revertir (ROLLBACK); el comportamiento al cerrar sesión se cambia en
  **Preferencias › General › Cierre de sesión con una transacción abierta**.

## Contraseñas y Touch ID

Las contraseñas de bases de datos y SSH se guardan únicamente en el llavero de inicio de sesión de macOS (sin
sincronización con iCloud). No van a archivos, registros, historial de comandos ni argumentos de procesos.

En **Preferencias › Oracle › Contraseñas de conexiones** puedes activar **Requerir Touch ID o la contraseña del Mac
antes de usar una contraseña guardada**. Pelikan pedirá entonces confirmación una vez por conexión mientras la
aplicación esté en marcha, también cuando use la conexión un agente de IA.

Cuando la contraseña de la base de datos ha caducado (ORA-28001), Pelikan muestra la ventana de cambio de contraseña:
escribe la contraseña nueva dos veces. Si está activado recordarla, la contraseña nueva sustituye a la antigua en el
Llavero en cuanto la conexión tiene éxito.

También puedes cambiar la contraseña en cualquier momento: **Sesión › Cambiar contraseña…** (la conexión debe estar
abierta). Pelikan la cambia mediante la interfaz OCI —la contraseña no aparece en el texto SQL ni en el historial de
comandos— y guarda la nueva en el Llavero si la conexión recuerda su contraseña.

## Oracle Wallet

Pelikan admite dos tipos de cartera:

- **Almacén de contraseñas** (Secure External Password Store): inicio de sesión sin contraseña en Pelikan (`/@alias`).
  El directorio de la cartera y el directorio de configuración de Oracle Net se indican en **Preferencias › Oracle ›
  Oracle Net y Oracle Wallet**; Pelikan muestra ahí el estado de la cartera (se requiere una cartera de inicio de sesión
  automático `cwallet.sso`). En la definición de la conexión elige la autenticación *Oracle Wallet (almacén de
  contraseñas)*. El campo **Base de datos** debe ser exactamente el alias o la cadena de conexión guardados en la
  cartera. Los cambios en esta sección de Preferencias surten efecto tras reiniciar Pelikan.
- **Cartera TLS** (mTLS, p. ej., Autonomous Database): se configura en la pestaña **Avanzado** de la definición de la
  conexión.

Las contraseñas de la cartera nunca llegan a Pelikan.

## Otros métodos de autenticación

- **Externa (Kerberos, sistema)**: inicio de sesión con las credenciales del sistema operativo o de Kerberos.
- **Microsoft Entra ID (navegador)**: para bases de datos Oracle en Azure. Indicas el identificador del inquilino, el
  identificador de la aplicación cliente y el URI de la aplicación de la base de datos; Instant Client 23 abre el
  navegador para iniciar sesión y entrega el token a la base de datos por sí mismo. Pelikan no ve ni guarda el token.
  Requiere una conexión TCPS.
- **Token OAuth2 desde archivo**: un token preparado antes con una herramienta externa (p. ej., Azure CLI); indicas el
  archivo o el directorio del token.

## Ventanas, sesiones y conexión de la ventana

Cada ventana tiene su propia conexión, visible en la barra de estado. Haz clic en ella para cambiar la ventana a otra
conexión; si la ventana tiene una transacción abierta, Pelikan pregunta primero por COMMIT o ROLLBACK. Una ventana con
la conexión **fijada** (📌) no la cambia cuando cambias la conexión principal; la fijación por omisión de las ventanas
nuevas se activa en **Preferencias › General**.

Modo de sesión (**Preferencias › General › Modo de sesión**):

- **Multi** (por omisión): cada ventana tiene su propia sesión de base de datos, así que una consulta larga en una
  ventana no bloquea las demás y las transacciones de las ventanas son independientes;
- **Dual**: las ventanas comparten una sesión, y la compilación tiene otra aparte;
- **Single**: todo en una sola sesión.

Cada 60 segundos Pelikan comprueba si la conexión sigue viva (el intervalo se cambia en Preferencias) y reacciona si se
pierde. Opcionalmente, cierra las sesiones de las ventanas inactivas durante más tiempo del indicado, si no tienen una
transacción abierta (**Preferencias › Oracle**).

Cuando no se puede interrumpir una consulta (**Interrumpir**, ⌘.), usa **Sesión › Finalizar la sesión de la ventana
(Kill)**: Pelikan finaliza la sesión de la ventana en la base de datos desde una sesión aparte (requiere el privilegio
ALTER SYSTEM) y vuelve a conectar la ventana.

**Sesión › Consola de la conexión** abre una SQL Window asignada a la conexión (una por conexión). Su contenido se
guarda automáticamente y vuelve al abrirla de nuevo, también tras reiniciar Pelikan: un buen lugar para consultas a
mano.

## Exportar e importar definiciones

**Sesión › Conexiones › Exportar definiciones de conexión…** guarda las definiciones con sus carpetas en un archivo JSON
sin contraseñas. **Importar definiciones de conexión…** las carga en otro Mac; las contraseñas las indicarás en la
primera conexión.

**Sesión › Conexiones › Exportar conexiones con contraseñas…** guarda las definiciones junto con las contraseñas de
las bases de datos y de los túneles SSH, por ejemplo para llevar las conexiones a un Mac nuevo o leer una contraseña de
hace años y configurar otra herramienta. La exportación requiere la confirmación del propietario del Mac (Touch ID o
contraseña). Las contraseñas pueden ir **cifradas con una frase** (sin la frase no se pueden recuperar) o en **texto
plano**; en ese caso Pelikan avisa una vez más y cualquiera que tenga el archivo puede leerlas. **Importar definiciones
de conexión…** reconoce un archivo con contraseñas, pide la frase si está cifrado, guarda las contraseñas en el Llavero
y **elimina el archivo**.

## Licencias de los paquetes de Oracle

Los informes AWR, ASH y ADDM requieren el Oracle Diagnostics Pack de pago, y SQL Monitor y SQL Tuning Advisor, el Tuning
Pack. La primera vez que usas una función así, Pelikan pregunta qué licencia tiene la base de datos (*Diagnostics y
Tuning Pack*, *Solo Diagnostics Pack*, *Sin licencia*) y recuerda la respuesta en la definición de la conexión (puedes
cambiarla en la pestaña **Avanzado**). La función tampoco funciona si el parámetro de la base de datos
`CONTROL_MANAGEMENT_PACK_ACCESS` no lo permite.
