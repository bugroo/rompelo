# Adaptador Codex (OpenAI) · hooks PreToolUse, UserPromptSubmit, Stop y PostToolUse

**16-09-2026 · disparo `entrega`.** `hooks.json` de este directorio trae ahora cuatro eventos: `PreToolUse`
(matcher `Bash`: deniega commit/push/deploy con el contrato sin cumplir), `UserPromptSubmit` (declara el cierre
cuando el usuario lo pide y adelanta lo que falta), `Stop` (juzga solo con el cierre declarado) y `PostToolUse`
(observador). Es el mismo `rompelo hook codex` para los tres primeros: decide por `hook_event_name`. Formato de
deny leído en `developers.openai.com/codex/hooks` el 16-09-2026: `hookSpecificOutput.permissionDecision: deny`
(Codex acepta también `{"decision":"block"}`); contexto: `hookSpecificOutput.additionalContext`. Campo del prompt en
UserPromptSubmit: `prompt` (se acepta `user_prompt` por si acaso). **Verificado desde Codex CLI 0.154.0 el 17-09-2026**:
deny, contexto, Stop condicional y retirada de la marca; salidas y límites en «Estado · Parte 6». Fusionar las cuatro entradas en `~/.codex/hooks.json` y volver a
confiar en `/hooks`. Detalle del disparo: `docs/disparo.md`.


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
Hay que **fusionar** con el `hooks.json` existente: añadir las entradas de los cuatro eventos y conservar los demás hooks.
Este ejemplo hace una copia previa y evita duplicar los manejadores ya instalados:

```bash
python3 - <<'PY'
import datetime, json, os, shutil, tempfile
from pathlib import Path
f = Path.home() / '.codex/hooks.json'
d = json.loads(f.read_text()) if f.exists() else {'hooks': {}}
nuevos = json.loads((Path.home() / 'rompelo/adapters/codex/hooks.json').read_text())['hooks']
cambios = []
for evento, grupos in nuevos.items():
    actuales = d.setdefault('hooks', {}).setdefault(evento, [])
    for grupo in grupos:
        comando = grupo['hooks'][0]['command']
        encontrados = [g for g in actuales if any(h.get('command') == comando for h in g.get('hooks', []))]
        if encontrados:
            if encontrados != [grupo]:
                raise SystemExit(f'{evento}: entrada distinta; revisa su matcher y sus manejadores antes de fusionar')
        else:
            actuales.append(grupo)
            cambios.append(evento)
if cambios:
    f.parent.mkdir(parents=True, exist_ok=True)
    if f.exists():
        fecha = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        shutil.copy2(f, f.with_name(f.name + '.bak-' + fecha))
    with tempfile.NamedTemporaryFile(mode='w', dir=f.parent, delete=False) as t:
        json.dump(d, t, ensure_ascii=False, indent=2)
        t.write('\n')
    os.chmod(t.name, f.stat().st_mode & 0o777 if f.exists() else 0o600)
    os.replace(t.name, f)
print('añadidos: ' + ', '.join(cambios) if cambios else 'los cuatro eventos ya coinciden')
PY
```

Luego, en Codex, `/hooks` → revisar y confiar las entradas nuevas. El script no modifica la confianza.

## Alcance en los lanzadores de este Mac (medido el 04-09-2026)

`ai`, `ai-web`, `ai-build`, `ai-resume` (funciones de `.zshrc`) llaman a `command codex` sin `--profile` ni `-c`; `~/bin/clobs-codex` usa `--profile` con `clobs.config.toml` y hace `unset CODEX_HOME`. Todos leen `~/.codex/hooks.json`, así que el hook global los alcanza.

## Estado

### 17-09-2026 · Parte 6: disparo `entrega` desde Codex real

Cliente: `codex-cli 0.154.0`; binario de rompelo en `b03c55e`, después de fusionar PR #4 con CI verde.
La instalación añadió únicamente `PreToolUse` y `UserPromptSubmit`: `Stop` y `PostToolUse` ya coincidían.
Los otros diez manejadores del archivo global conservaron su configuración. La skill de Codex coincide
con `adapters/skill/SKILL.md`. Se revisaron y confiaron las entradas nuevas en la interfaz `/hooks`, sin
bypass ni escritura manual de hashes. `rompelo doctor` enumera los cuatro eventos.

