# Lab 4 — Respuestas

## Parte A — Respaldo y diagnóstico

### A.3 — Notas de mi entorno
- Copia en frío `lab3-final`: 564 MB, `archivos_fuera_del_volumen=0`, SHA-256 verificado (todo OK).
- Mi base está en **ARCHIVELOG** (en el entorno del guion salía NOARCHIVELOG). No afecta a la copia:
  es consistente porque se tomó tras `SHUTDOWN IMMEDIATE`, no por el modo de archivado.

### P1 — Copia tras SHUTDOWN IMMEDIATE
**Respuesta: A y D.**
Tras SHUTDOWN IMMEDIATE se hace un checkpoint final: todos los datafiles comparten el mismo SCN
y la copia es consistente. Se restaura y se abre con STARTUP sin aplicar redo.
B es falsa: una copia en frío no exige ARCHIVELOG. C es falsa: IMMEDIATE hace rollback de lo no
confirmado y la copia es consistente. E es falsa: es una copia del sistema operativo y no necesita RMAN.

### A.4 — Punto de control
- Archivos FUERA del volumen: **0**.
- Los cinco datafiles de negocio (`academia01`, `clinica01`, `fintech01`, `logistica01`, `retail01`)
  están en `$ORACLE_HOME/dbs` porque V000 los creó con **ruta relativa** (`'academia01.dbf'`) y
  `db_create_file_dest` está vacío (sin OMF). Sin ruta absoluta ni OMF, Oracle usa `$ORACLE_HOME/dbs`.
- En mi imagen (oficial) `$ORACLE_HOME/dbs` es un **enlace simbólico** al volumen
  (`/opt/oracle/oradata/dbconfig/FREE/dbs`), así que sobreviven a `docker rm`.
  Aun así están en una carpeta no estándar y dependen de un enlace que una actualización de la imagen
  puede cambiar, así que la corrección de la Parte C sigue siendo necesaria.

### A.4 — Informe de diagnóstico
1. **Alto**: contraseñas de los cinco propietarios en V000, en el historial de Git para siempre → V003 (Parte D).
2. **Alto**: `08-aplicar-migraciones.sh` pasa `sys/<contraseña>` por la línea de comandos (visible con `ps` y en el historial) → 08 v2 (Parte D).
3. **Medio**: datafiles en `$ORACLE_HOME/dbs` por ruta relativa y sin OMF; en mi entorno sobreviven gracias a un enlace, pero en carpeta no estándar → Parte C.
4. **Bajo**: puerto 8181 publicado sin servicio (ORDS escucha en 8080, en Linux) → 05 v2 (Parte C). **Bajo**: incoherencias del documento del Lab 3 (V000/V001, nombre de variable).
Orden: primero las credenciales, porque ya están expuestas y cualquiera con acceso al repo las puede usar; después los datafiles, que en mi entorno no se pierden; y por último el puerto y los documentos, que no comprometen datos.

## Parte B — Cuenta de observabilidad

### B.2 — Comprobación del ejecutor
- `bash scripts/ops/ro.sh /tmp/quien.sql` → `C##OPS_RO` en `CDB$ROOT`.
- `bash scripts/ops/ro.sh /tmp/quien.sql FREEPDB1` → `C##OPS_RO` en `FREEPDB1`.
- `CREATE TABLE prueba_ro (x NUMBER);` en `FREEPDB1` → `ORA-01031: insufficient privileges`. La cuenta lee, pero no escribe.

### Reto — Mínimo privilegio
Dar el rol `DBA` a `C##OPS_RO` tendría dos riesgos concretos:
- **Puede escribir y romper el entorno:** `DBA` incluye privilegios de escritura y administración; un error en un script ejecutado con `ro.sh` podría modificar o borrar objetos, cambiar parámetros o parar la instancia. La cuenta dejaría de ser de solo lectura.
- **Demasiado alcance sobre los datos:** incluye privilegios `ANY` (por ejemplo `SELECT ANY TABLE`), así que podría leer datos de negocio de cualquier esquema y de todas las PDB. Si se filtra la credencial, el daño es mucho mayor.

Para leer el alert log no hace falta nada de eso: solo el privilegio sobre la vista, que se concede en la Parte J:

```sql
GRANT SELECT ON sys.v_$diag_alert_ext TO c##ops_ro CONTAINER = ALL;
```

`CONTAINER = ALL` porque es un usuario común y debe valer en `CDB$ROOT` y en `FREEPDB1`.

## Parte C — Reubicar los datafiles y persistencia

### P2 — Mover un datafile en Standard Edition
**Respuesta: B.** `ALTER TABLESPACE ... OFFLINE` hace checkpoint y cierra el tablespace; se copia el archivo con el sistema operativo, `RENAME DATAFILE` actualiza la ruta del control file y `ONLINE` valida la cabecera del archivo nuevo.
- A es falsa: `ALTER DATABASE MOVE DATAFILE` es de Enterprise Edition (`ORA-00439`).
- C es falsa: `RENAME DATAFILE` no copia nada y exige el tablespace OFFLINE.
- D es innecesaria y arriesgada: `SHUTDOWN ABORT` deja la instancia sin cierre limpio y puede necesitar recuperación.

### Reto — Que no vuelva a pasar
```sql
ALTER SYSTEM SET db_create_file_dest='/opt/oracle/oradata' SCOPE=BOTH;
```
- **SCOPE=BOTH:** el cambio se aplica en caliente y queda guardado en el SPFILE, así que sobrevive a un reinicio.
- **Qué cambia:** el siguiente `CREATE TABLESPACE tbs_x;` **sin cláusula DATAFILE** deja de crear el archivo en `$ORACLE_HOME/dbs`. Con OMF, Oracle genera el nombre y lo crea dentro de `/opt/oracle/oradata`, que es el volumen. El archivo ya no depende de una ruta relativa ni de la capa del contenedor.
- **Matiz:** OMF solo actúa cuando se omite `DATAFILE`. Si alguien escribe una ruta relativa explícita, se seguirá resolviendo contra `$ORACLE_HOME/dbs`. La medida evita el descuido habitual, no impide una ruta relativa a propósito.
- **Comprobado:** `db_create_file_dest` vale `/opt/oracle/oradata` tanto en `CDB$ROOT` como en `FREEPDB1` (evidencia `03-omf`).

## Parte D — Migraciones V003 y V002

### P-D1 — Propietario de esquema sin login
**Respuesta: C.** `ALTER USER app_owner NO AUTHENTICATION;` convierte la cuenta en *schema-only*: no tiene contraseña ni ninguna forma de iniciar sesión, y su `ACCOUNT_STATUS` puede seguir `OPEN` porque la cuenta existe para poseer objetos.
- A (`ACCOUNT LOCK`) conserva la contraseña y se puede desbloquear.
- B (`PASSWORD EXPIRE`) solo obliga a cambiarla; sigue habiendo contraseña.
- D (`REVOKE CREATE SESSION`) impide entrar, pero la credencial sigue existiendo y el privilegio se podría volver a conceder.

### Comprobaciones
- Las cinco cuentas `ADMIN_*` quedan con `AUTHENTICATION_TYPE = NONE`.
- Un intento de login como `admin_academia` con cualquier contraseña devuelve `ORA-01017: invalid credential or not authorized; logon denied`.
- V002 deja `20000` estudiantes, `40` asignaturas y `60000` matrículas; la fila `101` es `ACTIVO`.
- V002 ejecutada por segunda vez responde `V002 ya aplicada (20000 estudiantes): no se inserta nada`.

## Parte E — Instancia, arranque por etapas y alert log

### P3 — Instancia frente a base de datos
**Respuesta: A y C.**
- A correcta: `STARTUP_TIME` cambia cada vez que se arranca la instancia.
- C correcta: `CREATED` es la fecha en que se creó la base, no la del arranque.
- B falsa: el `DBID` identifica la base y no cambia al recrear el contenedor.
- D falsa: una instancia monta y abre una sola base a la vez.
- E falsa: `v$database` también responde en MOUNT. En NOMOUNT da `ORA-01507` porque aún no se ha leído el control file.

### P4 — Qué se puede hacer en NOMOUNT
**Respuesta: A y C.**
- A: `v$parameter` responde porque los parámetros ya están en la SGA.
- C: `CREATE CONTROLFILE` se ejecuta en NOMOUNT.
- B: `dba_users` necesita el diccionario, que está en SYSTEM y exige OPEN.
- D: pasar a ARCHIVELOG exige MOUNT.
- E: renombrar el datafile de SYSTEM exige MOUNT.

### P5 — Etapa para ARCHIVELOG
**Respuesta: B. MOUNT.**

### Reto — El parte del reinicio
- **Parada pedida:** 2026-10-25 16:49:41 UTC (18:49:41 local).
- **Instancia apagada:** 16:49:52 UTC. Tardó **10,2 s**.
- **Arranque:** 16:49:52 UTC. MOUNT completado a las 16:49:56; redo abierto a las 16:49:57; `ALTER DATABASE OPEN` completado (con FREEPDB1) a las **16:50:03 UTC**.
- **Tiempo hasta OPEN:** **11,4 s** desde el arranque y **21,8 s** desde que se pidió la parada.
- **Recuperación:** el log muestra `Crash Recovery excluding pdb 2 which was cleanly closed` y lo mismo para `pdb 3`. SMON hizo crash recovery del CDB raíz y excluyó las PDB porque estaban cerradas limpiamente. Fue automática, sin intervención, y abrió en la secuencia 6. Aunque el apagado fue IMMEDIATE y terminó con `Instance shutdown complete`, esta imagen registra ese `Crash Recovery` en el OPEN.
- **Errores:** dos `ORA-00800: soft external error [Set Priority Failed]` (VKTM y LGWR). Son **conocidos**: el contenedor no permite elevar la prioridad de esos procesos (falta `CAP_SYS_NICE`) y la base funciona igual. También aparecen avisos `Time stalled` / `backward drift` por el reloj del contenedor, que no son errores de la base. **Nada a investigar** en este reinicio.
- **Diferencia con el guion:** mi base está en **ARCHIVELOG** (en el guion sale NOARCHIVELOG). FREEPDB1 abrió sola por el `SAVE STATE`; `dba_pdb_saved_states` la muestra en `OPEN`.

## Parte F — Parámetros: alcance, estáticos y PFILE versionado

### P6 — `ALTER SYSTEM SET open_cursors = 500;` con SPFILE
**Respuesta: B.** Si la instancia arrancó con SPFILE, el SCOPE por defecto es **BOTH**: el cambio entra en memoria al instante y se escribe en el SPFILE, así que sobrevive al reinicio.
- A sería correcto solo con `SCOPE=MEMORY` o si la instancia hubiera arrancado con PFILE (entonces el alcance por defecto es MEMORY).
- C no existe como comportamiento: `SCOPE=SPFILE` no toca la memoria.
- D es falsa: `SCOPE` es opcional.

### P7 — `PROCESSES` desde FREEPDB1
**Respuesta: C.** Devuelve `ORA-65040: Operation is not allowed from within a pluggable database` porque `PROCESSES` es un parámetro de instancia (`ISPDB_MODIFIABLE = FALSE`) y solo se cambia desde `CDB$ROOT`.
- A y B describen un cambio que nunca llega a producirse.
- D es falsa: el error de staticidad (`ORA-02095`) aparecería en el CDB, no en la PDB; la PDB ni siquiera deja intentarlo.

### P8 — Recuperar una instancia que no arranca por el SPFILE
**Respuesta: A y C.**
- A: `STARTUP PFILE='/ruta/init_bueno.ora'` arranca con la copia legible, sin leer el SPFILE roto.
- C: ya arrancada, `CREATE SPFILE FROM PFILE='/ruta/init_bueno.ora'` reescribe el SPFILE con los valores buenos.
- B no sirve: si la instancia no arranca, no hay memoria que resetear.
- D es para resetear el redo, no la configuración.
- E solo apaga; no repara nada.

### Reto — Petición de cambio: `open_cursors` a 1000
**Título:** subir `OPEN_CURSORS` de 300 a 1000 por `ORA-01000` en la aplicación.

