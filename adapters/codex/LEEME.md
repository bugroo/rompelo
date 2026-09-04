# Adaptador Codex (OpenAI) · hook Stop

Contrato oficial leído el 04-09-2026 en `developers.openai.com/codex/hooks.md`:

- Codex busca hooks en `~/.codex/hooks.json` (global) o `<repo>/.codex/hooks.json` (proyecto, solo si la capa `.codex/` está en confianza). Los hooks de usuario se cargan aunque el proyecto no sea de confianza.
- `Stop` recibe por stdin `session_id`, `cwd`, `stop_hook_active`, `last_assistant_message`.
- Para impedir el cierre: JSON en stdout `{"decision":"block","reason":"…"}` con exit 0. Codex convierte `reason` en un prompt de continuación. Texto plano en stdout es inválido para este evento.
- Exit 0 sin salida = seguir con normalidad.
- Si otro hook Stop devuelve `continue: false`, ese prevalece.
- **Todo hook no gestionado hay que revisarlo y marcarlo de confianza en `/hooks` antes de que corra.** La confianza va atada al hash exacto; un hook cambiado vuelve a quedar pendiente.

`assure hook codex` cumple ese contrato: mismo evaluador que para Claude Code, mismos motivos (probado en la batería, caso «paridad»).

## Hooks Stop que ya tiene Codex (leído el 04-09-2026, solo lectura)

| Hook | Qué hace en Stop | ¿Choca con assure? |
|---|---|---|
| `~/.codex/hooks/global_protocol.py` | con `stop_hook_active` emite `continue: true`; si el mensaje final dice «hecho» sin mencionar verificación, `decision: block` | No. Nunca emite `continue: false`, así que no prevalece. Los dos pueden bloquear a la vez; Codex concatena continuaciones. |
| ai-memory `stop.sh` | registro de memoria | No decide. |

## Instalación global (la hace José o Codex, no Claude Code)

`~/.codex/**` es territorio exclusivo de Codex por regla de casa. Claude Code no escribe ahí.
Hay que **fusionar** con el `hooks.json` existente (no sustituirlo): añadir a su lista `Stop` la entrada de `hooks.json` de este directorio.

```bash
python3 - <<'PY'
import json,os
f=os.path.expanduser('~/.codex/hooks.json'); d=json.load(open(f))
nuevo=json.load(open(os.path.expanduser('~/assure/adapters/codex/hooks.json')))['hooks']['Stop'][0]
stop=d.setdefault('hooks',{}).setdefault('Stop',[])
if not any('assure' in h.get('command','') for m in stop for h in m.get('hooks',[])):
    stop.append(nuevo); json.dump(d,open(f,'w'),indent=2); print('añadido')
PY
```

Luego, en Codex, `/hooks` → revisar y confiar el hook nuevo.

## Alcance en los lanzadores de este Mac (medido el 04-09-2026)

`ai`, `ai-web`, `ai-build`, `ai-resume` (funciones de `.zshrc`) llaman a `command codex` sin `--profile` ni `-c`; `~/bin/clobs-codex` usa `--profile` con `clobs.config.toml` y hace `unset CODEX_HOME`. Todos leen `~/.codex/hooks.json`, así que el hook global los alcanza.

## Estado

### 04-09-2026 · instalación pendiente por permisos de la sesión

**NO VERIFICADO en vivo desde Codex.** El encargo se inició sobre `f9218b8`, con el
árbol limpio. `bash tests/assure-stop-test.sh` terminó con código 0 y
`PASS=58 FAIL=0` antes de cualquier edición.

La copia previa de `~/.codex/hooks.json` está en
`~/assure/.assure/evidence/hooks.json.20260904T214552Z.bak`, ignorada por Git.
`cmp` confirmó igualdad byte a byte antes y después del intento de fusión.
La herramienta rechazó el parche con:

```text
patch rejected: writing outside of the project; rejected by user approval settings
```

La sesión permite leer `~/.codex`, pero no escribir ahí ni solicitar elevación.
El archivo conserva los dos hooks Stop anteriores y no contiene aún assure.
La lectura limitada a `features.hooks` / `features.codex_hooks` no encontró un
override explícito en `config.toml`; esto no acredita que el hook haya corrido.
No se modificó la confianza ni se usó una vía alternativa para saltar el rechazo.

La entrada pendiente es exactamente la del adaptador: evento `Stop`, comando
`"$HOME/assure/bin/assure" hook codex`, timeout `30`. Tras fusionarla en una sesión
con permiso de escritura, José debe revisarla y confiarla en `/hooks` (o en la
revisión de hooks de la app), conforme al [contrato oficial](https://developers.openai.com/codex/hooks#review-and-trust-hooks).
Codex ejecutará después el cruce desechable, conservará el bloqueo literal,
comprobará el paso a silencio y limpiará el repo y su entrada de allowlist.

`ASSURE-CODEX-01` queda abierto con los tres checks y junta solicitados.
No se inició el módulo de control positivo: el encargo exige completar primero
la instalación y el cruce en vivo. Faltan la fusión, la confianza humana, ese
cruce y la Parte 2 completa; no hay salida literal de bloqueo en vivo que aportar.

Verificación del punto de reanudación: segunda pasada de la batería también
`PASS=58 FAIL=0` (código 0); `git diff --check` sin incidencias. `assure verify`
devuelve 1: los tres checks del contrato nuevo siguen sin evidencia registrada
y falta la junta. Las pasadas directas de la batería no sustituyen `assure check`
ni prueban la ejecución del hook por Codex.
