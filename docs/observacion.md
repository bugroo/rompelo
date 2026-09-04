# Capa de observación · diseño (05-09-2026)

Texto común para José, Claude Code y Codex. Se escribe antes de tocar código y se cambia
aquí primero. Todo lo que diga «hay que medir» está sin medir.

## 1. Para qué

La puerta (`rompelo hook`) ya impide cerrar sin evidencia. Pero comprobar a fondo cada tarea
no se sostiene, y esperar a ver errores para empezar a comprobar deja pasar justo los fallos
silenciosos, que en el corpus son mayoría (clase I: 8 de 28; S: 6; T: 3). La capa de
observación decide **cuándo subir la intensidad**, con tres disparadores, y **avisa antes**
de subirla. Lo decide código a partir de eventos, no el modelo opinando sobre sí mismo.

## 2. De dónde salen los datos

Los dos agentes ya emiten el evento que hace falta: `PostToolUse`, con `tool_name`,
`tool_input` y `tool_response` (docs oficiales leídas el 04-09-2026: code.claude.com/docs/en/hooks.md
y developers.openai.com/codex/hooks.md). Un hook `rompelo observe <agente>` lee cada evento y
escribe una línea en un libro por sesión, **fuera del repo**:

```
~/rompelo/state/sesiones/<agente>-<session_id>.jsonl      (append-only)
```

Cada línea guarda solo lo necesario para reconocer patrones, nunca contenido:

| Campo | Qué es | Qué NO se guarda |
|---|---|---|
| `t` | instante UTC | |
| `repo` | raíz git real (realpath) o `null` | |
| `tool` | `Bash`, `Edit`, `Write`, `apply_patch`, MCP… | |
| `prog` | primer token del comando y subcomando (`git commit`, `pnpm test`) | el comando entero: puede llevar secretos (`curl -H "Key: $(pass show …)"`) |
| `cmd_sha` | sha256 corto del comando normalizado | |
| `codigo` | código de salida si el agente lo da; si no, `null` (**NO VERIFICADO** que Claude Code lo incluya siempre en `tool_response`; el hook `werixo-medir-de-verdad.sh` lo lee con fallback) | |
| `stderr_lineas` | recuento | el texto |
| `firma` | ver §3 | la línea de error |
| `ficheros` | rutas relativas tocadas por Edit/Write/apply_patch | el contenido |

Retención: 30 días, borrado por `rompelo state prune`. Tamaño esperado: unas decenas de KB por sesión.

## 3. Firma de error

`firma` = sha256 corto de la **última línea no vacía de stderr**, normalizada: minúsculas,
números → `#`, hex largo → `#`, rutas absolutas → `/…/`, comillas fuera, espacios
colapsados. Dos fallos con la misma firma son «el mismo error» aunque cambien líneas,
ficheros o ids. Si no hay stderr y `codigo ≠ 0`, la firma es `prog:codigo`.

Control positivo de la firma (obligatorio en la batería): dos stderr reales distintos en
texto pero iguales en causa producen la misma firma; dos causas distintas, firmas distintas.

## 4. Los tres disparadores

### D1 · riesgo de la tarea (no espera a ningún error)

`~/rompelo/config/riesgo.json` mapea patrones de ruta y de comando a un perfil:

| Perfil | Señal | Ejemplo |
|---|---|---|
| `auth` | rutas con `auth`, `session`, `login`, `token`, `oauth` | INC-0004 |
| `secretos` | `.env*`, `secrets`, `vault`, `pass show` en comando | INC-0001 |
| `datos` | `migrations/`, `*.sql`, `psql`, `supabase` | INC-0008 |
| `despliegue` | `deploy`, `wrangler`, `docker compose up`, `systemctl` | INC-0012 |
| `junta` | `functions/api/`, `webhook`, `n8n`, `workflows/`, variables de entorno en dos sitios | INC-0004, 0014, 0027 |
| `exterior` | `pnpm add`, `pip install`, cambio en `dependencies` de `package.json`, `pyproject` | criterio de rootml-de |

