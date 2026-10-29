# Pruebas utPLSQL

Pelikan incorpora compatibilidad con utPLSQL, la biblioteca de pruebas unitarias para PL/SQL: ejecución de pruebas con
resultados en directo, cobertura de código, generación de esqueletos de pruebas y navegación entre un paquete y sus
pruebas. Los comandos están en el menú **Herramientas › utPLSQL**.

## Instalar utPLSQL en la base de datos

**Herramientas › utPLSQL › utPLSQL: versión en la base de datos** comprueba si utPLSQL está instalado y en qué versión.

Si no lo está, **utPLSQL: instalar o actualizar…** descarga la versión oficial de GitHub, comprueba su suma de
verificación y ejecuta los scripts de instalación en una consola SQL*Plus visible. Este comando solo funciona en
conexiones de desarrollo y de pruebas, y siempre pide confirmación. El nuevo propietario de utPLSQL recibe una
contraseña aleatoria que nadie conoce, y su cuenta se bloquea de inmediato. En las bases de datos compartidas, la
instalación suele hacerla un administrador.

## Escribir pruebas

- **utPLSQL: generar paquete de pruebas**: cuando el cursor está en un paquete (o el paquete está seleccionado en el
  Object Browser), abre una Program Window con el esqueleto de un paquete de pruebas: una suite y una prueba por cada
  procedimiento y función, con `ut.fail` para completar. El esqueleto se compila y se ejecuta de inmediato.
- La ventana de plantillas tiene una carpeta **utPLSQL** con plantillas de paquete de pruebas, prueba, excepción
  esperada, contexto, expectativas y comparación de cursores.
- La sugerencia de código conoce las anotaciones (tras `--%`) y los matchers (tras `ut.expect(…).`).
- Al compilar la especificación de un paquete de pruebas, Pelikan avisa de anotaciones desconocidas, de procedimientos
  indicados en `--%beforeall`, `--%aftereach`, etc., que no existen en la especificación, de `--%test` sin `--%suite` y
  de `--%context`/`--%endcontext` sin pareja.
- **utPLSQL: ir a la prueba / al paquete probado** (⌃⌘T) alterna entre un paquete y su paquete de pruebas (según el
  nombre `test_nombre` o las dependencias).

## Ejecutar pruebas

| Comando | Atajo (macOS) | Qué ejecuta |
|---|---|---|
| utPLSQL: ejecutar todas las pruebas | ⇧⌘U | todas las pruebas del usuario actual |
| utPLSQL: ejecutar la prueba bajo el cursor | ⌃⌘U | el procedimiento de prueba bajo el cursor o todo el paquete de pruebas |
| utPLSQL: ejecutar pruebas de la ruta… | — | rutas `esquema.paquete.procedimiento` o `esquema:ruta.de.suite`, varias separadas por comas |
| utPLSQL: ejecutar con opciones… | — | rutas, cobertura, esquemas de cobertura, objetos incluidos y excluidos |
| utPLSQL: volver a ejecutar las fallidas | — | las pruebas que no pasaron en la última ejecución |
| utPLSQL: interrumpir | — | la ejecución en curso |

En el perfil PL/SQL Developer los atajos son ⌃⇧U (todas), ⌃⌥U (bajo el cursor) y ⌃⇧T (ir a la prueba). Las pruebas del
paquete, procedimiento o usuario seleccionado también se ejecutan con **Herramientas › Objeto › Ejecutar pruebas
utPLSQL**.

## Explorador de pruebas

**Vista › Explorador de pruebas utPLSQL** muestra el árbol de suites, contextos y pruebas del usuario actual con el
resultado de la última ejecución. El árbol se actualiza tras compilar; un doble clic en una prueba abre su anotación en
la especificación. Ejecutas las pruebas seleccionadas con el botón **Ejecutar** o **Ejecutar con cobertura**.

## Ventana de resultados

Los resultados aparecen en directo: barra de progreso, contadores y nombre de la prueba actual. Las pruebas se ejecutan
en sesiones aparte, así que las ventanas de Pelikan siguen disponibles.

- Árbol de suites, contextos y pruebas con tiempos y estados: **Correcto**, **Fallos**, **Errores**, **Desactivado**.
  **Mostrar:** filtra por estado, **Ordenar:** cambia el orden (orden de ejecución, nombre, tiempo, estado).
- Detalles de la prueba: el mensaje de la expectativa, **Esperado** y **Obtenido** uno junto a otro con las diferencias
  resaltadas (también filas de cursores), **Pila de errores** con salto a la línea, el DBMS_OUTPUT de la prueba y
  **Abrir código fuente de la prueba**.
- El menú de la prueba permite volver a ejecutar una sola prueba, y **Fallidos de nuevo**, todas las fallidas.
- **Historial** guarda las 20 últimas ejecuciones; **Cambios** muestra qué pruebas cambiaron de estado respecto a la
  ejecución anterior.

## Cobertura de código

**utPLSQL: pruebas con cobertura de código** (o **Ejecutar con cobertura**) recoge la cobertura del esquema actual; en
la ventana **ejecutar con opciones…** indicas otros esquemas y los objetos incluidos y excluidos.

- En la Program Window las líneas se marcan en el margen: verde, cubiertas; amarillo, parcialmente; rojo, sin cubrir.
- La barra de estado muestra el porcentaje de cobertura del objeto y del esquema.
- **Informe de cobertura** abre el informe HTML de utPLSQL en el navegador.

La cobertura usa los datos del profiler: antes de la primera ejecución de este tipo en una sesión, Pelikan recuerda los
privilegios necesarios.

## Depurar una prueba

**Depuración › utPLSQL: depurar la prueba bajo el cursor** abre una Test Window con una llamada `ut.run` para esa
prueba, establece un punto de interrupción en el procedimiento de prueba e inicia el depurador (consulta el capítulo
*Test Window, depurador y profiler*).

## Resultados para CI

- **utPLSQL: exportar resultados…** ejecuta las pruebas con el reporter JUnit, Sonar, TeamCity o TAP (o con un informe
  de cobertura Cobertura, Sonar o HTML) y guarda el resultado en un archivo.
- **utPLSQL: script para la línea de comandos** crea un script de SQL*Plus/SQLcl que ejecuta las mismas pruebas con
  resultado JUnit, y un script de shell. Los scripts no contienen la contraseña: la indicas en la CI desde tu propio
  almacén de secretos.
