# Respuestas — Laboratorio 1: Git Fundamentals

## 1. Working Directory, Staging Area y Local Repository

El Working Directory es la carpeta del proyecto que veo y modifico en mi ordenador. La Staging Area es una zona intermedia donde preparo de forma explícita los cambios que quiero incluir en el siguiente commit. El Local Repository es el historial local de commits que Git guarda dentro de la carpeta `.git`.

Por ejemplo, al editar `README.md`, el cambio está primero en el Working Directory. Cuando ejecuto `git add README.md`, pasa a la Staging Area. Finalmente, al ejecutar `git commit -m "docs: update README"`, queda guardado como una versión permanente en el Local Repository.

## 2. Cambio sin `git add`

No. Si modifico un archivo pero no ejecuto `git add`, ese cambio no aparece en el siguiente commit. Git solo confirma lo que se encuentra en la Staging Area. Por eso conviene revisar `git status` y `git diff --staged` antes de confirmar.

## 3. Carpetas vacías

Git no versiona carpetas directamente; versiona archivos. Una carpeta vacía no contiene nada que Git pueda registrar, por lo que no aparece en `git status`. Para conservarla usamos un archivo vacío llamado `.gitkeep` dentro de la carpeta.

## 4. HEAD

HEAD es un puntero que indica en qué commit y en qué rama estoy trabajando ahora. Por ejemplo, cuando estaba en `feature/customer-search`, HEAD apuntaba al commit que añadía `docs/customer-search.md`. Al cambiar a `main`, HEAD pasó al último commit de `main`.

## 5. Branch frente a carpeta

Crear una branch con `git switch -c nombre-rama` crea una línea independiente del historial de commits y cambia a ella. No crea una carpeta nueva en el disco. En cambio, `mkdir` crea una carpeta física en el sistema de archivos. Lo comprobé al crear `feature/customer-search`: no apareció ninguna carpeta llamada `feature`, pero `customer-search.md` desaparecía al cambiar a `main` y reaparecía al volver a la rama.

## 6. Marcadores de conflicto

Entre `<<<<<<< HEAD` y `=======` estaba el contenido que ya tenía mi rama actual, `main`: la versión Training Edition. Entre `=======` y `>>>>>>> fix/readme-subtitle` estaba el contenido que venía de la rama que estaba fusionando: la versión Academic Version. Tuve que elegir y escribir el resultado final eliminando los marcadores.

## 7. Por qué no usar `--amend` tras `push`

No se debe usar `git commit --amend` sobre un commit que ya se ha subido porque reescribe el historial y cambia el hash del commit. Si otras personas ya descargaron el commit antiguo, sus historiales pueden divergir y causar problemas al sincronizar. Tras un `push`, es más seguro crear un commit nuevo que corrija el anterior.

## 8. Borrar `.git`

Si borro la carpeta `.git`, pierdo toda la información de Git local: commits, ramas, configuración local, referencias al remoto y el historial. El código fuente y los archivos normales del proyecto seguirían en el disco, pero la carpeta dejaría de ser un repositorio Git hasta inicializarlo de nuevo.

## 9. Git y GitHub

Git es el programa de control de versiones instalado en mi ordenador. Permite crear commits, ramas, merges e historial incluso sin conexión. GitHub es una plataforma web para alojar repositorios Git y colaborar con otras personas mediante ramas remotas, Pull Requests, Issues, revisiones de código y automatizaciones.

## 10. Archivo `.env` con contraseñas

No se debe subir un archivo `.env` con contraseñas, tokens o claves reales porque cualquier persona con acceso al repositorio podría verlas, copiarlas o utilizarlas. Incluso si el repositorio es privado, una filtración, una captura o permisos mal configurados pueden exponerlas. Si se sube una credencial por accidente, se debe revocar o rotar inmediatamente.

## 11. Error `non-fast-forward`

Probablemente el remoto contiene commits nuevos que el compañero no tiene en su copia local, por ejemplo porque alguien cambió un archivo directamente en GitHub o hizo push desde otro ordenador. Primero ejecutaría `git pull`, resolvería un posible conflicto si fuera necesario y después volvería a ejecutar `git push`.

## 12. Tipos de Conventional Commit

Para añadir un índice de rendimiento a una tabla usaría `perf`, por ejemplo: `perf(db): add customer lookup index`.

Para corregir una restricción mal definida usaría `fix`, por ejemplo: `fix(db): correct customer foreign key`.

Para actualizar el README usaría `docs`, por ejemplo: `docs: update project README`.