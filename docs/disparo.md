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
| `entrega` (defecto) | deniega los comandos que **publican** (`gh pr merge`, `git push` a main/master, `wrangler deploy`, `scripts/desplegar`, deploy…) si el contrato no está cumplido; lo demás pasa sin mirar nada. Hasta el 28-10-2026 también commit, push a una rama y `gh pr create`: José («utiliza rompelo solamente a la hora de desplegar, no cada vez que haces una tarea») los sacó de la lista | si el prompt del usuario pide desplegar o publicar («despliega», «a producción», «ship it», «release»…), declara el cierre y le dice al agente qué falta antes de que empiece | juzga **solo** con el cierre declarado (marca en `state/marcas/cerrando-<repo>`), o si `rompelo close` falló; con todo cumplido retira la marca y calla |
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
- El comando se juzga **por tramos** (partido por `&&`, `||`, `;`, `|`, salto de línea, paréntesis y comillas),
  no por el texto entero (17-09-2026). Así `git push --dry-run && git push` entrega (el `--dry-run` solo exime a su
  tramo) y `bash -c 'git commit …'` o `eval "git push"` también (hasta entonces pasaban: el patrón exigía un
  separador de shell delante). El precio: si «git commit» solo aparece citado (un `grep`, un mensaje), la puerta
  deniega y lo dice; fail-closed. Los patrones siguen siendo expresiones regulares (sin mayúsculas), ahora sobre
  cada tramo; `git -C dir commit` casa igual.
- Un comando compuesto (`pnpm test && git add -A && git commit`) se deniega **entero**: la puerta no deja pasar
  la mitad, y el motivo dice qué tramo entrega y que la preparación vaya en un comando aparte.
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

## 6b. Lo que se escribe por subcomando (29-10-2026)

Hasta el 29-10 el agente editaba `task.json` y `revision.json` a mano: cinco contratos quedaron ilegibles
(`JSONDecodeError` en el hook, bloqueo sin salida) y «hallazgo sin disposición» fue el bloqueo más repetido
(46 veces en 47 sesiones). Ahora:

- `rompelo hallazgo` lista los hallazgos y qué les falta; `rompelo hallazgo <id> confirmado --regresion X |
  rechazado --motivo M [--comprobado C] | aceptado --nota N` escribe la disposición de forma atómica y **solo si el
  gate la va a aceptar** (mismo criterio, `motivo_hallazgo`): lo que falta se dice en el momento, no en el Stop.
- `rompelo afirmar '<texto>' verificado --fuente F --cita C | derivado --de D | no_verificado --falta F`.
- `rompelo revisar --revisado <ruta>...`, `--saltado --motivo M <ruta>...`, `--hallazgo ID --path P [--linea N]
  [--categoria C] [--severidad S] --texto T` rellenan el manifiesto; una ruta que no está en el diff no se puede
  marcar (marcar lo que no cambió no es revisar).
- `rompelo check <id>` acepta los ids sueltos (ocho veces en sesiones reales el agente los dio así y salía con
  error); un `--flag` desconocido sigue siendo error. `rompelo <subcomando> --help` existe.
- A nivel 2, un contrato cuyo árbol no difiere de la base **no** exige manifiesto: no hay nada que revisar
  (11-10-2026: «nada que revisar» y `close` pidiendo una segunda pasada imposible).

## 7. Base del contrato: `rompelo base --mover`

El contrato mide la tarea contra `base`, el commit que `init` escribió. En una tarea larga otros fusionan sus PR
en la rama: contra la base vieja esas rutas salen como «fuera de scope» y arrastran checks caducados que no son
de esta tarea (17-09-2026: 38 rutas ajenas en un contrato de ClaveON, añadidas a mano una a una).

```
rompelo base                                  # base, HEAD, commits por delante y qué rutas traen; movimientos anteriores
rompelo base --mover [REF] --motivo '<por qué>'   # adelanta la base (REF por defecto HEAD)
```

Reglas, todas fail-closed: solo hacia delante (REF desciende de la base), solo dentro de la historia de HEAD,
con motivo obligatorio, y queda escrito en el contrato (`base_movida`: de, a, fecha, motivo, commits, rutas
absorbidas). La huella cambia con la base, así que la evidencia anterior caduca y hay que repetir `rompelo check`
(y `close`). No esconde trabajo sin juzgar: lo que el agente pudo commitear ya pasó por la puerta (PreToolUse
deniega el commit con el contrato sin cumplir, y con el contrato cerrado un cambio posterior también).