La prueba usó un repositorio desechable alistado, contrato `CX-CODEX-06`, un fichero modificado y el check
real `rompelo.tests` pendiente. Se reanudó la misma sesión nativa en tres fases; no se invocó el hook a mano
para acreditar esos resultados.

**PreToolUse.** El primer comando fue `git commit -am x`. El resultado de herramienta nativo conservado
en el transcript, no solo el relato del modelo, contiene literalmente:

```text
Command blocked by PreToolUse hook: [rompelo] Este comando ENTREGA (commit/push/deploy) y la tarea CX-CODEX-06 no está verificada:
- check `rompelo.tests` sin ejecutar (usa `rompelo check`)
Siguiente: rompelo check
Cumple lo que falta y vuelve a lanzar el comando. Lo que no se pueda cumplir se declara en el contrato como NO VERIFICADO, no se omite.. Command: git commit -am x
```

El repositorio mantuvo un único commit. Las tres llamadas siguientes sí llegaron a ejecutarse:

| Comando | Código del proceso | Denegado por el hook |
|---|---|---|
| `ls` | 0 | no |
| `git status --short` | 0 | no |
| `git commit --dry-run` | 1, sin cambios preparados | no |

**Stop sin cierre declarado.** Ese turno terminó con código 0 y `VERIFICACION NATIVA PASO A`, sin
`HookPrompt` de rompelo, sin marca de cierre y sin contador de bloqueo, aunque el contrato seguía pendiente.

**UserPromptSubmit.** El mensaje de usuario exacto `termina y sube esto` produjo este contexto real:

```text
[rompelo] El usuario pide cerrar o entregar la tarea CX-CODEX-06: la puerta la juzgará al terminar este turno y no dejará commit ni push sin evidencia. Ahora mismo falta:
- check `rompelo.tests` sin ejecutar (usa `rompelo check`)
Siguiente: rompelo check
```

En esta ejecución de `codex exec --json` se observó como mensaje `developer` inyectado en el transcript;
no hubo un evento separado con ese contexto en stdout JSON. La presentación visual en la app de escritorio
queda **NO VERIFICADA**. El Stop posterior entregó un `HookPrompt` nativo con este contenido:

```text
[rompelo] La tarea CX-CODEX-06 NO puede darse por terminada (1/3):
- check `rompelo.tests` sin ejecutar (usa `rompelo check`)
Siguiente: rompelo check
No declares la tarea terminada. Resuelve cada punto (rompelo check / rompelo cruce / disposición del hallazgo) y vuelve a intentarlo. Si algo no se puede cumplir, dilo como NO VERIFICADO y déjalo escrito en el contrato.
```

El controlador interrumpió la ejecución después de persistirse ese primer `HookPrompt`; el contador quedó
en 1 y la marca de cierre existía. Después ejecutó la batería real: check código 0, control positivo código 1,
`rompelo close` código 0 y `rompelo verify --json` con `{"ok": true, "motivos": [], "siguiente": ""}`.
Una nueva reanudación devolvió `VERIFICACION NATIVA PASO C`, código 0, cero bloqueos nuevos, marca ausente
y contador todavía en 1. El silencio final no procede del tope de tres bloqueos.

**Forma medida.** Una sonda temporal de proyecto, revisada y confiada en `/hooks`, registró únicamente
nombres de campos y metadatos de evento, nunca el contenido del prompt ni de los comandos:

- ambos eventos traen `hook_event_name`;
- `PreToolUse` identifica el shell como `Bash` y su entrada lleva `tool_input.command`;
- `UserPromptSubmit` trae `prompt` de tipo string; no trae `user_prompt`.

| Batería | Antes | Después |
|---|---|---|
| `tests/rompelo-disparo-test.sh` | `PASS=54 FAIL=0 ROTOS=0` | `PASS=54 FAIL=0 ROTOS=0` |
| `tests/rompelo-observe-test.sh` | `PASS=112 FAIL=0 ROTOS=0` | `PASS=112 FAIL=0 ROTOS=0` |

`rompelo check` también ejecutó ambas: código 0; el control positivo de `rompelo.disparo-tests` devolvió 1.

No fue necesario modificar `bin/rompelo`, `tests/` ni la configuración de Claude. El cruce
`tests/cruce-hooks-entrega.sh` sigue siendo una prueba directa del adaptador de Claude hacia el binario;
complementa esta evidencia nativa de Codex y no la sustituye. El check `rompelo.observe-tests` no tiene
un control positivo separado registrado; su resultado no acredita uno inexistente.

