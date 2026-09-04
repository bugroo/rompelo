# assure · puerta de cierre por tarea para agentes de código

Spike de la Fase 1 del plan `~/.claude/plans/dictamen-no-necesitas-fizzy-bear.md`
(04-09-2026). Vive fuera de `ClaveON_B2C` y de `WERIXO` a propósito: sirve a los dos
y no pertenece a ninguno.

**Qué hace.** Un repo se alista con `assure init`, que crea `.assure/task.yaml`
(el contrato). Desde entonces el hook `Stop` de Claude Code o de Codex llama a
`assure hook <agente>` y el agente no puede dar la tarea por terminada hasta que el
contrato se cumple. Lo decide código normal; el modelo solo puede pedir.

| Condición | Cómo se cumple |
|---|---|
| checks obligatorios ejecutados sobre el árbol actual | `assure check` (guarda código, duración y hash de la salida; nunca la salida) |
| junta cruzada después del último cambio | `assure cruce --nota '…' -- <comando real>` |
| hallazgos con disposición | editar `hallazgos:` en el contrato |
| cambios dentro de `scope_paths` | o ampliar el scope a propósito |
| prueba en el diff (si `exige_prueba_en_diff`) | tocar un fichero de prueba |

Fail-closed: contrato ilegible = bloqueo. Tope de 3 bloqueos por sesión y tarea.

**Estructura**

- `bin/assure` · CLI y evaluador (Python 3.9 + PyYAML). `assure --help`.
- `adapters/claude/` · hook Stop y fragmento de `settings.json`.
- `adapters/codex/` · `hooks.json` y LEEME. Lo instala José o Codex, no Claude Code.
- `incidents/` · corpus de 15 fallos reales, uno por YAML. `corpus/TABLA.md` se genera con `python3 bin/assure-corpus.py`.
- `tests/assure-stop-test.sh` · el gate visto en rojo y en verde, mutación a mutación.

**Lo que NO es (todavía).** Ni ledger de hallazgos con fingerprint, ni CI, ni
máquina de estados de once fases, ni motor de políticas. Eso se decide con la tabla
del corpus en la mano, no antes.
