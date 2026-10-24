# Pro*C: build remoto por SSH

Pelikan permite editar programas Pro*C localmente y compilarlos en un servidor (p. ej., AIX) por SSH, con un flujo
basado en Git: los cambios llegan al servidor mediante `git pull` en la copia de trabajo (working copy) del servidor, y
Pelikan ejecuta allí `make`, instala los binarios y lleva un historial de despliegues con posibilidad de revertirlos.
Pelikan nunca envía el código fuente al servidor directamente, no hace `merge` ni `reset` en el servidor y no ejecuta
`git push`.

Los comandos están en el menú **Herramientas › Build remoto de Pro*C**.

## Destinos SSH

**Herramientas › Build remoto de Pro*C › Destinos SSH…** abre el gestor de destinos: los servidores en los que
despliegas. Puedes agrupar los destinos en carpetas, duplicarlos y eliminarlos. El formulario del destino:

- **Conexión**: nombre, carpeta, entorno **UAT** o **PROD** (con color), host, puerto, usuario y autenticación:
  **Archivo de clave** (opcionalmente con la frase de paso de la clave), **Agente SSH** o **Contraseña SSH**. La
  contraseña SSH y la frase de paso de la clave se guardan en el Llavero (**Recordar en el Llavero**); con la protección
  Touch ID activada (**Preferencias › Oracle › Contraseñas de conexiones**), Pelikan confirma su uso una vez por
  destino. **Algoritmos antiguos (AIX 6.1 y servidores más antiguos)** activa algoritmos SSH compatibles con servidores
  antiguos. **Codificación de nombres** y **Codificación de la consola** (UTF-8 o ISO-8859-2) determinan cómo codifica
  Pelikan los nombres de archivo y cómo lee la salida.
- **Directorios en el servidor**: directorio base, directorio de copias de seguridad, working copy y subdirectorios de
  código fuente y binarios.
- **Git y build**: rama, remoto, comando de build (p. ej., `make`) y lista de binarios (separados por comas).
- **Entorno del shell**: ruta de `ksh`, `ORACLE_HOME`, `LIBPATH`, `PATH` y variables adicionales (`NOMBRE=valor`): un
  shell no interactivo no lee `.profile`, así que aquí indicas lo que necesita el build.

Las definiciones de destinos se guardan sin secretos; **Exportar destinos SSH…** e **Importar destinos SSH…** las
trasladan entre ordenadores. En el servidor no hace falta ninguna contraseña de Oracle: Pro*C debe estar configurado en
el servidor.

### Probar un destino

**Probar** (en el gestor o **Herramientas › Build remoto de Pro*C › Probar destino SSH**) comprueba: la versión del
servidor SSH, el inicio de sesión, el sistema (`uname -a`, en AIX `oslevel -s`), la disponibilidad de `make`, `git` y
`compress`/`gzip`, la rama y la limpieza de la working copy (`git status --porcelain`) y la posibilidad de escribir en
los directorios. Si falta el directorio de copias de seguridad, Pelikan lo crea tras tu confirmación.

## Despliegue

1. Abre un proyecto con un repositorio Git local (Pelikan lo compara con el servidor). Sin proyecto, el despliegue
   funciona, pero sin información sobre los commits locales.
2. Elige **Herramientas › Build remoto de Pro*C › Desplegar en destino…** y un destino. La ventana muestra un
   **Resumen**: el commit del servidor y del remoto, los commits que se desplegarán, `git diff --stat` y advertencias,
   p. ej., commits locales sin enviar o el despliegue en PROD de un commit que no estuvo en UAT.
3. En un destino **PROD** debes escribir el nombre del destino para confirmar el despliegue.
4. Haz clic en **Desplegar**.

En el servidor, Pelikan realiza por orden:

1. establece un **bloqueo** (en un destino solo puede haber un despliegue a la vez);
2. comprueba la rama y la limpieza de la working copy: los cambios manuales en el servidor detienen el despliegue antes
   de `pull`;
3. `git pull --ff-only`;
4. una copia de seguridad de los binarios (con la fecha y el commit en el nombre, comprimida con `compress` o `gzip`,
   con un límite de copias);
5. `make` (el comando de build);
6. la instalación de los binarios nuevos (la versión anterior se conserva como `.prev`);
7. una entrada en el historial de despliegues en el servidor y en Pelikan.

## Consola de despliegue

La **Consola de despliegue** muestra los pasos con su tiempo y resultado, y la salida en directo. Los errores del
compilador Pro*C (`PCC-…`, también `PLS-…`) y del compilador IBM XL C (`1506-…`) son clicables: abren el archivo del
repositorio local en la línea del error. La opción **Solo errores y advertencias** filtra la salida, y **Guardar
registro…** la guarda en un archivo.

**Herramientas › Build remoto de Pro*C › Detener despliegue** (o **Detener** en la consola) interrumpe el build en el
servidor (también los procesos iniciados por `make`) y siempre libera su propio bloqueo. Un bloqueo abandonado de otro
despliegue se libera manualmente con **Liberar bloqueo del destino…**, solo cuando estés seguro de que nadie está
desplegando en ese momento (en PROD, tras escribir el nombre del destino).

## Reversión e historial

- **Revertir binario…** intercambia el binario actual por la versión anterior (`.prev`) o restaura la copia de seguridad
  elegida (descomprimida, con los permisos del binario actual).
- **Historial de despliegues** muestra los despliegues hechos desde Pelikan (con el registro completo) y el historial
  guardado en el servidor.
- **Estado de git y de los despliegues** reúne: la rama local y los commits sin enviar, el estado del remoto, el último
  despliegue del historial y el commit (HEAD) de cada servidor. **git fetch y actualizar** obtiene el estado del remoto
  sin preguntas en el terminal.

## Codificación de archivos

El código fuente en los servidores antiguos suele estar en ISO-8859-2. Pelikan detecta la codificación de los archivos
existentes y no la cambia sin avisar: un carácter que no se puede guardar en la codificación del archivo bloquea el
guardado e indica exactamente el lugar. La codificación solo se cambia de forma explícita (**Archivo › Codificación del
archivo…**); un proyecto también puede imponer la codificación de sus archivos.