- **Valor actual y de dónde sale:** `300`. Está fijado explícitamente en el SPFILE (`v$spparameter.value = 300`, `ISDEFAULT = FALSE`), no es un valor derivado ni el de fábrica.
- **Síntoma:** la aplicación recibe `ORA-01000: maximum open cursors exceeded`. En el fondo suele haber cursores que no se cierran (falta de `CLOSE` en el código); subir el límite da margen, no cura.
- **Valor propuesto:** `1000`.
- **SCOPE:** `BOTH`. `OPEN_CURSORS` es dinámico (`ISSYS_MODIFIABLE = IMMEDIATE`, `ISPDB_MODIFIABLE = TRUE`) y el cambio debe sobrevivir al reinicio, así que se aplica ya y se guarda en el SPFILE. Además, al ser modificable por PDB, se decide si se sube solo en `FREEPDB1` (donde corre la aplicación) o en el CDB. Propongo hacerlo en la PDB para no ampliar el límite de todo el contenedor.
- **Comando:** `ALTER SESSION SET CONTAINER = FREEPDB1;` y luego `ALTER SYSTEM SET open_cursors = 1000 SCOPE = BOTH COMMENT = 'CR-2026-042: ORA-01000 en la app' ;`
- **Cómo se prueba:** antes del cambio, medir el consumo real con `SELECT COUNT(*) FROM v$open_cursor WHERE sid = <sid>;` y el máximo histórico por sesión; después, repetir la carga que provocaba el error y comprobar que no aparece `ORA-01000`. Verificar el valor efectivo en `v$parameter` y el pendiente en `v$spparameter`. La prueba se hace primero con `SCOPE=MEMORY` en una ventana de bajo uso y se confirma con la carga.
- **Rollback:** `ALTER SYSTEM SET open_cursors = 300 SCOPE = BOTH COMMENT = '';` en la PDB. Si el problema aparece tras un reinicio, `ALTER SYSTEM RESET open_cursors SCOPE = SPFILE;` deja que herede el valor del CDB. Antes de tocar el SPFILE se guarda un `CREATE PFILE` para poder arrancar con la copia buena.
- **Evidencia que se archiva:** el PFILE anterior y el posterior en `docs/bitacora/lab4/evidencia/config/`, el spool con el valor antes/después, el ticket de cambio con aprobación y la medición de cursores abiertos antes y después de la carga.
- **Recomendación adicional:** abrir un ticket con desarrollo para localizar los cursores que no se cierran. `OPEN_CURSORS` alto consume memoria por sesión y solo retrasa el fallo si la fuga sigue.

### Comprobaciones de la Parte F
- La instancia arrancó con SPFILE (`spfileFREE.ora`).
- `v$parameter` documenta **564** parámetros; **19** no están en su valor por defecto y **134** son estáticos.
- El SPFILE solo contiene **33** líneas efectivas: el resto son valores por defecto o derivados (por ejemplo, `sessions=322` sale de `processes=200`).
- `db_files` en `SCOPE=MEMORY` da `ORA-02095`; en `SCOPE=SPFILE` queda pendiente (200 en memoria, 300 en SPFILE) y `RESET` borra la línea.
- `processes` en memoria da `ORA-02095` y `memory_size` da `ORA-62352`.
- Desde `FREEPDB1`, `processes` da `ORA-65040`; `open_cursors` sí se puede fijar en la PDB (350) y al resetearlo vuelve a heredar 300 del CDB.
- Todo quedó deshecho: `open_cursors = 300` en memoria y SPFILE, `db_files` sin especificar.
- PFILE versionados: `initFREE_lab4.ora` (33 líneas) e `initFREE_lab4_memoria.ora` (123 líneas). Los parámetros que están en memoria pero no en el SPFILE son 12: `connection_brokers`, `core_dump_dest`, `job_queue_processes`, `lockfree_reservation`, `log_buffer`, `optimizer_mode`, `parallel_min_servers`, `plsql_warnings`, `query_rewrite_enabled`, `result_cache_max_size`, `result_cache_max_temp_result` y `result_cache_max_temp_size`.

## Parte G — Memoria: SGA, Buffer Cache, análisis y PGA

### P9 — ASMM con `DB_CACHE_SIZE` fijado
**Respuesta: B.** Con `MEMORY_TARGET = 0`, la gestión es **ASMM** (`SGA_TARGET`): Oracle reparte la SGA entre buffer cache, shared pool, large pool, etc. `DB_CACHE_SIZE = 512M` fija un **mínimo** para el buffer cache, no un valor exacto: ASMM puede subirlo si le sobra memoria en otros componentes.
- A es falsa: 512 MB es el suelo, no el tamaño permanente.
- C describe AMM, que necesita `MEMORY_TARGET > 0`.
- D es falsa: `DB_CACHE_SIZE` sigue contando como mínimo dentro de `SGA_TARGET`.

### P10 — Qué hay en la PGA de un servidor dedicado
**Respuesta: A y D.**
- A: el área de ordenación (sort area) de un `ORDER BY` o un `GROUP BY`.
- D: la memoria de sesión (session memory) del proceso servidor dedicado.
- B, C y E (shared pool, log buffer y buffer cache) están en la **SGA**, no en la PGA.

### P-G1 — Miles de cursores casi idénticos
**Respuesta: B.** La solución definitiva es modificar la aplicación para que use **variables de enlace**: un solo texto, un cursor compartido y un único análisis.
- A solo retrasa el problema y consume memoria.
- C vacía la shared pool y provoca más análisis duros.
- D (`CURSOR_SHARING = FORCE`) es un parche global que oculta el defecto y puede empeorar los planes.

### P-G2 — `LAST_EXECUTION = '6 PASSES'`
**Respuesta: B.** El área de trabajo no cabía en la PGA: Oracle escribió tramos ordenados en **TEMP** y tuvo que releerlos seis veces (multi-pass).
- A confunde pasadas con ejecuciones: la ordenación se ejecutó una vez.
- C y D no tienen relación con las pasadas de una work area.

### Reto — Encontrar a los culpables
Consulta guardada en `scripts/lab4/08-reto-literales.sql`; agrupa `V$SQL` por `force_matching_signature` y filtra las firmas con más de 50 cursores. Ejecutada justo después del experimento, devuelve:

| FIRMA | CURSORES | EJECUCIONES | EJEMPLO |
|---|---:|---:|---|
| 1.8632E+18 | 1000 | 1000 | `SELECT /* lab4_literal */ COUNT(*) FROM admin_academia.aca_estudiantes WHERE estudiante_id = ...` |

Es exactamente la firma de las 1000 consultas con literal: misma sentencia salvo el valor del `WHERE`. La de `lab4_bind` no aparece porque solo tiene un cursor. En una base real, esta consulta se lanza cuando la CPU de análisis se dispara y señala qué módulo de la aplicación hay que corregir.

### Comprobaciones de la Parte G
- **Modelo de memoria:** `memory_target = 0`, `sga_target = 1536M`, `pga_aggregate_target = 512M` y `pga_aggregate_limit = 2G` → ASMM.
- **SGA:** 1529,1 MB en total; buffer cache 1024 MB, shared pool 464 MB, large pool 16 MB, shared IO pool 80 MB. `v$sgainfo` cuenta el Shared IO Pool dentro del buffer cache (1024 frente a los 944 MB del componente ASMM).
- **Asesor de SGA:** todas las filas dan el mismo tiempo y las mismas lecturas físicas (18 591) porque la base está ociosa; no sirve para decidir.
- **PGA:** objetivo 512 MB, en uso 307,9 MB, asignada 408,3 MB, máximo 472,3 MB, `over allocation count = 0` y acierto del 100 %. El máximo supera el objetivo sin error: el objetivo no es un límite.
- **Buffer cache:** la tabla `ACA_ESTUDIANTES` ocupa 244 bloques (245 contando la cabecera del segmento). En frío: 359 lecturas lógicas y 262 físicas; en caliente: 247 lógicas y **0** físicas. Tasa de acierto de la ronda 2: **100 %**. Las 262 físicas superan los 244 bloques porque incluyen la cabecera del segmento y bloques de undo para la lectura consistente; por eso la ronda 1 también tiene más lógicas que la 2.
- **Parse:** 1000 literales → 1000 análisis duros, 830 ms de CPU de análisis y 940 ms totales; con `:id` → 1 análisis, 0 ms de CPU y 10 ms totales (unas 94 veces más rápido). En `V$SQL`: 1000 cursores y 38 845 KB frente a 1 cursor y 39 KB. Aquí no hubo `aged out`: los 1000 cupieron en los 464 MB de shared pool.
- **PGA y TEMP:** con PGA automática, la ordenación de 60 000 filas fue `OPTIMAL` (2 604 KB estimados, 2 314 usados, 0 KB en TEMP, 40 ms). Con `workarea_size_policy = MANUAL` y `sort_area_size = 65536`, usó 65 KB, escribió 2 048 KB en TEMP y necesitó **6 pasadas** (350 ms): casi 9 veces más lenta.
- **Histograma de la instancia:** 4 279 ejecuciones óptimas, 0 de una pasada y 2 de varias pasadas; las de varias pasadas son las del experimento manual. Cualquier valor distinto de cero en producción es una alarma.
- El `ALTER SYSTEM FLUSH BUFFER_CACHE` bajó el acierto de caché de la instancia al 88,3 %: es el precio de vaciar la caché en caliente y la razón por la que no se hace en producción.

## Parte H — Procesos de background y procesos servidor

### P11 — Qué proceso espera el COMMIT
**Respuesta: C. LGWR.** El COMMIT no devuelve el control hasta que LGWR ha escrito el redo de la transacción en los redo logs online (write-ahead logging). DBWn escribe los bloques de datos mucho después; CKPT solo actualiza cabeceras y control file; ARCn archiva redo ya cerrado; SMON recupera la instancia.
- A es el error clásico: DBWn **no** escribe en cada COMMIT.

### P12 — Procesos obligatorios
**Respuesta: B y D.** PMON y SMON son obligatorios en cualquier instancia.
- A: ARCn solo existe en ARCHIVELOG (aquí sí hay 4, pero no es obligatorio).
- C: RECO solo aparece si hay transacciones distribuidas que resolver.
- E: CJQ0 es el coordinador de jobs y se puede desactivar.

### Reto — La sesión que más consume
Consulta larga lanzada como SYSDBA en `FREEPDB1`:

```sql
SELECT /* reto_h */ COUNT(*)
  FROM admin_academia.aca_matriculas a, admin_academia.aca_matriculas b
 WHERE a.matricula_id < 3000;
```

Mientras corría, desde otra sesión:

```sql
SELECT s.sid, s.serial#, s.username, s.status, p.spid,
       ROUND(p.pga_used_mem / 1048576, 1) AS pga_usada_mb,
       ROUND(p.pga_alloc_mem / 1048576, 1) AS pga_asignada_mb,
       s.sql_id, s.event
  FROM v$session s JOIN v$process p ON p.addr = s.paddr
 WHERE s.sql_id = (SELECT MAX(sql_id) FROM v$sql WHERE sql_text LIKE '%/* reto_h */%')
   AND s.status = 'ACTIVE';
```

Resultado:

| SID | SERIAL# | USUARIO | SPID (Linux) | PGA usada | PGA asignada | SQL_ID | EVENT |
|---:|---:|---|---:|---:|---:|---|---|
| 65 | 20309 | SYS | 2235 | 3,3 MB | 3,7 MB | 95f633c1g3dbs | db file sequential read |

- La consulta terminó en **6,48 s** y devolvió **179 940 000** filas contadas.
- Mientras corría acumulaba 258 lecturas lógicas y 254 físicas; el evento `db file sequential read` confirma que estaba esperando lecturas de disco, no CPU.
- Los tres valores (SID, SPID y PGA) son el punto de partida de cualquier diagnóstico: con el SID se puede mirar la sesión, con el SPID se localiza el proceso en Linux y con la PGA se sabe cuánta memoria privada está usando.

### Comprobaciones de la Parte H
- La instancia tiene **87 procesos Oracle** de background pero solo **54 procesos Linux**: varios son hilos dentro del mismo proceso (por ejemplo, los de SCMN).
- Están los obligatorios y los habituales: PMON (916), LREG (980), SMON (970), DBW0 (962), LGWR (964), CKPT (968), MMON (988), MMNL (990), RECO (977), ARC0-3 (1067-1073), VKTM, PMAN, PSP0, MMAN, CLMN, DIA0, DIAG y CJQ0.
- Hay **4 archivadores** porque la base está en ARCHIVELOG (en el guion, NOARCHIVELOG, saldría 0).
- Mi sesión de `C##OPS_RO` era la SID 65, SPID 1956, atendida por un proceso servidor dedicado.
- Desde Linux, el SPID de LGWR es **964** y su proceso es `db_lgwr_FREE`, con 98 MB de RSS. Coincide exactamente con el `SPID` de `v$process`: se lee desde dentro del contenedor, no con `docker top` (que da el PID del anfitrión).
- El RSS de cada proceso de background (80-200 MB) es en su mayoría la SGA compartida repetida: sumarlo daría más de 5 GB en un contenedor de 2 GB. La memoria real se mide con `v$sga` y `v$pgastat`.

## Parte I — Contenedores: qué ve cada usuario

### P13 — `V$DATAFILE` dentro de FREEPDB1
**Respuesta: B.** Dentro de una PDB, las vistas `V$` se filtran por el contenedor actual: solo devuelve la fila de `CON_ID 3` (los 9 datafiles de FREEPDB1).
- A sería cierto solo desde la raíz con un usuario con `CONTAINER_DATA`.
- C no aplica: `CON_ID 0` es para datos de toda la instancia (redo, procesos), no para datafiles.
- D es falsa: la vista existe en todos los contenedores.

### P14 — Ver todas las PDB desde la raíz
**Respuesta: B.** `ALTER USER c##audit SET CONTAINER_DATA = ALL CONTAINER = CURRENT;` es lo que hace que las vistas `CDB_` y `V$` muestren las filas de todos los contenedores al consultar desde la raíz.
- A da privilegio de lectura del diccionario, pero las filas se siguen filtrando sin `CONTAINER_DATA`.
- C (`SET CONTAINER`) solo permite cambiar de contenedor; no amplía lo que se ve desde la raíz.
- D abre las PDB, pero no cambia la visibilidad del usuario.

