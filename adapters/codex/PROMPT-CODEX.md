# Encargo para Codex · rompelo, lado Codex y módulo «control positivo»

Contexto en una línea: `~/rompelo/` es una puerta de cierre por tarea para agentes de código.
Un hook `Stop` llama a `~/rompelo/bin/rompelo hook <agente>`, que lee `.rompelo/task.json` del
repo y bloquea el cierre hasta que el contrato se cumple. Hoy funciona y está cruzado en vivo
en Claude Code. Tu trabajo tiene dos partes, en este orden. Lee antes `~/rompelo/README.md`,
`~/rompelo/adapters/codex/LEEME.md` y `~/rompelo/bin/rompelo --help`.

Reglas que no se negocian:
- No escribas en `~/.claude/**`. Es de Claude Code. Tú solo tocas `~/.codex/**` y `~/rompelo/**`.
- `~/rompelo/bin/rompelo` sigue siendo Python 3.9 con biblioteca estándar. Sin PyYAML, sin
  dependencias, sin reescribirlo en Bash ni en TypeScript, sin monorepo.
- Nada se da por bueno sin haberlo visto fallar. Cada condición nueva del gate se ve primero en
  ROJO con un caso que la incumple y luego en VERDE con uno bueno, y las dos cosas quedan en
  `~/rompelo/tests/rompelo-stop-test.sh`. Antes de tocar nada, las dos baterías tienen que estar en
  verde: `bash ~/rompelo/tests/rompelo-stop-test.sh` (hoy: PASS=77 FAIL=0) y
  `bash ~/rompelo/tests/rompelo-observe-test.sh` (hoy: PASS=64 FAIL=0).
- Cuando mutes un fichero para ver rojo, comprueba que la mutación ocurrió (grep del cambio) y
  que crea el fallo que buscas. Una mutación que no casa no prueba nada.
- Commits en `~/rompelo` con mensajes en español y sin ninguna atribución a IA
  (nada de Co-Authored-By ni «generated with»).
- No toques producción ni datos de clientes. Todo en repos desechables (`mktemp -d`).
- Lo que no puedas verificar se entrega como NO VERIFICADO, diciendo qué falta.

## Parte 1 · Instalar el hook Stop de rompelo en Codex y cruzarlo en vivo

> **Hecha el 05-09-2026.** Hooks fusionados y confiados; cruce en vivo con `codex exec` desde Claude
> Code (bloqueo literal, cierre, silencio, tope de tres). Punto 4 respondido: Codex no manda código
> de salida; el observador firma por heurística de texto (INC-2026-0036, `LEEME.md`). Si retomas
> este encargo, salta directamente a la Parte 2.

1. Fusiona, sin sustituir, las entradas `Stop` y `PostToolUse` de
   `~/rompelo/adapters/codex/hooks.json` en `~/.codex/hooks.json`. Ya existen dos hooks Stop
   (`global_protocol.py` y el de ai-memory); se quedan. Si hay una entrada antigua que apunta a
   `~/assure/bin/assure` (nombre viejo; hoy vive un shim que reenvía), sustitúyela por
   `"$HOME/rompelo/bin/rompelo" hook codex`. El guion de fusión está en
   `~/rompelo/adapters/codex/LEEME.md`. Haz copia previa de `~/.codex/hooks.json` con fecha en
   el nombre.
2. La confianza del hook la da José en la interfaz de Codex (`/hooks`, revisar y confiar).
   Dile exactamente qué entrada tiene que aceptar. No intentes escribir el hash de confianza
   en `config.toml` a mano.
