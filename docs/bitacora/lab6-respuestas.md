# Lab 6 — Respuestas y bitácora

## Línea base (Parte B)
- Errores ORA- en las últimas 24 h: 4
- Causa: simulacros del Lab 5 (ORA-01113, ORA-01110, etc.).
## Arranque — errores desde el último arranque (Parte C)
- ORA-00800 (4 veces): ruido conocido de contenedor; Linux no deja subir la prioridad de VKTM/LGWR.
- ORA-65019 (2 veces): provocado por el propio script al intentar OPEN READ WRITE sin cerrar; es el error esperado del bloque 2, no un fallo nuevo.
## Parte D — servicio, cuenta y sesión
- common_user_prefix en la raíz: C##.
- APP_ACADEMIA es local (COMMON=NO), OPEN, default tablespace USERS, autenticación PASSWORD.
- CANCEL SQL: ORA-01013 en la aplicación, pero la transacción sigue abierta (1).
- KILL SESSION IMMEDIATE: ORA-00031, sesión terminada y fila 101 de vuelta a ACTIVO.
- SYSOPER entra como PUBLIC y no ve DBA_USERS (ORA-00942).

## 9.1 Partes A-C · Rol operativo, parámetros y estados

1. En la Parte B mi alert log tenía 4 errores ORA- en 24 h, procedentes de los simulacros del Lab 5 (ORA-01113, ORA-01110...). Ese número no es una alarma por sí solo: es una línea base; lo que importa es compararlo con el estado normal y con otros momentos, por eso en la guardia del incidente 2 vi 9 y supe interpretarlo.
2. WEDNESDAY_WINDOW empieza a las 22:00 y dura 4 horas (byhour=22, bysecond=0, HORAS 4). En ella corren auto optimizer stats collection, auto space advisor y sql tuning advisor, los tres ENABLED (spool 01-automatizacion).
3. Tras SCOPE = SPFILE, V$SPPARAMETER mostraba 250 con ISSPECIFIED = TRUE, pero V$PARAMETER seguía mostrando 200 en memoria: el cambio solo valdría en el próximo arranque. Sin el RESET, db_files habría quedado fijado en 250 al reiniciar.
4. RESET fue la vuelta atrás correcta para db_files porque en la copia del PFILE no aparecía («sin fijar», ISSPECIFIED FALSE). Para processes no habría sido igual: la línea *.processes=200 aparece en el PFILE sacado del SPFILE (y processes=200 en el sacado de memoria), así que RESET habría borrado un valor configurado expresamente.
5. C##OPS_RO obtuvo ORA-01109: database not open al entrar por freepdb1. «Database opened» se refería a la CDB y a la instancia, pero la PDB había quedado en MOUNTED al no tener estado guardado. Tras OPEN y SAVE STATE la PDB quedó READ WRITE y la conexión entró bien.

## 9.1.1 Partes D-E · Servicios, sesiones y diccionario

6. La sesión de la aplicación era SID 52, SERIAL# 6373, SPID 7721, evento PL/SQL lock timer; MODULE = matriculas, ACTION = cierre-periodo y CLIENT_IDENTIFIER = ana.garcia@ucam. USERNAME solo dice quién es; MODULE, ACTION y CLIENT_IDENTIFIER dicen por qué está ahí, qué está haciendo y a quién atiende, y permiten encontrar la sesión correcta entre varias de la misma cuenta.
7. Tras CANCEL SQL quedaba 1 transacción abierta: solo cayó la llamada (ORA-01013). Tras KILL SESSION IMMEDIATE (ORA-00031) quedaban 0 sesiones de la aplicación y la fila 101 volvió a ACTIVO, porque PMON deshizo el UPDATE sin confirmar.
8. common_user_prefix vale C## en mi imagen, así que una cuenta común debe empezar por C## (como C##OPS_RO). Una cuenta local como APP_ACADEMIA no lleva ese prefijo.
9. Tres miradas: C##OPS_RO en CDB$ROOT ve USER_TABLES 0, ALL_TABLES de ADMIN_ACADEMIA 0, ALL_USERS 37, DBA_USERS 37, CDB_USERS con_id 1 = 37 y con_id 3 = 47, V$DATAFILE 17. Entrando por freepdb1 ve ALL_USERS 47, DBA_USERS 47, CDB_USERS con_id 3 = 47 y V$DATAFILE 10. APP_ACADEMIA por academia_app ve USER_TABLES 0 y ALL_TABLES de ADMIN_ACADEMIA 1, pero DBA_USERS, CDB_USERS y V$DATAFILE dan ORA-00942. La diferencia es de identidad, contenedor y privilegios: con CONTAINER_DATA = ALL veo más datafiles desde la raíz, y la cuenta de aplicación no tiene acceso al diccionario.
10. La carga costó 53.773 lecturas lógicas en total y 5.377 por recorrido (10 recorridos), con DB time de 0,64 s y DB CPU de 0,56 s en 0,62 s de reloj. Que DB time y DB CPU casi coincidan indica que el trabajo fue casi todo CPU, con muy poca espera no Idle.

## 9.1.2 Partes F-G · Espacio y acceso