### P15 — `GRANT READ ANY TABLE ON SCHEMA hr TO analista`
**Respuesta: A y D.**
- A: el privilegio de esquema cubre las tablas actuales **y las futuras** de HR.
- D: no permite leer tablas de otros esquemas (el experimento lo confirmó con `ADMIN_CLINICA`: `ORA-00942`).
- B es falso: es solo el esquema HR, no toda la PDB.
- C es falso: es lectura; el `UPDATE` dio `ORA-41900`.
- E es falso: `lab4_analista` era un usuario **local** y funcionó.

### Reto — Acceso de una auditora externa a `ADMIN_CLINICA`
Diseño (no ejecutado):

```sql
-- En FREEPDB1, como SYSDBA
CREATE USER lab4_auditora IDENTIFIED BY "<aleatoria>" PASSWORD EXPIRE;
GRANT CREATE SESSION TO lab4_auditora;
GRANT READ ANY TABLE ON SCHEMA admin_clinica TO lab4_auditora;
```

- **¿Común o local? ¿En qué contenedor?** **Local**, creada dentro de `FREEPDB1`. Solo necesita esa PDB; un usuario común existiría en todos los contenedores y exigiría prefijo `C##`, más superficie de la necesaria. En I.2 se vio que un usuario local sin privilegios no ve nada y que el privilegio de esquema le abre exactamente un esquema.
- **GRANT mínimo:** `CREATE SESSION` para entrar y `READ ANY TABLE ON SCHEMA admin_clinica` para leer todas las tablas de ese esquema, presentes y futuras. Nada de `SELECT ANY TABLE` (abriría todos los esquemas de la PDB), nada de `DBA` y ningún privilegio de escritura: el intento de `UPDATE` en I.2 devolvió `ORA-41900`.
- **Contraseña:** aleatoria, entregada por canal seguro y con `PASSWORD EXPIRE` para que la cambie en el primer acceso. No se guarda en el repositorio.
- **Sin cuotas ni tablespace por defecto:** no va a crear objetos.
- **Revocación el último día:**
  ```sql
  REVOKE READ ANY TABLE ON SCHEMA admin_clinica FROM lab4_auditora;
  DROP USER lab4_auditora CASCADE;
  ```
  El `REVOKE` deja constancia inmediata de que ya no puede leer; el `DROP` elimina la cuenta y sus objetos. Si solo se quisiera suspender el acceso sin borrar la cuenta: `ALTER USER lab4_auditora ACCOUNT LOCK;`.
- **Justificación:** es el mismo patrón que funcionó en I.2 con `ADMIN_ACADEMIA`. El privilegio de esquema limita el alcance al esquema nombrado, y el `ORA-00942` de `ADMIN_CLINICA` en el experimento demuestra que los demás esquemas siguen cerrados.

### Comprobaciones de la Parte I
- **SYS en la raíz:** ve 4 datafiles de `CDB$ROOT`, 3 de `PDB$SEED` y 9 de `FREEPDB1`; `V$LOG` devuelve 3 filas con `CON_ID 0` (el redo es de toda la instancia).
- **SYS en FREEPDB1:** solo los 9 datafiles de la PDB y 10 tablespaces; `CDB_TABLESPACES` devuelve únicamente las 10 de la PDB (dentro de una PDB, `CDB_` se comporta como `DBA_`).
- **Usuario local sin privilegios:** `USER_TABLES = 0`, `ALL_TABLES` de `ADMIN_ACADEMIA = 0`, y `ORA-00942` al consultar `DBA_TABLES`, `V$SESSION` o `ADMIN_ACADEMIA.ACA_ESTUDIANTES`. `ALTER SESSION SET CONTAINER = CDB$ROOT` da `ORA-01031`.
- **Tras `GRANT READ ANY TABLE ON SCHEMA admin_academia`:** ve las 3 tablas del esquema y lee las 20 000 filas; `ADMIN_CLINICA` sigue en `ORA-00942` y el `UPDATE` da `ORA-41900`.
- **Usuario común sin `CONTAINER_DATA`:** desde la raíz solo ve 5 tablespaces (los de `CDB$ROOT`) y sesiones de `CON_ID 0` y 1; con `SET CONTAINER` a FREEPDB1 ve sus 10 tablespaces. `C##OPS_RO` sí tiene `CONTAINER_DATA = ALL`.
- **Diccionario:** 656 vistas `USER_`, 590 `ALL_`, 1309 `DBA_`, 1307 `CDB_`, 921 `V$` y 880 `GV$`; 1591 tablas `X$` frente a 1803 vistas fijas. `DBA_TABLESPACES` = 5 y `CDB_TABLESPACES` = 15 (5 de la raíz + 10 de FREEPDB1, sin la semilla).
- **Ciclo de vida:** `CREATE PLUGGABLE DATABASE` creó `PDB_LAB4` en `MOUNTED`, `OPEN` la abrió, sus 3 datafiles quedaron en `/opt/oracle/oradata/FREE/PDB_LAB4`, el servicio `pdb_lab4` se registró y el `DROP` sin cerrar dio `ORA-65025`. Tras `CLOSE IMMEDIATE` y `DROP ... INCLUDING DATAFILES`, la carpeta vacía se eliminó y quedaron solo `PDB$SEED` y `FREEPDB1`.
- **Errores de usuarios:** `CREATE USER lab4_local` en la raíz dio `ORA-65096` (falta el prefijo `C##`), `c##lab4_comun` desde la PDB dio `ORA-65094`, y el usuario local en la PDB se creó correctamente. Los usuarios de prueba se borraron: `USUARIOS_LAB4_RESTANTES = 0`.

## Parte J — Autopsia de los archivos

### P16 — Qué archivos son la base de datos
**Respuesta: B y D.** Forman la base de datos los **control files** y los **online redo logs** (junto con los datafiles y tempfiles).
- A, C y E (password file, SPFILE y alert log) son archivos relacionados: imprescindibles para operar, pero no son la base.

### P17 — Pérdida del disco en NOARCHIVELOG
**Respuesta: C.** Si se pierde el único disco con datafiles, control files y redo, no hay redo archivado con el que recuperar: solo se puede restaurar la última copia completa y se pierden los cambios posteriores.
- A es imposible: `RECOVER DATABASE` necesita redo archivado.
- B no devuelve los datos: `CREATE CONTROLFILE` reconstruye el índice, no el contenido perdido.
- D es falsa: no hay FRA configurada y, aunque la hubiera, no habría copias automáticas de los datafiles.

### Reto — Plan de copia a partir del inventario
**Copia en frío completa** (datafiles + control files + redo online + SPFILE + password file), con los tamaños reales de la evidencia `11-archivos-so`:

| Concepto | Archivos | Tamaño |
|---|---:|---:|
| Datafiles (raíz, semilla y FREEPDB1) | 16 | 4 251 058 176 B ≈ 4054 MiB |
| Control files | 2 | 37 584 896 B ≈ 36 MiB |
| Redo online (3 grupos de 200 MB) | 3 | 629 147 136 B ≈ 600 MiB |
| SPFILE | 1 | 3584 B |
| Password file | 1 | 2048 B |
| **Total** | **23** | **4 917 795 840 B ≈ 4690 MiB ≈ 4,6 GiB** |

Los **tempfiles** (3, 60 MB) no entran: TEMP se recrea vacío y no hay nada que recuperar.

**Qué sobraría en una copia con RMAN:**
- **Tempfiles:** RMAN no los copia; se recrean.
- **Redo online:** RMAN no los incluye como tales. En ARCHIVELOG lo que necesita para recuperar son los **redo archivados** (5 archivos, 628 MB ahora mismo, y creciendo). Una copia en frío sin ellos solo sirve para arrancar en el punto de la copia; con ellos se recupera hasta el último instante.
- **Password file:** RMAN no lo respalda; hay que copiarlo aparte (2 KB) si se quiere conservar el acceso SYSDBA remoto.
- **SPFILE y control files:** sí entran (el control file, además, con autobackup).
- **Datafiles de `PDB$SEED`:** no sobran si se quiere poder crear PDB nuevas; son parte de la CDB (828 MB).

**Comparación:** un `BACKUP DATABASE PLUS ARCHIVELOG` de RMAN ocuparía aproximadamente lo mismo que la copia en frío (datafiles + control + SPFILE + los 628 MB de archivados), pero con la ventaja de que permite recuperar a un punto en el tiempo y de que no hay que parar la instancia. La copia en frío solo es válida con la base cerrada y limpia.

### Comprobaciones de la Parte J
- **J.1:** `GRANT SELECT ON sys.v_$diag_alert_ext TO c##ops_ro CONTAINER = ALL;` añade solo ese objeto (el privilegio va sobre `V_$DIAG_ALERT_EXT`, no sobre el sinónimo `V$`). El alert log ya se puede leer con SQL.
- **J.2:** la base suma 16 datafiles (4054 MB), 3 tempfiles (60 MB), 2 control files (36 MB), 3 redo online (600 MB) y 5 redo archivados (628 MB, relacionados). `v$pwfile_users` muestra solo a `SYS` con SYSDBA/SYSOPER.
- **J.2:** el modo es **ARCHIVELOG** (en el guion, NOARCHIVELOG) y no hay FRA configurada: los archivados van a `$ORACLE_HOME/dbs` (`arch1_*.dbf`), dentro del volumen.
- **J.2:** los últimos mensajes del alert log son avisos `Time stalled` / `backward drift` del reloj del contenedor, no errores de la base.
- **J.3:** el volumen contiene los datafiles, los control files, los redo y los archivados; el SPFILE y el password file están en `dbconfig/FREE/dbs`, al que apunta `$ORACLE_HOME/dbs`. En esta imagen está enlazada **la carpeta entera**, no cada archivo por separado (por eso el script del kit se adaptó a leer `$ORACLE_HOME/dbs/` con barra final y a mirar hasta cuatro niveles).
- **J.3:** el ADR (`/opt/oracle/diag`) **no** está en el volumen: al recrear el contenedor se pierde el alert log, aunque los datos sobrevivan. Es un hallazgo con riesgo (se pierde la historia del incidente) y acción (llevar `diagnostic_dest` a almacenamiento persistente o centralizar los logs).

## Parte K — Anatomía de un bloque, una fila y un ROWID

### P18 — `ROWID_BLOCK_NUMBER` en un tablespace BIGFILE
**Respuesta: B.** Sin el segundo argumento, `DBMS_ROWID.ROWID_BLOCK_NUMBER` interpreta el ROWID como **SMALLFILE**: reserva 10 bits para el número de archivo relativo y solo 22 para el bloque (máximo 4 194 304 bloques, 32 GB con bloques de 8 KB). En **BIGFILE** no hay archivo relativo: esos bits forman parte del bloque y el número puede ocupar los 32 bits. Por eso hay que pasar `'BIGFILE'` para que la función use el reparto correcto.
- A es falsa: en BIGFILE el ROWID sigue llevando el bloque (y más bits para él).
- C es falsa: el bloque no cambia entre consultas.
- D es falsa: funciona con tablas normales; el problema es el modo de decodificación.
- **Matiz medido en esta base:** el bloque de la fila 101 es el 783, muy por debajo de 2²², así que la decodificación SMALLFILE también devuelve 783 y el error no se reproduce. La diferencia aparece cuando el bloque supera los 4 194 304. `ROWID_RELATIVE_FNO` devolvió 0 (no un `file_id`); el archivo real se obtiene con `ROWID_TO_ABSOLUTE_FNO`, que dio 16 → `academia01.dbf`.

### P19 — PCTFREE 10 con ASSM
**Respuesta: A y B.**
- A: un bloque deja de aceptar `INSERT` cuando el espacio libre baja del 10 % (PCTFREE), aunque queden bytes sueltos.
- B: ese 10 % se reserva para que las filas ya existentes crezcan con `UPDATE`; si no bastara, la fila migra a otro bloque y deja un puntero.
- C es falsa: la ITL se dimensiona con `INITRANS`/`MAXTRANS`, no con PCTFREE.
- D es falsa: PCTFREE afecta a tablas e índices.
- E es falsa: una fila puede migrar aunque el bloque tenga PCTFREE; el PCTFREE reduce la probabilidad, no la elimina.

### Reto — Abrir otro bloque (estudiante 20000)
Elegí el ID más alto, **20000** (`EGRESADO`). Su dirección física:

| Dato | Valor |
|---|---|
| ROWID | `AAAR2mAAAAAAASvABD` |
| `DATA_OBJECT_ID` | 73126 (`ADMIN_ACADEMIA.ACA_ESTUDIANTES`) |
| Archivo absoluto | 16 → `/opt/oracle/oradata/FREE/FREEPDB1/academia01.dbf` |
| Bloque | **1199** (`0x4af`) |
| Fila en el bloque | 67 |
| Fecha de registro | 2026-10-25 16:47:35.071962 |

Comparación de los dos volcados (ambos en `evidencia/config/`):

