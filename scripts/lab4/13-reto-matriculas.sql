-- scripts/lab4/13-reto-matriculas.sql — reto L: dimensionar ACA_MATRICULAS (60 000 filas) antes de mirar
-- Predice con la formula de la Unidad 3, mide con DBA_TABLES y explica la diferencia. Se lanza como SYSDBA.
ALTER SESSION SET CONTAINER = FREEPDB1;
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF
SET SERVEROUTPUT ON
PROMPT
PROMPT ===== 1. Estadisticas reales de las dos tablas de negocio =====
EXEC DBMS_STATS.GATHER_TABLE_STATS('ADMIN_ACADEMIA', 'ACA_MATRICULAS')
COLUMN tabla FORMAT A18
SELECT t.table_name AS tabla, t.num_rows AS r, t.avg_row_len AS r_bytes, t.blocks AS bloques_hwm,
       t.pct_free, t.ini_trans, s.blocks AS bloques_asignados,
       ROUND(s.bytes / 1048576, 1) AS mb_asignados
  FROM dba_tables t JOIN dba_segments s ON s.owner = t.owner AND s.segment_name = t.table_name
 WHERE t.owner = 'ADMIN_ACADEMIA' AND t.table_name IN ('ACA_MATRICULAS', 'ACA_ESTUDIANTES')
 ORDER BY t.table_name;
PROMPT
PROMPT ===== 2. Filas reales por bloque de ACA_MATRICULAS =====
SELECT COUNT(*) AS bloques_con_filas, MIN(n) AS min_filas, ROUND(AVG(n), 1) AS media_filas, MAX(n) AS max_filas
  FROM (SELECT DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE') AS blk, COUNT(*) AS n
          FROM admin_academia.aca_matriculas GROUP BY DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE'));
PROMPT
PROMPT ===== 3. Prediccion con las formulas y tiempo de un recorrido completo =====
DECLARE
  b_blk CONSTANT NUMBER := 8192;
  h_u3  CONSTANT NUMBER := 96;
  h_ora CONSTANT NUMBER := 104 + 18;
  r NUMBER; rlen NUMBER; pf NUMBER; b NUMBER;
  bfr_u3 NUMBER; bfr_ora NUMBER;
  PROCEDURE tiempo(p_etiqueta VARCHAR2, p_bloques NUMBER) IS
    mb NUMBER := p_bloques * 8192 / 1048576;
  BEGIN
    DBMS_OUTPUT.PUT_LINE(RPAD(p_etiqueta, 42) || p_bloques || ' bloques = ' || ROUND(mb, 2) || ' MB -> '
      || ROUND(mb / 150 * 1000) || ' ms en HDD a 150 MB/s  ·  ' || ROUND(mb / 1024 * 1000) || ' ms en SSD a 1 GB/s');
  END;
BEGIN
  SELECT num_rows, avg_row_len, pct_free, blocks INTO r, rlen, pf, b
    FROM dba_tables WHERE owner = 'ADMIN_ACADEMIA' AND table_name = 'ACA_MATRICULAS';
  bfr_u3  := FLOOR((b_blk - h_u3) * (1 - pf / 100) / rlen);
  bfr_ora := FLOOR((b_blk - h_ora) * (1 - pf / 100) / (rlen + 2));
  DBMS_OUTPUT.PUT_LINE('bfr (Unidad 3) = floor((8192-96)*(1-' || pf || '%)/' || rlen || ') = ' || bfr_u3
                       || ' filas/bloque -> b = ceil(' || r || '/' || bfr_u3 || ') = ' || CEIL(r / bfr_u3) || ' bloques');
  DBMS_OUTPUT.PUT_LINE('bfr (Oracle)   = floor((8192-122)*(1-' || pf || '%)/(' || rlen || '+2)) = ' || bfr_ora
                       || ' filas/bloque -> b = ceil(' || r || '/' || bfr_ora || ') = ' || CEIL(r / bfr_ora) || ' bloques');
  DBMS_OUTPUT.PUT_LINE('b real (estadisticas, bajo la HWM) = ' || b || ' bloques');
  DBMS_OUTPUT.PUT_LINE('');
  tiempo('Con la prediccion de la Unidad 3:', CEIL(r / bfr_u3));
  tiempo('Con la prediccion "Oracle":', CEIL(r / bfr_ora));
  tiempo('Con los bloques bajo la HWM:', b);
  tiempo('Con los bloques que tienen filas (301):', 301);
  tiempo('Con el segmento asignado completo:', 384);
END;
/
PROMPT
PROMPT ===== 4. Tamano real de una fila de ACA_MATRICULAS (columnas y VSIZE) =====
COLUMN rowid_fila FORMAT A20
SELECT m.matricula_id, ROWIDTOCHAR(m.ROWID) AS rowid_fila,
       DBMS_ROWID.ROWID_BLOCK_NUMBER(m.ROWID, 'BIGFILE') AS bloque,
       DBMS_ROWID.ROWID_ROW_NUMBER(m.ROWID) AS fila_en_bloque,
       VSIZE(m.matricula_id) + VSIZE(m.estudiante_id) + VSIZE(m.asignatura_id)
       + VSIZE(m.periodo) + VSIZE(m.fecha_matricula) AS bytes_datos
  FROM admin_academia.aca_matriculas m WHERE m.matricula_id = 1;
PROMPT
PROMPT ===== 5. El bloque 1446: nrow y la fila 0 columna a columna =====
COLUMN f NEW_VALUE f NOPRINT
COLUMN b NEW_VALUE b NOPRINT
SELECT TO_CHAR(DBMS_ROWID.ROWID_TO_ABSOLUTE_FNO(ROWID, 'ADMIN_ACADEMIA', 'ACA_MATRICULAS')) AS f,
       TO_CHAR(DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE')) AS b
  FROM admin_academia.aca_matriculas WHERE matricula_id = 1;
ALTER SESSION SET tracefile_identifier = 'lab4_matriculas';
ALTER SYSTEM DUMP DATAFILE &f BLOCK &b;
COLUMN tf NEW_VALUE tf NOPRINT
SELECT SUBSTR(value, INSTR(value, '/', -1) + 1) AS tf FROM v$diag_info WHERE name = 'Default Trace File';
SET PAGESIZE 0
WITH t AS (SELECT line_number AS n, payload FROM v$diag_trace_file_contents WHERE trace_filename = '&tf'),
     m AS (SELECT MIN(CASE WHEN payload LIKE 'data_block_dump%' THEN n END) AS dat,
                  MIN(CASE WHEN payload LIKE 'tab 0, row 0,%' THEN n END) AS fil
             FROM t)
SELECT CASE WHEN t.n = m.fil THEN CHR(10) || '--- La fila 0, columna a columna ---' || CHR(10) END
       || RTRIM(t.payload, CHR(10)) AS payload
  FROM t, m
 WHERE t.n BETWEEN m.dat AND m.dat + 14
    OR t.n BETWEEN m.fil AND m.fil + 6
 ORDER BY t.n;
EXIT
