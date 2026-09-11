---
name: rompelo
description: Abre una tarea con rompelo (contrato con scope, checks del registro y junta) y no la da por terminada hasta que `rompelo close` cierra en verde. Úsala cuando el usuario escriba /rompelo o $rompelo seguido de la tarea, o al empezar cualquier trabajo de código en un repo alistado en rompelo.
---

# rompelo · cómo se trabaja una tarea con la puerta puesta

Lo que viene después de `/rompelo` (o `$rompelo`) es la tarea. Antes de tocar código:

1. **Mira qué hay.** `rompelo doctor` dice si el repo está alistado, qué contrato hay abierto y qué
   ids de check existen en el registro (`~/rompelo/checks/registry.json` y `registry.local.json`).
   Los ids llevan prefijo de repo: `claveon.test`, `mi-app.typecheck`. Si no hay ninguno para este
   repo, `rompelo init` sin `--check` los detecta de `package.json`, `pyproject`, `Makefile`…
2. **Si hay un contrato abierto de otra sesión**, no lo pises: abre el tuyo con `--force` o trabaja en
   un worktree (dos sesiones sobre la misma raíz comparten `.rompelo/task.json`, INC-0048).
3. **Abre el contrato** con lo que la tarea de verdad necesita:

   ```
   rompelo init --force --id <ID-CORTO> --desc "<la tarea en una línea>" \
     --scope '<rutas que vas a tocar>' [--scope ...] \
     --check <id> [--check ...] [--junta] [--prueba]
   ```

   - `--scope`: solo las rutas que la tarea toca. Cambiar fuera bloquea; eso es lo que se quiere.
   - `--check`: los checks que juzgan este repo (typecheck, test, build, humo). Sin ninguno, la puerta
     no comprueba nada.
   - `--junta`: si tocas algo que solo se prueba cruzando dos lados desplegados aparte (webhook,
     variable de entorno, DNS, cola, contrato de API, `functions/api/`). Obliga a un cruce real.
   - `--prueba`: si cambias código, obliga a que el diff traiga un test cambiado.

4. **Trabaja.** El observador (`PostToolUse`) mira solo; a nivel 2 pedirá `segunda_pasada` en el
   contrato y, según el perfil, cruce o afirmaciones con fuente.
5. **Cierra de verdad**, en este orden y después del último cambio:
   - `rompelo check` (la suite entera puede pasar de 120 s: en Claude Code lánzala con timeout ≥ 300000
     o itera con `rompelo check --id <uno>`).
   - Si hay junta: `rompelo cruce --nota '<qué cruzas>' -- <comando real>` o `--id <check del registro>`.
     Una petición real por el camino real, no un mock.
   - `rompelo close`. Imprime el informe: qué se comprobó, qué no se pudo, qué queda a cargo del usuario.
6. **Si el Stop bloquea**, lee los motivos y resuélvelos con lo que piden (`check`, `cruce`,
   disposición del hallazgo, `segunda_pasada`). La última línea, «Siguiente:», trae los comandos exactos
   en orden; lo que no lleva comando (un hallazgo, una ruta fuera de scope) se resuelve en el contrato o
   en el código. Lo que no puedas cumplir se declara, no se maquilla:
   - una afirmación sobre el mundo exterior va en `afirmaciones` con estado `verificado` (fuente +
     cita), `derivado` (de qué) o `no_verificado` (qué falta);
   - un hallazgo se cierra con `confirmado` (+ `regresion`), `rechazado` (+ `motivo`) o `aceptado`
     (+ `nota`); «pendiente» no desbloquea;
   - algo que no se puede comprobar aquí va en `excepciones: [{que, motivo, quien}]`, con nombre
     del responsable.

Prohibido para conseguir verde: editar `.rompelo/evidence/`, quitar checks del contrato, ampliar el
scope a `**` porque sí, bajar `min_lineas`, borrar tests, o escribir `segunda_pasada` sin haber
revisado. Un verde que no has visto rojo no es información.

Al terminar, di qué se comprobó, qué quedó como NO VERIFICADO y por qué, y pega el informe de
`rompelo close`.