### 11-09-2026 · Parte 5: PR #2 medido desde este Codex

Cliente: `codex-cli 0.153.4` (`codex --version`). El proceso principal confirmó escritura
efectiva en `.git`; `git pull --ff-only` respondió `Already up to date.` sin cambiar de
rama. `HEAD` y `origin/main` quedaron en `044eef3`, merge del PR #2 y posteriores al commit
`337dd84` («contrato MEJORAS-2026-09-11 cerrado»). Se abrió el contrato propio
`ROMPELO-CODEX-05`, con los siete checks prescritos, scope exclusivo de este LEEME y junta.

**Stop y `no_afecta`:** esta misma sesión recibió dos `HookPrompt` nativos desde la
definición global confiada; no se invocó el adaptador directamente, no se usó bypass y no
se modificaron hooks ni hashes de confianza. El primer bloqueo llegó completo, conservó los
saltos de línea y terminó con `Siguiente:` entero y el párrafo de no declarar la tarea
terminada:

```text
[rompelo] La tarea ROMPELO-CODEX-05 NO puede darse por terminada (1/3):
- observación: nivel 2 (firma-repetida). Hace falta una segunda pasada explícita antes de cerrar: campo `segunda_pasada` en el contrato con qué se revisó y qué se encontró (aunque sea nada)
- check `rompelo.tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.observe-tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.instrumento-tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.portabilidad-tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.sin-var-pegada` sin ejecutar (usa `rompelo check`)
- check `rompelo.cruce-settings-claude` sin ejecutar (usa `rompelo check`)
- check `rompelo.control-negativo-sesiones` sin ejecutar (usa `rompelo check`)
- toca_junta: true y no hay cruce real registrado (`rompelo cruce --nota '…' -- <comando real>`)
Siguiente: rompelo check && rompelo cruce --nota '<qué cruzas>' -- <comando real>
No declares la tarea terminada. Resuelve cada punto (rompelo check / rompelo cruce / disposición del hallazgo) y vuelve a intentarlo. Si algo no se puede cumplir, dilo como NO VERIFICADO y déjalo escrito en el contrato.
```

Después, `bin/rompelo check --id rompelo.sin-var-pegada` devolvió código 0, una línea
de una exigida y control positivo 1. Otra edición de este Markdown no invalidó esa evidencia.
El segundo bloqueo no dijo «se ejecutó sobre otro árbol», dejó solo los otros seis checks
sin ejecutar y pidió los seis `--id` exactos:

```text
[rompelo] La tarea ROMPELO-CODEX-05 NO puede darse por terminada (2/3):
- observación: nivel 2 (firma-repetida). Hace falta una segunda pasada explícita antes de cerrar: campo `segunda_pasada` en el contrato con qué se revisó y qué se encontró (aunque sea nada)
- check `rompelo.tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.observe-tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.instrumento-tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.portabilidad-tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.cruce-settings-claude` sin ejecutar (usa `rompelo check`)
- check `rompelo.control-negativo-sesiones` sin ejecutar (usa `rompelo check`)
- toca_junta: true y no hay cruce real registrado (`rompelo cruce --nota '…' -- <comando real>`)
Siguiente: rompelo check --id rompelo.tests --id rompelo.observe-tests --id rompelo.instrumento-tests --id rompelo.portabilidad-tests --id rompelo.cruce-settings-claude --id rompelo.control-negativo-sesiones && rompelo cruce --nota '<qué cruzas>' -- <comando real>
No declares la tarea terminada. Resuelve cada punto (rompelo check / rompelo cruce / disposición del hallazgo) y vuelve a intentarlo. Si algo no se puede cumplir, dilo como NO VERIFICADO y déjalo escrito en el contrato.
```

**Raíz y evidencia nativa:** la sesión real `01a08f3a-ee58-70b1-b600-40243d0a790e`
dejó su consolidado en `.rompelo/evidence/ROMPELO-CODEX-05/cliente-nativo.json`.
`cd adapters/codex && ls` produjo `"repo": "/Users/rootml/rompelo"`; cambiar solo el
`workdir` de una herramienta conservó el `cwd` principal que Codex entregaba al hook, una
limitación comprobada de ese paso de contexto y no un fallo del buscador de raíz. Al reanudar
esta misma sesión con `-C /tmp/rompelo-wt-codex`, una única herramienta nativa `pwd`/`ls`
produjo el 2026-09-11T07:10:00+00:00 un `PostToolUse` con
`"repo": "/private/tmp/rompelo-wt-codex"` y el proceso terminó con código 0: la ruta
canónica del worktree queda verificada. El controlador retiró después el worktree y comprobó
su ausencia; la rama local `rompelo-wt-codex` se conserva. Los dos bloques de arriba
transcriben las razones con las entidades XML decodificadas (`&lt;` → `<`, `&amp;` → `&`);
el envoltorio literal, el código 0 del CLI, el contador 2 y la ausencia de `SIN-VERIFICAR`
permanecen en `cliente-nativo.json`.