3. Cruce real, después de que José lo haya confiado:
   - crea un repo desechable, haz un commit, y dentro ejecuta
     `~/rompelo/bin/rompelo init --id CRUCE-CODEX --check rompelo.sin-var-pegada --junta`
     (eso lo alista en `~/rompelo/config/repos.json`);
   - termina el turno con el contrato sin cumplir. Tiene que llegarte un bloqueo con dos
     motivos: check sin ejecutar y junta sin cruzar;
   - cumple el contrato (`rompelo check`, `rompelo cruce -- true`, `rompelo close`) y termina el
     turno otra vez: silencio;
   - quita el repo desechable de `~/rompelo/config/repos.json` y bórralo.
   Reporta las tres cosas con la salida literal del bloqueo. Si no llega el bloqueo, no lo
   arregles a ciegas: mide si el hook corrió (`~/.codex/hooks.json`, estado en `config.toml`,
   salida de `printf '{"cwd":"<repo>","session_id":"x"}' | ~/rompelo/bin/rompelo hook codex`).
4. Forma real de `tool_response` en un comando que FALLA. La doc de Codex dice que `PostToolUse`
   «also runs after commands that exit with a non-zero status», pero no dice qué forma tiene
   `tool_response` para Bash. `rompelo observe codex` acepta un campo entero `exit_code`
   (también dentro de `metadata`) o una primera línea `Exit code N`; si Codex manda otra cosa,
   el observador anota 0 y dos disparadores (firma repetida, check en rojo) quedan ciegos, que
   es exactamente INC-2026-0031 en Claude Code. Con el hook `PostToolUse` conectado, ejecuta
   `ls /no-existe` y mira el libro `~/rompelo/state/sesiones/codex-<session>.jsonl`: la última
   línea tiene que llevar `"codigo": 1` (o 2). Si lleva 0 o null, captura SOLO las claves y la
   primera línea de `tool_response` (nunca el texto) y reporta la forma para adaptar
   `evento_desde_hook` en `bin/rompelo`.
5. Anota el resultado en `~/rompelo/adapters/codex/LEEME.md`, sección «Estado», con fecha.

## Parte 2 · Módulo «control positivo»: que un check no pueda dar verde sin haber mirado

> **Implementada el 05-09-2026 sobre c652432.** Gate 109/109; registro con triestado y dos
> controles reales. Resultados y límites en `docs/control-positivo.md`. Los requisitos de
> abajo se conservan como contrato de la implementación; no implican controles específicos
> ya conectados a ClaveON.

Motivo, medido en `~/rompelo/corpus/TABLA.md`: de 35 incidentes reales, la clase mayor (15) es
«la comprobación no podía fallar»: validador sobre el artefacto equivocado, instrumento que
muere y sale con el código de hallazgo, `pnpm audit` con 0 tras un timeout, «no tests» leído
como 0 fallos, mutación que no casó, un observador que nunca recibía los fallos (INC-0031).
Hoy `rompelo` ya exige `min_lineas`. Falta esto:

1. **Triestado en el registro.** En `~/rompelo/checks/registry.json` cada check puede declarar
   `"triestado": true`. Significa que el comando promete 0 = limpio, 1 = hay hallazgos,
   2 = no pude mirar. `rompelo check` guarda el código tal cual y el gate distingue los motivos:
   con 1 «FALLÓ», con 2 «NO PUDO MIRAR (instrumento, no hallazgo)», y cualquier otro código
   distinto de 0 en un check triestado se trata como «abortó por una ruta no prevista», que
   bloquea con su propio motivo. Ejemplo ya escrito: `~/rompelo/tests/sin-var-pegada.sh`.
2. **Control positivo por check.** Cada entrada del registro puede declarar
   `"control_positivo": {"argv": [...], "cwd": "repo|rompelo"}`: un comando que ejecuta el
   mismo instrumento sobre una entrada que SABEMOS mala y que por tanto TIENE que salir con 1.
   `rompelo check` lo ejecuta antes del check real. Si el control positivo sale con 0, el
   instrumento está ciego: la evidencia se guarda con `"instrumento": "ciego"` y el gate bloquea
   con «check X: su control positivo no detectó el caso malo; el verde no vale». Si sale con 2,
   «no pudo mirar». Solo con 1 se ejecuta el check real y cuenta.
   Escribe el control positivo para `rompelo.sin-var-pegada` (un guion temporal con `«$X»`) y
   para `rompelo.tests` (la batería sobre una copia de `bin/rompelo` con una condición anulada,
   por ejemplo la de scope, tiene que dar FAIL>0).
