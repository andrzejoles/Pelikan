# Preferencias y atajos de teclado

## Ventana Preferencias

La abres con **Pelikan › Ajustes…** (⌘,). Los cambios se guardan al instante: no hay botón Aplicar. El campo **Buscar
ajustes** de la parte superior encuentra un ajuste por su nombre (en el idioma de la interfaz) y lleva a la pestaña
correspondiente.

| Pestaña | Qué ajustas |
|---|---|
| General | modo de sesión (Multi, Dual, Single), comportamiento al cerrar sesión con una transacción abierta, comprobación de la conexión, fijación de la conexión de las ventanas nuevas, colores de las conexiones y reglas `usuario@base`, apariencia (como el sistema, clara, oscura), idioma de la interfaz, directorios iniciales y extensiones de archivo adicionales, pregunta para guardar las ventanas nuevas |
| SQL Window | AutoSelect, AutoCommit, confirmación de COMMIT y ROLLBACK, AutoCommit de la Test Window, filas por página, formato de números, Auto Format en el Large Data Editor, estadísticas, DBMS_OUTPUT (activado, limpieza antes de ejecutar), formatos de DATE y TIMESTAMP |
| Editor | fuente (también ligaduras) y colores, sugerencia de código (automática tras un punto, coincidencia, mayúsculas, funciones estándar, disposición de «(todos)»), AutoReplace, recordar el estado de las ventanas, mayúsculas de las palabras clave, resaltados, estado de líneas, ajuste de líneas, caracteres especiales, sangrías y tabulaciones |
| Formateador | reglas de formato de PL/SQL y formato automático (al abrir desde la base de datos, antes de compilar, antes de guardar) |
| Teclado | perfil de atajos y atajos propios de los comandos |
| Oracle | Instant Client, ajustes NLS de la sesión, cierre de sesiones inactivas, versión de la documentación de Oracle para F1, Touch ID para las contraseñas guardadas, Oracle Net y Oracle Wallet, compilador, depurador, sugerencias del compilador y convenciones de nombres, vistas DBA_ |
| Object Browser | carpetas visibles y orden, confirmación de la recompilación, acciones al arrastrar, filtros con nombre, carpetas de usuario |
| Herramientas | búsquedas en la web, editor externo, visor de diferencias externo, documentos, copias de seguridad y recuperación de ventanas, preguntas «No volver a preguntar» |
| Agentes | programas de agentes, modo estricto, límites de llamadas y consultas del agente |
| Conjuntos | conjuntos de preferencias, exportación e importación, barra de acceso rápido |

Algunos ajustes solo surten efecto tras reiniciar Pelikan: el directorio de Instant Client, Oracle Net y Oracle Wallet,
y el idioma de la interfaz.

### Copias de seguridad y recuperación

En la pestaña **Herramientas** activas la copia de la versión anterior del archivo al guardar (`archivo.~ext`) y la
conservación de las ventanas sin guardar para recuperarlas tras un cierre inesperado (instantánea cada cierto tiempo y,
opcionalmente, también antes de cada ejecución). Tras un fallo, Pelikan propone recuperar las ventanas; también puedes
hacerlo más tarde con **Archivo › Recuperar ventanas…**.

### Preguntas «No volver a preguntar»

Algunas preguntas (p. ej., la confirmación de COMMIT o mover a la Papelera) tienen la casilla **No volver a preguntar**:
Pelikan recuerda entonces tu respuesta. La lista de respuestas recordadas y el botón **Volver a mostrar** están en la
pestaña **Herramientas**. Las confirmaciones de cambios en producción y las autorizaciones para los agentes de IA no se
pueden desactivar de este modo.

## Conjuntos de preferencias

Los conjuntos permiten tener ajustes distintos para distintas conexiones, p. ej., otro formato de fecha para una base de
datos o reglas más estrictas para producción. Pelikan aplica los conjuntos en este orden (del más importante):
**Personal de conexión**, **Personal**, **Predeterminado de conexión**, **Predeterminado** para todas las conexiones.
Los conjuntos de conexión tienen un patrón `usuario@base` o un nombre de conexión con `*` y `%` (p. ej., `app@prod*`) y
se aplican cuando la conexión principal coincide con ellos.

![Pestaña Conjuntos de Preferencias](../img/zestawy-preferencji.png)

En la pestaña **Conjuntos** (o con **Herramientas › Preferencias › Conjuntos de preferencias…**):

1. Añade un conjunto: elige el tipo, escribe el nombre y el patrón de conexiones y haz clic en **Añadir**.
2. En el campo **Guardar los cambios de Preferencias en**, elige el conjunto que quieres editar. A partir de ese
   momento, los cambios de las demás pestañas van a ese conjunto.
3. Junto a cada ajuste se ve de qué conjunto procede el valor; **Heredar** quita el valor del conjunto que se edita.

**Exportación e importación** guarda en un archivo JSON las secciones elegidas de las preferencias vigentes
(**Herramientas › Preferencias › Exportar preferencias…**) y las carga en el conjunto que se edita (**Importar
preferencias…**). La exportación no contiene contraseñas ni el historial de archivos.

