# Lab 3 — Respuestas de comprobación

Alumno: Alejandro Revilla · Issue #1 · Branch `chore/1-install-oracle-environment`

## Docker

**1. ¿Qué diferencia hay entre una imagen y un contenedor?**
La imagen es una plantilla de solo lectura; el contenedor es una instancia en ejecución creada a partir de ella. En G2, `docker run hello-world` creó un contenedor (`amazing_hugle`) a partir de la imagen `hello-world`; en G4 creé otro contenedor, `prueba`, a partir de `alpine:3.20`. Puedo borrar esos contenedores y la imagen sigue intacta para crear otros nuevos.

**2. En G5 `nota.txt` desapareció y en G6 no. ¿Por qué?**
En G5 el archivo se escribió en el sistema de archivos propio del contenedor `prueba`, que es temporal: al hacer `docker rm prueba` se borró con él, y `prueba2` nació limpio desde la imagen. En G6 se escribió en `/datos`, donde estaba montado el volumen con nombre `datos-prueba`, que vive fuera del ciclo de vida del contenedor; un contenedor nuevo con el mismo volumen encontró el dato.

**3. ¿`docker ps` frente a `docker ps -a`? ¿Qué significa `Exited (0)`?**
`docker ps` lista solo los contenedores en marcha; `docker ps -a` lista todos, también los detenidos. `Exited (0)` indica que el proceso principal terminó y lo hizo correctamente (código 0); un código distinto de 0 indicaría que terminó con error.

**4. En `-p 8181:8181`, ¿qué número es de mi equipo y cuál del contenedor? ¿Qué pasaría con `-p 80:8080` en nginx?**
El formato es `anfitrión:contenedor`: el primero es el puerto de mi equipo y el segundo el del contenedor. Con `-p 80:8080` el tráfico del puerto 80 de mi equipo iría al 8080 del contenedor, pero nginx escucha en el 80, así que la página no cargaría.

**5. ¿Por qué Oracle se queda en marcha y hello-world termina solo?**
Un contenedor vive lo que vive su proceso principal. hello-world ejecuta un programa que imprime un mensaje y termina; el proceso principal del contenedor de Oracle es el motor de base de datos, que es un servicio que no termina.

**6. ¿Qué es el digest y por qué lo registramos si usamos `:latest`?**
Es la huella `sha256` exacta del contenido de la imagen. `:latest` es una etiqueta móvil que apunta a versiones distintas con el tiempo; el digest no cambia. Mi evidencia 04 registra `sha256:f988b0c0…8fba`, así cualquiera sabe exactamente qué versión de Oracle instalé.

**7. ¿Qué comando borraría realmente los datos de Oracle? ¿Por qué `docker rm oralab-26ai` no lo hace?**
`docker volume rm oralab-26ai-data`. `docker rm` solo borra el contenedor; los datafiles de la base viven en el volumen montado en `/opt/oracle/oradata`, que sobrevive al contenedor (lo mismo que comprobé en G6).

> Nota: en mi entorno los datafiles de los 5 tablespaces de V000 se crearon en `$ORACLE_HOME/dbs` y no en `/opt/oracle/oradata`, porque V000 usa nombres de archivo sin ruta. Esos 5 archivos sí se perderían con `docker rm`. Lo documento en el PR como hallazgo.

## Git, organización y evidencia

**8. ¿Por qué dentro del repositorio, con Issue, branch y PR?**
Porque preparar un entorno es un cambio de infraestructura: así es reproducible (repito los scripts y obtengo el mismo entorno), verificable (el reviewer ve los scripts y la salida real) y sirve de onboarding. Fuera de Git el conocimiento solo existiría en mi máquina (un *snowflake server*).

**9. ¿`source 00-config.sh` frente a `bash 00-config.sh`?**
`bash` ejecuta el script en un proceso hijo y sus variables desaparecen al terminar. `source` lo ejecuta en mi terminal actual, así que `$CONT_NAME`, `$EVID` o la función `ts` quedan disponibles para los comandos siguientes.

**10. Explica `20260915T091230Z_02-docker.script.log`.**
`20260915T091230Z`: fecha y hora en UTC, formato ISO 8601 compacto (la `Z` es UTC). `02`: número del paso que la produjo. `docker`: descripción en kebab-case. `.script.log`: evidencia de terminal (`.spool.log` sería de una sesión SQL y `.png` una captura).

**11. ¿Para qué sirve `.gitattributes` y qué error evita?**
Obliga a Git a guardar `.sh`, `.sql` y `.md` con finales de línea LF. Evita que un script con CRLF de Windows falle en Linux con errores como `$'\r': command not found`, y los diffs llenos de cambios invisibles.

