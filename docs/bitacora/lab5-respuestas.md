# Lab 5 — Respuestas

Evidencias en `docs/bitacora/lab5/evidencia/` (se citan por el número de evidencia y el valor que lo demuestra).
Todas las cifras son de mi ejecución del 27 de octubre de 2026, no del enunciado.

## Notas de mi entorno

- La base ya estaba en **ARCHIVELOG** antes de empezar (lo vi en `05-instancia-y-base.sql` y en el paso 2 de la copia: `log_mode=ARCHIVELOG`), con el destino de archivado por defecto (`arch1_<seq>_<id>.dbf`). En la Parte L `11-activar-archivelog.sh` detectó el modo, no reinició, y movió el archivado a la FRA de 4 GB (desde entonces los nombres son OMF: `o1_mf_1_<seq>_….arc`).
- Mis grupos de redo son de **200 MB** (el guion habla de 20 MB), por eso hay menos cambios de log por hora.
- `CLIENTE` salió con 1517 bloques y 102 bytes por fila (el guion: 1467 y 98). `PEDIDO` coincide exactamente (5320 bloques, bfr 188).
- En la Parte L, la primera ejecución de `11-fra-llena.sql` **no** llenó la FRA: estaba vacía (0 MB) y el log archivado (≈1,8 MB) cabía en los 2 MB. La repetí (`*_11-fra-llena-repeticion.script.log`) y ahí sí salieron ORA-19815, ORA-19809 y ORA-16038. Las dos evidencias se conservan.
- Simulacro D: me tocó el camino en que **Oracle cerró la PDB** (ORA-63999).

## Preguntas tipo examen del texto

| Pregunta | Respuesta | Justificación (con mi evidencia) |
|---|---|---|
| B1 | **B** | Sin histograma Oracle supone 1/4 = 25 % por estado; con él (`ESTADO … FREQUENCY`, ev. 01) sabe que P es el 2 %. |
| C1 | **C** (4) | BLEVEL 2 = altura 3 → 3 lecturas de índice + 1 de tabla. Lo medí: `PK_PEDIDO` Buffers = 4 (3 en el índice), ev. 02. |
| C2 | **C** (4) | 1 + ⌈log₅₀₀ 2 000 000⌉ = 1 + ⌈2,33⌉ = 4. |
| D1 | **B** | Bitmaps en columnas de pocos valores y carga nocturna: Q14 4073 → 528 lecturas con `BITMAP AND` (ev. 03). |
| D2 | **A y C** | Cubriente evita la tabla (Q7 7 → 3 lecturas) y encarece las escrituras; no siempre ocupa menos (40 MB frente a 41,6 MB de la tabla) y Oracle no tiene `INCLUDE`. |
| E1 | **B** | CF ≈ filas: el 3 % es muy superior al umbral 1/bfr (≈0,5 %, medido en ev. 04). Un REBUILD no cambia el CF. |
| F1 | **B** | Número contra VARCHAR2 → `TO_NUMBER("CODIGO_POSTAL")` sobre la columna (Q3: 5232 lecturas, ev. 05). |
| F2 | **A y C** | Las dos dejan la columna desnuda y cubren el día completo. |
| G1 | **B** | INVISIBLE: se sigue manteniendo y se vuelve atrás con `VISIBLE`. Lo hice con `IX_PED_IMPORTE` (ev. 06). |
| G2 | **B** (≈1000) | Cada índice suma ≈2 bloques por INSERT (4 índices: 10,1; 5: 12,1) → 500 × 2 = 1000 bloques/s. |
| H1 | **B** | COALESCE en línea: la "siguiente fila" pasó de 226 a 2 lecturas (ev. 07). |
| H2 | **A y C** | Reparte la hoja caliente, pero un rango sobre REVERSE hizo `TABLE ACCESS FULL`: 878 lecturas frente a 4 (ev. 07). |
| I1 | **B** | SCN de checkpoint del control file frente al de la cabecera (ev. 08: 5410252 = 5410252, "sincronizado"). |
| J1 | **B** | La instancia no puede seguir sin una copia; se sustituye por una sana o se quita de `CONTROL_FILES`. |
| J2 | **A y C** | Nombres y rutas de datafiles y redo, y el SCN de checkpoint (secciones `DATAFILE`, `REDO LOG`, ev. 09). |
| K1 | **C** | ACTIVE: aún no cubierto por un checkpoint, se necesita para la recuperación de instancia (grupo 3, ev. 10). |
| L1 | **B** | Lo vi en ev. 11: `ORA-19802: cannot use DB_RECOVERY_FILE_DEST without DB_RECOVERY_FILE_DEST_SIZE`. |
| L2 | **A y C** | Más tamaño (lo que hizo el script: 2 MB → 4 GB) o copia y borrado con RMAN; nunca `rm` ni NOARCHIVELOG en caliente. |
| M1 | **C** | B vio ACTIVO mientras A ya lo había cambiado a EGRESADO (ev. 12, paso 1). |
| M2 | **C** | DELETE: 427 bloques de undo (3416 KB) frente a 140 del INSERT y 158 del UPDATE (ev. 12). |
| M3 | **B y D** | ORA-01555 es falta de undo retenido: más retención y tamaño, o RETENTION GUARANTEE. |
| N1 | **A** | Tras el COMMIT, LGWR escribió (3 escrituras, 1779 KB) y DBWn 0 bloques (ev. 13). |
| N2 | **B y C** | DBWn escribió 348 bloques en el CHECKPOINT, no en el COMMIT (ev. 13). |
| O1 | **B** | Simulacro A: abrió solo, el alert log muestra `Beginning crash recovery` … `Completed crash recovery` (ev. 14a). |
| O2 | **B y D** | Lo que hizo el simulacro B: copiar `control01.ctl` sobre `control03.ctl`; la alternativa es quitarla de `CONTROL_FILES`. |
| O3 | **B** | OFFLINE → RESTORE → RECOVER → ONLINE (en mi caso la PDB ya estaba MOUNTED y se abrió al final). |
| O4 | **D** | `PURGE` vacía la papelera (A no sirve); restaurar toda la base (B) pierde lo demás; C es Flashback Query, no recupera un DROP. RMAN `RECOVER TABLE` sí. |

