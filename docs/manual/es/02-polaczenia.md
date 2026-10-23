# Conexiones y seguridad de las contraseñas

## Definición de conexión

Una conexión tiene nombre, carpeta, usuario, base de datos (EZConnect `host:port/usługa`, `tcps://…` o un alias de
`tnsnames.ora`), rol (Normal, SYSDBA…), opcionalmente un usuario proxy, una edición (EBR) y un entorno: desarrollo,
pruebas o producción. Las conexiones de producción tienen un color de advertencia y en ellas las sentencias que
modifican datos requieren confirmación.

Una conexión puede ser de **solo lectura**: en ese caso Pelikan rechaza DML, DDL y PL/SQL antes de que lleguen a la
base de datos.

## Contraseñas

Las contraseñas se guardan exclusivamente en el **Llavero** de macOS (inicio de sesión, sin sincronización con iCloud)
y nunca acaban en archivos, registros ni argumentos de procesos. La contraseña se guarda solo tras una conexión correcta
y únicamente si marcas **Recordar la contraseña en el Llavero**.

En **Preferencias › Oracle** puedes activar
**Requerir Touch ID o la contraseña del Mac antes de usar una contraseña guardada**: Pelikan te pedirá entonces la verificación una vez
por conexión mientras la aplicación esté en ejecución.

## Oracle Wallet

Pelikan admite dos tipos de cartera:

- **almacén de contraseñas** (Secure External Password Store): inicio de sesión con `/@alias` sin escribir la
  contraseña; el directorio de la cartera se indica en **Preferencias › Oracle › Oracle Net y Oracle Wallet**, y en la
  conexión se elige la autenticación *Oracle Wallet*. El campo «Base de datos» debe ser exactamente el alias guardado
  en la cartera;
- **cartera TLS** (p. ej., Autonomous Database): el directorio de la cartera se indica en la definición de conexión; el
  archivo ZIP descargado del portal se descomprime con el botón **Importar ZIP…**.

## Otros métodos de autenticación

- **Externa** (Kerberos, sistema operativo).
- **Microsoft Entra ID**: Instant Client 23 abre el navegador para iniciar sesión y entrega el token a la base de datos
  por sí mismo; Pelikan no ve ni guarda el token.
- **Token OAuth2 desde archivo**: un token preparado previamente con una herramienta externa.
- **Túnel SSH**: conexión a través de un servidor intermedio (clave o agente SSH).

## Licencias de los packs de Oracle

Los informes AWR, ASH, ADDM, SQL Monitor y SQL Tuning Advisor requieren los packs de pago Oracle Diagnostics/Tuning
Pack. La primera vez que los usas, Pelikan pregunta si la base de datos tiene licencia y guarda la respuesta en la
definición de conexión.
