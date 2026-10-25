WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 170 PAGESIZE 100 FEEDBACK OFF VERIFY OFF
COLUMN rowid_fila FORMAT A20
ALTER SESSION SET CONTAINER = FREEPDB1;
PROMPT ===== Reto K: direccion fisica de un estudiante > 19000 =====
COLUMN f NEW_VALUE f NOPRINT
COLUMN b NEW_VALUE b NOPRINT
COLUMN s NEW_VALUE s NOPRINT
COLUMN id NEW_VALUE id NOPRINT
SELECT e.estudiante_id AS id, e.estado, ROWIDTOCHAR(e.ROWID) AS rowid_fila,
       DBMS_ROWID.ROWID_OBJECT(e.ROWID) AS data_object_id,
       DBMS_ROWID.ROWID_TO_ABSOLUTE_FNO(e.ROWID, 'ADMIN_ACADEMIA', 'ACA_ESTUDIANTES') AS archivo,
       DBMS_ROWID.ROWID_BLOCK_NUMBER(e.ROWID, 'BIGFILE') AS bloque,
       DBMS_ROWID.ROWID_ROW_NUMBER(e.ROWID) AS fila_en_bloque,
       TO_CHAR(DBMS_ROWID.ROWID_TO_ABSOLUTE_FNO(e.ROWID, 'ADMIN_ACADEMIA', 'ACA_ESTUDIANTES')) AS f,
       TO_CHAR(DBMS_ROWID.ROWID_BLOCK_NUMBER(e.ROWID, 'BIGFILE')) AS b,
       TO_CHAR(DBMS_ROWID.ROWID_ROW_NUMBER(e.ROWID)) AS s
  FROM admin_academia.aca_estudiantes e
 WHERE e.estudiante_id = (SELECT MAX(estudiante_id) FROM admin_academia.aca_estudiantes WHERE estudiante_id > 19000);
PROMPT
PROMPT ===== Volcado del bloque &b del archivo &f =====
ALTER SESSION SET tracefile_identifier = 'lab4_reto_bloque';
ALTER SYSTEM DUMP DATAFILE &f BLOCK &b;
COLUMN tf NEW_VALUE tf NOPRINT
SELECT SUBSTR(value, INSTR(value, '/', -1) + 1) AS tf FROM v$diag_info WHERE name = 'Default Trace File';
SET PAGESIZE 0
WITH t AS (SELECT line_number AS n, payload FROM v$diag_trace_file_contents WHERE trace_filename = '&tf'),
     m AS (SELECT MIN(CASE WHEN payload LIKE 'Block header dump%' THEN n END) AS cab,
                  MIN(CASE WHEN payload LIKE 'data_block_dump%' THEN n END) AS dat,
                  MIN(CASE WHEN payload LIKE 'tab 0, row &s,%' THEN n END) AS fil
             FROM t)
SELECT CASE WHEN t.n = m.cab THEN CHR(10) || '--- [A] CABECERA DEL BLOQUE Y LISTA DE TRANSACCIONES (ITL) ---' || CHR(10)
            WHEN t.n = m.dat THEN CHR(10) || '--- [B] CABECERA DE DATOS Y DIRECTORIO DE FILAS (slot array) ---' || CHR(10)
            WHEN t.n = m.fil THEN CHR(10) || '--- [C] LA FILA &s (estudiante &id), columna a columna ---' || CHR(10) END
       || RTRIM(t.payload, CHR(10)) AS payload
  FROM t, m
 WHERE t.n BETWEEN m.cab AND m.cab + 9
    OR t.n BETWEEN m.dat AND m.dat + 21
    OR t.n BETWEEN m.fil AND m.fil + 8
 ORDER BY t.n;
EXIT