## Puntos de control

**Antes de la durabilidad (fin de la Parte H).** PK cuesta 4 lecturas porque la altura es 3 + 1 bloque de tabla (ev. 02). `IX_PED_CLIENTE` pierde al 1 % porque con CF malo cada fila es un bloque distinto: 9920 lecturas frente a 5232 de la tabla (ev. 04). Q3 no usaba el índice por la conversión implícita `TO_NUMBER` (ev. 05). Cada índice cuesta ≈2 bloques por INSERT (ev. 06). La cola leía **226** bloques para una fila porque recorría 224 hojas vacías (ev. 07).

**Parte I.** `PDB$SEED` está en READ ONLY: no recibe checkpoints y se queda en 2098101. `ACTUAL_REDO_BLKS = 407 263` viene de la carga de TiendaSur y de las pruebas de índices (B a H). `ESTIMATED_MTTR = 40 s`; con diez veces más carga crecería, y lo acota `FAST_START_MTTR_TARGET`, que en mi base está a **0** (sin objetivo: los checkpoints solo dependen de los cambios de log y de `log_checkpoint_timeout = 1800`).

**Parte L.** Aparecen ARC0–ARC3 porque la base archiva (ARCHIVELOG). En mi base ya existían, porque ya estaba en ARCHIVELOG; lo nuevo es que ahora archivan en la FRA con nombres OMF (`o1_mf_1_17_og1r16yf_.arc`), mientras que los anteriores eran `arch1_16_1237845575.dbf`.

**Parte M.** Paso 1: el valor ACTIVO sale del **undo** (B reconstruye una versión consistente del bloque). Paso 4: leer no pide bloqueo; `FOR UPDATE` pide el bloqueo TX de la fila, que tiene A (modo 6) → ORA-00054. Paso 6: el valor antiguo sigue en el undo hasta que se reutiliza; lo limita `UNDO_RETENTION` (900 s).

**Parte N.** Tras el COMMIT, **0** bloques escritos por DBWn y 231 bloques sucios de la tabla: la garantía está en el redo online. DBWn escribe 348 en el checkpoint (más que 231) porque también vuelca bloques de undo y de toda la instancia. El UPDATE "sin cambio" generó 1779 KB de redo: Oracle no compara valores antes de escribir.