**INC-0036:** dos llamadas Bash nativas separadas, `false` y `ls /no/existe`, quedaron en
el libro con `"codigo": null` (respectivamente `stdout_vacio: true, firma: null` y
`stdout_vacio: false, firma: "75e8b671da81"`). Sigue sin código de salida con
`codex-cli 0.153.4`. Como no apareció un número, no se creó un `hooks.json` de proyecto ni
se activó `ROMPELO_DEBUG_FORMA`; no se capturó ni se copió texto de `tool_response`.

| Batería | Antes | Después |
|---|---|---|
| `bash tests/rompelo-stop-test.sh` | PASS=219 FAIL=0 ROTOS=0, rc 0 | PASS=219 FAIL=0 ROTOS=0, rc 0 |
| `bash tests/rompelo-observe-test.sh` | PASS=111 FAIL=0 ROTOS=0, rc 0 | PASS=111 FAIL=0 ROTOS=0, rc 0 |
| `bash tests/instrumento-test.sh` | 26/26 distinciones, rc 0 | 26/26 distinciones, rc 0 |
| `bash tests/portabilidad-test.sh` | PASS=18 FAIL=0 ROTOS=0, rc 0 | PASS=18 FAIL=0 ROTOS=0, rc 0 |

**Siete checks y cierre:** `bin/rompelo check` ejecutó las siete obligaciones y terminó
`todos en verde`, rc 0: `rompelo.tests` 0 (263 líneas; control 1),
`rompelo.observe-tests` 0 (146), `rompelo.instrumento-tests` 0 (39),
`rompelo.portabilidad-tests` 0 (24), `rompelo.sin-var-pegada` 0 (1; control 1),
`rompelo.cruce-settings-claude` 0 (1) y `rompelo.control-negativo-sesiones` 0 (47).
La segunda pasada exigida por nivel 2 quedó escrita en el contrato. Una primera pasada de
`cruce --id rompelo.cruce-settings-claude`, `close` y `verify --json` devolvió tres códigos
0 y `{"ok": true, "motivos": [], "siguiente": ""}`. Como escribir este resultado cambia
la huella de la junta, esta sección es la última edición versionada: después de ella se
repitieron cruce, cierre y verify; los tres volvieron a código 0 con el mismo JSON. El Stop
nativo siguiente quedó en silencio con el contrato cerrado; no se alcanzó el tope de tres
bloqueos. No se recibió un tercer bloqueo durante ninguna de las medidas de raíz, incluida
la ejecución adicional que terminó desde el worktree.

<details>
<summary>Salida literal de doctor antes de abrir ROMPELO-CODEX-05</summary>

```text
rompelo: /Users/rootml/rompelo/bin/rompelo
revisión de rompelo: 044eef3
python: 3.9.6 (/Library/Developer/CommandLineTools/usr/bin/python3)
git: git version 2.54.0 (Apple Git-157)
ROMPELO_HOME: /Users/rootml/rompelo (existe)
ROMPELO_REGISTRO: home
registro: /Users/rootml/rompelo/checks/registry.json + /Users/rootml/rompelo/checks/registry.local.json → 21 check(s): claveon.build, claveon.comprobar-deriva, claveon.comprobar-newsletter, claveon.factura, claveon.gitleaks, claveon.humo-navegador, claveon.mcp-publico, claveon.shellcheck, claveon.test, claveon.typecheck, claveon.typecheck-functions, claveon_b2c-rediseno.build …
allowlist: /Users/rootml/rompelo/config/repos.json → 3 repo(s); este repo SÍ está alistado
estado: /Users/rootml/rompelo/state (existe)
repo: /Users/rootml/rompelo
contrato: MEJORAS-2026-09-11 · estado cerrada · nivel efectivo 2 · checks exigidos ['rompelo.tests', 'rompelo.observe-tests', 'rompelo.instrumento-tests', 'rompelo.portabilidad-tests', 'rompelo.sin-var-pegada', 'rompelo.cruce-settings-claude', 'rompelo.control-negativo-sesiones']
hooks Claude Code: /Users/rootml/.claude/settings.json → Stop, PostToolUse, PostToolUseFailure
hooks Codex: /Users/rootml/.codex/hooks.json → Stop, PostToolUse
cliente claude: /Users/rootml/.local/bin/claude
cliente codex: /opt/homebrew/bin/codex
```

