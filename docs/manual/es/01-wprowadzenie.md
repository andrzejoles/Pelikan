# Introducción

Pelikan es un entorno nativo de macOS para trabajar con bases de datos Oracle: escribir y ejecutar SQL, desarrollar y
probar código PL/SQL, explorar objetos de la base de datos, depurar, ejecutar pruebas utPLSQL y usar herramientas de
administración. La disposición y los atajos siguen a PL/SQL Developer, así que los usuarios de ese programa encontrarán
ventanas conocidas: **SQL Window**, **Command Window**, **Program Window**, **Test Window** y **Object Browser**.

## Primeros pasos

1. Instala Oracle Instant Client (Basic o Basic Light) e indica su directorio en **Preferencias › Oracle**. Pelikan
   también detecta el directorio `instantclient_*` más reciente en Descargas. Sin Instant Client funciona el
   controlador *Thin*, con menos funciones.
2. Añade una definición de conexión: **Sesión › Conexiones › Conexión nueva…** o el botón de la lista de conexiones.
3. Conéctate y abre una **SQL Window** (⌘N). Escribe una consulta y ejecútala (F8 o ⌘↩).

## Ventana principal

A la izquierda hay un panel con pestañas: Object Browser, explorador de archivos, lista de ventanas, plantillas, To-Do y
proyecto. En el centro están las pestañas de documentos: cada ventana SQL, de programa o de prueba tiene su propia
pestaña. La barra de estado muestra la conexión de la ventana, el estado de la transacción, la posición del cursor, la
codificación del archivo y la rama de Git.

Cualquier acción se puede invocar desde el menú, con un atajo o desde la **paleta de comandos** (⇧⌘P), que busca
comandos por nombre.

## Idiomas

La interfaz está disponible en polaco, inglés, alemán, español y ucraniano. El idioma se elige en
**Preferencias › General › Idioma de la interfaz**; el cambio se aplica tras reiniciar la aplicación.