**Simulacro B.** Se detiene al **montar** (ORA-00205): NOMOUNT solo necesita el SPFILE, y montar es abrir los control files. Basta copiar otra copia porque, con la base parada, las tres son idénticas; abierta cambian continuamente y una copia en caliente sería inconsistente. Con las tres perdidas: `RESTORE CONTROLFILE FROM AUTOBACKUP` (el autobackup existe desde el simulacro D) + `RECOVER` + `OPEN RESETLOGS`, o el script `CREATE CONTROLFILE` de la Parte J.

**Simulacro D.** ORA-01116 dice qué número de archivo (16), ORA-01110 qué ruta (`academia01.dbf`) y ORA-27041 + `Linux Error 2: No such file or directory` la causa en el sistema operativo. Me tocó el camino de la **PDB cerrada** (ORA-63999 a las 17:40): un proceso de fondo intentó escribir en el archivo antes que mi consulta. La fila 104 salió EGRESADO porque `RECOVER` aplicó el redo posterior a la copia. RTO C 76 s frente a D 10 s; RPO C = todo lo posterior a la copia, D = 0.

**Bloque 5 del runbook.** Ver la pregunta 22.

## Preguntas de comprobación

### Punto de partida y banco de medida (A, B)

**1.** En mi copia `lab4-final` (ev. 00) el paso 6 dice "ninguno". En la de `lab3-final` (`lab4/evidencia/script/…_00-backup-lab3.script.log`) también dice "ninguno". En mi entorno `$ORACLE_HOME/dbs` es un enlace simbólico al volumen, y por eso salían "dentro". La diferencia real está en el paso 2: en Lab 3 los cinco datafiles de negocio estaban en `/opt/oracle/product/26ai/dbhomeFree/dbs/academia01.dbf`; en Lab 4 están en `/opt/oracle/oradata/FREE/FREEPDB1/academia01.dbf`. Demuestra que la reubicación del Lab 4 los llevó a la ruta estándar del volumen, sin depender de un enlace.

**2.** bfr = r / b. `CLIENTE` 100 000 / 1517 = **66**; `PEDIDO` 1 000 000 / 5320 = **188** (ev. 01). PEDIDO cabe casi el triple (188 / 66 = 2,85) porque su fila mide 32 bytes frente a 102 de CLIENTE (102 / 32 ≈ 3,2): seis columnas cortas (números, fecha, dos `CHAR(1)`) frente a DNI, email, nombre, apellidos, teléfono y ciudad. Comprobación: ⌈100 000 / 66⌉ = 1516 ≈ 1517 medidos.

**3.** La primera ejecución incluye trabajo que solo ocurre una vez: el análisis (parse), traer bloques a la caché y la limpieza diferida de bloques tras la carga (delayed block cleanout). Lo vi en ev. 02: el script descarta la primera ejecución y la segunda da los 4 buffers exactos de la teoría. Midiendo la segunda se compara el trabajo estable, en caliente.

### Anatomía y tipos de índice (C, D)

**4.** `IX_PED_CLIENTE` (ev. 02): altura **3**, **2216** hojas, 6 ramas, fan-out real (2216 + 6 − 1) / 6 = **370** y máximo 8028 / 14,8 = **543**. Llenado 451 de 503 entradas por hoja (90 %, `PCTFREE 10`). Con mil millones de filas: 2 208 969 hojas → **altura 4**, 5 lecturas para una fila.

**5.** Hoja de `PK_CLIENTE` (ev. 02), `row#0`: `data:(6): 00 00 03 1b 00 00` y `col 0: c1 02`. Los 4 primeros bytes son el bloque `0x0000031B = 795` y los 2 últimos la fila (ranura) `0`. La clave `c1 02` es el número 1, y la comprobación del script confirma que el cliente 1 está en el bloque 795, ranura 0. No aparece el número de archivo porque `tbs_tiendasur` es **bigfile**: un solo datafile por tablespace, y el índice solo guarda el ROWID restringido dentro de su tablespace.

