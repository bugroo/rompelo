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

**NO VERIFICADO en vivo desde Codex.** El cruce real (Codex bloqueado por assure y luego concedido) lo tiene que hacer José en su terminal de Codex, con un repo de la allowlist y un contrato sin cumplir. Hasta entonces el lado Codex de la junta está sin cruzar.
