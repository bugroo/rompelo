# Cambios

Formato: una entrada por versión, lo que cambia para quien usa la herramienta. Lo verificado y lo
no verificado de cada versión está en el relevo enlazado.

## Sin publicar

- **Una marca de cierre no sobrevive a un contrato cerrado ni a otra tarea (17-09).** Con disparo `entrega`, Stop retira
  en silencio la marca `cerrando-<repo>` si el contrato está `cerrada` o si la marca es de otra tarea (init --force
  desde otra sesión, `git checkout` de `task.json`); y el prompt de cierre sobre un contrato cerrado ya no declara
  cierre: dice que está cerrada, qué falta y que el camino es un contrato nuevo. Antes, una marca dejada por una prueba
  en otra sesión bloqueaba cada turno de cualquier sesión sobre ese repo. Batería de disparo 54 → 62 casos; el control
  positivo espera 6 fallos exactos.
- **Los motivos que vienen del estado del repo lo dicen (17-09).** «el repo está en nivel 2 desde 04-09-2026 (perfiles auth,
  junta, secretos; patrones firma-repetida, verde-ambiguo): hace falta segunda pasada…» y «el repo tiene perfil `junta`
  desde 04-09-2026: hace falta cruce real…» sustituyen a «observación: nivel 2 (…)» y a «la tarea tocó rutas de junta»,
  que atribuían a la tarea lo que era del repo. La fecha es `nivel_desde`, escrita al subir a 2 (y en
  `obligaciones_efectivas` para CI); un estado anterior sin fecha dice «desde una tarea anterior». Cómo se baja y cuándo
  no, en la skill.
- **La puerta salta al entregar, no en cada turno (16-09).** Disparo `entrega` por defecto: `PreToolUse` deniega
  `git commit`/`push`/`merge`, `gh pr`, `wrangler deploy`, `scripts/desplegar.sh`… con el contrato sin cumplir (motivos y
  línea «Siguiente:», sin tope); `UserPromptSubmit` reconoce la petición de cerrar del usuario («termina», «sube esto»,
  «haz el commit», «a producción»…), declara el cierre y adelanta lo que falta; `Stop` juzga solo con el cierre declarado
  (o tras un `rompelo close` en rojo) y calla al cumplirse. `turno` (lo de antes) en `config/disparo.json`, por repo
  o con `rompelo init --disparo turno`. Hooks nuevos en los dos adaptadores; `rompelo doctor` avisa si faltan.
  Batería `rompelo-disparo-test.sh` (54) con control positivo; cruce `tests/cruce-hooks-entrega.sh` visto ROTO contra
  el binario anterior. Detalle: `docs/disparo.md`.
- **El diff dicta el contrato (16-09).** `config/obliga.json` (+ `.local`, + `.rompelo/obliga.json` del repo, que CI ve):
  glob → {checks, junta, prueba}; una ruta cambiada que casa añade esas obligaciones al contrato efectivo (el escrito no
  cambia; `close` las deja en `obligaciones_efectivas`). `afecta` por check en el registro: un check cuyas rutas no
  cambiaron no aplica (ni se exige ni se ejecuta; `N/A` en CI) y su huella solo mira sus rutas. Batería
  `rompelo-obliga-test.sh` (38) con control positivo.
- **Segunda pasada con manifiesto (16-09).** `rompelo revisar` / `rompelo revisar --cerrar` sustituyen al campo de texto
  `segunda_pasada` a nivel ≥ 2 (`segunda_pasada: texto` en observacion.json lo devuelve): cada fichero cambiado revisado
  o saltado con motivo sobre la huella actual, reglas de `ocr delegate rule` si hay ocr (sin LLM), hallazgos al contrato
  sin disposición. Batería `rompelo-revisar-test.sh` (32) con control positivo.
- **Categorías protegidas (16-09).** Un hallazgo `security|bug|concurrency|memory|compat|data` no se rechaza sin
  `comprobado` (qué se ejecutó o leyó que lo refuta). Tres casos en la batería del gate (222).
