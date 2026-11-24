# Lab 6 — Respuestas y bitácora

## Línea base (Parte B)
- Errores ORA- en las últimas 24 h: 4
- Causa: simulacros del Lab 5 (ORA-01113, ORA-01110, etc.).
## Arranque — errores desde el último arranque (Parte C)
- ORA-00800 (4 veces): ruido conocido de contenedor; Linux no deja subir la prioridad de VKTM/LGWR.
- ORA-65019 (2 veces): provocado por el propio script al intentar OPEN READ WRITE sin cerrar; es el error esperado del bloque 2, no un fallo nuevo.
## Parte D — servicio, cuenta y sesión
- common_user_prefix en la raíz: C##.
- APP_ACADEMIA es local (COMMON=NO), OPEN, default tablespace USERS, autenticación PASSWORD.
- CANCEL SQL: ORA-01013 en la aplicación, pero la transacción sigue abierta (1).
- KILL SESSION IMMEDIATE: ORA-00031, sesión terminada y fila 101 de vuelta a ACTIVO.
- SYSOPER entra como PUBLIC y no ve DBA_USERS (ORA-00942).