| Campo | Bloque 783 (fila 101) | Bloque 1199 (fila 20000) | Lectura |
|---|---:|---:|---|
| `Block header dump` | `0x30f` = 783 | `0x4af` = 1199 | Coincide con `DBMS_ROWID` |
| `seg/obj` | `0x11da6` = 73126 | `0x11da6` = 73126 | Mismo segmento |
| `itc` | 2 | 2 | Dos ranuras de ITL, una usada |
| ITL 0x01 `Xid` | `0x0005.001.000002ab` | `0x0005.001.000002ab` | La misma transacción (V002) cargó las 20 000 filas |
| ITL 0x01 `Uba` | `0x00000af4.00ff.04` | `0x00000a47.0106.02` | Distinta dirección de undo por bloque |
| ITL 0x01 `Flag` | `--U-` | `--U-` | Confirmada (upper bound) |
| ITL 0x01 `Lck` | **90** | **68** | Filas aún marcadas por esa transacción |
| `tsiz` | `0x1f98` = 8088 | `0x1f98` = 8088 | Mismo espacio de datos |
| `hsiz` | `0xc6` = 198 | `0x9a` = 154 | Cabecera + directorio (2 bytes por fila) |
| `nrow` | **90** | **68** | Factor de bloqueo real |
| `fsbo` / `fseo` | `0xc6` / `0x427` = 198 / 1063 | `0x9a` / `0x9c5` = 154 / 2501 | Hueco libre |
| `avsp` = `tosp` | `0x361` = **865** (10,7 %) | `0x92b` = **2347** (29,0 %) | `fseo - fsbo` |
| Fila | `tab 0, row 5, @0x1cda` | `tab 0, row 67, @0x1839` | Ranura del directorio |
| `tl` / `fb` / `lb` / `cc` | 78 / `--H-FL--` / `0x1` / 7 | 82 / `--H-FL--` / `0x1` / 7 | 3 bytes de cabecera + 7 de longitudes + datos |

- **Sí se ve la limpieza diferida en los dos bloques.** La ranura 1 de la ITL está confirmada (`--U-`) pero mantiene `Lck` igual al número de filas (90 y 68), y la fila tiene `lb: 0x1`. El `COMMIT` de V002 no recorrió los bloques; la próxima modificación comprobará en el undo que la transacción terminó y limpiará las marcas.
- **Por qué 68 y no 90:** el bloque 1199 es el **último que se llenó**: contiene los IDs 19933-20000, los más altos. La carga terminó ahí y dejó 2347 bytes libres; por eso no llegó al PCTFREE. Las 13 filas FS4 de `DBMS_SPACE` son bloques formateados por delante de la HWM que se quedaron sin filas.
- **El orden físico no sigue al ID:** el bloque 782 contiene los IDs 1-95, el 783 el 96-185 y el 779 el 186-275. ASSM reparte los bloques según sus mapas de bits, no por dirección creciente; por eso el último bloque escrito (1199) no es el de mayor número (1279).
- **La longitud de la fila cambia:** 68 bytes de datos (fila 101: email de 19, `ACTIVO` de 6) frente a 72 (fila 20000: email de 21, `EGRESADO` de 8). De ahí que unos bloques admitan 95 filas y otros 85.

Distribución real de las 20 000 filas en 231 bloques:

| Filas por bloque | Bloques | Filas |
|---:|---:|---:|
| 95 | 1 | 95 |
| 90 | 10 | 900 |
| 89 | 9 | 801 |
| 88 | 93 | 8184 |
| 86 | 7 | 602 |
| 85 | 110 | 9350 |
| 68 | 1 | 68 |
| **Total** | **231** | **20 000** |

### Punto de control — interpretar el volcado
1. **`avsp = fseo - fsbo`.** Bloque 783: `0x427 - 0xc6 = 0x361 = 865`. Bloque 1199: `0x9c5 - 0x9a = 0x92b = 2347`. Se cumple en los dos.
2. **Fecha de la fila 101.** Bytes `78 7e 0a 19 11 30 24` → siglo `0x78 - 100 = 20`, año `0x7e - 100 = 26`, mes 10, día 25, hora `0x11 - 1 = 16`, minuto `0x30 - 1 = 47`, segundo `0x24 - 1 = 35`. Oracle guarda hora, minuto y segundo **con +1**. Los cuatro bytes siguientes, `04 4a 0d 90`, son la fracción: `0x044A0D90` = 71 962 000 ns → `2026-10-25 16:47:35.071962`, que coincide con `TO_CHAR`.
3. **Un `UPDATE` de la fila 101.** Usará la **ranura 2** de la ITL, que está libre. Antes de modificar, Oracle hará la *cleanout* de la ranura 1: comprobará en el undo que `0x0005.001.000002ab` terminó y borrará las marcas de las 90 filas (`Lck 90` → 0); ese trabajo puede generar redo aunque la sentencia sea un `SELECT`.

### Comprobaciones de la Parte K
- **Tablespaces:** `TBS_ACADEMIA` es BIGFILE, extensión LOCAL/SYSTEM (AUTOALLOCATE), ASSM (`SSM AUTO`) y bloque de 8192. `TEMP` es TEMPORARY, UNIFORM y MANUAL. `SYSTEM` y `UNDOTBS1` son BIGFILE en esta imagen 23ai.
- **Segmentos:** `ACA_ESTUDIANTES` ocupa 17 extensiones, 256 bloques y 2048 KB; `ACA_MATRICULAS` y su índice único, 18 y 384 bloques (3072 KB cada uno).
- **Extensiones:** 16 de 8 bloques (64 KB) y una de 128 bloques (1 MB), en el archivo 16. AUTOALLOCATE empieza con extensiones pequeñas y las agranda.
- **Fila 101:** ROWID `AAAR2mAAAAAAAMPAAF` → objeto `AAAR2m` = 73 126, archivo `AAA` = 0 (BIGFILE), bloque `AAAAMP` = 783, fila `AAF` = 5. `ROWID_TO_ABSOLUTE_FNO` = 16 → `academia01.dbf`.
- **La fila:** 68 bytes de datos (`VSIZE`), `tl` 78 en el bloque (3 de cabecera + 7 longitudes + 68) y 80 contando los 2 bytes del directorio. `AVG_ROW_LEN` = 76: es una media de `DBMS_STATS` que no cuenta el directorio.
- **Ocupación:** 230 bloques FULL + 1 FS2 (el 1199) + 13 FS4 = 244 bloques bajo la HWM, el mismo total que dan las estadísticas en la Parte L. La tabla usa 231 bloques con filas; los 13 FS4 están formateados y vacíos.
- **Volcado:** `Block header dump` 0x30f = 783, `seg/obj` 0x11da6 = 73 126, `typ: 1 - DATA`, `itc: 2`, `nrow: 90`, `avsp = tosp = 0x361`. La traza completa (2862 líneas) está en `evidencia/config/20261025T170224Z_12-volcado-bloque.trc.txt`; la del reto (2370 líneas), en `..._12-reto-volcado-bloque.trc.txt`.
- **Scripts del reto:** `12-reto-bloque.sql` (volcado del bloque 1199), `12-reto-analisis.sql` (distribución y rangos de IDs) y `12-reto-rowid-bigfile.sql` (comparación de la decodificación BIGFILE/SMALLFILE).

## Parte L — Capacidad y coste: factor de bloqueo, páginas y tiempo

### P20 — Bloques de una tabla de 2 000 000 de filas
**Respuesta: B. 50 000.**
`bfr = floor((8192 - 96) · (1 - 0,10) / 180) = floor(8096 · 0,9 / 180) = floor(40,48) = 40` filas por bloque.
`b = ceil(2 000 000 / 40) = 50 000` bloques.
- A (44 445) saldría de dividir por 45; C y D no corresponden a la fórmula con esos datos.

### P21 — `db file scattered read`
**Respuesta: B.** Es la espera de una **lectura multibloque a la buffer cache**, la típica de un recorrido completo de tabla (`TABLE ACCESS FULL`): Oracle pide varios bloques contiguos al sistema operativo y los dispersa en la caché.
- A es `db file sequential read` (un bloque, típico de índice).
- C es `direct path read` (a la PGA, sin pasar por la caché).
- D es la escritura de DBWn (`db file parallel write`, `free buffer waits`), no una lectura.

### Reto — Dimensionar `ACA_MATRICULAS`
Predicción antes de mirar (r = 60 000, R = `AVG_ROW_LEN` = 30, PCTFREE 10):

| Cálculo | bfr | Bloques | Tiempo HDD 150 MB/s |
|---|---:|---:|---:|
| Unidad 3 (H = 96) | `floor((8192-96)·0,9/30)` = **242** | `ceil(60000/242)` = **248** | 1,94 MB → **13 ms** |
| Versión Oracle (H = 122, R+2) | `floor((8192-122)·0,9/32)` = **226** | `ceil(60000/226)` = **266** | 2,08 MB → **14 ms** |
| Medido (estadísticas bajo la HWM) | 199,3 de media | **370** | 2,89 MB → **19 ms** |
| Medido (solo bloques con filas) | 199,3 | **301** | 2,35 MB → **16 ms** |
| Asignado al segmento | — | **384** | 3,00 MB → **20 ms** |

Datos reales: 60 000 filas, `AVG_ROW_LEN` 30, `BLOCKS` 370, PCTFREE 10, `INI_TRANS` 1, 384 bloques asignados (3 MB). La tabla usa **301 bloques con filas**, con un mínimo de 159, una media de 199,3 y un máximo de **210 filas por bloque**.

**Por qué la fórmula se queda corta (248 frente a 301):**
1. **`AVG_ROW_LEN` no incluye el coste de la fila en el bloque.** La fila de la matrícula 1 mide 24 bytes de datos (2+3+2+6+11), pero ocupa `tl = 32` (3 de cabecera + 5 de longitudes) y **34** con los 2 bytes del directorio. La fórmula divide solo por 30. Ese sobrecoste de ~10 bytes por fila, sobre una fila de 30, es un tercio más.
2. **`AVG_ROW_LEN` es una media.** El `PERIODO` y los `NUMBER` no ocupan lo mismo en todas las filas: de ahí los bloques de 159 a 210 filas. La fórmula supone una fila uniforme.
3. **La HWM no es lo que ocupa la tabla.** Los 370 bloques incluyen 69 bloques formateados sin filas; los 384 asignados incluyen el resto de la última extensión. El segmento reserva por extensiones, no por filas.

Es el mismo patrón de la tabla L.2: Unidad 3 211 / Oracle 216 / medido 231 / estadísticas 244 / asignado 256 para `ACA_ESTUDIANTES`. La fórmula acierta el orden de magnitud, no el número exacto. Para dimensionar sirve; para decidir si cabe en un disco concreto, se mide.

**Tiempo de un recorrido completo en HDD a 150 MB/s:** con los 370 bloques bajo la HWM, `370 · 8 KB = 2,89 MB → 2,89/150 = 0,0193 s ≈ 19 ms`. Con los 301 bloques que tienen filas, 16 ms; con el segmento entero, 20 ms. En SSD a 1 GB/s serían 2-3 ms. Es una tabla pequeña: el coste de leerla entera es despreciable frente a la latencia de un solo acceso aleatorio a un HDD (5 ms).

### Comprobaciones de la Parte L
- **`ACA_ESTUDIANTES`:** 20 000 filas, `AVG_ROW_LEN` 76, 244 bloques bajo la HWM, PCTFREE 10, `INI_TRANS` 1, 256 bloques asignados. Medido: 231 bloques con filas, entre 68 y 95, media 86,6.
- **Fórmulas:** Unidad 3 → 95 filas/bloque y 211 bloques; versión Oracle → 93 y 216; realidad → 231 con filas y 244 bajo la HWM. La diferencia es la misma que en el reto: cabecera, ITL, directorio, longitud variable y huecos.
- **Banco de pruebas:** `TBS_LAB4` y `LAB4_PRUEBAS` creados dentro del volumen; `LECTURAS` con 400 000 filas, 78 bytes, 4676 bloques y 36,5 MB.
- **Lectura lógica:** 400 000 lecturas lógicas (4 por búsqueda: raíz, rama, hoja y tabla) en 840 ms de CPU → **2,1 µs** por lectura.
- **Lectura física aleatoria:** 5464 lecturas en 59,1 ms con la caché vacía → **10,8 µs** por lectura. Es una cota superior: incluye CPU y, sobre todo, la caché de páginas de Linux, que sirve muchas de esas "físicas" desde RAM.
- **Lectura secuencial:** 4595 bloques en 53 peticiones (36 multibloque, ~87 bloques por petición) en 31 ms → **1171 MB/s**; 30,6 ms de tiempo de pared.
- **Predicción frente a medida:** `T_aleatorio = 4595 · 10,8 µs = 49,6 ms`, **1,6 veces** el secuencial. `c_sec/c_aleat = 0,618`; el umbral de rentabilidad del índice queda en el **0,72 %** de las filas. Con HDD (5 ms de latencia) el aleatorio serían 23 s y con SSD (0,1 ms) 460 ms.
- **Esperas de la instancia:** `db file scattered read` 1510 esperas a 123 µs; `db file sequential read` 9784 a 182 µs; `direct path read` 8 a 569 µs. Son medias desde el arranque y están infladas por los dos `FLUSH BUFFER_CACHE` y los recorridos de este laboratorio; el método es el mismo que se usa en producción.
- **Estado:** la caché de Oracle quedó vacía tras los experimentos. `TBS_LAB4` y `LAB4_PRUEBAS` siguen creados; `14-filas-migradas.sql` los borra al final de la Parte M.