### 7b. `--mover` sin REF (29-10-2026)

Tras un `git rebase origin/main`, HEAD lleva lo ajeno **y** los commits propios: `--mover` a HEAD vaciaba el diff y a
nivel 2 ya no había nada que revisar ni cerrar (19-10-2026, dos `reset --soft`). Sin REF, la base va ahora a la base
común de HEAD con el upstream (`@{upstream}`, si no `origin/main`, `origin/master`) cuando está por delante de la base;
sin upstream, a HEAD como antes. Y sin REF **nunca** se absorben rutas del `scope_paths` (eso es absorber el trabajo
de la tarea): se niega y dice qué REF dar; `--mover HEAD` explícito sí lo hace, a propósito.

## 8. `rompelo check`: vigente y compartido (29-10-2026)

El 28-10-2026, en un worktree de ClaveON, `rompelo init` estrenó `claveon_b2c-umland.test` (mismo `pnpm test` que
`claveon.test`, que entraba por obliga) y la suite de seis minutos corrió dos veces por pasada; y perseguir un rojo
suelto la repetía entera cada vez. Tres cambios:

- `init` nombra los ids por el repo **principal** (`git rev-parse --git-common-dir`), no por la carpeta del worktree,
  y un comando ya registrado bajo otro id (`pnpm typecheck` ≡ `pnpm run typecheck`) se reutiliza con su `afecta` y
  su control positivo en vez de estrenar un gemelo sin nada.
- `rompelo check --pendientes` no repite un check cuya evidencia ya es verde sobre esta misma huella (su huella, con
  `afecta`/`no_afecta`) y con esta misma definición: dice «vigente … no se repite». Es exactamente lo que el gate
  acepta. Sin la opción, `rompelo check` ejecuta lo que se le pide: un control positivo que se quedó ciego sin que
  cambiara el registro solo se descubre ejecutándolo (batería «control recién fallado»). La línea `Siguiente:` del
  bloqueo ya nombra solo los ids que faltan.
- Dos ids con el mismo argv y cwd corren una vez por pasada; la evidencia del segundo dice `compartida_con`. El
  control positivo es de cada id y se ejecuta aparte.

El estado se poda solo: en cada Stop, como mucho una vez al día (`state/.poda`), se borran libros de sesión, cachés
de Codex y marcas con más de 30 días (había 489 libros y 63 marcas de septiembre). `rompelo repos --podar` quita de la
allowlist las rutas que ya no existen (worktrees borrados).

## Baterías y controles

| Batería | Casos | Control positivo (mutante) |
|---|---|---|
| `tests/rompelo-disparo-test.sh` | 67 | Stop en `entrega` ignora el cierre declarado → 6 fallos exactos (3 bloqueos que no llegan, 3 marcas que no se retiran) |
| `tests/rompelo-obliga-test.sh` | 38 | toda regla aplica sin ruta que case → 3 fallos exactos |
| `tests/rompelo-revisar-test.sh` | 32 | la revisión vale aunque sea de otro árbol → fallos exactos |
| `tests/rompelo-stop-test.sh` | 242 (+3 de categorías protegidas, +17 de la base movible) | scope anulado → 2 fallos exactos (el fichero fuera de scope y el commit ajeno tras la base) |
| `tests/rompelo-observe-test.sh` | 113 | el observador nunca sube a nivel 2 → 4 fallos exactos (nivel, segunda pasada, perfil junta, perfil exterior) |
| `tests/instrumento-test.sh` | 26 distinciones | `es_bloqueo` de `lib.sh` acepta cualquier JSON → 2 fallos exactos |
| `tests/portabilidad-test.sh` | 19 | el estado del repo se nombra por carpeta y no por ruta → 3 fallos exactos |
| `tests/ocr-review-test.sh` | 22 (+5 de effort/presupuesto) | tope anulado |
| `tests/cruce-hooks-entrega.sh` | cruce adaptador → binario con payloads reales; visto ROTO contra el binario anterior | |

Las baterías anteriores fijan `{"defecto":"turno"}` y `{"segunda_pasada":"texto"}` en su `ROMPELO_HOME`
desechable: prueban el Stop por turno y el campo de texto; lo nuevo tiene batería propia.