</details>

### 07-09-2026 · Parte 4: binario del PR #1 cruzado en vivo

Cliente: `codex-cli 0.153.4` (`codex --version`). Precondición comprobada contra la API de
GitHub: PR [#1](https://github.com/bugroo/rompelo/pull/1) fusionado; al iniciar, `HEAD` en
`main` coincidía con su merge commit `35c02955d677e9279a8de003ba5c612df7e034be`.
`git pull --ff-only` respondió `Already up to date.` Se abrió el contrato propio
`ROMPELO-CODEX-04`, con los siete checks de la Parte 4 y junta, sin cambiar de rama.

**Resultado en el cliente real:** sesión `01a07d8b-5bef-77b0-ad0a-66274cc8bcce`,
lanzada con `codex exec --json --sandbox workspace-write -C /Users/rootml/rompelo`,
sin bypass ni cambios de confianza. El transcript contiene dos `HookPrompt` nativos de
`Stop` procedentes de la definición global. Tras `check`, `cruce`, `close` y
`verify --json` ejecutados dentro de esa sesión (todos con código 0; verify:
`{"ok": true, "motivos": []}`), el cliente terminó con código 0 sin otro bloqueo.
La marca quedó en 2 y no existe `SIN-VERIFICAR.json`: el silencio no fue por alcanzar el tope.

Durante la verificación de esta nota, otra sesión añadió commits de documentación hasta
`855bfcc`. El cierre detectó esos archivos fuera de scope y evidencia obsoleta (`close` 1;
los siete checks habían devuelto 0). Se conservó ese intento en la evidencia y se reabrió
el contrato propio con `init --force` sobre la nueva base, manteniendo el scope y los siete
checks. No se tocaron los cambios ajenos; binario y tests conservaron sus SHA-256 originales.
La validación posterior se ejecuta completa sobre esta base, sin reutilizar las evidencias
del intento invalidado. Véanse `base-tras-concurrencia.json` y `comandos-finales.json`.

| Comando real de batería | Antes del cruce | Después de los estímulos |
|---|---|---|
| `bash tests/rompelo-stop-test.sh` | PASS=193 FAIL=0 ROTOS=0 | PASS=193 FAIL=0 ROTOS=0 |
| `bash tests/rompelo-observe-test.sh` | PASS=100 FAIL=0 ROTOS=0 | PASS=100 FAIL=0 ROTOS=0 |
| `bash tests/instrumento-test.sh` | 26 de 26 distinciones correctas, rc 0 | 26 de 26 distinciones correctas, rc 0 |
| `bash tests/portabilidad-test.sh` | PASS=18 FAIL=0 ROTOS=0 | PASS=18 FAIL=0 ROTOS=0 |

`bin/rompelo check --id rompelo.sin-var-pegada` pasó con código 0 y control positivo 1.
El siguiente `apply_patch` invalidó esa evidencia, y el segundo Stop lo detectó.
`bin/rompelo check` completo pasó los siete checks, con controles positivos 1 para
`rompelo.tests` y `rompelo.sin-var-pegada`. Se esperó el proceso persistente hasta su
fin; después se ejecutó `bin/rompelo cruce --id rompelo.cruce-settings-claude`.

**Observador:** la primera herramienta fue `apply_patch`; la primera lectura tras el
bloqueo encontró en la última línea del libro de esa misma sesión:

```json
{"tool":"apply_patch","evento":"PostToolUse","ficheros":["/Users/rootml/rompelo/adapters/codex/LEEME.md"]}
```

Es un extracto de campos del evento real, no un payload sintético. No fue necesario activar
`ROMPELO_DEBUG_FORMA`. La segunda edición del LEEME también dejó la ruta correcta.

**Permisos:** con `checks_nivel3: ["rompelo.tests"]` temporal, `permiso rompelo.tests si`
subió de 2 a 3; `permiso rompelo.tests no` volvió a 2, con permisos activos vacíos.
El siguiente Stop dijo literalmente «permiso revocado; queda pendiente». Se retiró el
`checks_nivel3` temporal, manteniendo los siete checks ordinarios. No se usó
`--recordar`, `nivel bajar` ni una excepción. Las dos entradas temporales añadidas por
el comando a `config/permisos.json` se conservaron en la evidencia del ensayo y se
restauró la configuración previa byte a byte; el estado revocado se conservó.

**Diferencias respecto al guion:** el registro efectivo contiene 19 checks (7 del registro
versionado y 12 locales); el nivel previo era 2 por observación, por lo que revocar no lo
llevó a 0. El primer Stop no contenía la palabra «huella»: los checks estaban sin ejecutar.
El segundo sí detectó evidencia obsoleta con el texto «se ejecutó sobre otro árbol».
También detectó `config/permisos.json` fuera de scope durante el estímulo de permiso;
la restauración indicada eliminó ese cambio antes del check completo.

**Ruta:** Stop sigue en `"$HOME/rompelo/bin/rompelo" hook codex`, timeout 30;
PostToolUse en `"$HOME/rompelo/bin/rompelo" observe codex`, timeout 10.
**Confianza efectiva:** confirmada por la ejecución de las definiciones globales sin bypass;
no se modificaron `hooks.json` ni hashes de confianza, ni se realizó una nueva revisión en
`/hooks`. **Ejecución automática:** confirmada por los dos HookPrompt y el cierre posterior;
una invocación directa del adaptador no se ha usado como prueba de ese resultado.
Binario, `tests/` y shim de compatibilidad conservan sus SHA-256. No se escribió en
`~/.claude/`; los dos checks locales prescritos solo consumen settings/transcripts.

**NO VERIFICADO:** transición a nivel 0 tras revocar en esta instalación (se observó 2,
su nivel previo); una nueva aprobación visual en `/hooks` (no era necesaria porque las
definiciones no cambiaron). Estas pruebas no acreditan los cruces de otros clientes ni
las limitaciones de la auditoría ajenas a esta Parte 4.

Evidencia local ignorada por Git: `.rompelo/evidence/ROMPELO-CODEX-04/`
(`antes.json`, `baseline.json`, `baterias-despues.json`, `cruce-automatico.json`,
`apply-patch-observado.json`, `permisos-observados.json` y salidas del cliente).

<details>
<summary>Salida literal de doctor antes de abrir el contrato propio</summary>

```text
rompelo: /Users/rootml/rompelo/bin/rompelo
revisión de rompelo: 35c0295
python: 3.9.6 (/Library/Developer/CommandLineTools/usr/bin/python3)
git: git version 2.50.1 (Apple Git-155)
ROMPELO_HOME: /Users/rootml/rompelo (existe)
ROMPELO_REGISTRO: home
registro: /Users/rootml/rompelo/checks/registry.json + /Users/rootml/rompelo/checks/registry.local.json → 19 check(s): claveon.build, claveon.comprobar-deriva, claveon.comprobar-newsletter, claveon.gitleaks, claveon.humo-navegador, claveon.shellcheck, claveon.test, claveon.typecheck, claveon.typecheck-functions, claveon_b2c-rediseno.build, claveon_b2c-rediseno.test, claveon_b2c-rediseno.typecheck …
allowlist: /Users/rootml/rompelo/config/repos.json → 3 repo(s); este repo SÍ está alistado
estado: /Users/rootml/rompelo/state (existe)
repo: /Users/rootml/rompelo
contrato: MEJORAS-AUDITORIA-2026-09-07 · estado cerrada · nivel efectivo 2 · checks exigidos ['rompelo.tests', 'rompelo.instrumento-tests', 'rompelo.portabilidad-tests', 'rompelo.cruce-settings-claude', 'rompelo.sin-var-pegada', 'rompelo.observe-tests', 'rompelo.control-negativo-sesiones']
hooks Claude Code: /Users/rootml/.claude/settings.json → Stop, PostToolUse, PostToolUseFailure
hooks Codex: /Users/rootml/.codex/hooks.json → Stop, PostToolUse
cliente claude: /Users/rootml/.local/bin/claude
cliente codex: /opt/homebrew/bin/codex
```

</details>

<details>
<summary>Primer bloqueo automático: checks sin ejecutar</summary>

```text
[rompelo] La tarea ROMPELO-CODEX-04 NO puede darse por terminada (1/3):
- observación: nivel 2 (firma-repetida). Hace falta una segunda pasada explícita antes de cerrar: campo `segunda_pasada` en el contrato con qué se revisó y qué se encontró (aunque sea nada)
- check `rompelo.tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.observe-tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.instrumento-tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.portabilidad-tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.sin-var-pegada` sin ejecutar (usa `rompelo check`)
- check `rompelo.cruce-settings-claude` sin ejecutar (usa `rompelo check`)
- check `rompelo.control-negativo-sesiones` sin ejecutar (usa `rompelo check`)
- toca_junta: true y no hay cruce real registrado (`rompelo cruce --nota '…' -- <comando real>`)
No declares la tarea terminada. Resuelve cada punto (rompelo check / rompelo cruce / disposición del hallazgo) y vuelve a intentarlo. Si algo no se puede cumplir, dilo como NO VERIFICADO y déjalo escrito en el contrato.
```

</details>

<details>
<summary>Segundo bloqueo automático: evidencia obsoleta y permiso revocado</summary>

```text
[rompelo] La tarea ROMPELO-CODEX-04 NO puede darse por terminada (2/3):
- observación: nivel 2 (firma-repetida). Hace falta una segunda pasada explícita antes de cerrar: campo `segunda_pasada` en el contrato con qué se revisó y qué se encontró (aunque sea nada)
- fuera de scope_paths: config/permisos.json
- check `rompelo.tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.observe-tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.instrumento-tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.portabilidad-tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.sin-var-pegada` se ejecutó sobre otro árbol (hay cambios posteriores)
- check `rompelo.cruce-settings-claude` sin ejecutar (usa `rompelo check`)
- check `rompelo.control-negativo-sesiones` sin ejecutar (usa `rompelo check`)
- nivel 3: check `rompelo.tests`: permiso revocado; queda pendiente. Vuelve a concederlo (`rompelo permiso rompelo.tests si`) o escribe una excepción en el contrato
- el cruce real es anterior al último cambio; hay que cruzar DESPUÉS de desplegar el último cambio
No declares la tarea terminada. Resuelve cada punto (rompelo check / rompelo cruce / disposición del hallazgo) y vuelve a intentarlo. Si algo no se puede cumplir, dilo como NO VERIFICADO y déjalo escrito en el contrato.
```

</details>

### 06-09-2026 · Parte 3 desde Codex sobre 86001d2

`git pull --ff-only` ya estaba al día en `86001d2`. Antes de cualquier cambio, las baterías
reales terminaron con `PASS=113 FAIL=0` (`rompelo-stop-test.sh`) y `PASS=75 FAIL=0`
(`rompelo-observe-test.sh`). `rompelo check --id` es repetible y solo admite checks incluidos
en el contrato. La suite debe ejecutarse en un proceso persistente o con timeout de al menos
300000 ms, sin envolver `check` en bucles. El observador se comprueba entre DOS llamadas de
herramienta; cada worktree tiene su propia raíz y su propia entrada en la allowlist.

Acabo de recibir el bloqueo automático desde `codex exec` en `~/rompelo`; no procede de una
invocación directa del adaptador. Cabecera y motivos recibidos literalmente:

```text
[rompelo] La tarea ROMPELO-CODEX-03 NO puede darse por terminada (1/3):
- check `rompelo.tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.cruce-settings-claude` sin ejecutar (usa `rompelo check`)
- check `rompelo.sin-var-pegada` sin ejecutar (usa `rompelo check`)
- check `rompelo.observe-tests` sin ejecutar (usa `rompelo check`)
- check `rompelo.control-negativo-sesiones` sin ejecutar (usa `rompelo check`)
- toca_junta: true y no hay cruce real registrado (`rompelo cruce --nota '…' -- <comando real>`)
```

Los hooks siguen sin cambios: `Stop` usa timeout 30 y `PostToolUse` timeout 10. No hubo
reconfianza. Esta nota sustituye el `NO VERIFICADO` de la entrada anterior de `fa672f9`, que
se conserva debajo como historial.

### 06-09-2026 · `check --id`, aviso de timeout, INC-0037/0038 (Claude Code, `fa672f9`)

`rompelo check` rechaza argumentos sueltos y admite `--id`. Parte 3 de `PROMPT-CODEX.md` pide a
Codex ponerse al día (pull, baterías, anotar aquí). Hook de Codex sin cambios. NO VERIFICADO:
que Codex reciba el bloqueo tras este commit (el binario cambió; `hooks.json` no).

### 05-09-2026 · Parte 2 implementada sobre c652432

Triestado y control positivo por check disponibles en `check` y `verify --ci`.
Controles reales incluidos para `rompelo.tests` (scope anulado en una copia) y
`rompelo.sin-var-pegada` (guion malo conocido). Gate 77 → 109 casos; rojo previo: 23 fallos,
más un caso de cierre que ocultaba un check recién fallado. Detalles y límites en
[`docs/control-positivo.md`](../../docs/control-positivo.md).

El estado histórico de la Parte 1 se conserva debajo. Esta intervención no vuelve a instalar
hooks ni cambia la confianza. Comprobado en disco: Stop sigue apuntando a
`"$HOME/rompelo/bin/rompelo" hook codex`, con timeout 30; el shim sigue disponible.
Los controles de ClaveON INC-0033/0034/0035 siguen pendientes de implementación específica.

### 05-09-2026 (mediodía) · cruzado en vivo desde Claude Code con `codex exec`

Los hooks corren y están confiados (José los aceptó en `/hooks`). Cruce sobre repos desechables:

- Stop con contrato sin cumplir → bloqueo literal «`[rompelo] La tarea CRUCE-CODEX NO puede darse
  por terminada (1/3)`: check `rompelo.sin-var-pegada` sin ejecutar; `toca_junta: true` y no hay
  cruce real registrado». Codex cumplió el contrato solo (`check`, `cruce`, `close`) y el siguiente
  Stop fue silencio. Con instrucción de insistir: tres bloqueos, a la cuarta `systemMessage`.
- La marca del tope no se escribía bajo el sandbox de Codex (tempdir no escribible): movida a
  `~/rompelo/state/marcas/`. Verificado: la marca cuenta 4 y el cuarto intento no bloquea.
- `PostToolUse` llega para las herramientas observadas. **Codex no manda código de salida** en
  `tool_response` de Bash: es salida del proceso. Corrección del diagnóstico, 16-09-2026:
  no depende de `text(r.output)`; el rollout 0.154.0 sí contiene eventos de estado estructurados. El
  observador lo deja desconocido y firma por heurística de texto (INC-2026-0036). «Check en rojo» y
  «verde ambiguo» no podían saltar en esa implementación. Véase la corrección INC-0036 al final.

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

## 16-09-2026 · INC-0036: códigos de salida con procedencia

El adaptador de Bash ya no interpreta stdout como estado, aunque contenga `Exit code 0`
o JSON con `exit_code`. Codex CLI 0.154.0 registra el resultado en eventos estructurados
del transcript. Rómpelo los correlaciona por sesión, turno e identificador completo;
valida código y estado, deduplica y reconcilia resultados tardíos también en Stop.
La explicación antigua que atribuía la pérdida a `text(r.output)` era incorrecta.

No cambian las definiciones ni la confianza de los hooks. Los libros incorporan procedencia
del código y motivo de cobertura incompleta, sin copiar salidas o conversación.
Una versión no comprobada, archivo ausente o datos contradictorios mantienen `codigo: null`.
No se reinterpretan ceros históricos sin procedencia. El formato de transcript no es una
API estable; [límites y funcionamiento](../../docs/observacion.md#inc-0036--estado-con-procedencia-16-09-2026).

Verificación nativa: sesiones nuevas de Codex CLI 0.154.0 y Claude Code 2.1.273, con los hooks
existentes, registraron los códigos esperados de nueve casos distintos, incluidos stdout
engañoso, polling, TTY en Codex y terminación del propio proceso por señal; también se repitieron
`true` y `false` concurrentemente. Cada cliente recibió un bloqueo real de Stop y cerró su
contrato tras cumplirlo. La prueba automática vive en `tests/codex-native-test.py`.
También se cruzaron entrada por stdin (0) e interrupción con Ctrl-C: Codex informó 1,
que coincidió con el libro. No se presupone el código convencional 130; se exige el estado
real no cero y su coincidencia independiente por identificador con el runtime.

**NO VERIFICADO:** interacción desde la app gráfica de Codex; Computer Use bloqueó el acceso
a `com.openai.codex` por seguridad. La prueba CLI no se presenta como prueba de esa interfaz.
Otras versiones, subagentes y sesiones remotas requieren su propia verificación de compatibilidad.
Evidencia local completa en `.rompelo/evidence/CODEX-INC0036-20260916/`.
