# Disparo, obliga, afecta y revisar · el diff dicta el contrato y la puerta salta al entregar

Cuatro cambios del 16-09-2026, todos con su batería vista en rojo y su control positivo. Nacen de dos
quejas reales: la puerta saltaba al final de **cada turno** mientras se trabajaba (fricción: escape,
teclear, esperar), y el contrato lo escribía el propio agente (`--scope`, `--check`, `--junta`), así que
una obligación que no declaraba no existía. Ideas tomadas de alibaba/open-code-review (reglas por
ruta deterministas, cobertura obligatoria por fichero, filtro que no descarta de memoria) y de la
literatura de 2026 sobre «done» falso (un juez LLM no distingue un cierre falso de uno real, AUROC ≈ 0,65;
la señal tiene que ser un hecho, no una frase).

## 1. Disparo: cuándo juzga la puerta

`config/disparo.json` (`defecto`, `entrega`, `cierre`, `por_repo`), `config/disparo.local.json` (sin
versionar, pisa clave a clave) y el campo `disparo` del contrato (`rompelo init --disparo`), que manda.

| Modo | PreToolUse (Bash) | UserPromptSubmit | Stop |
|---|---|---|---|
| `entrega` (defecto) | deniega los comandos que **entregan** (commit, push, merge, `gh pr`, deploy…) si el contrato no está cumplido; lo demás pasa sin mirar nada | si el prompt del usuario pide cerrar/entregar («termina», «sube esto», «haz el commit», «a producción»…), declara el cierre y le dice al agente qué falta antes de que empiece | juzga **solo** con el cierre declarado (marca en `state/marcas/cerrando-<repo>`), o si `rompelo close` falló; con todo cumplido retira la marca y calla |
| `turno` | igual | igual | juzga al final de cada turno (comportamiento hasta el 16-09-2026) |

- El deny de PreToolUse no cuenta para el tope de 3 bloqueos: denegar un commit no atrapa al agente en un
  bucle, solo le impide guardar sin evidencia. Trae la misma lista de motivos y la línea `Siguiente:`.
- `rompelo close` en rojo declara el cierre (el agente intentó terminar: desde ahí Stop juzga hasta que cierre
  de verdad). `rompelo close` en verde y `rompelo init --force` retiran la marca. Una marca de más de un día
  es de otra jornada y se ignora.
- La marca solo vale si es de hoy, de **esta** tarea y el contrato está **abierto**. Una marca a nombre de otra tarea
  (init --force desde otra sesión, `git checkout` de `task.json`) o sobre un contrato `cerrada` se retira en silencio:
  lo cerrado ya se entregó y lo que cambie después lo frena el deny al entregar. Por lo mismo, el prompt de cierre
  sobre un contrato cerrado no declara nada: dice que está cerrada, qué falta y que el camino es un contrato nuevo (o
  repetir `check` y `close` si el cambio es de esa tarea). Incidente 17-09-2026: una marca de una prueba en otra sesión
  bloqueó cada turno de una sesión distinta sobre un contrato ajeno y cerrado en otro árbol.
- Con la config ilegible o un `disparo` inválido la puerta no adivina: PreToolUse deniega la entrega y Stop
  bloquea (fail-closed) diciendo qué arreglar.
- `--dry-run` en el comando no es entregar. Los patrones son expresiones regulares (sin mayúsculas) sobre el
  comando entero; `git commit` dentro de `cd x && …` o `git -C dir commit` también casan.
- Hooks: `adapters/claude/settings-fragment.json` (PreToolUse con matcher `Bash`, UserPromptSubmit, Stop,
  PostToolUse, PostToolUseFailure) y `adapters/codex/hooks.json` (PreToolUse, UserPromptSubmit, Stop,
  PostToolUse). Los dos clientes aceptan el mismo JSON de respuesta
  (`hookSpecificOutput.permissionDecision: deny` / `additionalContext`; docs oficiales leídas el 16-09-2026).
  `rompelo doctor` avisa si faltan PreToolUse o UserPromptSubmit.

Lo que NO hace: leer el último mensaje del agente para adivinar si «dijo hecho». Claude Code lo da
(`last_assistant_message`), pero esa señal es exactamente la que un cierre falso imita mejor. La señal es
el comando que entrega o la frase del usuario.

## 2. Obliga: las rutas cambiadas añaden obligaciones

`config/obliga.json` (versionado; las reglas del propio rompelo), `config/obliga.local.json` (sin versionar,
esta máquina), `.rompelo/obliga.json` del repo (versionado: CI lo ve). Formato:

```json
{"reglas": {"functions/api/**": {"junta": true},
            "*.sh": {"checks": ["claveon.shellcheck"]},
            "src/**": {"checks": ["claveon.typecheck", "claveon.test"], "prueba": true}},
 "por_repo": {"/ruta/real/del/repo": {"reglas": {…}}}}
```

