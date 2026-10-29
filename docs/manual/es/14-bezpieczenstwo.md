# Seguridad y privacidad

Este capítulo reúne en un solo lugar cómo protege Pelikan las contraseñas, los datos y las bases de datos, también
frente a errores y frente a los agentes de IA.

## Contraseñas

- Las contraseñas de bases de datos, las contraseñas SSH (túneles y destinos Pro*C) y las frases de paso de claves SSH
  se guardan **únicamente en el Llavero de macOS**: en el llavero de inicio de sesión, sin sincronización con iCloud y
  solo disponibles con el Mac desbloqueado.
- Las contraseñas **nunca** van a los archivos de Pelikan (definiciones de conexiones, ajustes, worksets),
  a los registros, al historial de comandos, a los argumentos de procesos ni a las variables de entorno.
  Los comandos con contraseñas (`CONNECT`, `ALTER USER … IDENTIFIED BY`, `CREATE DATABASE LINK`) no se guardan en el
  historial de comandos.
- La única excepción, solo a petición expresa tuya: **Exportar conexiones con contraseñas…** escribe las contraseñas
  en un archivo (cifradas con una frase o en texto plano) tras confirmar con Touch ID o la contraseña del Mac; consulta
  **Conexiones**, «Exportar e importar definiciones». El agente de IA no tiene este comando.
- Una contraseña que no se recuerda en el Llavero se mantiene solo en memoria hasta cerrar la aplicación.
- La opción **Requerir Touch ID o la contraseña del Mac antes de usar una contraseña guardada** (**Ajustes › Oracle
  › Contraseñas de conexiones**) exige confirmación una vez por conexión mientras la aplicación está en marcha, también
  cuando usa la conexión un agente de IA.
- La contraseña SSH llega al programa `ssh` a través de una canalización de un solo uso accesible solo para tu cuenta, y
  no mediante argumentos, el entorno o un archivo.
- Las contraseñas de una cartera Oracle Wallet nunca llegan a Pelikan: del inicio de sesión se encarga el cliente de
  Oracle.
- La exportación de definiciones de conexiones, la exportación de ajustes, las definiciones de trabajos, traslados
  y herramientas de usuario, los scripts utPLSQL para CI y los parámetros de inicio no contienen contraseñas.

## Protección de las bases de datos frente a errores

- El **entorno de la conexión** (desarrollo, pruebas, producción) se ve por su color en toda la interfaz.
- En una conexión de **producción**, las sentencias que modifican datos u objetos requieren confirmación.
- Una conexión de **solo lectura** bloquea, antes de enviarlo a la base de datos, todo lo que no sean consultas (también
  `SELECT … FOR UPDATE` y los bloques PL/SQL). El parámetro de inicio `readonly=` permite abrir las conexiones elegidas
  en solo lectura durante un inicio.
- Pelikan no confirma transacciones por sí mismo: AutoCommit está desactivado por omisión, y cerrar una ventana o la
  aplicación con una transacción abierta termina con una pregunta.
- La instalación de utPLSQL desde la aplicación solo funciona en conexiones de desarrollo y de pruebas.
- Las herramientas que generan scripts (comparaciones, cesta, refactorización, DDL de vistas de dualidad, ORDS) los
  abren en una SQL Window para revisarlos: no los ejecutan por sí mismas.

## Agentes de IA

Las reglas de trabajo de los agentes se describen en el capítulo *Agentes de IA*. En resumen:

- el agente conoce las conexiones solo por su nombre y entorno: no ve contraseñas, hosts, puertos, servicios ni nombres
  de usuario;
- tiene sus propias sesiones de base de datos y no ve tu transacción;
- lee en transacciones de solo lectura, con límites;
- solo hace cambios con tu autorización, en una ventana sin botón predeterminado, y el DML queda sin confirmar hasta una
  autorización aparte para el COMMIT;
- no tiene acceso a la consola SQL*Plus, a los comandos del sistema, al depurador, a los informes de los paquetes de
  Oracle ni al build remoto;
- se comunica con Pelikan solo a través de un socket accesible para tu cuenta, con un token de sesión de un solo uso;
- los datos que lee el agente llegan al proveedor del modelo de IA: para datos sensibles, usa un usuario de base de
  datos independiente para el agente con privilegios limitados y el enmascaramiento de columnas.

## Qué sale de tu Mac

Pelikan no tiene telemetría ni analítica. Solo establece conexiones de red:

- con las bases de datos y los servidores SSH que configures;
- con GitHub: una vez al día para buscar actualizaciones (y descargarlas si aceptas), y al instalar utPLSQL desde la
  aplicación (descarga de la versión oficial);
- en el navegador, cuando tú mismo abres la documentación de Oracle (F1), una búsqueda en la web o un documento con una
  dirección http(s).

Los programas de los agentes de IA (Claude Code, Codex, Grok, Antigravity) son aplicaciones independientes de sus
proveedores y se conectan a sus servidores: envían allí lo que el agente lee en Pelikan.

## Datos en el disco

Los datos de Pelikan están en el directorio `~/Library/Application Support/Pelikan`: definiciones de conexiones (sin
contraseñas), ajustes, historial de comandos, worksets e instantáneas para recuperar ventanas (pueden contener el
texto de ventanas sin guardar), historial local de archivos, informes, cestas y el registro de agentes. Los archivos con
el contenido de las ventanas y del registro se guardan con permisos de acceso solo para tu cuenta. Si tu Mac es
compartido, recuerda que una persona con acceso a tu cuenta de macOS también tiene acceso a estos datos: los protegen la
contraseña de inicio de sesión del Mac y el cifrado de disco FileVault.

## Frente a qué no protege Pelikan

- El software malicioso que se ejecuta en tu cuenta de macOS puede leer la memoria y los archivos de tus programas: esa
  es tarea del sistema (Gatekeeper, XProtect).
- Un programa de agente iniciado sin el modo estricto tiene los permisos de tu cuenta.
- Los cambios confirmados (COMMIT) y el DDL sobre tablas no se pueden deshacer: Pelikan lo dice claramente antes de
  ejecutar.
- Las funciones llamadas en las consultas pueden tener efectos secundarios (p. ej., transacciones autónomas): solo los
  limita el modelo de privilegios de la base de datos.
