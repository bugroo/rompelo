# Adaptador Codex (OpenAI) · hook Stop

Contrato oficial leído el 04-09-2026 en `developers.openai.com/codex/hooks.md`:

- Codex busca hooks en `~/.codex/hooks.json` (global) o `<repo>/.codex/hooks.json` (proyecto, solo si la capa `.codex/` está en confianza). Los hooks de usuario se cargan aunque el proyecto no sea de confianza.
- `Stop` recibe por stdin `session_id`, `cwd`, `stop_hook_active`, `last_assistant_message`.
- Para impedir el cierre: JSON en stdout `{"decision":"block","reason":"…"}` con exit 0. Codex convierte `reason` en un prompt de continuación. Texto plano en stdout es inválido para este evento.
- Exit 0 sin salida = seguir con normalidad.
- Si otro hook Stop devuelve `continue: false`, ese prevalece.
- **Todo hook no gestionado hay que revisarlo y marcarlo de confianza en `/hooks` antes de que corra.** La confianza va atada al hash exacto; un hook cambiado vuelve a quedar pendiente.

`rompelo hook codex` cumple ese contrato: mismo evaluador que para Claude Code, mismos motivos (probado en la batería, caso «paridad»).

## Hooks Stop que ya tiene Codex (leído el 04-09-2026, solo lectura)

| Hook | Qué hace en Stop | ¿Choca con rompelo? |
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
nuevo=json.load(open(os.path.expanduser('~/rompelo/adapters/codex/hooks.json')))['hooks']['Stop'][0]
stop=d.setdefault('hooks',{}).setdefault('Stop',[])
if not any('rompelo' in h.get('command','') for m in stop for h in m.get('hooks',[])):
    stop.append(nuevo); json.dump(d,open(f,'w'),indent=2); print('añadido')
