# Agentes de IA

Pelikan ofrece herramientas a los agentes de IA que se ejecutan en el terminal (Claude Code, Codex, Grok, Antigravity) a
través de un servidor MCP accesible solo para la sesión correspondiente. El agente trabaja en el **Panel del agente**,
junto a las ventanas.

## Reglas de seguridad

- El agente ve las conexiones solo por su nombre (alias), nunca contraseñas, direcciones ni nombres de usuario.
- El agente tiene **su propia sesión de base de datos** (marcada en V$SESSION), opcionalmente a través de un usuario
  proxy con privilegios limitados. Ejecuta las consultas en una transacción de solo lectura, con límites de filas y de
  tiempo.
- Los cambios (DML, DDL, compilación) requieren **tu consentimiento** en una ventana de consentimiento con la vista
  previa de la sentencia y de los objetos afectados. El DML queda sin confirmar hasta que aceptes el COMMIT.
- En las conexiones de producción el agente solo tiene acceso de lectura. El agente no tiene acceso a la Command
  Window, a los comandos del sistema operativo, al depurador ni a los informes AWR/ASH.
- Las columnas indicadas se pueden enmascarar en los resultados destinados al agente.
- **Deshacer sesión de agente** devuelve los objetos modificados por el agente a su estado anterior a los cambios (con
  detección de conflictos).

Los privilegios, la lista de programas y el registro de actividad están en **Preferencias › Agentes**.
