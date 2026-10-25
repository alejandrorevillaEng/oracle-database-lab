-- scripts/lab4/08-reto-literales.sql - firmas que esconden sentencias con literales
-- Agrupa por force_matching_signature: misma firma = misma sentencia salvo los literales.
-- Más de 50 cursores distintos por firma delata a la aplicación que no usa variables de enlace.
@scripts/ops/marca
SPOOL docs/bitacora/lab4/evidencia/spool/&marca._08-reto-literales.spool.log
SET SQLFORMAT DEFAULT
SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF
COLUMN ejemplo FORMAT A80
SELECT force_matching_signature AS firma,
       COUNT(*)                  AS cursores,
       SUM(executions)           AS ejecuciones,
       MAX(SUBSTR(sql_text, 1, 80)) AS ejemplo
  FROM v$sql
 WHERE force_matching_signature <> 0
 GROUP BY force_matching_signature
HAVING COUNT(*) > 50
 ORDER BY cursores DESC;
SPOOL OFF
