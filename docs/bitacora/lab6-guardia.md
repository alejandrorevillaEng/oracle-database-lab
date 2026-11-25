Modelo INC-601
## INC-601 · Ficha del alumno 101 colgada
- Detección: A las 15:20 UTC avisó a Ana García, de Secretaría, mediante un ticket INC-601 de prioridad ALTA: al guardar la ficha del alumno 101 la pantalla se quedaba colgada. Había reiniciado su ordenador dos veces sin mejoría.
- Impacto: Secretaría no pudo guardar esa ficha desde las 15:20 hasta las 15:24, unos 4 minutos.
- Diagnóstico: Con 08-diagnostico.sql vi a la sesión 228 (ANA Garcia, secretaria/ficha-alumno) en enq: TX - row lock contention, con BLOQ = 48. La sesión 48 (APP ACADEMIA, matriculas/cierre-periodo) tenía el TX con LMODE 6 y BLOCK 1, los mismos ID1 458784 e ID2 707, y estaba ociosa en PL/SQL lock timer. La fila esperada era ACA_ESTUDIANTES, archivo 1024, bloque 783, fila 5; deshacer la transacción costaba solo 1 bloque y 1 registro de undo, y el ASH mostró muestras de 15:22:00 a 15:22:04.
- Causa raíz: Una sesión de la aplicación dejó una transacción abierta mientras estaba en una pausa, reteniendo la fila que Ana intentaba actualizar; no era un fallo de la base ni del equipo cliente.
- Intervención: Ejecuté ALTER SYSTEM KILL SESSION '48,11504' IMMEDIATE;, que devolvió System altered. Fue el cambio más pequeño: terminó solo esa sesión, con 1 registro de undo por deshacer, y no tocó la instancia ni el esquema. CANCEL SQL no habría servido porque la llamada en curso era el SLEEP y el TX habría seguido abierto.
- Validación: Repetí 08-diagnostico.sql y las secciones 1 a 4 quedaron vacías; el ASH solo mostraba las muestras antiguas de las 15:23:26 a las 15:23:30. Conectando por el servicio academia_app con la cuenta de aplicación, el alumno 101 salió ACTIVO.
- Acción preventiva: Evitar dejar transacciones abiertas durante pausas del programa, hacer COMMIT o ROLLBACK antes de dormir, y añadir una alerta cuando aparezca blocking_session con el evento enq: TX.
Modelo INC-602
## INC-602 · ORA-12514 al conectar la aplicación
- Detección: A las 15:25 UTC avisó el equipo de matrículas mediante el ticket INC-602 (prioridad CRÍTICA): ninguna instancia de la aplicación conectaba y el error era ORA-12514.
- Impacto: La aplicación de matrículas se quedó sin conexión desde las 15:25 hasta las 15:29, unos 4 minutos, en todas sus instancias.
- Diagnóstico: La lista de turno mostró la instancia FREE OPEN/ALLOWED, la CDB y FREEPDB1 en READ WRITE, 0 sesiones bloqueadas y 0 alertas, así que la base no estaba caída. En la sección 6 de 08-diagnostico.sql, FREEPDB1 salía SI pero academia_app salía NO. En lsnrctl status aparecía Service "freepdb1" y no aparecía Service "academia_app".
- Causa raíz: El servicio academia_app estaba parado, por lo que el listener no lo anunciaba y los clientes recibían ORA-12514. La base seguía abierta; no hubo que reiniciarla.
- Intervención: Arranqué ese servicio con EXEC DBMS SERVICE.START SERVICE('academia_app'); desde FREEPDB1 y guardé el estado con ALTER PLUGGABLE DATABASE FREEPDB1 SAVE STATE;. La salida fue PL/SQL procedure successfully completed y Pluggable database altered. No reinicié la base porque el problema era solo del servicio.
- Validación: La sección 6 volvió a salir academia app SI; lsnrctl status mostró Service "academia app" con Instance "FREE", status READY; la conexión real por @//localhost:1521/academia_app funcionó sin ORA-12514 y devolvió el alumno 101 ACTIVO.
- Acción preventiva: Incluir en la lista de turno la comparación entre servicios definidos y servicios activos, revisar los servicios después de cada despliegue y guardar el estado de la PDB con el servicio arrancado.
Modelo INC-603
## INC-603 · Cuenta de aplicación bloqueada
- Detección: A las 15:29 UTC avisó el equipo de matrículas mediante el ticket INC-603 (prioridad ALTA): la aplicación no entraba con ORA-28000 después del despliegue de las 21:00, y comentaron que no habían cambiado la contraseña. El turno de tarde dejó la nota de que ese día se ejecutó el script trimestral de bajas.
- Impacto: La aplicación estuvo sin acceso desde las 15:29 hasta las 15:31, unos 2 minutos.
- Diagnóstico: En la sección 7 de 08-diagnostico.sql apareció APP ACADEMIA en CON ID 3 con ACCOUNT_STATUS = LOCKED, fecha de bloqueo 2026-11-25 15:29, perfil DEFAULT con FAILED LOGIN ATTEMPTS = 10. No era LOCKED(TIMED) ni el perfil PRF PERSONAS, que tiene 3 intentos, así que no podía venir de contraseñas fallidas.
- Causa raíz: El script trimestral de bajas bloqueó una cuenta de servicio porque no distingue entre cuentas de personas y cuentas de aplicación; la contraseña seguía siendo válida.
- Intervención: Desbloqueé solo esa cuenta con ALTER USER app_academia ACCOUNT UNLOCK;, que devolvió User altered. No cambié la contraseña porque el estado era LOCKED, no EXPIRED, y no toqué ninguna otra cuenta.
- Validación: La sección 7 quedó vacía y la conexión real por el servicio academia_app entró sin ORA-28000, devolviendo el alumno 101 ACTIVO.
- Acción preventiva: Excluir las cuentas de aplicación del script de bajas, por ejemplo con una lista blanca o un campo que identifique el tipo de cuenta, revisar la lista antes de ejecutarlo y alertar si una cuenta de servicio pasa a estado LOCKED.