- **ocr con esfuerzo y presupuesto (16-09).** `checks/ocr-review.py` pasa `--effort` (auto: low ≤ 150 líneas, medium
  después) y `--max-tokens-budget` (600000; 0 = sin tope); presupuesto agotado = 2, nunca 0. Cinco casos más (22).
- **Tope de tamaño para ocr (16-09, rama `ocr-max-lineas` fusionada).** `OCR_MAX_LINEAS` (1500; 0 = sin tope) sale con 2
  antes de llamar a ocr; control positivo registrado para `rompelo.ocr-review-tests`.

- **Más rápido en la ruta caliente (11-09).** El observador (`PostToolUse`, tras CADA herramienta) ya no lanza
  ningún proceso: la raíz del repo se halla subiendo hasta `.git` (igual que `git rev-parse --show-toplevel`
  en los casos corrientes, worktrees incluidos), y `subprocess` y `tempfile` no se importan. El hook Stop
  lanza 3 procesos git en vez de 7: los ficheros cambiados y sus hashes se calculan una vez por invocación y
  la base del contrato solo se comprueba con `cat-file` cuando el diff falla. El registro y la configuración
  se leen una vez por proceso (caché por inode, mtime y tamaño). Medido el 11-09-2026 (Mac, python 3.9 de
  Apple, libro de 1.775 eventos, 9 sesiones vecinas, media de 10 llamadas): observador 109 → 49 ms con un
  shim de git en el PATH y 62 → 49 sin él; Stop sobre este repo 374 → 168 ms con shim y 102 → 66 sin él.
  Las baterías, que invocan el binario cientos de veces, pasan de 101 a 72 s y de 28 a 20 s.
- **`no_afecta` por check en el registro (11-09).** Lista de globs cuyas rutas no entran en la huella de ESE
  check: editar el README o una imagen después de la suite no obliga a repetirla; cualquier otra ruta sí.
  Forma parte de la definición del check (cambiarla invalida la evidencia). Las de rompelo llevan `docs/**`,
  `*.md`, `corpus/**`, `incidents/**`.
- **La línea «Siguiente:»** en cada bloqueo (Stop, `verify`, `close`; `Next:` en inglés): los comandos exactos
  que desbloquean, en orden (`rompelo check` o `--id` por cada check caducado, `rompelo cruce …`,
  `rompelo close`), y solo los que un comando resuelve. `verify --json` la lleva en `siguiente`.
- **`rompelo check` avisa cuando el propio check cambia el árbol** (un formateador, un build que escribe un
  fichero rastreado), con las rutas: antes solo se veía «se ejecutó sobre otro árbol» en el Stop siguiente.
- **Detección de checks en más ecosistemas.** Scripts `test:*`/`typecheck:*`/`lint:*` de `package.json`
  (`typecheck:functions` → `<repo>.typecheck-functions`), `bun run test` (antes `bun test`, que es el runner
  de bun y no el script), `deno.json` tasks, `composer.json` scripts, `uv run pytest` con `uv.lock`, `ruff` y
  `mypy` solo si están configurados, `go vet`, `mix test`, `rspec`/`rake test`, Gradle, Maven, .NET, Swift,
  `justfile` y `Taskfile`. El observador reconoce como check verde `uv run pytest`, `deno task check`,
  `just test`, `mix test`, `rspec`, `dotnet test`, `ruff check` y otros.
- **`config/permisos.json` deja de estar versionado** (como `repos.json` y `state/`): es estado de la máquina
  y lo escribe `rompelo permiso`. Al ejecutarlo dentro del propio repo de rompelo aparecía como «fuera de
  scope_paths» (visto por Codex en la Parte 4, 07-09). La entrada que había versionada era un ensayo del 05-09.
