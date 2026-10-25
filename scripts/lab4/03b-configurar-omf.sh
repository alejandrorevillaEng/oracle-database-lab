#!/usr/bin/env bash
# scripts/lab4/03b-configurar-omf.sh - reto de la Parte C: destino por defecto para archivos nuevos.
# Con DB_CREATE_FILE_DEST dentro del volumen, un CREATE TABLESPACE sin DATAFILE deja el archivo
# en /opt/oracle/oradata (OMF) y no en $ORACLE_HOME/dbs. SCOPE=BOTH: aplica ya y queda en el SPFILE.
set -euo pipefail
source scripts/deployment/env/00-config.sh
docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba <<SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SYSTEM SET db_create_file_dest='$DATA_ROOT' SCOPE=BOTH;
SET LINESIZE 160 PAGESIZE 50 FEEDBACK OFF
COLUMN name FORMAT A24
COLUMN value FORMAT A40
SELECT name, value FROM v\$parameter WHERE name = 'db_create_file_dest';
ALTER SESSION SET CONTAINER = FREEPDB1;
SELECT name, value FROM v\$parameter WHERE name = 'db_create_file_dest';
EXIT
SQL