## Parte M — Filas migradas y encadenadas

### P22 — `table fetch continued row` crece tras un `UPDATE` masivo
**Respuesta: A y C.**
- **A** es correcta: `ANALYZE TABLE ... LIST CHAINED ROWS INTO` guarda en `CHAINED_ROWS` el ROWID de cada fila migrada o encadenada. Es la forma de pasar de una estadística global a una lista concreta de filas.
- **C** es correcta: `ALTER TABLE ... MOVE ONLINE` con un `PCTFREE` mayor reescribe las filas con hueco para crecer y mantiene los índices válidos; es la reparación de la migración.
- **B** es falsa: `DBMS_STATS.GATHER_TABLE_STATS` **no rellena `CHAIN_CNT`**. Esa columna solo la actualiza `ANALYZE ... COMPUTE STATISTICS`. En la prueba, tras el `UPDATE` y el `ANALYZE`, `CHAIN_CNT` valió 1000; con `DBMS_STATS` habría seguido a 0.
- **D** es falsa: `FLUSH BUFFER_CACHE` solo vacía la caché y empeora el rendimiento; no mueve ni cura ninguna fila.
- **E** es falsa: `DB_FILE_MULTIBLOCK_READ_COUNT` afecta a las lecturas multibloque de los recorridos completos, no a la lectura por ROWID que sufre la migración.

### P23 — Una fila de 12 000 bytes en bloques de 8 KB
**Respuesta: B.** La fila **no cabe en un bloque**, así que Oracle la guarda **encadenada** en varias piezas. `ALTER TABLE ... MOVE` no lo arregla: reescribe las filas en bloques del mismo tamaño y la fila seguirá sin caber. Solo se cura con un tablespace de bloques mayores (16/32 KB) o rediseñando la tabla (separar columnas grandes, LOB, etc.).
- A es falsa: la migración es para una fila que **sí cabía** en su bloque original y creció con un `UPDATE`; aquí nunca cupo.
- C es falsa: Oracle acepta filas mayores que un bloque encadenándolas; `ORA-01401` es «valor demasiado grande para la columna», otro error.
- D es falsa: Oracle no comprime la fila para meterla en un bloque; el almacenamiento en fila no funciona así.

### Comprobaciones de la Parte M

**1. Provocar la migración.** `MIGRA` se creó con `PCTFREE 0` (sin hueco para crecer) y 5000 filas cortas (`'x'`, 9 bytes de media). El `UPDATE` de una de cada cinco filas a 300 bytes no cupo en su bloque:

| Momento | `NUM_ROWS` | `BLOCKS` | `PCT_FREE` | `AVG_ROW_LEN` | `CHAIN_CNT` |
|---|---:|---:|---:|---:|---:|
| Tras el `INSERT` | 5000 | 13 | 0 | 9 | 0 |
| Tras el `UPDATE` | 5000 | **58** | 0 | 70 | **1000 (20 %)** |

Las 1000 filas son exactamente las de `MOD(id, 5) = 0`: el 20 % que creció. `CHAIN_CNT` **no distingue** migradas de encadenadas; hay que mirar el bloque o la lista.

**2. Detectarlas fila a fila.** `LIST CHAINED ROWS INTO lab4_pruebas.chained_rows` listó **1000** filas. La primera que devolvió el script fue la matrícula `id = 2935`, con ROWID `AAASAqAAAAAABYLAAC` → archivo **24**, bloque **5643**, ranura **2**.

**3. El coste medido.** En 1000 búsquedas por clave, `table fetch continued row` subió **200** (las 200 filas migradas entre los id 1 y 1000) y las lecturas lógicas **3200**, es decir **3,2 por búsqueda**. El cálculo cuadra: `(800 · 3 + 200 · 4) / 1000 = 3,2`. Una búsqueda normal cuesta 3 lecturas (índice de dos niveles + bloque de tabla); la migrada paga una cuarta para seguir el `nrid`. Es un **7 % más de trabajo en cada acceso**, y no desaparece solo.

**4. La prueba en el bloque.** El volcado del bloque 5643 (`0x160b`, objeto 73770) muestra `nrow = 733` y `avsp = tosp = 0x7` (**7 bytes libres**): el bloque está lleno. De sus 733 filas, **147** son cabezas:

```
tab 0, row 2, @0x1f7d
tl: 9 fb: --H----- lb: 0x2  cc: 0
nrid:  0x00001626.0
```

`fb: --H-----` significa **solo cabeza** (Head): no hay ni First ni Last porque los datos no están ahí. `nrid: 0x00001626.0` es la dirección nueva: en BIGFILE, `0x1626` = **bloque 5670**, ranura **0**.

**5. La limpieza diferida, vista por segunda vez.** La traza conserva también la imagen del bloque **antes** del `UPDATE` (SCN `0x427587`, la del `INSERT`): allí las 733 filas eran normales (`--H-FL--`) y la ITL 0x01 estaba en `--U-` con `Lck 733`. En la imagen actual la ITL 0x01 aparece `C---` con `Lck 0` y la 0x02 `--U-` con `Lck 147`. El `UPDATE` hizo la *cleanout* que el `COMMIT` del `INSERT` había dejado pendiente, exactamente lo que anticipamos en la Parte K.

**6. Encadenamiento de verdad.** `ANCHA` tiene dos filas: una de ~12 000 bytes (4000 + 4000 + 4000) y otra corta. Resultado: `NUM_ROWS` 2, `BLOCKS` 5, `AVG_ROW_LEN` 6016, `CHAIN_CNT` **1**. La fila larga está encadenada; la corta no. Reorganizar no la cura.

**7. Curar la migración.** `ALTER TABLE lab4_pruebas.migra MOVE PCTFREE 20` dejó el índice `PK_MIGRA` en **UNUSABLE** (las filas tienen ROWID nuevo y el índice apuntaba a los viejos). Tras `ALTER INDEX lab4_pruebas.pk_migra REBUILD` volvió a **VALID**. El resultado final:

| `NUM_ROWS` | `BLOCKS` | `PCT_FREE` | `AVG_ROW_LEN` | `CHAIN_CNT` |
|---:|---:|---:|---:|---:|
| 5000 | 63 | 20 | 69 | **0** |

Son 63 bloques frente a 58 porque ahora cada bloque reserva un 20 % para que las filas crezcan. En producción se usaría `MOVE ONLINE`, que mantiene los índices válidos y no bloquea el DML.

**8. Limpieza.** El script borró `LAB4_PRUEBAS CASCADE` y `TBS_LAB4 INCLUDING CONTENTS AND DATAFILES`; las comprobaciones posteriores dan **0** tablespaces y **0** usuarios con ese nombre. El banco de pruebas de la Parte L ya no existe.

**Evidencias:** `evidencia/script/20261025T171133Z_14-filas-migradas.script.log` y la traza completa del volcado (12 432 líneas, tres imágenes del bloque) en `evidencia/config/20261025T171133Z_14-volcado-migra.trc.txt`.

## Parte N — Autopsia y verificación final

### P24 — Informe diario con el mínimo privilegio
**Respuesta: B.** Un **usuario común de solo lectura** con `SELECT_CATALOG_ROLE`, `CONTAINER_DATA` donde haga falta y el `GRANT` puntual sobre `V_$DIAG_ALERT_EXT` es exactamente lo que se construyó en las Partes B y J: ve el diccionario y el alert log, no puede escribir y no necesita la contraseña de nadie.
- A es falsa: `SYSDBA` puede hacer cualquier cosa; un informe de lectura no justifica ese privilegio, y además exige acceso a la cuenta de sistema operativo `oracle` desde `cron`.
- C es falsa: el rol `DBA` es el máximo privilegio y la contraseña en el script es un secreto expuesto.
- D es falsa: `SYSTEM` tiene privilegios de administración y la contraseña en una variable de entorno sigue siendo un secreto en claro.

### Comprobaciones de la Parte N

- **Autopsia:** `15-autopsia-instancia.sql` ejecutado como `C##OPS_RO` contra `FREE`; el spool quedó en `evidencia/spool/20261025T171508Z_15-autopsia-instancia.spool.log`.
- **Informe:** `docs/bitacora/lab4-autopsia.md`, con seis hallazgos priorizados y el resumen para dirección. Los dos de prioridad alta/media son de redundancia (control files y redo en un solo volumen, archivados sin FRA); no hay ningún problema de capacidad.
- **Verificación final:** `16-verificacion-final.sh` terminó con **0 fallos** y el mensaje «TODO OK. Lab 4 listo para entregar». Evidencia en `evidencia/script/20261025T171718Z_16-verificacion-final.script.log`.
- **Estado que confirma la verificación:** CDB y `FREEPDB1` abiertas, `C##OPS_RO` común y sin privilegios `ANY` de escritura, `open_cursors=300`, `db_files` sin línea pendiente, `PDB_LAB4` y los usuarios `*LAB4*` borrados, `TBS_LAB4` borrado, las cinco tablas de negocio en su carpeta, las cuentas `ADMIN_*` sin contraseña, los datos de V002 (20 000/40/60 000), el volcado del bloque y las evidencias 00 a 15.

## Preguntas de comprobación (1–38)

### Respaldo y diagnóstico (A)

**1. ¿Por qué la copia de la Parte A es consistente? ¿Qué pasaría si se tomara con la base abierta?**
Porque se tomó **en frío**: `backup-estado.sh` ejecuta `SHUTDOWN IMMEDIATE`, hace el checkpoint final y solo entonces copia el volumen. Al cerrarse la base, todos los datafiles quedan con el mismo SCN y sin escrituras pendientes, así que el `tar` es una imagen coherente de un instante. Con la base abierta, DBWn estaría escribiendo bloques sucios mientras se leen los archivos: la copia sería *fuzzy*, con datafiles de SCN distintos, y sin ARCHIVELOG no habría redo con el que recuperarla (habría que restaurar y abrir con `RECOVER`, que fallaría).
Evidencia: `evidencia/script/20261022T171859Z_00-backup-lab3.script.log`, secciones «4. Parada limpia» y «5. Copia del volumen»; al terminar, `t=10s docker=healthy cdb/pdb=READWRITE/READWRITE`.

**2. ¿Para qué sirven manifiesto.txt y SHA256SUMS? ¿Qué comprueba restaurar-estado.sh antes de tocar nada?**
- `manifiesto.txt` describe la copia (etiqueta, fecha, versión, base, SCN, modo de log, tamaño del volumen, archivos y extras fuera del volumen): permite saber qué hay dentro y si la copia corresponde a lo que se cree, sin abrir el `tar`.
- `SHA256SUMS` guarda la suma de cada archivo: detecta corrupción o manipulación (un `tar` truncado, un archivo cambiado) antes de restaurar.
- `restaurar-estado.sh` comprueba, **antes de tocar nada**: (1) que Docker responde —si no, sale sin haber tocado nada—; (2) `sha256sum --check --quiet SHA256SUMS`, y aborta si la copia no está íntegra; (3) muestra el manifiesto; (4) exige confirmación escribiendo el nombre del volumen (o `--si`). Solo después para la base, sustituye el volumen, restaura los extras y arranca verificando instancia, base, PDBs y tablas de negocio.
Evidencia: `scripts/ops/restaurar-estado.sh`, líneas 6-16 (pasos 1 y 2).

**3. Define RPO y RTO con los datos de tu propia copia.**
- **RPO** (cuántos datos puedo perder): **0** en el instante de la copia. El manifiesto registra `scn=4196349` y la copia se tomó con la base cerrada, así que todo lo confirmado hasta ese SCN está dentro. Como estrategia, si solo se hace una copia por práctica, el RPO real es el intervalo entre copias: la mía es del **22-oct 17:18 UTC** y hoy es 25-oct → hasta ~72 h de datos. Con ARCHIVELOG y los 5 archivados (628 MB) se aplica redo y baja a minutos.
- **RTO** (cuánto tardo en volver a servir): la copia pesa **564 MB**; restaurar es descomprimirla sobre el volumen más arrancar. Medí el arranque: `t=10s docker=healthy cdb/pdb=READWRITE/READWRITE` (`00-backup-lab3`). En este equipo el RTO es del orden de **un minuto**, contando la ejecución del script; no hice una restauración completa cronometrada, así que lo doy como cota.
Evidencia: `00-backup-lab3` (manifiesto, `scn=4196349`, `564M`, `t=10s`).

### Correcciones del Lab 3 (C, D)