3. **`rompelo check` informa de lo visto, no solo de lo malo.** En la salida de cada check,
   además del código: si el registro declara `min_lineas`, cuántas líneas produjo; si declara
   `control_positivo`, qué dio. Nada de la salida del comando se guarda (puede llevar secretos):
   solo recuentos y hashes, como ahora.
4. **Batería.** Casos nuevos, cada uno visto en rojo y en verde, con el `ROMPELO_HOME`
   desechable que ya usa la batería: control positivo que pasa (bloquea, «ciego»); control
   positivo con 2 (bloquea, «no pudo mirar»); check triestado con 2 (bloquea con su motivo,
   distinto de FALLÓ); check triestado con código 3 (bloquea, «ruta no prevista»); y el caso
   bueno (control positivo con 1, check con 0: silencio).
5. **Corpus.** Marca en los YAML de `~/rompelo/incidents/` (campo `existe_hoy`) qué incidentes
   de clase I quedan cubiertos por esto, y regenera la tabla:
   `python3 ~/rompelo/bin/rompelo-corpus.py`. No inventes cobertura: solo los que un control
   positivo o el triestado habrían cazado de verdad.
6. Cierra tu propia tarea con rompelo: en `~/rompelo` el contrato `ROMPELO-CODEX-01` está
   cerrado; abre uno nuevo con `rompelo init --force --id ROMPELO-CODEX-02 --check rompelo.tests
   --check rompelo.cruce-settings-claude --check rompelo.sin-var-pegada --check rompelo.observe-tests
   --check rompelo.control-negativo-sesiones --junta` (el último tarda dos o tres minutos:
   reproduce cinco sesiones reales de esta máquina), y no des la tarea por terminada hasta que
   `rompelo verify` dé 0 y el hook te deje parar.

## Parte 3 · Ponerte al día con la herramienta (06-09-2026, commit `fa672f9`)

Contexto: una auditoría desde otra sesión de Claude Code encontró que `rompelo check no.existe`
ejecutaba todos los checks, decía «todos en verde» y salía 0 (INC-0037, verde ambiguo), y que la
suite entera (~250 s) supera el timeout de 120 s de la herramienta Bash de Claude Code. Está
arreglado y subido a `origin/main`. Tu trabajo aquí es actualizarte, no construir.

1. `git -C ~/rompelo pull --ff-only` y lee `CHANGELOG.md` («Sin publicar») y
   `~/rompelo/bin/rompelo --help`. Lo que cambia para ti:
   - `rompelo check` solo admite `--id ID` (repetible, acotado a los checks del contrato).
     Cualquier otro argumento es error sin ejecutar nada. Para iterar durante el desarrollo:
     `rompelo check --id rompelo.tests`. Para cerrar hace falta el `check` completo, porque la
     huella vincula cada evidencia al árbol actual.
   - Corpus 38 (I=18): INC-0037 y INC-0038 (código de salida del envoltorio que no es el del
     trabajo: un `for … done` que acaba en `[ … ] && …` sale 1 con todo en verde). No envuelvas
     `rompelo check` en bucles propios; su código ya es el recuento de rojos.
   - `docs/observacion.md` §9: el control positivo del observador abarca dos llamadas de
     herramienta separadas; la allowlist va por raíz de árbol y un worktree es raíz aparte.
2. Baterías en verde antes de tocar nada: `bash tests/rompelo-stop-test.sh` (hoy PASS=113
   FAIL=0) y `bash tests/rompelo-observe-test.sh` (anota el recuento que veas).