El perfil se calcula en cada Edit/Write/Bash. Cuando **sube** (de ninguno a uno, o entra uno
nuevo), se avisa una vez (§6). El perfil activo se guarda en el estado de la sesión y la
puerta lo lee: `junta` obliga a `toca_junta: true` en el contrato aunque el agente no lo
haya puesto; `exterior` obliga a al menos una afirmación con estado sobre la dependencia
(licencia, versión, límite); `secretos` y `datos` obligan al control positivo de todos los
checks. **El perfil manda sobre el contrato**, porque el contrato lo escribe el agente.

### D2 · patrón repetido (el disparador de José)

Se calcula sobre el libro de la sesión, y también sobre las últimas 24 h del mismo repo
(un patrón que cruza sesiones es peor, no mejor):

| Patrón | Umbral inicial | Por qué ese número |
|---|---|---|
| misma `firma` de error | 2 | José: «una más de dos veces» |
| mismo check de rompelo en rojo (`check-<id>.json` con código ≠ 0 dos veces seguidas) | 2 | igual |
| mismo fichero editado sin que ningún check pase entre medias («thrashing») | 4 ediciones | a partir de la 4ª el agente está adivinando; hay que medirlo con sesiones reales antes de fijarlo |
| verde ambiguo repetido (código 0 con salida vacía o `stderr_lineas > 0`) sobre el mismo `prog` | 2 | clase I, INC-0018/0019 |

Los umbrales viven en `~/rompelo/config/observacion.json`, no en el código, y la batería los
muta (umbral 1 → salta a la primera; umbral 99 → no salta) para ver que se leen de verdad.

### D3 · afirmación sobre el mundo exterior

No se puede leer del flujo de herramientas con fiabilidad, así que se apoya en dos cosas:
el perfil `exterior` de D1 (dependencia nueva) y el campo `toca_exterior` del contrato. Al
activarse, la puerta exige afirmaciones con estado (ya implementado) y la escalada (§5)
autoriza búsquedas con la regla de rootml-de: pregunta que decide, fuente de primera mano,
cita textual. Una búsqueda sin cita no cuenta.

## 5. Niveles de intensidad

| Nivel | Nombre | Qué exige la puerta | Cuándo |
|---|---|---|---|
| 0 | suelo | contrato + evidencia sobre la huella (lo de hoy) | siempre; cuesta ~1 s |
| 1 | vigilancia | igual, más aviso al agente y al usuario de qué patrón se vio | al primer disparo |
| 2 | exigencia | control positivo en todos los checks; cruce de junta si el perfil lo incluye; afirmaciones con estado si `exterior`; una segunda pasada explícita antes de cerrar | tras el aviso (§6) |
| 3 | externo | además, herramientas externas del perfil: mutation testing (Stryker/PIT) en `lógica`, Strix o semgrep en `expuesto`, búsqueda en internet con cita | solo con permiso de José, recordado por patrón |

El nivel se guarda en `~/rompelo/state/sesiones/…` y en `~/rompelo/state/repos/<sha-de-la-ruta>.json`
(nivel del repo, con fecha). Baja solo de forma explícita (`rompelo nivel bajar --motivo`) o
al cerrar una tarea con todo en verde en nivel 2.

## 6. Aviso y permiso

1. **Aviso, siempre y una vez por patrón y sesión.** El hook devuelve `additionalContext`
   (los dos agentes lo admiten en PostToolUse) con un texto fijo: qué patrón, con qué
   evidencia (dos firmas iguales, cuatro ediciones…), a qué nivel se sube y qué va a exigir.
   El agente tiene que decírselo al usuario en su siguiente mensaje, en dos líneas, y seguir.
2. **Subir a nivel 2 no pide permiso.** Son comprobaciones locales, sin coste externo, y es
   lo que evita el fallo silencioso.
3. **Subir a nivel 3 sí pide permiso**, porque gasta (búsquedas, herramientas externas,
   tiempo). El agente pregunta; la respuesta se registra con
   `rompelo permiso <patron> si|no [--recordar]`. Con `--recordar` queda en
   `~/rompelo/config/permisos.json` y no se vuelve a preguntar por ese patrón: eso es el
   aprendizaje de Hermes, pero como regla ejecutable y aprobada por una persona.