PY
```

Luego, en Codex, `/hooks` → revisar y confiar el hook nuevo.

## Alcance en los lanzadores de este Mac (medido el 04-09-2026)

`ai`, `ai-web`, `ai-build`, `ai-resume` (funciones de `.zshrc`) llaman a `command codex` sin `--profile` ni `-c`; `~/bin/clobs-codex` usa `--profile` con `clobs.config.toml` y hace `unset CODEX_HOME`. Todos leen `~/.codex/hooks.json`, así que el hook global los alcanza.

## Estado

### 05-09-2026 (mediodía) · cruzado en vivo desde Claude Code con `codex exec`

Los hooks corren y están confiados (José los aceptó en `/hooks`). Cruce sobre repos desechables:

- Stop con contrato sin cumplir → bloqueo literal «`[rompelo] La tarea CRUCE-CODEX NO puede darse
  por terminada (1/3)`: check `rompelo.sin-var-pegada` sin ejecutar; `toca_junta: true` y no hay
  cruce real registrado». Codex cumplió el contrato solo (`check`, `cruce`, `close`) y el siguiente
  Stop fue silencio. Con instrucción de insistir: tres bloqueos, a la cuarta `systemMessage`.
- La marca del tope no se escribía bajo el sandbox de Codex (tempdir no escribible): movida a
  `~/rompelo/state/marcas/`. Verificado: la marca cuenta 4 y el cuarto intento no bloquea.
- `PostToolUse` llega para cada herramienta. **Codex no manda código de salida** en
  `tool_response` de Bash: es solo el texto que el modelo imprimió (`text(r.output)`). El
  observador lo deja desconocido y firma por heurística de texto (INC-2026-0036). «Check en rojo» y
  «verde ambiguo» no pueden saltar en Codex.

Con esto, la Parte 1 del `PROMPT-CODEX.md` queda cerrada (puntos 3 y 4 respondidos). Queda la Parte 2.

### 05-09-2026 · Stop y PostToolUse fusionados; revisión humana pendiente

Estado comprobado en disco el 05-09 a las 07:30 UTC. La ruta directa de `Stop`
ya estaba instalada; se conserva sin cambios, junto con `global_protocol.py`
y ai-memory. Se añadió únicamente la entrada de `PostToolUse` del adaptador:
`"$HOME/rompelo/bin/rompelo" observe codex`, timeout de 10 segundos. La entrada
de `Stop` es `"$HOME/rompelo/bin/rompelo" hook codex`, timeout de 30 segundos.

Copia previa, comprobada byte a byte antes de editar:
`~/.codex/hooks.json.20260905T073000221984Z.bak`.
La comparación estructural posterior confirma JSON válido, una sola instancia
de cada entrada del adaptador y conservación exacta del resto de la configuración.
No se escribió en `config.toml` ni en `~/.claude/`.

Antes de cualquier edición, ambas baterías terminaron con código 0:
`bash tests/rompelo-stop-test.sh`: `PASS=77 FAIL=0`;
`bash tests/rompelo-observe-test.sh`: `PASS=64 FAIL=0`.
El evaluador y las baterías no se han modificado en esta fase.

**NO VERIFICADO:** confianza efectiva de las dos entradas, bloqueo y silencio
automáticos de `Stop`, y código de un comando fallido recibido por `PostToolUse`.
Falta que José revise y confíe el nuevo `PostToolUse` en `/hooks`, y la entrada
`Stop` solo si figura pendiente. La revisión humana corresponde al encargo y al
[contrato oficial de hooks](https://learn.chatgpt.com/docs/hooks#review-and-trust-hooks).
Todavía no existe una salida literal de bloqueo en vivo de esta intervención.

La Parte 2 no se ha iniciado: el encargo exige completar primero el cruce real.
`ROMPELO-CODEX-01` estaba cerrado al comenzar; `ROMPELO-CODEX-02` queda pendiente.

### 05-09-2026 · cambio a rompelo preparado; escritura global bloqueada

Esta comprobación sustituye el estado de instalación anterior tras el cambio de
nombre. El archivo global conserva tres entradas Stop y la tercera todavía llama
a `"$HOME/assure/bin/assure" hook codex`, cuyo ejecutable ya no existe. La confianza
guardada corresponde a esa definición antigua; no acredita la del comando nuevo.

La batería previa terminó con `PASS=60 FAIL=0` y código 0. Se preparó una fusión
que cambia únicamente el comando de la tercera entrada a
`"$HOME/rompelo/bin/rompelo" hook codex`, conserva el timeout de 30 segundos y deja
intactos todos los demás eventos y opciones. Los archivos revisados son:

- Copia previa: `.rompelo/evidence/hooks.json.20260904T222906Z.bak`.
- Fusión preparada: `.rompelo/evidence/hooks.json.20260904T222906Z.pending.json`.

La escritura mediante `apply_patch` fue rechazada por la política de esta sesión:

```text
patch rejected: writing outside of the project; rejected by user approval settings
```

La comparación posterior confirmó que el archivo global permanece idéntico a la
copia previa. No se escribió en `config.toml` ni se alteró la confianza.

La prueba directa del comando nuevo, con repositorio y `ROMPELO_HOME` desechables,
bloqueó por check sin ejecutar y junta sin cruzar. Después de `rompelo check`,
`rompelo cruce -- true` y `rompelo close`, `rompelo verify` devolvió 0 y el mismo
comando del adaptador quedó en silencio. El bloqueo literal está conservado en
`.rompelo/evidence/codex-adapter-check-20260905.json`; esta prueba no usó la
allowlist real y no constituye un cruce en vivo de Codex.

**NO VERIFICADO:** instalación de la ruta nueva, confianza de esa definición y
bloqueo automático al terminar un turno. Falta aplicar la fusión desde una sesión
con escritura permitida en `~/.codex`; después José debe revisar y confiar en
`/hooks` la entrada `"$HOME/rompelo/bin/rompelo" hook codex`, según el encargo.

### 05-09-2026 · hook instalado; confianza y cruce pendientes

La fusión global está aplicada tras aprobar la escritura puntual. La nueva copia
previa es `~/rompelo/.rompelo/evidence/hooks.json.20260904T220001Z.bak` (fecha UTC).
El JSON instalado contiene exactamente tres entradas Stop: las dos anteriores
y la entrada del adaptador, con timeout de 30 segundos. La comparación estructural
confirma que el resto de eventos, comandos y opciones permanece idéntico.
`cmp` confirmó que el archivo instalado coincide byte a byte con la fusión revisada.

**NO VERIFICADO:** confianza del nuevo hook y cruce en vivo. José debe revisar y
confiar en `/hooks` la entrada `"$HOME/rompelo/bin/rompelo" hook codex`. Esta instalación
no escribe el hash de confianza en `config.toml`. El cruce desechable y la Parte 2
siguen pendientes; `ROMPELO-CODEX-01` permanece abierto.

La batería previa tiene dos pasadas `PASS=58 FAIL=0`; no se ha modificado el
evaluador ni la batería. El bloqueo inicial de escritura queda resuelto.

### 05-09-2026 · comandos que fallan

En Claude Code, `PostToolUse` solo llega tras éxito y el fallo va por `PostToolUseFailure`
(INC-2026-0031; arreglado y cruzado en vivo). Codex no tiene ese evento: su doc dice que
`PostToolUse` «also runs after commands that exit with a non-zero status», así que
`adapters/codex/hooks.json` no cambia. **NO VERIFICADO:** la forma de `tool_response` para un
Bash que falla en Codex; el observador acepta `exit_code` (también en `metadata`) o una primera
línea `Exit code N`. Comprobación concreta en `PROMPT-CODEX.md`, Parte 1, punto 4.

### 04-09-2026 · historial del bloqueo inicial de instalación (resuelto)

**NO VERIFICADO en vivo desde Codex.** El encargo se inició sobre `f9218b8`, con el
árbol limpio. `bash tests/rompelo-stop-test.sh` terminó con código 0 y
`PASS=58 FAIL=0` antes de cualquier edición.

La copia previa de `~/.codex/hooks.json` está en
`~/rompelo/.rompelo/evidence/hooks.json.20260904T214552Z.bak`, ignorada por Git.
`cmp` confirmó igualdad byte a byte antes y después del intento de fusión.
La herramienta rechazó el parche con:

```text
patch rejected: writing outside of the project; rejected by user approval settings
```

La sesión permite leer `~/.codex`, pero no escribir ahí ni solicitar elevación.
El archivo conserva los dos hooks Stop anteriores y no contiene aún rompelo.
La lectura limitada a `features.hooks` / `features.codex_hooks` no encontró un
override explícito en `config.toml`; esto no acredita que el hook haya corrido.
No se modificó la confianza ni se usó una vía alternativa para saltar el rechazo.

La entrada pendiente es exactamente la del adaptador: evento `Stop`, comando
`"$HOME/rompelo/bin/rompelo" hook codex`, timeout `30`. Tras fusionarla en una sesión
con permiso de escritura, José debe revisarla y confiarla en `/hooks` (o en la
revisión de hooks de la app), conforme al [contrato oficial](https://developers.openai.com/codex/hooks#review-and-trust-hooks).
Codex ejecutará después el cruce desechable, conservará el bloqueo literal,
comprobará el paso a silencio y limpiará el repo y su entrada de allowlist.

`ROMPELO-CODEX-01` queda abierto con los tres checks y junta solicitados.
No se inició el módulo de control positivo: el encargo exige completar primero
la instalación y el cruce en vivo. Faltan la fusión, la confianza humana, ese
cruce y la Parte 2 completa; no hay salida literal de bloqueo en vivo que aportar.

Verificación del punto de reanudación: segunda pasada de la batería también
`PASS=58 FAIL=0` (código 0); `git diff --check` sin incidencias. `rompelo verify`
devuelve 1: los tres checks del contrato nuevo siguen sin evidencia registrada
y falta la junta. Las pasadas directas de la batería no sustituyen `rompelo check`
ni prueban la ejecución del hook por Codex.