- **Parte 4 de Codex incorporada** (`adapters/codex/LEEME.md`, 07-09-2026, codex-cli 0.153.4): el binario del
  PR #1 cruzado desde un cliente Codex real (Stop nativo, `apply_patch` con rutas, permiso revocado). Su
  contrato cerrado queda en `docs/auditoria-2026-09-07/contrato-ROMPELO-CODEX-04.json`. Parte 5 del encargo
  en `adapters/codex/PROMPT-CODEX.md`: cruzar desde Codex lo de esta versión.
- **Instrumento de prueba (auditoría 07-09, RMP-004).** Las baterías ya no dan por «silencio» un hook
  que muere: cada invocación pasa por `tests/invocar.py` (código de salida, stderr, plazo) y una
  aserción de bloqueo exige que TODA la salida sea el JSON. `tests/instrumento-test.sh` ejercita las
  aserciones contra hooks falsos en las dos direcciones. El binario que prueban las baterías es el que
  está junto a ellas (`ROMPELO_BIN` para otro), no `~/rompelo`. Recuento nuevo: `PASS= FAIL= ROTOS=`.
- **Huella v2 (RMP-001/002/015).** El sujeto de cada ruta cambiada es contenido + bit ejecutable + destino
  del enlace + borrado, con el nombre real (`git … -z`): `año.py`, tabuladores y espacios ya no se firman como
  borrados ni salen «fuera de scope». Una `base` que no existe en el repo es un error con instrucción, no
  `HEAD` en silencio; un repo sin commits mide contra el árbol vacío; un fallo de git bloquea. La evidencia con
  huella sin versión queda obsoleta y pide `rompelo check` de nuevo (no se migra). Borrar el único test ya no
  cuenta como «prueba en el diff». La CI propia hace `fetch-depth: 0`.
- **Errores propios, runner y privacidad (RMP-003/007/010).** Una allowlist corrupta bloquea diciéndolo (antes
  el hook moría sin JSON); un estado de repo o `permisos.json` corrupto es un error y no se pisa (antes se leía
  como `{}` y el nivel 3 desaparecía). Estado, permisos, allowlist y evidencia se escriben de forma atómica;
  el observador actualiza el estado bajo cerrojo (`flock`), así dos sesiones sobre el mismo repo no se pierden
  actualizaciones. El runner tiene plazo por check (`timeout`, 900 s), mata el grupo de procesos, acota la
  captura a 4 MiB y lee bytes (un `0xff` ya no tumba la evaluación); «no arrancó» y «no terminó» son
  instrumento, no «FALLÓ con código». La evidencia guarda programa y hash del argv, no el argv: una cabecera
  o una URL con credencial ya no llega a `.rompelo/evidence/` ni al informe. `ROMPELO_DEBUG_FORMA` guarda
  la longitud del texto, no su cabeza.
- **Contrato efectivo único y CI sin falsos completos (RMP-005/006/008/014).** `contrato_efectivo()` es lo
  que leen `check`, `verify`, `close`, hook e informe: `close` firma el contrato escrito y `verify` compara
  lo mismo (antes un perfil `junta` hacía que verify dijera «el contrato cambió» nada más cerrar).
  `checks: []` ya no apaga los `checks_nivel3`. `close` escribe `obligaciones_efectivas` en el contrato y
  CI las exige sin estado local. `verify --ci` informa `PASS/FAIL/ERROR/SKIPPED/WAIVED` por obligación,
  distingue «contrato completo» de «OK PARCIAL, INCOMPLETO» y nunca dice «puede cerrarse» con algo
  omitido; `excepciones: [{que, motivo, quien}]` en el contrato es la única forma de un `WAIVED`.
  `ROMPELO_REGISTRO=repo` elige el registro del consumidor a propósito (la plantilla lo pone; sin
  registro es error, no carga implícita). El tope de 3 bloqueos deja `SIN-VERIFICAR.json` en la evidencia,
  `status` lo dice y solo un `close` real lo quita. Plantilla de CI con `permissions: contents: read` y
  revisión de rompelo fijable (`ROMPELO_REV`).
