---
name: rompelo
description: Abre una tarea con rompelo (contrato con scope, checks del registro y junta) y no la da por entregada hasta que `rompelo close` cierra en verde. Úsala cuando el usuario escriba /rompelo o $rompelo seguido de la tarea, o al empezar cualquier trabajo de código en un repo alistado en rompelo.
---

# rompelo · cómo se trabaja una tarea con la puerta puesta

Lo que viene después de `/rompelo` (o `$rompelo`) es la tarea. Antes de tocar código:

1. **Mira qué hay.** `rompelo doctor` dice si el repo está alistado, qué contrato hay abierto, qué ids de check
   existen en el registro (`~/rompelo/checks/registry.json` y `registry.local.json`) y qué hooks faltan. Los ids
   llevan prefijo de repo: `claveon.test`, `mi-app.typecheck`. Si no hay ninguno para este repo, `rompelo init`
   sin `--check` los detecta de `package.json`, `pyproject`, `Makefile`…
2. **Si hay un contrato abierto de otra sesión**, no lo pises: abre el tuyo con `--force` o trabaja en un
   worktree (dos sesiones sobre la misma raíz comparten `.rompelo/task.json`, INC-0048).
3. **Abre el contrato** con lo que la tarea de verdad necesita:

   ```
   rompelo init --force --id <ID-CORTO> --desc "<la tarea en una línea>" \
     --scope '<rutas que vas a tocar>' [--scope ...] \
     --check <id> [--check ...] [--junta] [--prueba]
   ```

   - `--scope`: solo las rutas que la tarea toca. Cambiar fuera bloquea; eso es lo que se quiere.
   - `--check`: los checks que juzgan este repo (typecheck, test, build, humo). Sin ninguno, la puerta
     no comprueba nada. **Las rutas que cambies pueden añadir más por su cuenta** (`config/obliga.json`,
     `.rompelo/obliga.json`): un `functions/api/**` exige junta, un `*.sh` exige el check de shell. El motivo
     del bloqueo dice `(obliga: <glob>)`; no se discute, se cumple.
   - `--junta`: si tocas algo que solo se prueba cruzando dos lados desplegados aparte (webhook,
     variable de entorno, DNS, cola, contrato de API, `functions/api/`). Obliga a un cruce real.
   - `--prueba`: si cambias código, obliga a que el diff traiga un test cambiado.

4. **Trabaja sin fricción.** Con el disparo `entrega` (defecto) la puerta calla mientras trabajas: no salta al final
   de cada turno. Salta cuando ENTREGAS: un `git commit`, `git push`, `gh pr create`, `wrangler deploy` o un guion
   de despliegue se deniega si el contrato no está cumplido, con los motivos y la línea `Siguiente:`. Y cuando el
   usuario pide cerrar («termina», «sube esto», «haz el commit»…) la puerta juzga al acabar ese turno, y te
   adelanta lo que falta al empezar. No intentes rodear el deny (otro comando, `--no-verify`, editar la evidencia):
   cumple lo que pide y vuelve a lanzar el comando. El observador (`PostToolUse`) mira solo; a nivel 2 exigirá una
   segunda pasada con manifiesto (punto 5) y, según el perfil, cruce o afirmaciones con fuente.
5. **Cierra de verdad**, en este orden y después del último cambio:
   - `rompelo check` (la suite entera puede pasar de 120 s: en Claude Code lánzala con timeout ≥ 300000
     o itera con `rompelo check --id <uno>`). Un check cuyas rutas (`afecta`) no cambiaron dice «no aplica» y no
     se ejecuta: no lo fuerces.
   - Si el bloqueo pide segunda pasada: `rompelo revisar` abre el manifiesto (cada fichero cambiado, cómo ver su
     diff, las reglas, el criterio). Revisa cada fichero de verdad (lee el diff; el fichero entero si hace falta;
     quién lo llama), pon `revisado` o `saltado` + motivo, apunta los hallazgos con ruta, línea, categoría y
     severidad, y `rompelo revisar --cerrar`. Los hallazgos pasan al contrato sin disposición: dales una.
   - Si hay junta: `rompelo cruce --nota '<qué cruzas>' -- <comando real>` o `--id <check del registro>`.
     Una petición real por el camino real, no un mock.
   - `rompelo close`. Imprime el informe: qué se comprobó, qué no se pudo, qué queda a cargo del usuario.
     Un `close` en rojo declara el cierre: desde ahí la puerta juzga cada turno hasta que cierre en verde.
6. **Si la puerta deniega o bloquea**, lee los motivos y resuélvelos con lo que piden (`check`, `revisar`, `cruce`,
   disposición del hallazgo). Lo que no puedas cumplir se declara, no se maquilla:
   - una afirmación sobre el mundo exterior va en `afirmaciones` con estado `verificado` (fuente +
     cita), `derivado` (de qué) o `no_verificado` (qué falta);
   - un hallazgo se cierra con `confirmado` (+ `regresion`), `rechazado` (+ `motivo`; si es de `security`, `bug`,
     `concurrency`, `memory`, `compat` o `data`, además `comprobado`: qué ejecutaste o leíste que lo refuta) o
     `aceptado` (+ `nota`); «pendiente» no desbloquea;
   - algo que no se puede comprobar aquí va en `excepciones: [{que, motivo, quien}]`, con nombre
     del responsable;
   - un motivo que empieza por «el repo está en nivel 2 desde <fecha>» o «el repo tiene perfil `junta` desde
     <fecha>» viene del estado del observador del REPO (`rompelo nivel` lo enseña), no de tu diff: se cumple igual
     (segunda pasada, cruce). El nivel solo se baja con `rompelo nivel bajar --motivo '<por qué>'` cuando el patrón
     que lo subió está resuelto de verdad y el usuario lo decide en ese turno; nunca para conseguir verde.

Prohibido para conseguir verde: editar `.rompelo/evidence/`, quitar checks del contrato, ampliar el
scope a `**` porque sí, bajar `min_lineas`, borrar tests, cambiar el disparo a mitad de tarea, marcar
`revisado` sin haber leído el diff, escribir `segunda_pasada` a mano, o bajar el nivel del repo (`rompelo nivel
bajar`) para que deje de pedir segunda pasada o cruce. Un verde que no has visto rojo no es
información.

Al terminar, di qué se comprobó, qué quedó como NO VERIFICADO y por qué, y pega el informe de
`rompelo close`.
