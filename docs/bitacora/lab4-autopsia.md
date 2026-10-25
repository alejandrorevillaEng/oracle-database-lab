# Autopsia de la instancia — Lab 4

- **Instancia:** `FREE` (23.26.3.0.0), CDB con `FREEPDB1`.
- **Fecha de la ejecución:** 2026-10-25, 17:15 UTC.
- **Ejecutado como:** `C##OPS_RO`, usuario común de solo lectura (`SELECT_CATALOG_ROLE` y `SELECT` puntual sobre `V_$DIAG_ALERT_EXT`).
- **Script:** `scripts/lab4/15-autopsia-instancia.sql`.
- **Evidencia:** `docs/bitacora/lab4/evidencia/spool/20261025T171508Z_15-autopsia-instancia.spool.log`.

## Resumen para dirección

La base está sana y sobrada de espacio: ningún tablespace pasa del 3 % y el alert log no contiene errores reales, solo avisos del contenedor y pruebas del propio laboratorio. El riesgo no es la capacidad sino la redundancia: los control files y los redo viven en el mismo volumen, y los archivados no tienen FRA. Antes de producción hay que configurar FRA, multiplexar control files y redo, persistir el diagnóstico y recoger estadísticas de los cuatro esquemas vacíos.

## Hallazgos

| # | Sección | Hallazgo | Evidencia | Riesgo | Acción | Prioridad |
|---|---|---|---|---|---|---|
| 1 | §1, §4 | **ARCHIVELOG sin FRA.** Los archivados van al destino por defecto, en el mismo volumen que los datafiles. | `log_mode=ARCHIVELOG`; `db_recovery_file_dest` vacío; `db_recovery_file_dest_size=0`; 5 archivados (628 MB) en `/opt/oracle/oradata/dbconfig/FREE/dbs` | Sin política de retención ni borrado automático; si el volumen se llena, la base se detiene | Configurar FRA con tamaño y retención (Lab 5) | Media |
| 2 | §4 | **Un solo juego de control files y de redo.** | `control01.ctl` y `control02.ctl` (17,9 MB cada uno) en `/opt/oracle/oradata/FREE/`; 3 grupos de redo de 200 MB con **1 miembro** cada uno | Punto único de fallo: perder ese volumen deja la base sin control files ni redo | Multiplexar control files y miembros de redo en volúmenes distintos (Lab 5) | Alta |
| 3 | §4 | **ADR fuera del volumen.** | `diagnostic_dest=/opt/oracle`; `/opt/oracle/diag` no está en el volumen `oralab-26ai-data` | Se pierden el alert log y las trazas al recrear el contenedor | `diagnostic_dest` persistente o centralización de logs | Media |
| 4 | §6 | **Cuatro esquemas de negocio sin estadísticas.** | `ADMIN_CLINICA` (3 tablas, 8 índices), `ADMIN_FINTECH` (2, 6), `ADMIN_LOGISTICA` (3, 6) y `ADMIN_RETAIL` (3, 7): 0 filas y todos los `LAST_ANALYZED` nulos | El optimizador irá a ciegas cuando se carguen esos esquemas | `DBMS_STATS.GATHER_SCHEMA_STATS` después de la carga | Media |
| 5 | §6 | **Dos índices con factor de agrupamiento pegado al número de filas.** | `ADMIN_ACADEMIA.IDX_ACA_MAT_EST`: 60 000 / 60 000 (100 %); `UQ_ACA_MATRICULA_UNICA`: 59 011 / 60 000 (98,4 %) | Un rango por esos índices lee casi un bloque por fila: el índice no ahorra E/S | Revisar el orden de carga y el diseño en el Lab 5 | Baja |
| 6 | §10 | **Seis errores ORA en 24 h, todos explicables.** | 4 × `ORA-00800` (prioridad de `VKTM`/`LGWR` al arrancar), 1 × `ORA-65025` (`DROP` de `PDB_LAB4` aún abierta, Parte I) y 1 × `ORA-959` (`DROP TABLESPACE IF EXISTS`, Parte L) | Ninguno: son ruido del contenedor o pruebas del laboratorio | Documentar y excluir de las alertas; no borrar del log | Baja |

## Lo que está sano

**§1 Identidad.** Instancia `FREE`, host `947e1f1ca7d8`, versión 23.26.3.0.0, arrancada el 2026-10-25 a las 16:49 (0,02 días arriba), `OPEN`/`ACTIVE`. Base `FREE`, DBID 1509902213, CDB, `ARCHIVELOG`, `READ WRITE`, `FORCE_LOGGING=YES`, `FLASHBACK=NO`, `PRIMARY`. Contenedores: `CDB$ROOT` 0 MB, `PDB$SEED` 810 MB, `FREEPDB1` 1472 MB.

**§2 Memoria.** SGA de 1529 MB: buffer cache 1024, shared pool 464, free 16, large pool 16, fixed 5 y redo 4. PGA: objetivo 512 MB, asignada 422 MB, máxima 499 MB. Los 16 MB libres de SGA indican que ASMM está en su objetivo, sin presión.

