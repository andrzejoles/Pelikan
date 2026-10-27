# Introducción y primer inicio

Pelikan es un entorno nativo de macOS para trabajar con bases de datos Oracle: escribir y ejecutar SQL, crear, probar y
depurar código PL/SQL, explorar y editar objetos de la base de datos, pruebas utPLSQL y herramientas de comparación,
exportación y administración. La disposición de las ventanas y los atajos de teclado siguen a PL/SQL Developer, así que
sus usuarios encontrarán ventanas conocidas: **SQL Window**, **Command Window**, **Program Window**, **Test Window**,
**Explain Plan Window** y **Object Browser** (pestaña **Objetos**).

Este manual describe cómo realizar las tareas habituales. La lista completa de comandos con sus atajos actuales está en
el último capítulo, **Atajos de teclado**, que genera la propia aplicación.

## Requisitos

- Un Mac con procesador Apple (M1 o posterior) y macOS 27 o posterior.
- Oracle Instant Client para macOS (ARM64): el paquete Basic o Basic Light. Pelikan no lo incluye (la licencia de Oracle
  no lo permite), así que lo descargas tú mismo del sitio web de Oracle. Sin Instant Client funciona el controlador
  *Thin*, con limitaciones (consulta más abajo).
- Una base de datos Oracle. Pelikan se desarrolla y prueba en Oracle Database 26ai Free; las consultas del diccionario
  de datos tienen variantes para las versiones 19c, 21c y 23ai. En versiones anteriores algunas carpetas y funciones
  pueden no estar disponibles.

## Instalación