**6.** (ev. 03)
- **Único (Q13):** 1486 lecturas con recorrido completo frente a **3** con `UX_CLI_DNI`. Además impide el duplicado: ORA-00001 + ORA-03301 con el valor `00004711L`.
- **Compuesto y cubriente (Q7):** 15 lecturas + `SORT ORDER BY` con `IX_PED_CLIENTE`; 7 con `(id_cliente, fecha)` porque devuelve las filas ya ordenadas (`RANGE SCAN DESCENDING`, sin SORT); **3** con el cubriente, que no toca la tabla.
- **Hash frente a IOT (Q15):** búsqueda por token: montículo + PK 4, IOT 3, clúster hash **1** (la clave es la dirección del bloque). Pero la limpieza por rango en el hash lee la tabla entera: **2770**. Gana el hash solo si nunca hay rangos.

### Agrupamiento, equilibrio y sargabilidad (E, F)

**7.** (ev. 04) `IX_PED_FECHA` CF = 5220 ≈ 5320 bloques: los pedidos se cargaron en orden (`ORDER BY n`) y la fecha crece con ese orden, así que filas vecinas en el índice son vecinas en disco. `IX_PED_CLIENTE` CF = 999 041 ≈ 1 000 000 filas: el cliente se reparte al azar y cada entrada salta a otro bloque. Calculado a mano coincide exactamente (5220 y 999 041). Un **REBUILD no lo arregla**: el CF depende del orden de las filas en la **tabla**, no del índice. Solo reordenar la tabla (por cliente) lo bajaría, y empeoraría el de fecha.

**8.** (ev. 04)
- **Índice con CF malo:** deja de compensar entre el 0,5 % (4875 frente a 5232) y el 1 % (9920). Es exactamente la fórmula en lecturas lógicas: k / r < 1 / bfr = 1 / 188 = **0,53 %**.
- **Índice con CF bueno:** gana hasta el 50 % (3938) y solo pierde al 100 % (7875 frente a 5232). Lee unas k / bfr hojas y bloques.
- **El optimizador:** cambia a recorrido completo ya en el **0,2 %**. Está más cerca de la fórmula en disco (c_sec / c_aleat = 1/5 → 0,11 %) porque su modelo de coste penaliza la lectura aleatoria y premia la multibloque.

**9.** (ev. 05) Q4b `LIKE 'Gonz%'` es sargable y usa `IX_CLI_APELLIDOS` (`RANGE SCAN`), pero devuelve 2056 filas (2,1 %) y lee **2024** bloques frente a 1523 del recorrido completo (Q4a). Los clientes "Gonz…" están repartidos por toda la tabla (CF malo): cada fila es casi un bloque distinto. El 2,1 % está muy por encima del umbral de 0,53 %. Sargable no significa que el índice sea lo más barato.

### Coste de escritura y mantenimiento (G, H)

**10.** (ev. 06) Bloques modificados por INSERT: **10,1** con 4 índices (hoy), **20,4** con 9 (compañero) y **12,1** con 5 (V005). Rechacé:
- `IX_PED_ESTADO`: 4 valores, 25 % por valor, no viable. Lo sustituye el parcial `IX_PED_PENDIENTES` (54 hojas frente a 2933).
- `IX_PED_CANAL`: 3 valores (33 %) y `USA = NO` en `MONITORING USAGE`.
- `IX_PED_FEC_CLI`: `USA = NO`, y además convertía `IX_PED_FECHA` en redundante.
- `IX_PED_CLI_FEC`: lo sustituye el cubriente `IX_PED_CLI_FEC_CUB` (Q7: 3 lecturas en vez de 7).

Acepté `IX_PED_CP`: Q3 pasa de 5232 a 106 lecturas, 0,009 % por valor. V005 además retira `IX_PED_IMPORTE` (`USA = NO` y, ya INVISIBLE, Q2 siguió en 331 lecturas por `IX_PED_FECHA`) e `IX_PED_CLIENTE` (prefijo de `IX_PED_CLI_FEC_CUB`, que sigue cubriendo la clave ajena).