3. Tu hook no cambia: `~/.codex/hooks.json` sigue apuntando a `"$HOME/rompelo/bin/rompelo"
   hook codex` y `observe codex`; la confianza va sobre `hooks.json`, no sobre el binario, así
   que no debería pedirte reconfiar. NO VERIFICADO desde aquí: compruébalo con un turno en
   `~/rompelo` con el contrato abierto (tiene que llegarte el bloqueo).
4. Anota en `adapters/codex/LEEME.md`, sección «Estado», con fecha: recuentos de las dos
   baterías y si el bloqueo llegó.

Encargo opcional, solo si José lo pide: firma del observador para INC-0038 («verde ambiguo al
revés»: código distinto de 0 con la última línea de stdout igual al resumen de verde del propio
check). Caso en rojo primero, en `tests/rompelo-observe-test.sh`.

## Parte 4 · Cruzar en vivo el binario nuevo de la auditoría (07-09-2026, PR #1)

Contexto: una auditoría externa encontró 19 puntos (RMP-001…019) y se arreglaron en la rama
`mejoras-auditoria-2026-09-07` (PR #1, CI en verde en Ubuntu). Lo que te toca a ti es lo que solo
un cliente Codex real puede comprobar. **Precondición:** José ha fusionado el PR. Si `git -C ~/rompelo
log --oneline -1 origin/main` no muestra «contrato MEJORAS-AUDITORIA-2026-09-07 cerrado» o posterior,
para y dilo: no cambies de rama en `~/rompelo` (es el binario que ejecutan los hooks de todas las
sesiones).

1. `git -C ~/rompelo pull --ff-only`. Lee `CHANGELOG.md` («Sin publicar») y
   `docs/auditoria-2026-09-07/SEGUIMIENTO.md`. Lo que cambia para ti:
   - `apply_patch` ya se observa: tus ediciones quedan en el libro con sus rutas (antes, 64 eventos
     reales sin fichero). `hookEventName` de la respuesta es el del evento recibido.
   - `rompelo permiso <x> no` revoca de verdad y el check queda pendiente; un permiso para un id de
     `checks_nivel3` autoriza solo ese; sin `--recordar` no pasa a otra tarea.
   - Evidencia sin `argv`; huella `v2:` (la evidencia vieja pide `rompelo check` de nuevo); una `base`
     ausente es error; `verify --ci` dice «OK PARCIAL» cuando algo queda sin comprobar.
   - `rompelo doctor` y `rompelo state prune --dias N [--dry-run]` existen.
2. `rompelo doctor` en `~/rompelo`: tiene que decir «hooks Codex: … → Stop, PostToolUse» y un
   registro con 7 checks. Copia esa salida (sin rutas de secretos, no las hay) a tu nota.
3. Abre tu contrato, no uses el que hay (INC-0048: dos sesiones comparten `.rompelo/task.json`):
   `rompelo init --force --id ROMPELO-CODEX-04 --scope adapters/codex/LEEME.md --check rompelo.tests
   --check rompelo.observe-tests --check rompelo.instrumento-tests --check rompelo.portabilidad-tests
   --check rompelo.sin-var-pegada --check rompelo.cruce-settings-claude
   --check rompelo.control-negativo-sesiones --junta`.
4. Cruces que solo tú puedes hacer, en este orden, anotando cada resultado:
   a. **Stop.** Edita `adapters/codex/LEEME.md` (una línea) y termina el turno sin `rompelo check`.
      Tiene que llegarte el bloqueo con «sin ejecutar» y «huella». Si no llega, es el hallazgo
      principal: anótalo y sigue.
   b. **apply_patch.** Haz esa edición con `apply_patch`, no con shell. Luego:
      `tail -1 ~/rompelo/state/sesiones/codex-<tu session_id>.jsonl` tiene que llevar
      `"tool": "apply_patch"` y `"ficheros": ["/Users/rootml/rompelo/adapters/codex/LEEME.md"]`.
      Si `ficheros` va vacío, anota la forma del payload con `ROMPELO_DEBUG_FORMA=1` (solo claves).
   c. **Permiso.** `rompelo permiso rompelo.tests si` → `rompelo nivel` dice 3; `rompelo permiso
      rompelo.tests no` → dice 0 y el siguiente Stop menciona «permiso revocado» si el check está
      en `checks_nivel3` (ponlo ahí un momento para verlo; luego quítalo).
   d. **Cierre.** `rompelo check` (la suite entera tarda ~5 min; en Codex no hay timeout de 120 s),
      `rompelo cruce --id rompelo.cruce-settings-claude`, `rompelo close`. El Stop siguiente tiene
      que callar.
5. Anota en `adapters/codex/LEEME.md`, sección «Estado», con fecha y `codex --version`: recuentos de
   las baterías, si llegó el bloqueo, si `apply_patch` dejó las rutas, si revocar dejó el check
   pendiente. Lo que no llegaste a ver, como NO VERIFICADO.

No toques `bin/rompelo` ni `tests/`: si algo falla, es un hallazgo para José, no un arreglo tuyo.
No toques `~/.claude/`. Tu `~/.codex/hooks.json` no debería necesitar cambios (la confianza va sobre
`hooks.json`, no sobre el binario).

## Parte 5 · Cruzar desde Codex lo del 11-09-2026 (PR #2) y medir lo que solo Codex sabe

Tu Parte 4 está incorporada (`LEEME.md`, contrato en `docs/auditoria-2026-09-07/contrato-ROMPELO-CODEX-04.json`)
y motivó dos cambios: `config/permisos.json` ya no está versionado (aparecía «fuera de scope_paths» al pedir
permiso dentro de este repo) y un check puede declarar en el registro las rutas que no lo invalidan
(`no_afecta`): tu segundo bloqueo decía «`rompelo.sin-var-pegada` se ejecutó sobre otro árbol» por editar
`LEEME.md`, y eso ya no pasa. Lo que trae esta versión, con detalle en `CHANGELOG.md` («Sin publicar»):

- Cada bloqueo termina con una línea **«Siguiente: …»** (`Next:` en inglés) con los comandos exactos, en
  orden: `rompelo check` (o `--id` por cada check caducado), `rompelo cruce …`, `rompelo close`.
- El observador **no lanza ningún proceso**: halla la raíz subiendo hasta `.git` (también en un worktree,
  donde `.git` es un fichero). El Stop lanza 3 procesos git en vez de 7.
- **`no_afecta`** por check en el registro; los siete `rompelo.*` llevan `docs/**`, `*.md`, `corpus/**`,
  `incidents/**`.
- `rompelo check` **avisa cuando el propio check cambia el árbol**, con las rutas.
- `rompelo init` sin `--check` detecta más ecosistemas (`bun run test`, `test:*`, deno, composer, uv, ruff y
  mypy solo si están configurados, mix, rspec, Gradle, Maven, .NET, Swift, justfile, Taskfile).

**Precondición:** José ha fusionado el PR #2. Si `git -C ~/rompelo log --oneline -1 origin/main` no muestra
«contrato MEJORAS-2026-09-11 cerrado» o posterior, para y dilo. No cambies de rama en `~/rompelo`.

1. `git -C ~/rompelo pull --ff-only`; `rompelo doctor` en `~/rompelo` tiene que decir «revisión de rompelo»
   con el commit nuevo y «hooks Codex: … → Stop, PostToolUse». Copia esa salida a tu nota.
2. Abre tu contrato: `rompelo init --force --id ROMPELO-CODEX-05 --scope adapters/codex/LEEME.md
   --check rompelo.tests --check rompelo.observe-tests --check rompelo.instrumento-tests
   --check rompelo.portabilidad-tests --check rompelo.sin-var-pegada --check rompelo.cruce-settings-claude
   --check rompelo.control-negativo-sesiones --junta`.
3. Cruces que solo tú puedes hacer, en este orden, anotando la salida literal de cada bloqueo:
   a. **Siguiente, entero.** Edita `adapters/codex/LEEME.md` con `apply_patch` (una línea) y termina el turno
      sin `rompelo check`. El bloqueo tiene que acabar en `Siguiente: rompelo check && rompelo cruce --nota
      '<qué cruzas>' -- <comando real>` seguido del párrafo «No declares la tarea terminada». Si en tu cliente
      la razón llega recortada o sin saltos de línea, anótalo con el texto tal cual: es el hallazgo principal.
   b. **no_afecta y Siguiente con `--id`.** `rompelo check --id rompelo.sin-var-pegada` (un segundo). Edita
      `LEEME.md` otra vez con `apply_patch` y termina el turno. El bloqueo NO puede decir que
      `rompelo.sin-var-pegada` «se ejecutó sobre otro árbol» (LEEME.md es `*.md`), los otros seis siguen «sin
      ejecutar», y la línea Siguiente tiene que llevar `--id` por cada uno de esos seis, no `rompelo check` a
      secas. Si sale «sobre otro árbol», anótalo: sería un fallo de `no_afecta` desde Codex.
   c. **Raíz sin git.** Desde un subdirectorio: `cd adapters/codex && ls`. La última línea de
      `~/rompelo/state/sesiones/codex-<tu session_id>.jsonl` tiene que llevar `"repo": "/Users/rootml/rompelo"`.
      Luego `git -C ~/rompelo worktree add /tmp/rompelo-wt-codex` y `ls /tmp/rompelo-wt-codex`: esa línea
      tiene que llevar `"repo": "/private/tmp/rompelo-wt-codex"` (ruta real, con `/private`). Quita el
      worktree al terminar (`git -C ~/rompelo worktree remove /tmp/rompelo-wt-codex`).
   d. **Lo que solo Codex sabe: el código de salida.** El observador deja `"codigo": null` en Codex porque
      el 05-09 `tool_response` de Bash era solo texto (INC-0036); por eso «check en rojo» y «verde ambiguo»
      no saltan en Codex. Mide si sigue así: ejecuta `false` y `ls /no/existe` en tu sesión y mira las dos
      últimas líneas del libro. Si `"codigo"` es un número, tu cliente ya manda el código: anota la versión
      y captura la FORMA del payload (solo claves, nunca texto) con un `hooks.json` de PROYECTO desechable
      cuyo PostToolUse sea `ROMPELO_DEBUG_FORMA=1 "$HOME/rompelo/bin/rompelo" observe codex`, y pega la
      última línea de `~/rompelo/state/forma.jsonl`. Si sigue siendo `null`, di «sigue sin código con
      codex X.Y.Z» y no busques más: el arreglo, si hay forma, es de José en `evento_desde_hook`.
   e. **Cierre.** `rompelo check` (unos 5 min), `rompelo cruce --id rompelo.cruce-settings-claude`,
      `rompelo close`. El Stop siguiente tiene que callar.
4. Anota en `adapters/codex/LEEME.md`, sección «Estado», con fecha y `codex --version`: los tres bloqueos
   literales (a, b y, si hubo, el de c), los recuentos de las baterías, el resultado de d y lo NO VERIFICADO.

Los mismos límites de la Parte 4: ni `bin/rompelo`, ni `tests/`, ni `~/.claude/`, ni el `hooks.json` global.

## Entrega

Tres bloques, en este orden: qué queda hecho, qué falta, qué problemas tiene el trabajo.
Con: comandos ejecutados y resultado; PASS/FAIL de la batería antes y después; la salida
literal del bloqueo en vivo de la Parte 1; y la lista de lo NO VERIFICADO con el motivo.
Sin narrar tus errores: si algo cambió una decisión, una línea.