- **Permisos con alcance, eventos correctos y `apply_patch` de Codex (RMP-009/011/019).** `permiso <x> no`
  revoca de verdad y el check queda pendiente (no cumplido) hasta un permiso nuevo o una excepción en el
  contrato; un permiso para un check autoriza solo ese; sin `--recordar` no se hereda en otra tarea; el
  nivel 3 se calcula, no se guarda. El observador responde con el `hookEventName` del evento recibido.
  Las ediciones de Codex por `apply_patch` (64 eventos reales sin fichero hasta hoy) quedan anotadas con
  sus rutas: forma medida con codex-cli 0.153.4 en una sesión desechable (docs/observacion.md §12.5).
- **Hallazgos, ventana entre sesiones, retención y corpus honesto (RMP-012/013/015/017).** Un hallazgo se
  adjudica con `confirmado` (+ `regresion`: check del registro o prueba de este diff), `rechazado` (+ `motivo`)
  o `aceptado` (+ `nota`); «pendiente» o cualquier otra cadena ya no desbloquea. El observador mira también
  los libros de otras sesiones del mismo repo en las últimas `ventana_horas` (24; 0 apaga): el mismo error
  una vez en Claude y otra en Codex es «el mismo error 2 veces»; otro repo no contamina. `rompelo state prune
  --dias N [--dry-run]` borra libros y marcas viejos y nunca el estado del repo ni la evidencia. Borrar el
  único test ya no cubre `exige_prueba_en_diff`. El corpus valida ids, clases y valores, distingue cobertura
  DECLARADA (etiqueta) de DEMOSTRADA (campo `regresion` con la prueba que lo caza; 9 de 48 hoy) y CI comprueba
  que `corpus/TABLA.md` coincide con lo generado. INC-2026-0048: dos sesiones en el mismo repo comparten
  contrato (relato de la sesión rootml-0e; reproducido aquí mismo).
- **Portabilidad y publicación preparada (RMP-016/018).** `rompelo doctor` (diagnóstico de solo lectura).
  El fragmento de settings de Claude lleva la ruta entre comillas, como el de Codex: con un HOME con espacios
  la línea sin comillas daba «command not found» (batería `tests/portabilidad-test.sh`: HOME con espacio,
  dos carpetas con el mismo nombre, ROMPELO_HOME alternativo). `actions/checkout` fijado por SHA y PyYAML
  por versión en los dos workflows, `permissions: contents: read`. La protección de `main` queda preparada
  en `docs/PROTECCION-MAIN.md` y NO activada: la decide José.
- `rompelo check` ya no descarta argumentos en silencio: `check no.existe` ejecutaba todo y
  decía «todos en verde» (INC-0037). Ahora solo admite `--id ID` (repetible, acotado a los
  checks exigidos por el contrato) y cualquier otro argumento es error sin ejecutar nada.
  Cuatro casos en rojo en la batería.
- `--help` y README avisan: una suite entera supera los 120 s del timeout por defecto de la
  herramienta Bash de Claude Code; lanzar con timeout ≥ 300000 o en segundo plano, e iterar con
  `--id`.
- Corpus 38 (I=18): INC-0037 y INC-0038 (código de salida del envoltorio que no es el del
  trabajo: cinco checks en verde reportados como exit 1).
- Corpus 47 (I=27): INC-0039 a INC-0047, nueve fallos de instrumento de una sola sesión de medición
  (07-09-2026) que dieron un número con buena pinta y se cazaron solo porque el resultado era
  imposible: unidades distintas en dos ramas del mismo reloj, la página 404 medida como home,
  un contraste sobre fotografía en verde con el control positivo pasando. Gates nuevos propuestos,
  ninguno construido; el más barato es `plausibilidad-fisica` (declarar el rango antes de creerse
  el número).
