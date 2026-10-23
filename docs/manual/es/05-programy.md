# Program Window y Object Browser

## Object Browser

Árbol de objetos del esquema actual (o del elegido en el filtro) con carpetas por tipo: tablas, vistas, paquetes, tipos,
disparadores, secuencias y, en 23ai, también módulos MLE y dominios. El menú contextual de un objeto abre su código
fuente, muestra su descripción, DDL, dependencias y datos, y permite compilar el objeto o eliminarlo. Los objetos no
válidos aparecen marcados.

## Program Window

La Program Window edita código PL/SQL: paquetes (especificación y cuerpo en pestañas separadas), procedimientos,
funciones, tipos y disparadores. **Ejecutar** (F8) compila el código en la base de datos, y los errores de compilación
aparecen bajo el editor: al hacer clic en uno vas a la línea. El esquema del código (Code Contents) muestra la
estructura de la unidad, e **Ir a la declaración** te lleva al lugar donde se declara un identificador.

El editor sugiere nombres de tablas, columnas, paquetes y sus elementos, pliega bloques, resalta los pares
`BEGIN`/`END`, formatea el código (**Formateador**) según tus ajustes y guarda un historial local de versiones del
archivo. Las plantillas insertan fragmentos de código ya preparados.

## Análisis de código

Mientras escribes, Pelikan subraya tablas, columnas y alias desconocidos y señala problemas: variables sin usar, código
después de `RETURN`, `UPDATE`/`DELETE` sin `WHERE`, conversiones implícitas. **Find Usages** busca los usos de un objeto
en la base de datos y en los archivos del proyecto, y **Cambiar nombre** muestra una vista previa de los cambios antes de
aplicarlos.

## Archivos y codificación

Los archivos conservan su codificación (UTF-8, ISO-8859-2, Windows-1250) y sus finales de línea. Un carácter que no se
puede guardar en la codificación del archivo bloquea el guardado e indica exactamente dónde está; la codificación solo se
puede cambiar de forma explícita (**Archivo › Codificación del archivo**).
