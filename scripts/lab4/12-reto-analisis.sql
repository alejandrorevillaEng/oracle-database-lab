-- scripts/lab4/12-reto-analisis.sql — reto K: distribucion de filas por bloque y rango de IDs del bloque elegido
-- Se lanza como SYSDBA (lee la tabla de negocio, no solo el diccionario)
ALTER SESSION SET CONTAINER = FREEPDB1;
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF
COLUMN bloque FORMAT 999999
COLUMN filas FORMAT 9999
COLUMN id_min FORMAT 99999
COLUMN id_max FORMAT 99999
PROMPT
PROMPT == 1. Bloques usados por la tabla y rango de IDs ==
SELECT COUNT(DISTINCT DBMS_ROWID.ROWID_BLOCK_NUMBER(e.ROWID, 'BIGFILE')) AS bloques_usados,
       MIN(DBMS_ROWID.ROWID_BLOCK_NUMBER(e.ROWID, 'BIGFILE')) AS bloque_min,
       MAX(DBMS_ROWID.ROWID_BLOCK_NUMBER(e.ROWID, 'BIGFILE')) AS bloque_max,
       COUNT(*) AS filas
  FROM admin_academia.aca_estudiantes e;
PROMPT
PROMPT == 2. Cuantas filas caben en cada bloque (la longitud de la fila cambia) ==
SELECT filas, COUNT(*) AS bloques FROM (
  SELECT DBMS_ROWID.ROWID_BLOCK_NUMBER(e.ROWID, 'BIGFILE') AS b, COUNT(*) AS filas
    FROM admin_academia.aca_estudiantes e
   GROUP BY DBMS_ROWID.ROWID_BLOCK_NUMBER(e.ROWID, 'BIGFILE'))
 GROUP BY filas ORDER BY filas DESC;
PROMPT
PROMPT == 3. Primeros y ultimos bloques por contenido (el orden fisico no sigue al ID) ==
SELECT DBMS_ROWID.ROWID_BLOCK_NUMBER(e.ROWID, 'BIGFILE') AS bloque, COUNT(*) AS filas,
       MIN(e.estudiante_id) AS id_min, MAX(e.estudiante_id) AS id_max
  FROM admin_academia.aca_estudiantes e
 GROUP BY DBMS_ROWID.ROWID_BLOCK_NUMBER(e.ROWID, 'BIGFILE')
 ORDER BY bloque
 FETCH FIRST 5 ROWS ONLY;
SELECT DBMS_ROWID.ROWID_BLOCK_NUMBER(e.ROWID, 'BIGFILE') AS bloque, COUNT(*) AS filas,
       MIN(e.estudiante_id) AS id_min, MAX(e.estudiante_id) AS id_max
  FROM admin_academia.aca_estudiantes e
 GROUP BY DBMS_ROWID.ROWID_BLOCK_NUMBER(e.ROWID, 'BIGFILE')
 ORDER BY bloque DESC
 FETCH FIRST 5 ROWS ONLY;
PROMPT
PROMPT == 4. El bloque del estudiante 20000 y los que tienen los IDs mas altos ==
SELECT 'bloque 1199' AS que, COUNT(*) AS filas, MIN(estudiante_id) AS id_min, MAX(estudiante_id) AS id_max
  FROM admin_academia.aca_estudiantes
 WHERE DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE') = 1199
UNION ALL
SELECT 'bloque del 20000', COUNT(*), MIN(estudiante_id), MAX(estudiante_id)
  FROM admin_academia.aca_estudiantes
 WHERE DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE') =
       (SELECT DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE')
          FROM admin_academia.aca_estudiantes WHERE estudiante_id = 20000);
SELECT bloque, filas, id_min, id_max FROM (
  SELECT DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE') AS bloque, COUNT(*) AS filas,
         MIN(estudiante_id) AS id_min, MAX(estudiante_id) AS id_max
    FROM admin_academia.aca_estudiantes
   GROUP BY DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE'))
 ORDER BY id_max DESC FETCH FIRST 3 ROWS ONLY;
PROMPT
PROMPT == 5. Fecha y tamano de las dos filas comparadas ==
COLUMN fecha FORMAT A32
SELECT estudiante_id, TO_CHAR(fecha_registro, 'YYYY-MM-DD HH24:MI:SS.FF9') AS fecha,
       VSIZE(estudiante_id) + VSIZE(dni) + VSIZE(nombres) + VSIZE(apellidos)
       + VSIZE(email_institucional) + NVL(VSIZE(estado), 0) + VSIZE(fecha_registro) AS bytes
  FROM admin_academia.aca_estudiantes WHERE estudiante_id IN (101, 20000) ORDER BY estudiante_id;
EXIT