- `docs/observacion.md` §9: el control positivo del observador abarca dos llamadas de
  herramienta separadas; solo repos git quedan cubiertos.
- Control positivo opcional por check: debe detectar un caso malo con código 1 antes de
  ejecutar el check real. Incluidos los controles de la batería (mutante de scope) y de
  `sin-var-pegada`; no se guarda salida de ninguno de los dos procesos.
- Triestado en el registro: hallazgo, instrumento que no pudo mirar y aborto inesperado
  tienen motivos distintos. `check` informa líneas/mínimo y resultado del control.
- Evidencia y cierre vinculados también a la definición del check; un cierre anterior no
  oculta un check recién fallado. Las evidencias antiguas requieren repetir `check`/`close`.
- Gate 77 → 109 casos. Cobertura concreta y límites de la Parte 2 en
  [docs/control-positivo.md](docs/control-positivo.md).
- Codex cruzado en vivo con `codex exec`: bloqueo del `Stop` con motivos, cierre por el propio
  agente, silencio después, tope de tres bloqueos. La marca del tope pasa de `tempdir` a
  `state/marcas/` (bajo el sandbox de Codex no se escribía y el tope nunca llegaba).
- Codex no manda código de salida en `PostToolUse`: el observador lo deja como desconocido en vez
  de 0 y saca la firma de error de la última línea por heurística (INC-2026-0036).
- `ROMPELO_DEBUG_FORMA=1` guarda la forma del payload (sin texto por defecto) en `state/forma.jsonl`.
- Corpus 32 → 36 (INC-0033 a 0036), batería del observador 64 → 75.
- Perfiles de riesgo por repo (`por_repo` en `config/riesgo.json` / `config/riesgo.local.json`).
- Nivel 3 usado de verdad: gitleaks y ShellCheck como `checks_nivel3` sobre un repo de trabajo.
- El motivo del gate a nivel 3 por permiso dice el nivel real («por permiso, sin patrones»).

## v0.1.0 · 2026-09-05

Primera versión etiquetada. Relevo: [docs/RELEVO-2026-09-05.md](docs/RELEVO-2026-09-05.md).

- Puerta de cierre por contrato (`.rompelo/task.json`, ids en un registro, argv sin shell,
  allowlist de repos) para el hook `Stop` de Claude Code y de Codex. Checks sobre la huella del
  contenido actual, salida mínima, cruce real de junta después del último cambio, hallazgos con
  disposición, afirmaciones con estado, scope, prueba en el diff. Tope de tres bloqueos.
- `rompelo verify --ci`: juez independiente que ignora la evidencia guardada. Workflow listo.
- `rompelo init` con detección de checks; `rompelo close` con informe en llano que incluye lo que
  vio el observador (nivel, perfiles, patrones, permisos).
- Capa de observación (`PostToolUse` y `PostToolUseFailure`): libro por sesión sin texto de
  comandos ni salidas, perfiles de riesgo (dos toques de escritura), patrones repetidos, niveles
  0/2/3, aviso una vez por patrón y sesión, `rompelo permiso`, `rompelo nivel bajar`. Checks de
  nivel 3 (`checks_nivel3` en el contrato) exigidos solo con permiso.
- Mensajes del gate y del observador en inglés con `ROMPELO_LANG=en` o `"idioma": "en"` en
  `config/observacion.json`. El informe de cierre sigue en español.
- Corpus de 32 incidentes reales con clase y disparador; tabla generada.
- Baterías: 77 casos del gate y 64 del observador, cada condición vista en rojo con mutación
  confirmada; control negativo con cinco sesiones reales reproducidas desde los transcripts.

Conocido y sin resolver en esta versión: el lado de Codex no está cruzado en vivo; la forma con
la que Codex entrega un comando que falla no está verificada; los checks no tienen control
positivo (es la Parte 2 de `adapters/codex/PROMPT-CODEX.md`).