**11.** (ev. 07, gráficos)
- **50/50, `IX_AZAR`:** 595 divisiones, ninguna 90/10. Ocupación media 75,4 %, histograma repartido entre el 40 y el 99 % y mapa mezclado `=`/`-`.
- **90/10, `IX_CRECIENTE`:** 398 divisiones, todas 90/10. Ocupación 99,9 % y mapa todo `#`. La hoja vieja se queda llena.
- **Patrón cola, `IX_COLA`:** 425 hojas para 100 000 entradas vivas, 224 hojas vacías y mapa `[                                =####…]`: vacío a la izquierda (lo borrado) y lleno a la derecha (lo nuevo).

**12.** `COALESCE` periódico: es en línea, sin bloqueo, y resuelve el síntoma (226 → **2** lecturas, 425 → 201 hojas, ev. 07). `SHRINK SPACE` también es en línea y además devolvió espacio (4 → 1,69 MB), pero el espacio vuelve a hacer falta en una cola. `REBUILD ONLINE` necesita espacio doble y mucho redo, que en ARCHIVELOG llena la FRA. La cura de fondo es de diseño: particionar por fecha y vaciar particiones enteras.

### SCN, control files, redo y FRA (I a L)

**13.** (ev. 08) Compara el SCN de checkpoint del **control file** (`v$database` / `v$datafile.checkpoint_change#`: 5410252) con el de la **cabecera** de cada datafile (`v$datafile_header`: 5410252, "sincronizado"). Tras `ALTER SYSTEM CHECKPOINT` ambos pasaron a 5416721. Si al abrir no coinciden, o el cierre no fue limpio, Oracle aplica redo desde el checkpoint.

**14.** Tres copias en el mismo volumen protegen del borrado o la corrupción de **un archivo**. Es justo el simulacro B: se borró `control03.ctl` y se reparó con `control01.ctl` en unos 10 s. **No** protegen de perder el disco o el volumen, porque las tres caen juntas. En producción cada copia va en un disco y controladora distintos (o en grupos ASM distintos: `+DATA`, `+FRA`), además del autobackup de RMAN.

**15.** (ev. 10)
- **CURRENT:** el grupo en el que escribe LGWR (grupo 1, seq 16, tras el primer cambio).
- **ACTIVE:** ya no se escribe, pero su redo aún no está cubierto por un checkpoint y haría falta en una recuperación de instancia (grupo 3, seq 15).
- **INACTIVE:** ya no hace falta (grupo 2, seq 14) y se puede reutilizar si está archivado.

Rechazos del paso 4:
- **ORA-01623:** no se puede borrar el grupo CURRENT, porque LGWR está escribiendo en él.
- **ORA-01609:** no se puede borrar un miembro del grupo CURRENT.
- **ORA-00350:** el log 1 necesita archivarse antes. Borrarlo rompería la cadena de archivado y dejaría menos de los dos grupos mínimos.

**16.** (ev. 11, repetición) La FRA baja a 2 MB y se genera redo:
1. **ORA-19815**, primero al 91,65 % y después al 100 %. Es el aviso.
2. **ORA-19809** (límite superado). ARCn no puede crear el archivado.
3. **ORA-16038**: "log 3 sequence# 21 cannot be archived". El grupo 3 queda `ARC = NO / ACTIVE`.
4. Cuando LGWR da la vuelta y necesita ese grupo, no puede reutilizarlo: las sesiones esperan en `log file switch (archiving needed)` y las conexiones nuevas reciben **ORA-00257**. La base deja de aceptar cambios.

Al devolver los 4 GB, ARCn reintenta solo: el grupo 3 pasa a `ARC = YES` y la FRA a 10,3 MB.

### Undo, WAL y simulacros (M a P)

**17.** (ev. 12)
1. **Paso 1:** con A ya modificando la fila 101, B la lee sin esperar y ve ACTIVO.
2. **Paso 2:** A consume 1 bloque y 1 registro de undo.
3. **Paso 3:** A tiene un TM en modo 3 sobre la tabla y un TX en modo 6 sobre la fila.
4. **Paso 4:** B solo choca (**ORA-00054**) cuando también quiere escribir (`FOR UPDATE WAIT 3`).

Leer no pide bloqueos y usa el undo para reconstruir la versión confirmada. Por eso los lectores no bloquean a los escritores, ni los escritores a los lectores. Solo se bloquean dos escritores sobre la misma fila.