**4. ¿Dónde creó Oracle los datafiles de V000 y por qué? ¿Qué parámetro habría evitado el problema?**
En `$ORACLE_HOME/dbs`: V000 los creó con **ruta relativa** (`'academia01.dbf'`) y `db_create_file_dest` estaba vacío, así que Oracle resolvió el nombre contra el directorio por defecto del `ORACLE_HOME`. Lo habría evitado **`db_create_file_dest=/opt/oracle/oradata`** (OMF), que hace que Oracle genere el nombre y la ruta dentro del volumen cuando se omite la cláusula `DATAFILE`; o, sin OMF, escribir una ruta absoluta en el `CREATE TABLESPACE`.
Evidencia: A.4 de este documento, `11-archivos-so` (los cinco archivos están en `dbconfig/FREE/dbs`) y `03-omf` (`db_create_file_dest` vale `/opt/oracle/oradata` en CDB$ROOT y en FREEPDB1).

**5. ¿Por qué ALTER TABLESPACE ... RENAME DATAFILE no basta para mover un archivo?**
Porque `RENAME DATAFILE` solo cambia **la ruta que el control file guarda**: no mueve ni copia un solo byte. Si se ejecuta sin haber movido el archivo con el sistema operativo, la base busca el nombre nuevo y no lo encuentra (el tablespace no abre). El orden correcto es: `OFFLINE` (hace checkpoint y cierra el archivo), copiar/mover con `cp`/`mv`, `RENAME DATAFILE`, `ONLINE` (valida la cabecera en la ruta nueva).
Evidencia: P2 y Parte C de este documento; `03-reubicar-datafiles` (los cinco pasaron a `/opt/oracle/oradata/FREE/FREEPDB1/`).

**6. ¿Por qué no se edita V000 y se crea V003? ¿Por qué invalidar una contraseña es mejor que borrarla del archivo?**
V000 ya está aplicada y versionada: editarla rompe el checksum de la migración, deja entornos divergentes (unos la aplicaron con contraseñas y otros sin ellas) y reescribe la historia. La corrección va en una migración **nueva e inmutable**, V003. Invalidar la contraseña es mejor que borrarla porque el secreto **ya está en el historial de Git**: borrarlo de la última versión no lo elimina de los commits, clones ni copias. `ALTER USER ... NO AUTHENTICATION` convierte la cuenta en *schema-only*: sigue poseyendo los objetos pero nadie puede iniciar sesión con ella, aunque el hash antiguo siga en el pasado.
Evidencia: `database/migrations/V003__cuentas_esquema_sin_password.sql`; `AUTHENTICATION_TYPE = NONE` para las cinco cuentas y `ORA-01017` al intentar entrar como `admin_academia`.

**7. ¿Qué demuestra la prueba de persistencia y por qué se ejecuta después de reubicar?**
Demuestra que los datos sobreviven a la **recreación del contenedor**: se para la base, se borra el contenedor (`docker rm`) y se crea de nuevo reutilizando el volumen; antes y después salen los mismos 5 tablespaces, las mismas 5 cuentas, las mismas 3 tablas y la fila 101 igual. Se ejecuta **después de reubicar** porque es la prueba de que la nueva ubicación está dentro del volumen: si los datafiles se hubieran quedado en la capa del contenedor, el `docker rm` los habría borrado y la prueba lo habría detectado.
Evidencia: `03-prueba-persistencia`, secciones 1 y 4 (idénticas) y «El volumen oralab-26ai-data ya contiene la base FREE: se reutiliza».

### Instancia, arranque y parámetros (E, F)

**8. Con tus evidencias: tres datos que pertenecen a la instancia y tres que pertenecen a la base de datos.**
- **Instancia** (memoria y procesos, mueren con `SHUTDOWN`): `STARTUP_TIME` de hoy 16:49, **87 procesos Oracle / 54 procesos Linux** y una **SGA de 1529 MB**.
- **Base de datos** (archivos en disco, sobreviven): `DBID 1509902213`, `CREATED` (fecha de creación de la base, no la del arranque), `log_mode=ARCHIVELOG` y **16 datafiles / 4054 MB**.
Evidencia: `05-instancia-so`, `09-procesos-so`, `11-archivos-so` y autopsia §1-§4.

**9. ¿Qué lee Oracle en NOMOUNT, en MOUNT y en OPEN? Relaciónalo con ORA-01507 y ORA-01219.**
- **NOMOUNT:** solo el SPFILE/PFILE. Arranca la memoria y los procesos, pero no ha leído el control file: `V$DATABASE` responde **ORA-01507: database not mounted**.
- **MOUNT:** lee los control files y ya conoce datafiles, redo y grupos (`V$DATAFILE` y `V$LOG` responden), pero no abre los datafiles ni el diccionario: consultar una tabla de `SYSTEM` da **ORA-01219: Database or pluggable database not open**.
- **OPEN:** abre datafiles, undo y diccionario, y abre las PDB: todo responde.
Evidencia: `06-arranque-por-etapas`, líneas 35-39 (ORA-01507) y 62-66 (ORA-01219).

**10. Diferencia entre v$parameter y v$spparameter con el ejemplo de db_files de tu evidencia.**
`V$PARAMETER` muestra el valor **en memoria** (lo que la instancia está usando); `V$SPPARAMETER` muestra lo **grabado en el SPFILE** (lo que se aplicará en el próximo arranque, con `ISSPECIFIED` indicando si la línea existe). Con `db_files`: `SCOPE=MEMORY` da **ORA-02095** (es estático), pero `SCOPE=SPFILE` deja **200 en memoria y 300 en el SPFILE**, es decir, el cambio queda **pendiente** hasta reiniciar; `RESET` borra la línea y `V$SPPARAMETER` pasa a «no especificado» (valor por defecto).
Evidencia: `07-parametros-cambios`, sección 3. El SPFILE solo tiene **33 líneas efectivas** frente a los 564 parámetros de `V$PARAMETER`: el resto son valores por defecto o derivados (`sessions=322` sale de `processes=200`).

**11. ¿Por qué PROCESSES rechaza el cambio en memoria aunque v$parameter lo marque IMMEDIATE?**
Porque `PROCESSES` dimensiona **estructuras fijas que se reservan al arrancar** (la tabla de procesos y, derivadas de ella, `SESSIONS` y `TRANSACTIONS`). Cambiarlas en caliente obligaría a recolocar la SGA: por eso Oracle solo lo acepta en el SPFILE y lo aplica en el siguiente arranque. La columna `ISSYS_MODIFIABLE` describe el parámetro, pero la prueba real es el `ALTER SYSTEM` fallido: `SCOPE=MEMORY` devuelve **ORA-02095** (y `ORA-02097` por el valor). Desde una PDB ni se intenta: **ORA-65040**.
Evidencia: `07-parametros-cambios`, sección 4; `processes=200` en `V$PARAMETER`.

### Memoria y procesos (G, H)

**12. ¿Qué modelo de gestión de memoria usa tu instancia? Justifícalo con tres parámetros.**
**ASMM**: gestión automática de la SGA y manual de la PGA. Los tres parámetros: `memory_target = 0` (no hay AMM), `sga_target = 1536M` (Oracle reparte la SGA: **1529 MB** reales, buffer cache 1024 MB, shared pool 464 MB, large pool 16 MB) y `pga_aggregate_target = 512M` con `pga_aggregate_limit = 2G` (el límite duro; el objetivo se superó sin error: 422 MB asignados, 499 MB de máximo).
Evidencia: `08-memoria`, `v$sgainfo`, `v$pgastat`; autopsia §2.

**13. Explica las cifras de tu experimento de caché: lecturas lógicas, físicas y tasa de acierto.**
Primera vuelta **en frío**: 359 lecturas lógicas y **262 físicas**. Las físicas son algo más que los 244 bloques de la tabla porque incluyen la cabecera del segmento y bloques de undo para la lectura consistente. Segunda vuelta **en caliente**: 247 lógicas y **0 físicas** → **100 % de acierto**: todos los bloques estaban ya en la buffer cache. La diferencia de lógicas (359 → 247) confirma que en frío hay más visitas a undo.
Evidencia: `08-experimento-cache`.

**14. Compara literales y variables de enlace (bind variables) con tus cifras de análisis (parse) y de V$SQL.**
Con **1000 literales distintos**: 1000 análisis duros, **830 ms** de CPU de parse y 940 ms totales; en `V$SQL`, **1000 cursores** y **38 845 KB** en la shared pool, todos con la misma `FORCE_MATCHING_SIGNATURE` (1.8632E+18). Con **`:id`**: **1 análisis**, 0 ms de CPU, 10 ms totales, **1 cursor** y **39 KB**. El texto es idéntico, así que el cursor se comparte y el plan se reutiliza: ~94 veces menos tiempo y ~1000 veces menos memoria.
Evidencia: `08-parse-y-pga`, `08-reto-literales.sql` y su salida.

**15. Relaciona el SPID de LGWR de v$process con el PID de /proc. ¿Por qué docker top muestra otro número?**
El `SPID` de `V$PROCESS` es el PID **dentro del contenedor**: LGWR es **964** y en `/proc/964` aparece `db_lgwr_FREE` (98 MB de RSS). `docker top` muestra el PID del **anfitrión**, porque el contenedor tiene su propio espacio de nombres de PID y el kernel traduce el número al listar desde fuera. El proceso es el mismo; el número cambia. Para cruzar dentro/fuera se usa `docker top` o `docker inspect`, no el `/proc` del host.
Evidencia: `09-procesos-so`, `09-procesos.sql`.

### Contenedores (I)

**16. Explica con tu evidencia por qué SYS ve 16 datafiles desde la raíz y 9 desde FREEPDB1.**
Desde la raíz, `SYS` (usuario común con `CONTAINER_DATA = ALL`) ve **16**: 4 de `CDB$ROOT`, 3 de `PDB$SEED` y 9 de `FREEPDB1`. Dentro de `FREEPDB1`, la misma vista se filtra por el contenedor de la sesión y devuelve solo los **9** de esa PDB. Los datafiles pertenecen a un contenedor (`CON_ID`) y `V$DATAFILE` respeta el contenedor actual salvo que el usuario tenga `CONTAINER_DATA`.
Evidencia: `10-que-ve-cada-usuario` y Parte I de este documento.

**17. ¿Por qué LAB4_ANALISTA recibe ORA-00942 y no "privilegios insuficientes" al consultar DBA_TABLES?**
Porque para ese usuario la vista **no existe en su espacio de nombres**: Oracle resuelve primero qué objetos puede ver (esquema propio, sinónimos y objetos concedidos) y, al no encontrarla, devuelve `ORA-00942: table or view does not exist`. Es deliberado: no revela la existencia de un objeto al que no se tiene acceso. El `ORA-01031: insufficient privileges` aparece en operaciones que la sintaxis permite pero el privilegio no (`CREATE TABLE`, `ALTER SESSION SET CONTAINER`), y `ORA-41900` al intentar escribir sobre lo concedido en solo lectura.
Evidencia: `10-que-ve-cada-usuario` (ORA-00942 en `DBA_TABLES`, `V$SESSION` y `ADMIN_ACADEMIA.ACA_ESTUDIANTES`; ORA-01031 en `CREATE TABLE` y `SET CONTAINER`).

**18. ¿Qué diferencia hay entre C##LAB4_AUDITOR y C##OPS_RO? ¿Qué sentencia los igualaría?**
Los dos son comunes y tienen `CREATE SESSION`, `SET CONTAINER` y `SELECT_CATALOG_ROLE`. La diferencia es el atributo **`CONTAINER_DATA`**: `C##OPS_RO` lo tiene en `ALL` —desde la raíz ve los datos de todos los contenedores— y además el `SELECT` puntual sobre `V_$DIAG_ALERT_EXT`; `C##LAB4_AUDITOR` solo ve los datos de `CDB$ROOT` y no puede leer el alert log. Los igualaría:
```sql
ALTER USER c##lab4_auditor SET CONTAINER_DATA = ALL CONTAINER = CURRENT;
GRANT SELECT ON sys.v_$diag_alert_ext TO c##lab4_auditor CONTAINER = ALL;
```
Evidencia: `10-ciclo-vida-pdb` §5-§6 y `CDB_CONTAINER_DATA` (`C##OPS_RO` CDB$ROOT + FREEPDB1; `C##LAB4_AUDITOR` solo CDB$ROOT).

**19. ¿Qué ventaja tiene GRANT READ ANY TABLE ON SCHEMA frente a conceder tabla por tabla? ¿Y qué riesgo?**
Ventaja: una sola sentencia cubre **todas las tablas presentes y futuras** del esquema, sin mantenimiento; tabla por tabla hay que repetir el `GRANT` con cada tabla nueva y es fácil olvidarse, con lo que el informe falla meses después. Riesgo: el privilegio es **automático y sin revisión**; si mañana ese esquema guarda una tabla sensible (nóminas, datos de salud), la auditora ya la puede leer. Se gobierna separando los datos sensibles en otro esquema o revisando el grant cuando cambie el modelo.
Evidencia: Parte I.2 — el grant abrió las 3 tablas de `ADMIN_ACADEMIA`, dejó `ADMIN_CLINICA` en `ORA-00942` y el `UPDATE` en `ORA-41900`.

