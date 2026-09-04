# Adaptador Codex (OpenAI) · hook Stop

Contrato oficial leído el 04-09-2026 en `developers.openai.com/codex/hooks.md`:

- Codex busca hooks en `~/.codex/hooks.json` (global) o `<repo>/.codex/hooks.json` (proyecto, solo si la capa `.codex/` está en confianza).
- `Stop` recibe por stdin `session_id`, `cwd`, `stop_hook_active`, `last_assistant_message`.
- Para impedir el cierre: JSON en stdout `{"decision":"block","reason":"…"}` con exit 0. Codex convierte `reason` en un prompt de continuación. Texto plano en stdout es inválido para este evento.
- Exit 0 sin salida = seguir con normalidad.
- **Todo hook no gestionado hay que revisarlo y marcarlo como de confianza en Codex antes de que corra.** Un hook cambiado vuelve a quedar pendiente de revisión.

`assure hook codex` cumple ese contrato (mismo evaluador que para Claude Code).

## Instalación global (la hace José o Codex, no Claude Code)

`~/.codex/**` es territorio exclusivo de Codex por regla de casa. Claude Code no escribe ahí.
Copia manual:

```bash
cp ~/assure/adapters/codex/hooks.json ~/.codex/hooks.json   # o fusiona si ya existe uno
```

Luego, en Codex, revisar y aceptar el hook cuando lo pida.

## Estado

NO VERIFICADO desde Codex: el cruce real (Codex bloqueado por assure y luego concedido) lo tiene que hacer José en su terminal de Codex. Hasta entonces, el lado Codex de la junta está sin cruzar.