4. Límite conocido: `rompelo permiso` lo ejecuta el agente, así que podría registrar un «sí»
   inventado. No es un control de seguridad, es de experiencia; el informe de cierre (§8)
   enseña cada permiso con su hora para que el usuario lo vea.

## 7. Adaptadores

- Claude Code: `PostToolUse` sin matcher → `~/rompelo/adapters/claude/rompelo-observe.sh` → `rompelo observe claude`.
  Convive con `werixo-medir-de-verdad.sh` (mismo evento, otro propósito); a medio plazo la
  regla del «cero ambiguo» de ese hook pasa aquí.
- Codex: entrada `PostToolUse` en `~/rompelo/adapters/codex/hooks.json` → `rompelo observe codex`.
  Mismo libro, mismos patrones: la paridad se prueba con el mismo flujo de eventos por los
  dos adaptadores.
- Los hooks de observación **nunca bloquean** (PostToolUse no puede deshacer nada) y fallan
  en silencio hacia un fichero de error, para no romper la sesión.

## 8. Informe de cierre en llano

Al cerrar la tarea, `rompelo close` imprime tres bloques para el usuario que no lee código:
**qué se comprobó y se vio fallar** (checks con control positivo), **qué no se pudo comprobar**
(afirmaciones `no_verificado` y checks sin control positivo), **qué patrones saltaron y qué
permisos diste** (con hora). Es lo que convierte la herramienta en algo que enseña.

## 9. Cómo se verifica este diseño (antes de darlo por bueno)

1. Batería con flujos de eventos sintéticos por fixture: cada disparador visto en rojo (salta)
   y en verde (no salta), umbrales mutados, paridad Claude/Codex sobre el mismo flujo.
2. Control negativo con sesiones reales: reproducir el libro de al menos 5 sesiones sanas
   (los transcripts de `~/.claude/projects/` sirven como fuente, leídos solo para extraer
   `prog`, códigos y rutas) y exigir cero alarmas. Es la tasa de falsos bloqueos.
3. Contra el corpus: para cada uno de los 28 incidentes, decir qué disparador lo habría
   subido de nivel y a qué altura de la tarea. Se anota en el YAML (`disparador`) y la tabla
   lo cuenta. Sin inventar: un incidente que ningún disparador ve se marca así.
4. Junta cruzada: sesión real con un error provocado dos veces y ver llegar el aviso.

## 10. Fuera de este diseño

Detección de patrones por LLM, resúmenes de transcript, dashboard, servidor, MCP, y cualquier
lectura del contenido de comandos o salidas más allá de recuentos y hashes.

## 11. Orden de trabajo

1. Codex termina el módulo de control positivo (`PROMPT-CODEX.md`), que es lo que el nivel 2 exige.
2. `rompelo observe` + libro + firma + D1 y D2, con la batería del §9.1.
3. Aviso, niveles y `rompelo permiso`.
4. Informe en llano.
5. D3 y nivel 3 (externo), con Strix o Stryker como primer check registrado de perfil.

## 12. Cruce en vivo (05-09-2026)

Implementados §2, §3, §4 (D1 y D2), §5 (niveles 0, 2 y 3), §6 (aviso una vez por patrón y
sesión; `rompelo permiso`) y §7 (adaptadores Claude y Codex). Batería propia:
`tests/rompelo-observe-test.sh`.

El primer cruce real lo hizo el propio observador sin provocarlo: conectado el hook
`PostToolUse` en Claude Code, la sesión que estaba escribiendo esta documentación en
`~/rompelo` recibió el aviso de nivel 2 con los perfiles `junta`, `auth`, `despliegue` y
`secretos`. Dos cosas verificadas a la vez: el camino settings.json → hook → `rompelo observe`
→ `additionalContext` funciona, y D1 tenía un falso positivo: leía las palabras de riesgo en el
**cuerpo de un heredoc** que escribía prosa, no en un comando. Arreglado quitando los cuerpos de
heredoc antes de evaluar D1, con caso en rojo primero.

Pendiente de este diseño: §4 D3 más allá del perfil `exterior`, §5 nivel 3 con herramientas
externas registradas, §8 informe con patrones y permisos (hoy el informe no los lista), §9.2
control negativo con sesiones reales y §9.3 anotar en cada incidente el disparador que lo
habría visto.