**18.** (ev. 12) Para deshacer un INSERT basta "borra este ROWID": 140 bloques de undo (1120 KB). Para deshacer un DELETE hay que guardar la **fila entera** y sus entradas en cada índice: 427 bloques (3416 KB), tres veces más. El ROLLBACK genera redo porque deshacer es **aplicar cambios** a bloques de datos e índices, y todo cambio de bloque se protege con redo: el ROLLBACK del DELETE generó 4701 KB.

**19.** (ev. 13) Justo después del COMMIT, LGWR había escrito 1779 KB de redo en 3 escrituras, DBWn **0** bloques, y 231 bloques de la tabla seguían sucios en memoria. La garantía está en el **redo log online** (write-ahead logging). Después del `CHECKPOINT`, DBWn escribió 348 bloques y quedaron 0 sucios: el cambio ya está también en los **datafiles**.

**20.** (ev. 14a) Antes de la caída, la fila 102 quedó EGRESADO **confirmado** y la 103 INACTIVO **sin confirmar**; después vino `SHUTDOWN ABORT`. Al arrancar, el alert log muestra `Beginning crash recovery of 1 threads`, `Recovery starting at checkpoint rba (logseq 23 block 51044), scn 5420259`, `read 10 KB redo, 6 data blocks need recovery` y `Completed crash recovery`.

- **Roll forward:** el redo rehace todos los cambios posteriores al checkpoint, los de 102 y los de 103, también su undo.
- **Roll back:** el undo deshace la transacción no confirmada.

Resultado: 102 = **EGRESADO** (sobrevive) y 103 = **ACTIVO** (deshecho). Nadie intervino.

**21.** Simulacro C: **RTO 76 s**; **RPO** = todo lo hecho entre la copia y el fallo (aquí 2 s, en la vida real desde la última copia en frío). Simulacro D: **RTO 10 s** (9 s desde que se empezó a reparar); **RPO 0**. Son tan distintos porque:

- **En C** se restaura el volumen entero (copia de 1,4 GB) con la base parada, y la copia en frío no permite aplicar redo posterior, así que se pierde lo hecho después.
- **En D** RMAN restaura un solo datafile (copia de 39 MB) y `RECOVER` aplica el redo archivado y el online hasta el último COMMIT.

Recuperación de medios + ARCHIVELOG = RPO 0.

**22.** Bloque 5 de mi runbook (ev. 15):

| Error | Clasificación | Explicación |
|---|---|---|
| ORA-01113 / ORA-01110 file 25 (`tiendasur01.dbf`) a las 17:41 | Efecto del laboratorio (Parte O, D) | Al reabrir la PDB tras el cierre forzado del simulacro D, Oracle pidió recuperar ese archivo; quedó resuelto en la propia apertura (`v$recover_file` vacío, FREEPDB1 READ WRITE). |
| ORA-63999 y ORA-01110 data file 16 (`academia01.dbf`) | Efecto del laboratorio (Parte O, D) | El datafile que borré a propósito. |
| ORA-00202 / ORA-205 (`control03.ctl`) | Efecto del laboratorio (Parte O, B) | La copia del control file que borré a propósito. |
| ORA-00800 `[Set Priority Failed]` (VKTM, LGWR) | Ruido conocido | El contenedor no tiene `CAP_SYS_NICE`; ya lo clasifiqué en el Lab 4. Sale en cada arranque. |

No hay ningún incidente real. Bloque 6: **17 cambios de log** en la hora de las 17 h. No es preocupante, porque casi todos fueron **forzados** (`SWITCH LOGFILE` y `ARCHIVE LOG CURRENT` de las Partes K y L, los arranques de J y O, la copia RMAN del simulacro D), con grupos de 200 MB. En producción, tantos cambios indicarían grupos de redo demasiado pequeños para la carga. Bloque 7: si saliera vacío en producción, hoy mismo haría una copia RMAN completa y abriría una alerta, porque sin copia no hay recuperación de medios.

## Simulacro de examen 1Z0-182