11. Antes de la carga, TBS_ACADEMIA_HIST tenía 10 MB asignados, 3,9 MB libres y 40 MB de máximo. Para alertar usaría el libre respecto al máximo (15,16 % ocupado sobre el techo), no el asignado, porque el fichero puede crecer y el límite real es el MAXSIZE.
12. En el ORA-01950 insertaba APP_ACADEMIA, pero quien debía pagar la cuota era el dueño del segmento, CARGA_HIST. En el ORA-01536 el tablespace tenía sitio; lo que faltaba era cuota del dueño (2 MB), así que ampliar el tablespace no habría cambiado nada.
13. La carga reanudable estuvo suspendida unos 12 segundos: DBA_RESUMABLE mostraba SUSPENDED, TIMEOUT 180 y ORA-01536 a las 19:50:40, y el alert log dejó «statement in resumable session 'carga-historico' was suspended due to» y después «was resumed» cuando amplié la cuota.
14. Antes del SHRINK: 2.000 filas, 2.944 bloques y 23 MB; después: 2.000 filas, 304 bloques y 2,4 MB, con 2,4 MB de cuota consumida. El DELETE no devolvió el espacio porque la HWM no baja: los bloques por debajo siguen asignados y la cuota sigue contada hasta que SHRINK mueve las filas y reduce la HWM.
15. Mi perfil DEFAULT tenía FAILED_LOGIN_ATTEMPTS 10, INACTIVE_ACCOUNT_TIME 365, PASSWORD_GRACE_TIME 7, PASSWORD_LIFE_TIME 180, PASSWORD_LOCK_TIME 1, PASSWORD_REUSE_MAX UNLIMITED, PASSWORD_REUSE_TIME UNLIMITED, PASSWORD_ROLLOVER_TIME 0 y PASSWORD_VERIFY_FUNCTION NULL. En PRF_PERSONAS justificaría 3 intentos fallidos (antes de que alguien adivine la contraseña) y 1 minuto de bloqueo, que es suficiente en el laboratorio sin dejar a Ana fuera demasiado tiempo.
16. Ana pudo leer ACA_MATRICULAS porque ROL_LECTURA_ACADEMIA tiene el privilegio de esquema SELECT ANY TABLE sobre ADMIN_ACADEMIA, aunque nadie le concediera esa tabla por nombre. Al cambiar el nombre de un alumno obtuvo ORA-41900: missing UPDATE privilege sobre la columna NOMBRES de ACA_ESTUDIANTES.

## 9.1.3 Partes H-I · Objetos, diagnóstico y guardia

17. Al añadir una columna que nadie usaba no se invalidó nada (dependencia de grano fino). Al ampliar email_institucional se invalidó solo V_CONTACTO_LAB6. Al ampliar nombres cayeron V_ACTIVOS_LAB6 y, en cascada, F_TOTAL_ACTIVOS_LAB6; V_CONTACTO_LAB6 seguía inválida. Luego UTL_RECOMP.RECOMP_SERIAL dejó los tres VALID.
18. No: con el advisor de SGA, desde el factor 0,75 hasta el 2 el ESTD_DB_TIME_FACTOR se queda en 1 y las lecturas físicas en 37.273, así que duplicar la SGA no mejora el DB time. En mi PGA, con 128 y 256 MB aparecen 3 sobreasignaciones y 81 % de aciertos; desde 384 MB hay 0 y 100 %, así que por debajo de 384 MB es donde salen las sobreasignaciones en mis cifras.
19. La consulta de la aplicación necesitó 247 lecturas lógicas: la línea FETCH muestra cr=247 y r=1, y tkprof resume query=247 para 1 fila devuelta.
20. INC-601: evidencia clave el TX con LMODE 6 y BLOCK 1 del SID 48 bloqueando al 228; intervención KILL SESSION '48,11504' IMMEDIATE; validación secciones 1-4 vacías y alumno 101 ACTIVO. INC-602: evidencia academia_app NO y ausente en lsnrctl status con la base READ WRITE; intervención DBMS_SERVICE.START_SERVICE + SAVE STATE; validación SI, READY y conexión sin ORA-12514. INC-603: evidencia APP_ACADEMIA LOCKED (no TIMED) con perfil DEFAULT de 10 intentos; intervención ALTER USER ... ACCOUNT UNLOCK; validación sección 7 vacía y conexión sin ORA-28000.

## 10. Simulacro 1Z0-182 (letra y Parte)

S1. B — Parte B (MMON genera las alertas de umbral).
S2. C — Parte C (DEFERRED SCOPE=BOTH aplica a sesiones nuevas).
S3. B — Parte C (CREATE PFILE FROM MEMORY).
S4. B y C — Parte C (FORCE, o CLOSE IMMEDIATE seguido de OPEN).
S5. C — Parte C (DBA_PDB_SAVED_STATES).
S6. B — Parte C (ORA-01035).
S7. A — Parte D (DBMS_SERVICE).
S8. B — Parte D (PADDR = ADDR).
S9. C — Parte D (la transacción sigue abierta).
S10. C — Parte D (SHOW USER devuelve PUBLIC).
S11. B — Parte E (V$CON_SYSMETRIC).
S12. A y C — Parte E (CPU de primer plano y esperas no Idle).
S13. B — Parte F (necesita cuota HR, el dueño de la tabla).
S14. A y C — Parte F (Undo y Temporal).
S15. A y C — Parte F (suspende hasta el timeout y se ve en DBA_RESUMABLE).
S16. B — Parte F (ENABLE ROW MOVEMENT y ASSM).
S17. B — Parte G (LOCKED(TIMED)).
S18. B — Parte G (B conserva el privilegio de sistema).
S19. A y B — Parte H (MOVE sin UPDATE INDEXES y ALTER INDEX ... UNUSABLE).
S20. B — Parte H (DBMS_MONITOR.SESSION_TRACE_ENABLE).
S21. C — Parte H (DIAGNOSTIC_DEST).
S22. C — Parte I (identificar BLOCKING_SESSION y qué está haciendo).