**20. ¿Qué valor tiene COMMON_USER_PREFIX en tu base y qué consecuencia tuvo en el bloque 3a de 10-ciclo-vida-pdb?**
Vale **`C##`**. Consecuencia: en el bloque 3a, `CREATE USER lab4_local` desde `CDB$ROOT` falló con **ORA-65096** («common user or role name must start with prefix C##»), porque en la raíz solo se crean usuarios comunes y deben llevar el prefijo; en la PDB sí se creó el usuario local. El script contempla el caso contrario (prefijo vacío) por si la imagen cambia.
Evidencia: `10-ciclo-vida-pdb` §3a.

### Archivos (J)

**21. Clasifica los archivos de tu evidencia 11 en "son la base de datos" y "relacionados". ¿Dónde va el password file y por qué?**
- **Son la base de datos:** los **16 datafiles** (4054 MB), los **2 control files** (36 MB) y los **3 redo online** (600 MB). Los 3 tempfiles no: TEMP se recrea vacío.
- **Relacionados:** **SPFILE** (3584 B), **password file** (2048 B), **5 redo archivados** (628 MB, imprescindibles para recuperar en ARCHIVELOG), `init.ora`, `listener.ora`, `sqlnet.ora`, `tnsnames.ora` y el ADR (alert log y trazas).
- **El password file va en «relacionados»:** guarda los usuarios con `SYSDBA`/`SYSOPER` y el hash de su contraseña **fuera** de la base. Sin él no hay acceso administrativo remoto, pero no contiene datos ni participa en la recuperación; RMAN no lo respalda y hay que copiarlo aparte.
Evidencia: `11-archivos-so` §1-§2 y `V$PWFILE_USERS` (solo `SYS`).

**22. Explica por qué academia01.dbf mide 104 865 792 bytes en Linux si v$datafile dice 100 MB.**
Porque los «100 MB» de Oracle son **100 MiB** = 104 857 600 bytes, y Oracle añade **un bloque de 8 KB** para la cabecera del archivo (bloque 0): 104 857 600 + 8 192 = **104 865 792**. No es un archivo más grande de lo pedido: es el redondeo a MiB más el bloque de cabecera.
Evidencia: `11-archivos-so` (`104865792 bytes /opt/oracle/oradata/FREE/FREEPDB1/academia01.dbf`) frente a los 100 MB de `DBA_DATA_FILES`.

**23. ¿Qué dos puntos únicos de fallo (single points of failure) ves en los control files y en el redo de tu base?**
1. Los **dos control files** están en el **mismo volumen** (`/opt/oracle/oradata/FREE/`): son dos copias, pero si se pierde el volumen se pierden las dos a la vez.
2. Los **3 grupos de redo tienen un solo miembro** cada uno y también en ese volumen: no hay multiplexación; un fallo del volumen deja la instancia sin redo.
Es el hallazgo #2 de la autopsia, prioridad **alta**; la acción es multiplexar en volúmenes distintos (Lab 5).
Evidencia: `11-archivos-so` (`control01.ctl` y `control02.ctl` en `FREE/`; `redo01-03.log` de 200 MB, un miembro cada uno) y autopsia §4.

**24. ¿Por qué el ADR fuera del volumen es un problema operativo aunque la base no pierda datos?**
Porque `/opt/oracle/diag` vive en la **capa del contenedor**, no en el volumen: al recrear el contenedor se pierden el alert log y las 220 trazas (29 MB). La base sigue con sus datos, pero se pierde la **historia del incidente**, que es justo lo que se necesita para el postmortem y para las alertas de los últimos días. Acción: `diagnostic_dest` en almacenamiento persistente o centralización de logs.
Evidencia: `11-archivos-so` §3-§4 y autopsia #3 (prioridad media).

### Bloque y fila (K)

**25. Descompón el ROWID de tu estudiante 101 en objeto, bloque y fila, y comprueba cada trozo con DBMS_ROWID.**
ROWID `AAAR2mAAAAAAAMPAAF`:
- **Objeto** `AAAR2m` → base 64 = **73 126**; `DBMS_ROWID.ROWID_OBJECT` = 73 126 = `DATA_OBJECT_ID` de `ADMIN_ACADEMIA.ACA_ESTUDIANTES`.
- **Archivo** `AAA` = 0 (relativo de BIGFILE); `ROWID_TO_ABSOLUTE_FNO` = **16** → `academia01.dbf`.
- **Bloque** `AAAAMP` = **783**; `ROWID_BLOCK_NUMBER(..., 'BIGFILE')` = 783.
- **Fila** `AAF` = **5**; `ROWID_ROW_NUMBER` = 5.
Evidencia: `12-bloque` y `12-reto-rowid-bigfile` (`783 / 783 / 783` en las tres decodificaciones).

**26. Del volcado: ¿qué significan nrow, fsbo, fseo y avsp? Demuestra que avsp = fseo - fsbo con tus números.**
`nrow` = filas del bloque (**90**); `fsbo` = primer byte libre tras la cabecera y el directorio (`0xc6` = 198); `fseo` = fin del espacio usado (`0x427` = 1063); `avsp`/`tosp` = espacio disponible dentro del bloque (`0x361` = **865**). Comprobación: `0x427 - 0xc6 = 0x361 = 865`. Son 865 de 8192 = **10,6 %**, justo el hueco que reserva `PCTFREE 10` para que crezcan las filas.
Evidencia: `evidencia/config/20261025T170224Z_12-volcado-bloque.trc.txt`.

**27. Explica la línea de la ITL con Lck = 90 y Flag --U-. ¿Qué es la limpieza diferida de bloques (delayed block cleanout)?**
La ranura 0x01 de la ITL conserva la transacción de V002 con `Flag --U-` (confirmada, *upper bound*) pero `Lck 90`: las 90 filas siguen marcadas con el bloqueo de esa transacción. El `COMMIT` no recorrió los bloques: solo escribió el SCN de confirmación en el undo. La **limpieza diferida** es que la primera operación que toque el bloque (una lectura consistente o un `UPDATE`) comprobará en el undo que la transacción terminó, borrará las marcas (`Lck` → 0) y dejará la ITL limpia; ese trabajo puede generar redo aunque la sentencia sea un `SELECT`.
Evidencia: volcado del bloque 783 (ITL 0x01 `--U-`, `Lck 90`) y volcado de `MIGRA`, donde el `UPDATE` hace la *cleanout* (ITL 0x01 `C---`, `Lck 0`).

**28. Calcula los 78 bytes de la fila 101 a partir de cabecera, bytes de longitud y datos.**
`tl: 78` = **3 bytes de cabecera** de fila (flag de estado + ITL/`cc`/`lb` empaquetados) + **7 bytes de longitud** (uno por columna: `cc: 7`, de un byte cada uno porque ningún dato llega a 250 bytes) + **68 bytes de datos** (`VSIZE` de la fila 101). 3 + 7 + 68 = **78**. En el bloque ocupa **80** porque el directorio de filas añade 2 bytes por fila. `lb: 0x1` es el byte de bloqueo: apunta a la ranura 1 de la ITL, la de la transacción que insertó la fila.
Evidencia: volcado 783, `tab 0, row 5, @0x1cda`, `tl: 78 fb: --H-FL-- lb: 0x1 cc: 7`; `VSIZE` = 68.

### Capacidad y coste (L)

**29. Calcula bfr y b de ACA_ESTUDIANTES con la fórmula de la Unidad 3 y explica por qué la tabla real tiene 244 bloques.**
`bfr = floor((8192 − 96) · (1 − 0,10) / 76) = floor(95,87) = 95` filas/bloque; `b = ceil(20 000 / 95) = 211` bloques. Con la cabecera de Oracle (122) y R+2: 93 y 216. La tabla real tiene **244** bloques bajo la HWM (**231** con filas) porque:
- la fila ocupa 78-80 bytes reales, no los 76 de media, y `AVG_ROW_LEN` es una media (de 68 a 95 filas por bloque);
- cada bloque gasta ITL y 2 bytes de directorio por fila;
- el segmento se llena por extensiones (AUTOALLOCATE), y quedan **13 bloques FS4** formateados y vacíos por delante de la HWM.
Evidencia: `13-capacidad`, `DBA_TABLES` (`BLOCKS` 244, `AVG_ROW_LEN` 76) y `DBMS_SPACE` (230 FULL + 1 FS2 + 13 FS4).

**30. Con tus cifras de 5a, 5b y 5c, ¿cuánto cuesta una lectura lógica, una física aleatoria y un bloque secuencial?**
- **Lógica: 2,1 µs** (400 000 lecturas lógicas en 840 ms de CPU).
- **Física aleatoria: 10,8 µs** (5464 lecturas en 59,1 ms con la caché vacía; es una cota superior porque parte la sirve la caché de páginas de Linux).
- **Bloque secuencial: 7,0 µs** (1171 MB/s → 8192 B / 1171 MB/s).
La aleatoria cuesta ~5 veces la lógica y ~1,5 veces la secuencial; por eso un índice solo compensa si evita casi todas las lecturas.
Evidencia: `13-capacidad`, secciones 5a-5c.

**31. Recalcula el umbral de rentabilidad de la sección 5d suponiendo un HDD (Bw = 150 MB/s, lat = 5 ms).**
`c_sec = 8192 B / 150 MB/s = 54,6 µs`; `c_aleat = 5 ms = 5000 µs`; cociente `54,6 / 5000 = 0,0109`. Con `bfr = 86` filas/bloque (medido): umbral `= (1/86) · 0,0109 = 0,000127 = **0,013 %**`, aproximadamente **1 fila de cada 7900**. Con SSD el umbral era **0,72 %**: en HDD el índice deja de compensar mucho antes, con el mismo método y otro hardware.
Evidencia: mis 86,6 filas/bloque de media (Parte L) y la fórmula de la Unidad 3.

**32. ¿Por qué la "lectura física" sale en microsegundos en el contenedor? ¿Invalida eso el método?**
Porque el «disco» es el del anfitrión (SSD/NVMe) y, sobre todo, la **caché de páginas de Linux** sirve muchas de esas lecturas: Oracle las cuenta como físicas porque no estaban en su buffer cache, pero no llegan al dispositivo. De ahí 10,8 µs en vez de los 5-10 ms de un HDD. **No invalida el método**: lo que decide es el **cociente** `c_sec/c_aleat` medido en el mismo hardware, y el resultado es una cota inferior (mejor caso). Al recalcular con HDD (pregunta 31) el mismo método da otro umbral.
Evidencia: `13-capacidad` §5b-5d.

### Filas migradas y encadenadas (M)

**33. Diferencia migración (row migration) y encadenamiento (row chaining): causa, cómo se detecta y cómo se cura.**
- **Migración:** la fila **cabía** en su bloque, pero un `UPDATE` la hizo crecer y no había hueco (`PCTFREE 0`); Oracle la muda a otro bloque y deja en el original una cabeza con `nrid`. Se detecta con `CHAIN_CNT` (`ANALYZE ... LIST CHAINED ROWS`), con `table fetch continued row` y en el volcado (`fb: --H-----`). Se cura con `ALTER TABLE ... MOVE ONLINE PCTFREE 20` y rebuild del índice.
- **Encadenamiento:** la fila **no cabe en ningún bloque** (12 000 B en bloques de 8 KB); Oracle la parte desde el `INSERT`. Se detecta igual (`CHAIN_CNT`, `ANALYZE`), pero **no se cura con MOVE**: hace falta un tablespace de bloques mayores o rediseñar la tabla.
Evidencia: `14-filas-migradas` §1-§7 (`MIGRA`: `CHAIN_CNT` 0 → 1000 → 0 tras curar; `ANCHA`: `CHAIN_CNT` 1 que no desaparece).

**34. Explica el 3,2 de lecturas lógicas por búsqueda de la sección 4 a partir del 20 % de filas migradas.**
De las 1000 búsquedas por clave, **200** (20 %) caen en filas migradas y **800** en normales. Una normal cuesta **3** lecturas lógicas (raíz + hoja del índice + bloque de tabla); una migrada cuesta **4** (la cuarta sigue el `nrid` hasta el bloque nuevo). Media: `(800 · 3 + 200 · 4) / 1000 = (2400 + 800) / 1000 = **3,2**`. Es un 7 % más de trabajo en cada acceso, y no desaparece solo.
Evidencia: `14-filas-migradas` §3 (`table fetch continued row` +200, lecturas lógicas +3200).

**35. ¿Por qué ALTER TABLE ... MOVE deja el índice UNUSABLE? ¿Qué harías en producción?**
Porque `MOVE` reescribe las filas en bloques nuevos y **cada fila cambia de ROWID**; el índice sigue apuntando a los ROWID viejos, así que Oracle lo marca `UNUSABLE` para no devolver resultados incorrectos (y las consultas por clave fallan o van por otro camino). En producción: `ALTER TABLE ... MOVE ONLINE` (no bloquea el DML y mantiene los índices válidos) o, si ya se hizo el `MOVE` clásico, `ALTER INDEX ... REBUILD` (o `REBUILD ONLINE`) en ventana de mantenimiento.
Evidencia: tras `MOVE PCTFREE 20`, `PK_MIGRA` quedó UNUSABLE y volvió a VALID con `REBUILD` (`14-filas-migradas` §7).

### Autopsia y trabajo profesional (N, O)

**36. Elige tres hallazgos de tu autopsia (15) y escribe para cada uno riesgo, acción y prioridad.**

| # | Hallazgo | Riesgo | Acción | Prioridad |
|---|---|---|---|---|
| 2 | Control files y redo en un solo volumen, un miembro por grupo | Perder el volumen deja la base sin control files ni redo: parada con pérdida | Multiplexar control files y redo en volúmenes distintos | Alta |
| 1 | ARCHIVELOG sin FRA; los archivados van al volumen de datos | Sin retención ni borrado automático; si el volumen se llena, la base se detiene | Configurar FRA con tamaño y retención | Media |
| 3 | ADR (`/opt/oracle/diag`) fuera del volumen | Al recrear el contenedor se pierden alert log y trazas: no hay postmortem | `diagnostic_dest` persistente o centralizar los logs | Media |

Evidencia: `docs/bitacora/lab4-autopsia.md`, tabla de hallazgos y plan de acción.

**37. ¿Por qué C##OPS_RO y no SYSTEM para observar? ¿Qué no puede hacer C##OPS_RO?**
Porque `SYSTEM` es una cuenta de administración con privilegios amplios y contraseña: usarla para leer convierte cada consulta en una oportunidad de daño y obliga a distribuir un secreto. `C##OPS_RO` es un usuario **común de solo lectura**, con `SELECT_CATALOG_ROLE`, `CONTAINER_DATA = ALL` y un `SELECT` puntual sobre `V_$DIAG_ALERT_EXT`. **No puede** escribir (`CREATE TABLE` → `ORA-01031`), leer tablas de negocio (`ORA-00942`), cambiar parámetros, crear o borrar usuarios ni parar la instancia.
Evidencia: Parte B, `11-ampliar-ops-ro.sql` y J.1.

**38. ¿Qué dos vías de exposición de contraseñas corrige este laboratorio respecto al Lab 3?**
1. **Contraseñas literales de los cinco `ADMIN_*` en V000**, versionadas en Git. V003 las convierte en cuentas *schema-only* (`NO AUTHENTICATION`): la credencial deja de existir, y un login da `ORA-01017`.
2. **`sys/<contraseña>` en la línea de comandos** de `08-aplicar-migraciones.sh`, visible con `ps` y en el historial del shell. La versión 2 usa **autenticación del sistema operativo** (`/ as sysdba`) y pasa el SQL por entrada estándar; no hay contraseña en ninguna parte.
Además, las credenciales de las cuentas de operación viven en `config/.env` (ignorado por Git), `.env.example` deja `OPS_RO_PWD=""`, y el control O.2 confirmó **0 apariciones** de las contraseñas en archivos e historia.
Evidencia: A.4 (puntos 1-2), `V003`, `08-aplicar-migraciones.sh` v2, `.gitignore` y O.2.

## Preguntas tipo examen adicionales (P25–P46)

### P25 — Contenedor plantilla de solo lectura
**Respuesta: B. PDB$SEED.**
Es el contenedor de solo lectura que Oracle usa como plantilla para crear PDB nuevas (`CREATE PLUGGABLE DATABASE ... FROM PDB$SEED`). En mi base ocupa 810 MB y está en `READ ONLY`; `FREEPDB1` es una PDB de trabajo y `CDB$ROOT` es la raíz, no una plantilla.

### P26 — `CREATE USER c##rep` desde FREEPDB1
**Respuesta: C. ORA-65094: invalid local user or role name.**
Dentro de una PDB, un nombre que empieza por el prefijo común (`C##`) está reservado para usuarios comunes y no vale como usuario local: Oracle rechaza la creación con `ORA-65094`. El `ORA-65096` es el error simétrico, al crear en la raíz un usuario sin prefijo (lo vi en el bloque 3a de `10-ciclo-vida-pdb`).

### P27 — Eliminar una PDB abierta con sus archivos
**Respuesta: B. `ALTER PLUGGABLE DATABASE p CLOSE IMMEDIATE;` y después `DROP PLUGGABLE DATABASE p INCLUDING DATAFILES;`.**
No se puede borrar una PDB abierta: probé el `DROP` directo y dio **ORA-65025**. Hay que cerrarla primero y luego borrarla indicando `INCLUDING DATAFILES` para que Oracle elimine también los archivos (la carpeta quedó vacía y se borró).

### P28 — Vistas que responden en MOUNT
**Respuesta: A y C. `V$DATAFILE` y `V$LOG`.**
En MOUNT ya se han leído los control files, y las vistas fijas `V$` se alimentan de esa información. `DBA_DATA_FILES`, `DBA_USERS` y `CDB_TABLESPACES` son vistas del diccionario y exigen OPEN (en MOUNT dan `ORA-01219`).

### P29 — Prefijo `KCC` en `X$KCCLE`
**Respuesta: A. Que los datos salen del control file.**
El prefijo `KCC` identifica las estructuras del *kernel cache control file*; `X$KCCLE` son las entradas del redo log leídas del control file, y por eso `V$LOG` responde en MOUNT. No tiene relación con el SPFILE ni con el diccionario.

### P30 — Dónde se definen las vistas `CDB_`
**Respuesta: B. En CDB$ROOT y en cada PDB; desde una PDB solo devuelven sus propias filas.**
Son vistas del diccionario comunes, presentes en todos los contenedores, pero filtran por el contenedor actual: en `FREEPDB1`, `CDB_TABLESPACES` devolvió solo sus 10 tablespaces, y desde la raíz con `CONTAINER_DATA = ALL` devolvió 15 (5 de la raíz + 10 de la PDB, sin la semilla).

### P31 — Tempfiles
**Respuesta: B. No se respaldan: se recrean si se pierden.**
Los tempfiles contienen datos temporales de ordenaciones y `HASH JOIN`; no hace falta recuperarlos. RMAN no los incluye en la copia y, tras una restauración, se recrean con `ALTER TABLESPACE TEMP ADD TEMPFILE`. En mi inventario son 3 archivos de 20 MB.

### P32 — Borrado del SPFILE con la base abierta
**Respuesta: B. La instancia sigue funcionando; puede recrearlo con `CREATE SPFILE FROM MEMORY`.**
Los parámetros ya están cargados en memoria; el archivo solo se necesita al arrancar. `CREATE SPFILE FROM MEMORY` lo reescribe con los valores actuales. No se cae la instancia, no hay que restaurar la base y los datafiles no se ven afectados.

### P33 — Vista del password file
**Respuesta: B. `V$PWFILE_USERS`.**
Lista los usuarios del password file con sus privilegios (`SYSDBA`, `SYSOPER`, `SYSBACKUP`...). En mi base devuelve una sola fila: `SYS` con `SYSDBA` y `SYSOPER`. `DBA_USERS` ve la cuenta pero no el privilegio del password file.

### P34 — Cabecera de un bloque de datos
**Respuesta: A y B. La ITL y el directorio de filas.**
La cabecera incluye el estado del bloque, el SCN, la ITL (`itc: 2`) y el directorio de filas (`nrow`, `fsbo`, `fseo`); los datos empiezan después (`avsp`). El texto SQL, la contraseña del propietario y el plan de ejecución no se guardan en el bloque de datos.

### P35 — Crecimiento con AUTOALLOCATE y bloques de 8 KB
**Respuesta: B. Extensiones de 64 KB (8 bloques) y, al crecer, de 1 MB.**
Con AUTOALLOCATE Oracle empieza con extensiones pequeñas de 8 bloques (64 KB) y las agranda: en `ACA_ESTUDIANTES` medí **16 extensiones de 8 bloques y una de 128 bloques (1 MB)**. No es un tamaño fijo ni depende de PCTFREE.

### P36 — `SEGMENT_SPACE_MANAGEMENT = AUTO`
**Respuesta: B. Que el espacio libre de los bloques se gestiona con mapas de bits (ASSM).**
ASSM lleva el espacio libre de cada bloque en mapas de bits dentro del propio segmento, en lugar de listas de espacio libre del diccionario. En mi base, `TBS_ACADEMIA` aparece con `SEGMENT_SPACE_MANAGEMENT = AUTO`. No tiene que ver con el crecimiento de los datafiles ni con los índices.

### P37 — `CREATE TABLESPACE t DATAFILE ... SIZE 100M` en 23ai
**Respuesta: B. BIGFILE gestionado localmente.**
Desde 23ai el valor por defecto es **BIGFILE** y la gestión de extensiones es **LOCAL** (AUTOALLOCATE), con ASSM. Lo comprobé: los cinco tablespaces de negocio son BIGFILE, LOCAL y `SEGMENT_SPACE_MANAGEMENT = AUTO`. No es SMALLFILE ni TEMPORARY/UNDO.

### P38 — 4 lecturas lógicas y 0 físicas
**Respuesta: A. Todos los bloques estaban en la buffer cache.**
Las lecturas lógicas se cuentan en la caché; las físicas solo cuando el bloque no está y hay que ir al disco. Cero físicas con 4 lógicas significa que los 4 bloques estaban ya en memoria (fue lo que pasó en la ronda 2 del experimento: 247 lógicas y 0 físicas). No dice nada del uso de índices ni implica un fallo.

### P39 — Qué reduce el factor de bloqueo
**Respuesta: A y B. Aumentar PCTFREE y aumentar el tamaño medio de fila.**
`bfr = floor((B − H) · (1 − PCTFREE/100) / R)`: más `PCTFREE` deja menos espacio útil, y más `R` hace que quepan menos filas. Un índice no cambia el bloque y recoger estadísticas solo mejora la estimación, no el tamaño real. Aumentar el bloque lo aumentaría, no lo reduciría.

### P40 — `FLUSH BUFFER_CACHE` en producción
**Respuesta: B. Todas las sesiones pasan a leer de disco hasta recalentar la caché: picos de latencia.**
El comando vacía la buffer cache de toda la instancia, no de una sesión. En mi experimento el acierto de caché de la instancia cayó al **88,3 %**. No pierde datos (solo ensucia bloques limpios) ni reinicia la instancia, pero provoca E/S masiva y lentitud para todos.

### P41 — Fila migrada frente a encadenada
**Respuesta: B. La migrada cabía en un bloque y se mudó al crecer; la encadenada no cabe en ningún bloque.**
Es exactamente lo medido: `MIGRA` (filas de 9 bytes que crecieron a 300 con `PCTFREE 0`) generó 1000 migradas y se curó con `MOVE`; `ANCHA` (12 000 bytes) quedó encadenada y el `MOVE` no la arregla. No son sinónimos ni tienen que ver con índices o IOT.

### P42 — Índice `UNUSABLE` tras `MOVE`
**Respuesta: A. `ALTER INDEX ... REBUILD` (o haber usado `MOVE ONLINE`).**
El `MOVE` cambia los ROWID de todas las filas y deja el índice apuntando a direcciones antiguas; Oracle lo marca `UNUSABLE`. `COALESCE` solo fusiona hojas, las estadísticas no reparan la estructura y vaciar la shared pool no toca el índice. Lo vi con `PK_MIGRA`: UNUSABLE tras el `MOVE` y VALID tras el `REBUILD`.

### P43 — Leer el alert log con SQL
**Respuesta: A. `V$DIAG_ALERT_EXT`.**
Es la vista externa sobre el XML del alert log; en la Parte J concedí `SELECT ON sys.v_$diag_alert_ext` a `C##OPS_RO` y desde entonces puede leerlo sin acceso al sistema de archivos. `DBA_ALERT_HISTORY` es el historial de alertas, no el log; `V$DIAG_INFO` solo da rutas.

### P44 — Tablespace al 92 % de su tamaño máximo
**Respuesta: A y B. Ampliar (datafile o `MAXSIZE`) y revisar qué segmentos crecen y por qué.**
Primero se entiende el crecimiento y después se decide: añadir espacio o subir `MAXSIZE` da margen, pero si un segmento crece sin control hay que corregirlo. Borrar redo, pasar a NOARCHIVELOG o reiniciar no liberan espacio de datos y sí destruyen capacidad de recuperación.

### P45 — Elementos compartidos por todas las PDB
**Respuesta: A y B. La SGA y los procesos de background, y el conjunto de online redo logs.**
Una CDB es una sola instancia: memoria y procesos son únicos, y el redo también (`V$LOG` devuelve 3 filas con `CON_ID 0`). Cada PDB tiene su `SYSTEM` (`CDB_TABLESPACES` da 15 = 5 + 10) y sus usuarios locales; en 23ai el undo es **local por PDB** por defecto, así que tampoco es común «siempre».

### P46 — `SET CONTAINER` desde una PDB sin privilegios
**Respuesta: B. `ORA-01031: insufficient privileges`.**
Un usuario local solo tiene la llave de su PDB: `ALTER SESSION SET CONTAINER = CDB$ROOT` le devuelve `ORA-01031` (lo probé en la Parte I). No cambia de contenedor ni se desconecta; el error es de privilegio, no de sintaxis (`ORA-65040` es otro caso: operación no permitida desde una PDB).