| | Respuesta | Dónde lo comprobé | Justificación |
|---|---|---|---|
| S1 | **B** | Parte E | CF ≈ filas: `IX_PED_CLIENTE` 999 041, un bloque por fila. |
| S2 | **A y C** | Partes D y F | Funcional: 1486 → 4; reescrita `email = LOWER(:e)`: 1486 → 4 sin índice nuevo. |
| S3 | **B** | Parte F | Plan: `filter(TO_NUMBER("CODIGO_POSTAL")=30001)`. |
| S4 | **B** | Parte D | Bitmap de región: 114 hojas frente a 1954 del B-tree; Q14 4073 → 528. |
| S5 | **B** | Parte D | Q6 solo por ciudad: `INDEX SKIP SCAN IX_CLI_PAIS_CIUDAD` (144 lecturas). |
| S6 | **B** | Parte G | `IX_PED_IMPORTE` INVISIBLE y Q2 sin cambios. |
| S7 | **A y C** | Parte H | COALESCE y SHRINK SPACE, en línea: 226 → 2 lecturas. |
| S8 | **B** | Parte H | Rango sobre REVERSE: `TABLE ACCESS FULL`, 878 lecturas frente a 4. |
| S9 | **C** | Partes G y M | Un UPDATE de columna sin índice solo toca la tabla (2 bloques por fila con 4 índices, ev. 06). |
| S10 | **B** | Parte C | Altura = 1 + ⌈log_fo(hojas)⌉; fo máximo 543 con clave numérica de ~15 bytes. |
| S11 | **A y C** | Parte D | IOT: `INDEX UNIQUE SCAN SYS_IOT_TOP_…`, 3 lecturas frente a 4 del montículo. |
| S12 | **B** | Parte I | Control file frente a cabecera (5410252 = 5410252). |
| S13 | **C** | Parte I | CKPT registra el SCN; DBWn escribe los bloques. |
| S14 | **B y E** | Simulacro B | En NOMOUNT la instancia está `STARTED`: hay SGA y parámetros, pero no control file (`v$database`, `v$logfile`) ni diccionario. |
| S15 | **B** | Parte L | Secuencia de `11-activar-archivelog.sh` (en mi base no hizo falta: ya estaba en ARCHIVELOG). |
| S16 | **B** | Parte K | INACTIVE y archivado: `CLEAR LOGFILE` lo recrea sin perder nada. |
| S17 | **A y C** | Parte M | Lectura consistente (paso 1) y Flashback Query (paso 6). |
| S18 | **B** | Parte M | "Describe el undo": 2064 de 4894 KB del redo del INSERT. |
| S19 | **A** | Parte N | Tras el COMMIT: redo escrito, 0 bloques en datafiles. |
| S20 | **A** | Parte I | Objetivo de MTTR más bajo → checkpoints incrementales más frecuentes. |
| S21 | **B** | Parte L | ARCn no archiva (ORA-16038 / ORA-19809) y LGWR no puede reutilizar el grupo. |
| S22 | **B** | Simulacro D | OFFLINE del archivo para aislarlo; el resto sigue en servicio. |
| S23 | **B** | Parte O (teoría del simulacro D) | SYSTEM no puede estar offline con la base abierta: hay que montar. |
| S24 | **B** | Partes A y O | Sin redo archivado solo vale la copia en frío completa (como en el simulacro C). |
| S25 | **B y D** | Parte M | Igual que M3. |
| S26 | **A** | Parte L | `v$recovery_area_usage`: `ARCHIVED LOG`, 2 archivos (ev. 11). |

## Game day: RTO y RPO de los cuatro simulacros

| Simulacro | Fallo | Recuperación | RTO medido | RPO real |
|---|---|---|---|---|
| A | Caída de la instancia (`SHUTDOWN ABORT`) | SMON: roll forward + roll back, sin intervención | **≈5 s** (abort 17:33:44 → `ALTER DATABASE OPEN` completado 17:33:49, alert log) | **0**: la fila confirmada 102 sobrevivió |
| B | Pérdida de `control03.ctl` | Copiar `control01.ctl` encima y montar desde NOMOUNT | **≈10 s** (parada 17:33:58 → abierta 17:34:08; ≈7 s desde el arranque fallido) | **0** |
| C | `DROP TABLE … PURGE` de `aca_matriculas` | Restaurar la copia en frío `lab5-pre-simulacro` | **76 s** | Todo lo posterior a la copia (2 s en el simulacro) |
| D | Borrado del datafile `academia01.dbf` | RMAN `RESTORE` + `RECOVER` (PDB cerrada por ORA-63999, reabierta) | **10 s** desde el fallo (9 s de reparación) | **0**: la fila 104 confirmada tras la copia sobrevivió |