1. Descarga la versión más reciente desde la página del proyecto:
   [github.com/andrzejoles/Pelikan/releases](https://github.com/andrzejoles/Pelikan/releases), un archivo `.dmg` o un
   instalador `.pkg`.
2. Desde la imagen `.dmg`, arrastra **Pelikan** al acceso directo **Aplicaciones (Applications)**. El instalador `.pkg`
   lo hace solo.
3. Abre Pelikan desde la carpeta Aplicaciones.

### Advertencia de Gatekeeper en el primer inicio

Pelikan está firmado con un certificado propio del autor («Pelikan Self-Signed»), pero no está notarizado por Apple
(para ello haría falta una cuenta de desarrollador de pago). Por eso, en el primer inicio macOS bloquea la aplicación y
muestra una advertencia. Para abrirla:

1. Cierra la ventana de advertencia.
2. Abre **Ajustes del Sistema › Privacidad y seguridad**, desplázate hasta la sección **Seguridad** y haz clic en
   **Abrir igualmente** junto al mensaje sobre Pelikan.
3. Confirma con tu contraseña o con Touch ID.

Solo tienes que hacerlo una vez. La firma estable hace además que, tras una actualización, macOS no vuelva a preguntar
por el acceso de Pelikan a las contraseñas del Llavero.

## Oracle Instant Client

Descarga «Instant Client for macOS (ARM64)», paquete **Basic** o **Basic Light**, de
[oracle.com](https://www.oracle.com/database/technologies/instant-client/macos-arm64-downloads.html) e instálalo según
las instrucciones de Oracle. Pelikan busca la biblioteca `libclntsh.dylib` en este orden:

1. el directorio indicado en **Preferencias › Oracle › Oracle Instant Client**;
2. `/opt/homebrew/lib`, `/usr/local/lib`, `/usr/local/oracle/instantclient` y los directorios
   `/opt/oracle/instantclient*`;
3. los directorios `instantclient_*` de tus carpetas **Descargas** y **Aplicaciones** (primero la versión más reciente).

Al buscar en la carpeta Descargas, macOS puede preguntar si permites que Pelikan acceda a ella; es una pregunta normal
de privacidad del sistema. Si prefieres evitarla, indica el directorio del cliente manualmente: **Pelikan › Ajustes…**
(⌘,), pestaña **Oracle**, botón **Elegir…**. El cambio de directorio surte efecto tras reiniciar Pelikan.

Sin Instant Client puedes conectarte con el controlador *Thin* (se elige en la definición de la conexión; consulta el
capítulo *Conexiones*). Thin no admite conexiones TCPS ni Oracle Wallet, autenticación externa, cambio de una contraseña
caducada ni interrupción de la ejecución (**Interrumpir**).

## Primeros pasos

1. Haz clic en la pestaña **Conexiones** de la columna izquierda y luego en el botón **+** (o elige **Sesión ›
   Conexiones › Conexión nueva…**).
2. Escribe el nombre, el usuario, la contraseña y la base de datos (`host:puerto/servicio` o un alias de
   `tnsnames.ora`), elige el entorno y haz clic en **Probar** y después en **Guardar**.
3. Haz doble clic en la conexión de la lista: se convierte en la **conexión principal** (en negrita).
4. Abre una SQL Window nueva (**Archivo › Nuevo › SQL Window**, ⌘N), escribe una consulta y ejecútala con F8 o ⌘↩.

![Ventana principal: lista de conexiones a la izquierda, SQL Window con el resultado de una consulta](../img/okno-glowne.png)

## Ventana principal

Pelikan tiene una única ventana principal:

- **Columna izquierda** con las pestañas **Conexiones** (lista de conexiones con carpetas y las usadas recientemente),
  **Objetos** (Object Browser), **Ventanas** (lista de ventanas abiertas), **Templates** y **Archivos** (explorador de
  archivos).
- **Pestañas de documentos** en el centro: cada ventana SQL, de programa, de prueba o de plan tiene su propia pestaña
  con una letra de tipo en color: S — SQL Window, P — Program Window, T — Test Window, C — Command Window, E — Explain
  Plan Window, R — Report Window, D — ventana de diagrama, N — cuaderno SQL. Un clic central en una pestaña cierra la
  ventana; el menú de la pestaña cierra las demás ventanas o las ventanas a la izquierda y a la derecha.
- **Barra de herramientas** con las acciones más frecuentes (ventana nueva, abrir, guardar, ejecutar, interrumpir,
  COMMIT, ROLLBACK, iniciar sesión) y el grupo **Acceso rápido**. Cambias la disposición con **Vista › Personalizar
  barra de herramientas…**.
- **Barra de estado** de la ventana: la conexión de la ventana (con el color del entorno, la fijación 📌 y la marca «solo
  lectura»), el estado de la transacción («● transacción abierta»), el número de filas y el tiempo de ejecución, la
  posición del cursor y la rama Git del archivo. Al hacer clic en el nombre de la conexión puedes cambiar la conexión de
  la ventana.
- **Paneles de herramientas** a la derecha y abajo: las herramientas (Sesiones, Buscar objetos de la base de datos,
  Tareas To-Do, Historial del portapapeles, este manual, editores de tablas, exportación e importación, informes y
  otras) se abren por omisión en el panel derecho, cada una en su propia pestaña. Arrastra una pestaña al otro panel o
  fuera de los paneles: la herramienta pasa entonces a una ventana independiente donde la sueltes; lo mismo hacen el
  menú de la pestaña y los botones de la cabecera del panel. Una ventana de herramienta vuelve a un panel con el botón
  de su barra de título. Pelikan recuerda la ubicación de cada tipo de herramienta. Un panel contraído con herramientas
  muestra en la barra de estado un botón con su número. Los comandos están en **Vista › Paneles de herramientas**; en
  **Preferencias › General › Paneles de herramientas** eliges dónde se abren las herramientas nuevas (también en
  ventanas independientes) y la ocultación automática. Los atajos de una herramienta acoplada (Retorno, Esc) solo
  funcionan mientras el cursor está en esa herramienta.
- **Panel del agente** a la derecha (contraído por omisión): el terminal del agente de IA con la lista de sus acciones.
  Se muestra con **Vista › Panel del agente** (consulta el capítulo *Agentes de IA*).

El título de la ventana muestra la conexión principal y el conjunto de trabajo (workset) activo, y el subtítulo, la
ventana actual.

## Cinta y «Buscar acciones»

Bajo la barra de herramientas está la **cinta**: cada acción con un clic, sin buscar en menús ni recordar atajos. Las
pestañas fijas son **Iniciar** (ventanas nuevas, archivos, ejecución, COMMIT y ROLLBACK, conexión, búsqueda),
**Edición**, **Objetos**, **Depuración y pruebas**, **Herramientas**, **Informes** y **Vista**. Con una ventana de
programa, resultado, diagrama, informe, cuaderno, plan o comandos aparece una **pestaña contextual** de color (p. ej.
**Programa** con compilación, unidades, comparación con el origen en la base de datos y pruebas). La cinta recuerda qué
pestaña eligió para cada tipo de ventana y vuelve a ella al cambiar de ventana.

Las acciones frecuentes tienen botones grandes y las demás pequeños; las menos usadas están en las listas desplegables
de los grupos (marcadas con ▾). La descripción emergente de un botón muestra su descripción y atajo, así aprende los
atajos sobre la marcha. Clic derecho en un botón añade el comando al acceso rápido. Doble clic en una pestaña o la
flecha de la derecha contrae la cinta a sus pestañas; **Vista › Cinta** la oculta (también en **Preferencias › General ›
Cinta**).

El campo **Buscar acciones…** a la derecha de las pestañas encuentra cualquier comando: escriba unas letras, «plan»,
«eksport tabel», una palabra sin diacríticos polacos o un nombre en inglés conocido de PL/SQL Developer, p. ej.
«beautifier», «compile invalid». Los resultados muestran dónde está el comando en la cinta, su atajo y si está
disponible ahora; Intro o un clic lo ejecuta.

## Paleta de comandos

Cada acción de Pelikan es un comando: tiene una entrada de menú, un atajo opcional y una descripción de sus efectos. La
**paleta de comandos** (**Vista › Paleta de comandos…**, ⇧⌘P) busca comandos por nombre y muestra en qué menú están y
qué atajo tienen. Es la forma más rápida de encontrar una función cuya ubicación en el menú no recuerdas.

## Perfiles de teclado

Pelikan tiene dos perfiles de atajos: **PL/SQL Developer** (teclas F y Ctrl; p. ej., F8 ejecuta y F9 inicia la
depuración) y **macOS** (atajos con ⌘). En ambos perfiles funcionan los equivalentes con ⌘; p. ej., ⌘↩ ejecuta una
sentencia. El perfil se elige en **Preferencias › Teclado**. Si las teclas F1–F12 controlan el brillo o el volumen,
activa en Ajustes del Sistema la opción de usarlas como teclas de función estándar o púlsalas junto con la tecla fn.

## Actualizaciones

Una vez al día Pelikan comprueba si hay una versión nueva y propone instalarla. También puedes comprobarlo manualmente:
**Pelikan › Buscar actualizaciones…**. Cada versión está firmada con la clave del autor: la aplicación no acepta un
archivo de otra procedencia. Los ajustes, las conexiones y las contraseñas no cambian.

## Idiomas

La interfaz está disponible en polaco, inglés, alemán, español y ucraniano. El idioma se elige en **Preferencias ›
General › Idioma de la interfaz**; el cambio surte efecto tras reiniciar. Los nombres de algunas ventanas y herramientas
(p. ej., Explain Plan, Large Data Editor, Query Builder) se mantienen en su forma original.

## Dónde guarda Pelikan sus datos

Las definiciones de conexiones (sin contraseñas), las preferencias, el historial, los worksets, el historial local de
archivos, el registro de agentes y otros datos de la aplicación están en el directorio `~/Library/Application
Support/Pelikan`. Las contraseñas están únicamente en el Llavero de macOS; consulta el capítulo *Seguridad y
privacidad*.

## Ayuda

- **Ayuda › Ayuda de Pelikan** (⇧⌘/) abre este manual.
- **F1** en el editor abre la documentación de Oracle de la palabra bajo el cursor (código de error, paquete, vista del
  diccionario, sentencia SQL).
- **Ayuda › Documentación de Oracle…** busca en los manuales de Oracle de la versión elegida.

## Acerca de

Pelikan es un proyecto abierto con licencia MIT:
[github.com/andrzejoles/Pelikan](https://github.com/andrzejoles/Pelikan). Autor: Andrzej Oleś w kooperacji z Claude AI.
Las licencias de las bibliotecas utilizadas están en el archivo «Licencje zewnętrzne» (licencias de terceros) que
acompaña a la aplicación.