**§3 Procesos.** 86 de segundo plano y 5 servidores de sesión (91 en total). Están los obligatorios y los esperables: `ARC0 ARC1 CKPT DBRM DBW0 LGWR LREG MMNL MMON PMON PSP0 RECO SMON VKTM`.

**§4 Archivos.** 16 datafiles (4054 MB), 3 tempfiles (60 MB), 2 control files (36 MB), 3 miembros de redo (600 MB) y 5 archivados (628 MB). Los datafiles de negocio están dentro de `/opt/oracle/oradata/FREE/FREEPDB1/`; control files y redo, en `/opt/oracle/oradata/FREE/`; el SPFILE, en `$ORACLE_HOME/dbs` (enlace al volumen).

**§5 Almacenamiento.** `TBS_ACADEMIA` 23 MB de 1024 (2,3 %); `TBS_CLINICA`, `TBS_FINTECH`, `TBS_LOGISTICA` y `TBS_RETAIL`, 6 MB de 1024 (0,6 %). En la raíz, `SYSTEM` 1066 MB y `SYSAUX` 644 MB (0,1 % de su máximo). Ningún tablespace supera el umbral de aviso del 85 %. En `FREEPDB1`, los segmentos mayores son los LOB (382 segmentos, 200 MB), los índices (848, 167 MB) y las tablas (643, 153 MB).

**§6 Índices.** `ADMIN_ACADEMIA` 9 índices (7 únicos, altura 2, 0 no válidos); `ADMIN_CLINICA` 8 (6 únicos); `ADMIN_FINTECH` 6 (3); `ADMIN_LOGISTICA` 6 (5); `ADMIN_RETAIL` 7 (4). Solo `ADMIN_ACADEMIA` tiene estadísticas; los otros cuatro esquemas están vacíos y sin analizar.

**§7 Seguridad.** En la raíz, 37 usuarios comunes (1 propio, `C##OPS_RO`); en `FREEPDB1`, 9 usuarios locales (todos de la casa) y 35 comunes (1 propio). Ninguna cuenta no mantenida por Oracle tiene el rol `DBA`. Las cuentas `ADMIN_*` no tienen contraseña (lo comprueba la verificación final).

**§8 Red.** Servicios anunciados: `free`, `freeXDB` y `freepdb1` (además de `SYS$BACKGROUND` y `SYS$USERS`). El contenedor solo publica el puerto 1521.

**§9 Configuración.** 19 parámetros no están en su valor por defecto y todos tienen justificación: `db_create_file_dest=/opt/oracle/oradata`, `sga_target=1536 MB`, `pga_aggregate_target=512 MB`, `processes=200`, `open_cursors=300`, `enable_pluggable_database=TRUE`, `dispatchers`, `diagnostic_dest`, etc. `common_user_prefix` conserva el valor por defecto `C##`, que es el correcto.

**§10 Salud.** 6 mensajes con `ORA-` en 24 h: los 4 `ORA-00800` son el fallo conocido de prioridad de `VKTM`/`LGWR` al arrancar en el contenedor; el `ORA-65025` lo provocó el `DROP PLUGGABLE DATABASE pdb_lab4` antes de cerrarla (Parte I) y se resolvió con `CLOSE IMMEDIATE`; el `ORA-959` es el `DROP TABLESPACE IF EXISTS tbs_lab4` del banco de pruebas (Parte L) cuando el tablespace ya no existía. Los tres códigos son esperados; el `DBA` debe mirar siempre el primer `ORA-` de cada bloque, no las líneas de pila (`ORA-06512`).

## Plan de acción

1. **Lab 5, alta prioridad:** multiplexar los control files y añadir un miembro por grupo de redo en un volumen distinto.
2. **Lab 5, prioridad media:** configurar FRA con tamaño y política de retención, y mover el `diagnostic_dest` a una ruta persistente.
3. **Antes de cargar los esquemas de negocio:** `DBMS_STATS.GATHER_SCHEMA_STATS` para `ADMIN_CLINICA`, `ADMIN_FINTECH`, `ADMIN_LOGISTICA` y `ADMIN_RETAIL`.
4. **Lab 5, prioridad baja:** revisar `IDX_ACA_MAT_EST` y `UQ_ACA_MATRICULA_UNICA`; si los rangos son habituales, un índice organizado por la clave de la consulta o un cambio en el orden de carga puede bajar el factor de agrupamiento.

No hay ninguna acción urgente: no hay tablespaces por encima del 85 %, la copia del Lab 3 está íntegra y la verificación final del laboratorio pasa con 0 fallos.

## Cómo reproducirlo

```bash
bash scripts/ops/ro.sh scripts/lab4/15-autopsia-instancia.sql
bash scripts/lab4/16-verificacion-final.sh
```

El primer comando es de solo lectura y se puede lanzar en producción en cualquier momento. El segundo es la prueba de aceptación del Lab 4: devuelve 0 si todo está en orden.