## Barra de herramientas y acceso rápido

**Vista › Personalizar barra de herramientas…** cambia la disposición de la barra con la ventana estándar de macOS. El
grupo **Acceso rápido** de la barra contiene cualquier comando (hasta 20): los añades en la pestaña **Conjuntos**
(**Barra de acceso rápido**) o desde la paleta de comandos.

## Teclado

En la pestaña **Teclado** elige el perfil: **PL/SQL Developer (teclas F, Ctrl)** o **macOS (Cmd)**. Busca un comando y
graba un atajo propio: Pelikan avisa si entra en conflicto con otro atajo. **Eliminar atajos del comando**,
**Predeterminado del comando** y **Restaurar todos los valores predeterminados** deshacen los cambios. El menú muestra
un atajo por comando, pero funcionan todos sus atajos.

## Atajos más importantes

| Acción | Perfil PL/SQL Developer | Perfil macOS |
|---|---|---|
| Nueva SQL Window / Program Window | ⌘N / ⇧⌘N | ⌘N / ⇧⌘N |
| Ejecutar | F8, ⌘↩ | ⌘↩, F8 |
| Ejecutar al contrario que AutoSelect | ⌃F8, ⇧⌘↩ | ⇧⌘↩, ⌃F8 |
| Interrumpir | ⇧⎋, ⌘. | ⌘. |
| Confirmar (COMMIT) / Revertir (ROLLBACK) | F10 / ⇧F10 (también ⌥⌘↩ / ⌥⌘⌫) | ⌥⌘↩ / ⌥⌘⌫ (también F10 / ⇧F10) |
| Explain Plan | F5 | F5 |
| Iniciar sesión… | ⇧⌘L | ⇧⌘L |
| Sugerencia de código | ⌃Espacio | ⌥⎋, ⌃Espacio |
| Ir a la declaración | ⌃⌥D, ⌃⌘J | ⌃⌘J |
| Historial de comandos | ⌃E, ⇧⌘H | ⇧⌘H |
| Buscar y reemplazar / ir a la línea | ⌃F, ⌘F / ⌃G, ⌘L | ⌘F / ⌘L |
| Comentario de línea | ⌃−, ⌘/ | ⌘/ |
| Formatear código PL/SQL | ⇧⌘F | ⇧⌘F |
| Buscar en editores y archivos | ⌥⇧⌘F | ⌥⇧⌘F |
| Buscar objetos de la base de datos | ⌃⇧O, ⇧⌘O | ⇧⌘O |
| Depurador: iniciar / detener | F9 / ⇧F9 | F9 / ⇧F9 |
| Depurador: continuar, entrar, pasar por encima, salir | ⌃R, ⌃N, ⌃O, ⌃T | ⌃R, ⌃N, ⌃O, ⌃T |
| Punto de interrupción | ⌃B | ⌃B |
| utPLSQL: todas las pruebas / prueba bajo el cursor | ⌃⇧U, ⇧⌘U / ⌃⌥U, ⌃⌘U | ⇧⌘U / ⌃⌘U |
| Macro: grabar / reproducir | F11 / F12 | F11 / F12 |
| Ventana siguiente / anterior | ⌃⇥ / ⌃⇧⇥ | ⇧⌘] / ⇧⌘[ |
| Paleta de comandos | ⇧⌘P | ⇧⌘P |
| Ayuda contextual de Oracle / manual | F1 / ⇧⌘/ | F1 / ⇧⌘/ |

La lista completa de comandos con sus atajos actuales (con tus cambios incluidos) está en el último capítulo del manual,
**Atajos de teclado**. Las teclas F1–F12 funcionan como teclas de función tras activar esa opción en los Ajustes del
Sistema de macOS, o junto con la tecla fn; algunos atajos con ⌃ (p. ej., ⌃F8, ⌃F2, ⌃F3) los intercepta macOS: usa el
equivalente con ⌘ o desactiva el atajo del sistema.

## Iniciar con parámetros

Pelikan se puede iniciar con parámetros, p. ej., desde el Terminal:

```
open -a Pelikan --args connection=dev_test editobject=APP.EMP_API
```

Entre los parámetros admitidos están `connection` (nombre de la conexión o `usuario@base`), `viewobject`, `editobject`,
`commandfile`, `project`, `workset`, `readonly` (patrones de las conexiones que se abren en solo lectura en este
inicio), `noloaddesktop` y rutas de archivos. También funciona la dirección `pelikan://open?connection=…`. No se admite
una contraseña en los parámetros: `userid=u/contraseña@base` se acepta sin la contraseña y con una advertencia, y la
contraseña procede del Llavero o de una pregunta.

Cualquier página web o mensaje puede abrir una dirección `pelikan://`, por eso solo acepta abrir (conexión, objeto,
archivo, workset, proyecto, `readonly`); Pelikan nunca ejecuta un script `commandfile` desde esa dirección.
