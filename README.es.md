# rompelo

**Tu agente de código no puede decir «hecho» hasta que una comprobación que se ha visto fallar diga que sí.**

Puerta de cierre para Claude Code y Codex. Se engancha al hook `Stop`, lee un contrato pequeño de la
tarea y no deja terminar hasta que la evidencia existe: checks ejecutados sobre el código actual,
un cruce real cuando dos sistemas tienen que coincidir, hallazgos con decisión. Lo decide código,
fuera del modelo. Python 3.9 y git, sin dependencias. English: [README.md](README.md).

![El agente dice hecho, el hook Stop llama a rompelo, rompelo compara contrato y evidencia; si falta algo bloquea con motivos, si todo se cumple hay silencio](docs/img/es/como-funciona.png)

## Instalar

```bash
git clone https://github.com/bugroo/rompelo ~/rompelo
```

1. **Hooks.** Claude Code: añade `Stop`, `PostToolUse` y `PostToolUseFailure` de
   [`adapters/claude/settings-fragment.json`](adapters/claude/settings-fragment.json) a
   `~/.claude/settings.json`. Codex: fusiona [`adapters/codex/hooks.json`](adapters/codex/hooks.json)
   en `~/.codex/hooks.json` y confía el hook en `/hooks` (detalle en
   [`adapters/codex/LEEME.md`](adapters/codex/LEEME.md)).
2. **Skill**, para que el agente sepa qué hacer al leer `/rompelo`:
   ```bash
   mkdir -p ~/.claude/skills/rompelo && cp ~/rompelo/adapters/skill/SKILL.md ~/.claude/skills/rompelo/
   mkdir -p ~/.codex/skills/rompelo  && cp ~/rompelo/adapters/skill/SKILL.md ~/.codex/skills/rompelo/
   ```
3. **Checks.** Tus comandos van en `~/rompelo/checks/registry.local.json`, un id por comando, como
   argv (sin shell). O deja que `rompelo init` los detecte de `package.json`, `pyproject.toml`,
   `Cargo.toml`, `go.mod` o el `Makefile`.
   ```json
   {"mi-app.test": {"argv": ["pnpm", "test"], "cwd": "repo", "min_lineas": 1, "timeout": 600}}
   ```
4. `rompelo doctor` confirma hooks, registro y allowlist.

## Usar

Tres maneras de decírselo al agente:

1. `/rompelo <tarea>` en Claude Code, `$rompelo <tarea>` en Codex. Lee la skill y abre su contrato.
2. Sin skill, al principio del encargo: *«Esta tarea va con rompelo: `rompelo init --force --id <ID>
   --scope '<rutas>' --check <ids> [--junta] [--prueba]`. No la des por terminada hasta que
   `rompelo close` cierre en verde; lo que no puedas cumplir, escríbelo como NO VERIFICADO.»*
3. Nada. Con el repo alistado y un contrato abierto, el `Stop` bloquea igual y le da al agente las
   órdenes exactas.

A mano:

```bash
cd tu-repo
rompelo init --id T-42 --scope 'src/**' --check mi-app.test --junta   # contrato + alistar el repo
# ... el agente trabaja ...
rompelo check                                  # ejecuta los checks y guarda evidencia (puede tardar minutos)
rompelo cruce --nota "petición real" -- curl -sf https://…   # el cruce real, DESPUÉS del último cambio
rompelo close                                  # se niega si falta algo; imprime el informe
```

Dos sesiones sobre la misma raíz comparten el contrato: cada una abre el suyo (`--force`) o trabaja
en un worktree.

## Qué exige la puerta

- Cada check del contrato ejecutado sobre el árbol **actual** (huella del contenido, no el commit).
  Un 0 sin salida no es verde (`min_lineas`); un check que no termina o no arranca es fallo del
  instrumento, no hallazgo; un control positivo que no detecta el caso malo invalida el verde.
- Si toca una junta, un cruce real después del último cambio.
- Cada hallazgo con `confirmado` (+ regresión), `rechazado` (+ motivo) o `aceptado` (+ nota).
- Cada afirmación sobre el exterior con `verificado` (fuente + cita), `derivado` o `no_verificado`.
- Nada cambiado fuera de `scope_paths`; con `--prueba`, un test en el diff.
- El observador sube el rigor solo (segunda pasada, cruce por perfil, checks de nivel 3 con
  `rompelo permiso`) cuando ve repetir errores, editar sin comprobar o tocar auth, secretos, datos,
  despliegue o juntas.

La evidencia nunca guarda argumentos ni salida de los comandos. El contrato solo lleva ids: no se
ejecuta texto del repo. Repos fuera de la allowlist: silencio. Contrato ilegible: bloqueo.

## CI

Copia [`adapters/ci/rompelo-gate.yml`](adapters/ci/rompelo-gate.yml) a `.github/workflows/`. Vuelve a
ejecutar los checks en un runner donde el agente no ha escrito nada e informa por obligación:
`PASS`, `FAIL`, `ERROR`, `SKIPPED`, `WAIVED`. «OK PARCIAL» significa que algo (junta, `solo_local`)
solo se cruza fuera de CI. Registro del consumidor: `ROMPELO_REGISTRO=repo` lee `.rompelo/registry.json`.

## El límite

El agente puede editar su contrato y escribir evidencia a mano. La puerta frena el descuido, no la
trampa; el juez independiente es `verify --ci`. Un verde aquí significa «no encontré los de mi
clase», no «está bien».

## Más

[Documentación completa](docs/README-completo.es.md) · [capa de observación](docs/observacion.md) ·
[corpus de 48 incidentes reales](corpus/TABLA.md) · [auditoría del 07-09-2026](docs/auditoria-2026-09-07/SEGUIMIENTO.md) ·
[cambios](CHANGELOG.md). Licencia MIT.
