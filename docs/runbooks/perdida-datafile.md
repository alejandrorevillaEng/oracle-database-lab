# Runbook · Pérdida de un datafile de aplicación (Oracle 26ai Free, contenedor `oralab-26ai`)

Para la persona de guardia. Probado en el simulacro D del Lab 5 (RTO medido: 10 s; RPO: 0).

## 1. Síntoma

Las consultas sobre un tablespace fallan con:

```
ORA-01116: error in opening database file 16          <- qué número de archivo
ORA-01110: data file 16: '/opt/oracle/oradata/FREE/FREEPDB1/academia01.dbf'   <- qué ruta
ORA-27041: unable to open file
Linux-x86_64 Error: 2: No such file or directory      <- la causa en el sistema operativo
```

Si en el alert log aparece `ORA-63999: data file suffered media failure`, Oracle ha cerrado la PDB entera (queda `MOUNTED`); la CDB y las demás PDB siguen abiertas.

## 2. Comprobaciones previas (no tocar nada hasta tenerlas)

```sql
-- SQL*Plus, en CDB$ROOT
SELECT log_mode FROM v$database;                 -- debe ser ARCHIVELOG (si no: solo cabe restaurar la copia en frío completa)
SELECT name, open_mode FROM v$pdbs;              -- ¿la PDB sigue READ WRITE o está MOUNTED / cerrándose?
SELECT file#, name, status FROM v$datafile WHERE file# = 16;
-- RMAN
LIST BACKUP OF DATAFILE 16;                      -- tiene que haber una copia
```

- Si el archivo es de `SYSTEM` o del undo de la raíz: **no es este runbook** (SHUTDOWN ABORT → STARTUP MOUNT → RESTORE → RECOVER → OPEN). Escalar.
- Si la PDB está *cerrándose*, esperar a que `v$pdbs` diga `MOUNTED` antes de lanzar RMAN (si no: ORA-01089).

## 3. Reparación

SQL*Plus: `docker exec -it oralab-26ai sqlplus / as sysdba` · RMAN: `docker exec -it oralab-26ai rman target /`

**Camino A — la PDB sigue abierta (`READ WRITE`):** solo el tablespace está caído; el resto de FREEPDB1 sigue en servicio.

```sql
-- SQL*Plus
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER DATABASE DATAFILE 16 OFFLINE;
-- RMAN
RESTORE DATAFILE 16;
RECOVER DATAFILE 16;
-- SQL*Plus
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER DATABASE DATAFILE 16 ONLINE;
```

**Camino B — Oracle cerró la PDB (`MOUNTED`, ORA-63999):** el que salió en el simulacro. Se repara con la PDB montada y después se abre.

```sql
-- RMAN
RESTORE DATAFILE 16;
RECOVER DATAFILE 16;
-- SQL*Plus
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER DATABASE DATAFILE 16 ONLINE;
ALTER SESSION SET CONTAINER = CDB$ROOT;
ALTER PLUGGABLE DATABASE FREEPDB1 OPEN;
```

Nunca borrar ni copiar archivos de la FRA a mano: todo a través de RMAN.

## 4. Verificación (el incidente no se cierra hasta que se cumplen las tres)

```sql
SELECT name, open_mode FROM v$pdbs;                         -- FREEPDB1 READ WRITE
SELECT file#, status FROM v$datafile WHERE file# = 16;      -- ONLINE
ALTER SESSION SET CONTAINER = FREEPDB1;
SELECT COUNT(*) FROM admin_academia.aca_estudiantes;        -- responde (20000) y el último cambio confirmado está
```

## 5. Comunicación

1. Al detectar: avisar al responsable de la aplicación afectada (tablespace → esquema → servicio) con hora de inicio.
2. Al cerrar: hora de fin, RTO, RPO (0 si RECOVER terminó sin errores) y causa del archivo perdido.
3. Abrir una retrospectiva sin culpables: ¿por qué desapareció el archivo? ¿alertó la monitorización?
