# rompelo · puerta de cierre por tarea para agentes de código

Spike de la Fase 1 del plan `~/.claude/plans/dictamen-no-necesitas-fizzy-bear.md`
(04-09-2026), corregido el mismo día con el segundo dictamen y con los dos mensajes de
la sesión `rootml-de`. Vive fuera de `ClaveON_B2C` y de `WERIXO` a propósito: sirve a
los dos y no pertenece a ninguno.

**Qué hace.** Un repo se alista con `rompelo init`, que crea `.rompelo/task.json` (el
contrato) y apunta el repo en `config/repos.json` (allowlist). Desde entonces el hook
`Stop` de Claude Code o de Codex llama a `rompelo hook <agente>` y el agente no puede
dar la tarea por terminada hasta que el contrato se cumple. Lo decide código normal,
solo biblioteca estándar de Python 3.9; el modelo solo puede pedir.

| Condición | Cómo se cumple |
|---|---|
| checks ejecutados sobre el contenido actual del árbol | `rompelo check`. Los ids apuntan a `checks/registry.json`; argv sin shell; se guarda código, duración y hash de la salida, nunca la salida |
| un check con código 0 pero sin la salida mínima del registro no es verde | `min_lineas` en el registro: «limpio» tiene que distinguirse de «no miré» |
| junta cruzada DESPUÉS del último cambio | `rompelo cruce --nota '…' -- <argv real>` o `--id <check del registro>` |
| hallazgos con disposición | editar `hallazgos` en el contrato |
| afirmaciones sobre el mundo exterior con estado | `afirmaciones`: `verificado` exige fuente de primera mano y cita textual; `derivado` exige `de`; `no_verificado` exige `falta`. Con `toca_exterior: true` tiene que haber al menos una |
| cambios dentro de `scope_paths` | o ampliar el scope a propósito |
| prueba en el diff (si `exige_prueba_en_diff`) | tocar un fichero de prueba |

**Lo que no hace, a propósito.**
- No ejecuta nada que venga del repositorio: el contrato solo lleva ids; una cadena
  de comando se rechaza sin ejecutarse (probado con canario).
- No actúa en repos fuera de la allowlist: un `.rompelo/` ajeno no engancha el gate.
- No lee la salida de los checks (podría llevar secretos).
- Fail-closed: contrato ilegible o ausente en repo alistado = bloqueo.
  Tope de 3 bloqueos por sesión y tarea; después avisa y deja parar.
- Un verde de rompelo quiere decir «no encontré los de mi clase», no «está bien».

**Estructura**

- `bin/rompelo` · CLI y evaluador. `rompelo --help`.
- `checks/registry.json` · único sitio con comandos (`argv`, `cwd: repo|rompelo`, `min_lineas`).
- `config/repos.json` · allowlist de repos donde el gate actúa.
- `adapters/claude/` · hook Stop y fragmento de `settings.json` (conectado el 04-09).
- `adapters/codex/` · `hooks.json` y LEEME. Lo instala José o Codex en `~/.codex/`, no Claude Code.
- `incidents/` · corpus de 28 fallos reales (15 propios, 13 de `rootml-de`), uno por YAML,
  con clase S/T/C/A/R/I/M. `corpus/TABLA.md` se genera con `python3 bin/rompelo-corpus.py`.
- `tests/rompelo-stop-test.sh` · 58 casos con `ROMPELO_HOME` desechable: el gate visto en rojo y
  en verde, mutación a mutación. `tests/cruce-settings-claude.sh` ejecuta la línea Stop tal cual
  está en `settings.json` (visto dar 0, 1 y 2). `tests/sin-var-pegada.sh` · check triestado de
  ejemplo (0 limpio · 1 hay · 2 no vi nada).

**Lo que NO es (todavía).** Ni ledger de hallazgos con fingerprint, ni CI, ni
máquina de estados, ni motor de políticas, ni PreToolUse. La tabla del corpus dice
que la clase mayor es **I** (comprobaciones incapaces de fallar): ahí va el siguiente
módulo, no en ampliar el Stop gate.