El `DROP` sin `PURGE` del simulacro C se resolvió en segundos con `FLASHBACK TABLE … TO BEFORE DROP` (60 000 matrículas), sin restaurar nada.

## Retrospectiva sin culpables

- **Qué salió bien:** los cuatro simulacros terminaron con la base abierta y la verificación final en TODO OK. Cada procedimiento estaba escrito antes de romper nada y había un punto de restauración comprobado (copias `lab4-final` y `lab5-pre-simulacro`, con SHA-256).
- **Qué me sorprendió:**
  - En el simulacro D, Oracle cerró la PDB entera (ORA-63999) antes de que yo actuara, y al reabrirla pidió recuperación de **otro** archivo (ORA-01113 sobre `tiendasur01.dbf`). El aislamiento por PDB funcionó: la CDB no cayó.
  - El escenario de la FRA llena no se reprodujo a la primera porque la FRA estaba vacía. Una prueba de alerta debe partir de un estado conocido.
- **Comparación clave:** restaurar una copia completa (C) tarda casi 8 veces más que restaurar un archivo con RMAN (D) **y además pierde datos**. RTO y RPO dependen de tener ARCHIVELOG y copias RMAN, no solo copias en frío.
- **Qué cambiaría:**
  1. Programar una copia RMAN completa periódica, no solo del tablespace del simulacro.
  2. Fijar `FAST_START_MTTR_TARGET` (ahora es 0) para acotar la recuperación de instancia.
  3. Llevar en producción las copias de control file y redo a discos distintos.
  4. Añadir al runbook una alerta de FRA al 85 % (reto P).

## Retos resueltos

- **B (bfr real de PEDIDO):** agrupando por `DBMS_ROWID.ROWID_BLOCK_NUMBER`: mínimo **2**, media **191,6** y máximo **200** filas por bloque, en 5220 bloques con filas. `NUM_ROWS / BLOCKS` = 188, porque `BLOCKS` cuenta 5320 (incluye cabecera de segmento, bloques de mapa y bloques sin filas). No todos los bloques tienen las mismas filas porque la longitud de fila varía (importe, código postal y fecha con distinto número de dígitos) y el último bloque queda casi vacío (2 filas).
- **C (altura de UX_CLI_EMAIL):** con 30 bytes por entrada caben ≈ 7996 · 0,9 / 30 ≈ 240 por hoja, es decir, ≈417 hojas (medidas: **501**). Con el fo de `IX_PED_CLIENTE` (543) saldría altura 2, pero la real es **3** (ev. 02). Las ramas de un índice de email guardan prefijos de cadena mucho más largos que un número de 3 bytes, así que su fo real es menor que 501 y hace falta un segundo nivel de ramas. El fo depende del tamaño de la clave.
- **D (Q9 cubriente):** Q9 lee **15** bloques con `IX_PED_FECHA` (ev. 06). Hacerlo cubriente con todas las columnas costaría casi lo que la tabla (41,6 MB; el cubriente de 5 columnas ya ocupa 40 MB) para ahorrar como mucho unas 12 lecturas. **No lo crearía.**
- **O:** runbook en `docs/runbooks/perdida-datafile.md`.
- **P (alerta):**

```sql
SELECT 'FRA al ' || ROUND(100 * space_used / space_limit) || ' %' AS alerta
  FROM v$recovery_file_dest WHERE space_used / space_limit > 0.85
UNION ALL
SELECT 'Sin copia RMAN en 24 h' FROM dual
 WHERE NOT EXISTS (SELECT 1 FROM v$rman_backup_job_details WHERE status = 'COMPLETED' AND start_time > SYSDATE - 1);
```

Devuelve filas solo cuando hay que despertar a alguien.
