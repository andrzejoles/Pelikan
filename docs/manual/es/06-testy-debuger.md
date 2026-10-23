# Test Window, depurador y utPLSQL

## Test Window

La Test Window ejecuta un bloque PL/SQL con variables de enlace cuyos valores introduces en la tabla bajo el bloque.
Tras la ejecución, la tabla muestra los valores de salida, y las pestañas, DBMS_OUTPUT, las estadísticas y el perfil de
ejecución. Las pruebas se guardan en archivos `.tst`.

## Depurador

**Iniciar depuración** ejecuta la prueba paso a paso: **Entrar** (entrar en un subprograma), **Pasar por encima** (línea siguiente),
**Salir** (volver del subprograma), puntos de interrupción (también condicionales), consulta y modificación de los
valores de las variables y pila de llamadas. El depurador requiere los privilegios `DEBUG CONNECT SESSION` y
`DEBUG ANY PROCEDURE` (o `DEBUG` sobre el objeto).

## Profiler

El profiler (DBMS_PROFILER o DBMS_HPROF) mide el tiempo de ejecución de cada línea y subprograma, y las estadísticas de
sesión muestran cómo cambian los contadores durante la prueba.

## utPLSQL

El explorador de pruebas muestra los paquetes de pruebas utPLSQL de la base de datos. Puedes ejecutar las pruebas de un
paquete, de una suite o de todo el esquema; los resultados, con tiempos y mensajes de error, aparecen en el árbol, y la
cobertura de código, en el editor. El generador crea el esqueleto de un paquete de pruebas para el paquete seleccionado.
Pelikan también puede instalar utPLSQL en un esquema (previa confirmación).