**12. ¿Por qué *Create a merge commit* y no *Squash and merge*?**
Porque cada commit corresponde a una Parte y tiene valor propio como evidencia (cuándo y cómo se verificó cada herramienta). Squash los fundiría en uno solo y se perdería ese historial paso a paso.

## Seguridad

**13. Las cuatro capas de contraseñas y qué pasa si te saltas la primera.**
1) Añadir `config/.env` al `.gitignore` antes de crear el archivo. 2) Una plantilla versionada `config/.env.example` sin valores reales. 3) El archivo real `config/.env`, solo local, comprobado con `git check-ignore`. 4) Cargar los secretos con `set -a; source config/.env; set +a` y usarlos como `"$ORACLE_PWD"`, sin teclearlos. Si me salto la primera, un `git add .` podría meter la contraseña en un commit y quedaría para siempre en el historial.

**14. ¿Por qué no escribir la contraseña en el `docker run` aunque el script no se suba?**
Porque todo lo que tecleo queda en `~/.bash_history` en texto plano. Usando `"$ORACLE_PWD"` en el historial solo queda el nombre de la variable.

**15. Si la contraseña está en un commit publicado, ¿basta con borrarla en un commit nuevo?**
No: sigue en el historial y cualquiera puede recuperarla. Hay que darla por comprometida y rotarla (recrear el contenedor con una contraseña nueva en `config/.env`) y avisar al docente para limpiar la branch.

## Oracle y herramientas

**16. ¿Por qué no SPOOL ni `@archivo.sql` con sqlplus dentro del contenedor?**
Porque sqlplus corre dentro del contenedor: SPOOL escribiría el archivo en el sistema de archivos del contenedor y `@archivo.sql` lo buscaría allí (SP2-0310). En su lugar redirigimos el `.sql` de mi equipo con `<` hacia `docker exec -i ... sqlplus` y capturamos la salida con `tee` en el repositorio.

**17. ¿Qué hace `WHENEVER SQLERROR EXIT SQL.SQLCODE`?**
Si cualquier sentencia falla, sqlplus se detiene en ese punto y devuelve el código de error. Sin ella seguiría ejecutando el resto sobre un estado a medias, y el script 08 no detectaría el fallo para no aplicar V001 sobre un V000 roto.

**18. ¿Qué es una migración y por qué no se editan V000 y V001 una vez aplicadas?**
Es un script SQL versionado y numerado que lleva la base de un estado al siguiente, aplicado en orden. Si se edita una ya aplicada, las bases donde ya se ejecutó y las nuevas quedarían distintas; las correcciones se hacen con una migración nueva (V002…).

**19. ¿Por qué FREEPDB1 en SQL Developer y no FREE ni un SID?**
FREEPDB1 es el servicio de la PDB donde trabajamos y donde están los 5 esquemas de negocio. FREE (o el SID) conectaría al contenedor raíz (CDB$ROOT), donde no están nuestros datos.

**20. ¿Qué aporta SQLcl frente a SQL*Plus y por qué dominar ambas?**
SQLcl añade autocompletado, historial, formato automático (`SET SQLFORMAT ansiconsole`), conexiones guardadas (`CONNECT -save`, `CONNMGR list`) e integración con Liquibase, y se instala en mi equipo, así que SPOOL escribe en el repositorio. SQL*Plus existe en cualquier servidor Oracle: cuando solo hay una terminal en el servidor es lo que hay.

## Entorno de trabajo

**21. ¿Por qué pasamos de Git Bash a Ubuntu en WSL 2?**
Porque Oracle, Docker y los servidores corren en Linux, y WSL 2 es Linux real, no una emulación. Problemas de Git Bash que desaparecen: convierte rutas como `/opt/...` a rutas de Windows y rompe argumentos de Docker; `docker run -it` necesita `winpty` ("not a TTY"); no trae `free`, `ss` ni `htop`; y las herramientas Java tienen problemas al pedir contraseñas. Además Docker Desktop ya usa WSL 2 como motor.

**22. ¿Por qué clonar en `~/oracle-database-lab` y no en `/mnt/c/...`? ¿Por qué bash y no zsh?**
Trabajar en `/mnt/c` cruza dos sistemas de archivos: Git y Docker van mucho más lentos, no se conservan los permisos de Linux (como el de ejecución) y vuelven los problemas de finales de línea. bash es la shell por defecto en prácticamente todos los servidores, así que un script en bash funciona en cualquier sitio; zsh es una comodidad interactiva con diferencias sutiles (arrays, globbing).
