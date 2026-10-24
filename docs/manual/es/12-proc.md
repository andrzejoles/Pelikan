# Pro*C: build remoto por SSH

Pelikan compila programas Pro*C en un servidor (p. ej., AIX) por SSH: obtiene los cambios del repositorio Git en la
working copy del servidor, ejecuta `make`, instala los binarios y mantiene un historial de despliegues con la posibilidad
de revertirlos.

## Destinos SSH

En **Destinos SSH** defines un servidor: host, puerto, usuario, autenticación (clave, agente SSH o contraseña),
codificación, entorno (ORACLE_HOME, LIBPATH, PATH), directorio base, directorio de copias de seguridad, rama y comando de
build. La contraseña SSH o la frase de contraseña de la clave se guarda en el Llavero, y las definiciones de destinos se
guardan sin secretos. Los destinos se marcan como UAT o PROD.

**Probar** comprueba el inicio de sesión, la versión del sistema y del servidor SSH, la disponibilidad de `make`, `git`,
`compress`/`gzip`, la rama y si la working copy está limpia, así como si se puede escribir en los directorios.

## Despliegue

El despliegue realiza, por orden: el bloqueo (un despliegue a la vez), la comprobación de la working copy (los cambios
manuales en el servidor detienen el despliegue), `git pull --ff-only`, la copia de seguridad de los binarios, `make`, la
instalación y la entrada en el historial. Pelikan nunca hace merge ni reset en el servidor. Antes de desplegar en PROD
hay que escribir el nombre del destino.

La consola muestra los pasos con su duración y resultado; los errores del compilador Pro*C (`PCC-…`) e IBM XL C
(`1506-…`) son clicables y abren el archivo en el lugar del error. **Detener** interrumpe el despliegue y siempre libera
el bloqueo. **Revertir** restaura los binarios anteriores o una copia seleccionada.
