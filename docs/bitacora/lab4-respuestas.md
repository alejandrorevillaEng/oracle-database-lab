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