Si alguna ruta cambiada casa con un glob, sus `checks` entran en el contrato efectivo (`rompelo check` los
ejecuta, Stop/PreToolUse los exigen, `close` los deja en `obligaciones_efectivas`, CI los repite), `junta`
exige cruce real y `prueba` exige un test cambiado en el diff. El contrato escrito no cambia; el motivo dice
de dónde viene: ``(obliga: *.sh) check `claveon.shellcheck` sin ejecutar``. Un check obligado que no está en
el registro bloquea sin ejecutar nada; un `obliga.json` corrupto o malformado bloquea.

## 3. Afecta: un check solo aplica y solo caduca por sus rutas

En el registro, por check: `"afecta": ["*.sh", "scripts/**"]`. Si ninguna ruta cambiada casa, el check **no
aplica**: ni se exige ni se ejecuta (`rompelo check` lo dice, `verify --ci` lo marca `N/A`). Si aplica, su
huella solo mira esas rutas: editar un `.ts` no caduca la evidencia del check de shell. `no_afecta` sigue
valiendo y se combina. Un check exigido por obliga con `afecta` aplica también a los globs de obliga (la
regla es más específica). Cambiar `afecta` en el registro invalida la evidencia (entra en el hash del check).

Es la palanca de velocidad: la ruta caliente de rompelo ya iba en 50 a 200 ms; lo lento eran suites enteras
repetidas por cambios que no las tocaban.

## 4. Revisar: la segunda pasada con manifiesto

A nivel ≥ 2 (observación) el gate exigía un campo de texto `segunda_pasada` que se ponía el propio agente.
Ahora (`segunda_pasada: revision`, defecto en `config/observacion.json`; `texto` vuelve al campo) exige un
manifiesto cerrado sobre la huella actual:

```
rompelo revisar            # abre .rompelo/evidence/<tarea>/revision.json: cada fichero cambiado (nuevo/modificado/borrado,
                           # +/-, obligaciones de obliga), cómo ver su diff, las reglas (ocr delegate rule si `ocr` está
                           # en PATH, sin LLM; si no, las reglas de la casa) y el criterio
<revisar cada fichero>     # estado: revisado | saltado + motivo; hallazgos: [{id, path, linea, categoria, severidad, texto}]
rompelo revisar --cerrar   # cobertura completa, misma huella, categorías y severidades válidas; los hallazgos pasan al
                           # contrato SIN disposición (bloquean hasta tenerla); escribe `segunda_pasada` con la huella
```

Un cambio posterior caduca la revisión (misma regla que los checks). Volver a abrir el manifiesto sobre la
misma huella conserva lo ya rellenado. Coste: 0 $ de API; lo revisa el mismo agente, así que sigue siendo
una segunda pasada, no un par de ojos independiente (para eso está `ocr.review`).

## 5. Categorías protegidas de hallazgo

Un hallazgo con `categoria` en {security, bug, concurrency, memory, compat, data} (o en español) no se
`rechaza` solo con `motivo`: necesita `comprobado` (qué se ejecutó o leyó que lo refuta). Criterio del filtro
de open-code-review: descartar un acierto en esas categorías cuesta más que conservar un fallo, y la
confianza propia es ahí menos fiable.

## 6. ocr: esfuerzo y presupuesto

`checks/ocr-review.py` pasa `--effort` (OCR_EFFORT=auto|low|medium|high; auto = low hasta OCR_LINEAS_LOW=150
líneas, medium por encima) y `--max-tokens-budget` (OCR_PRESUPUESTO_TOKENS=600000; 0 = sin tope). Si ocr agota
el presupuesto deja ficheros en `warnings` y el envoltorio lo lee como 2 (no pudo mirarlo todo), nunca 0.
Sigue `OCR_MAX_LINEAS` (1500) como tope previo. Medido: una corrida de `verify --ci` con ocr en el contrato
costó 1,3 M tokens (≈ 1,8 $) el 16-09-2026.

## Baterías y controles

| Batería | Casos | Control positivo (mutante) |
|---|---|---|
| `tests/rompelo-disparo-test.sh` | 62 | Stop en `entrega` ignora el cierre declarado → 6 fallos exactos (3 bloqueos que no llegan, 3 marcas que no se retiran) |
| `tests/rompelo-obliga-test.sh` | 38 | toda regla aplica sin ruta que case → 3 fallos exactos |
| `tests/rompelo-revisar-test.sh` | 32 | la revisión vale aunque sea de otro árbol → fallos exactos |
| `tests/rompelo-stop-test.sh` | 222 (+3 de categorías protegidas) | scope anulado |
| `tests/rompelo-observe-test.sh` | 113 | el observador nunca sube a nivel 2 → 4 fallos exactos (nivel, segunda pasada, perfil junta, perfil exterior) |
| `tests/ocr-review-test.sh` | 22 (+5 de effort/presupuesto) | tope anulado |
| `tests/cruce-hooks-entrega.sh` | cruce adaptador → binario con payloads reales; visto ROTO contra el binario anterior | |

Las baterías anteriores fijan `{"defecto":"turno"}` y `{"segunda_pasada":"texto"}` en su `ROMPELO_HOME`
desechable: prueban el Stop por turno y el campo de texto; lo nuevo tiene batería propia.
