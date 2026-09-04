# assure · puerta de cierre por tarea para agentes de código

Spike de la Fase 1 del plan `~/.claude/plans/dictamen-no-necesitas-fizzy-bear.md`
(04-09-2026), corregido el mismo día con el segundo dictamen. Vive fuera de
`ClaveON_B2C` y de `WERIXO` a propósito: sirve a los dos y no pertenece a ninguno.

**Qué hace.** Un repo se alista con `assure init`, que crea `.assure/task.json` (el
contrato) y apunta el repo en `config/repos.json` (allowlist). Desde entonces el hook
`Stop` de Claude Code o de Codex llama a `assure hook <agente>` y el agente no puede
dar la tarea por terminada hasta que el contrato se cumple. Lo decide código normal,
solo biblioteca estándar de Python 3.9; el modelo solo puede pedir.

| Condición | Cómo se cumple |
|---|---|
| checks ejecutados sobre el contenido actual del árbol | `assure check`. Los ids apuntan a `checks/registry.json`; argv sin shell; se guarda código, duración y hash de la salida, nunca la salida |
| junta cruzada DESPUÉS del último cambio | `assure cruce --nota '…' -- <argv real>` o `--id <check del registro>` |
| hallazgos con disposición | editar `hallazgos` en el contrato |
| cambios dentro de `scope_paths` | o ampliar el scope a propósito |
| prueba en el diff (si `exige_prueba_en_diff`) | tocar un fichero de prueba |

**Lo que no hace, a propósito.**
- No ejecuta nada que venga del repositorio: el contrato solo lleva ids; una cadena
  de comando se rechaza sin ejecutarse (probado con canario).
- No actúa en repos fuera de la allowlist: un `.assure/` ajeno no engancha el gate.
- No lee la salida de los checks (podría llevar secretos).
- Fail-closed: contrato ilegible o ausente en repo alistado = bloqueo.
  Tope de 3 bloqueos por sesión y tarea; después avisa y deja parar.

**Estructura**

- `bin/assure` · CLI y evaluador. `assure --help`.
- `checks/registry.json` · único sitio con comandos (`argv`, `cwd: repo|assure`).
- `config/repos.json` · allowlist de repos donde el gate actúa.
- `adapters/claude/` · hook Stop y fragmento de `settings.json` (conectado el 04-09).
- `adapters/codex/` · `hooks.json` y LEEME. Lo instala José o Codex en `~/.codex/`, no Claude Code.
- `incidents/` · corpus de 15 fallos reales, uno por YAML, con clase S/T/C/A/R/M.
  `corpus/TABLA.md` se genera con `python3 bin/assure-corpus.py` (usa PyYAML, fuera del camino del hook).
- `tests/assure-stop-test.sh` · 50 casos: el gate visto en rojo y en verde, mutación a
  mutación, con `ASSURE_HOME` desechable. `tests/cruce-settings-claude.sh` ejecuta la
  línea Stop tal cual está en `settings.json` (visto dar 0, 1 y 2).

**Lo que NO es (todavía).** Ni ledger de hallazgos con fingerprint, ni CI, ni
máquina de estados, ni motor de políticas, ni PreToolUse. Eso se decide con la tabla
del corpus: el Stop gate solo alcanza la clase S.
