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

> Ajuste del 05-09-2026 tras el control negativo real: D1 sube el nivel al **segundo** toque de
> escritura al mismo perfil (`toques_perfil` en `config/observacion.json`); `exterior` a uno.
> Las lecturas (`grep`, `cat`, `git log`… sin redirección) no cuentan como toque.

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

### 12.1 · Segundo cruce y control negativo con sesiones reales (05-09, mañana)

**El observador nunca había visto fallar un comando en Claude Code.** Un `ls` a una ruta
inexistente, ejecutado a propósito, no dejó línea en el libro. La doc oficial lo dice: `PostToolUse`
«fires after a tool has already executed successfully»; el fallo llega por `PostToolUseFailure`,
con `error` = «Exit code N» y la salida detrás. Sin ese evento, dos de los cuatro patrones de D2
(firma repetida, check en rojo) eran incapaces de saltar en vivo, y los 30 casos de la batería
estaban en verde porque los eventos sintéticos llevaban `exit_code` dentro de `tool_response`,
cosa que Claude Code no manda. Es [INC-2026-0031](../incidents/INC-2026-0031.yaml). Arreglado
(hook `PostToolUseFailure` en el fragmento y en `settings.json`, caso con la forma real visto en
rojo 31/37) y cruzado en vivo: el siguiente `ls` fallido quedó en el libro con código 1 y firma.

Al mirar el libro real salió lo segundo, [INC-2026-0032](../incidents/INC-2026-0032.yaml): el
código de salida se buscaba con una expresión sobre stdout, y un `curl` que imprimía «exit
code: 200» o un `sed` que leía documentación con «Exit code 1» dentro quedaban anotados con
esos códigos; y el aviso del harness «Shell cwd was reset to …», que viene en stderr de todo
comando con `cd`, generaba la misma firma de error en tres comandos correctos seguidos. Cuatro
casos en rojo, arreglo: el código solo de la primera línea y solo con la forma `Exit code N`;
sin firma para un comando que salió bien; avisos del harness fuera de stderr antes de contar.

**Control negativo con sesiones reales (§9.2).** `tests/control-negativo-sesiones.py` reproduce,
desde los transcripts locales de `~/.claude/projects/`, los eventos que el hook habría recibido
(éxito → `PostToolUse` con `{stdout, stderr, interrupted, isImage}`; fallo → `PostToolUseFailure`
con `error`) contra un `ROMPELO_HOME` desechable cuya allowlist contiene los repos de esas
sesiones. No imprime ni guarda texto de comandos ni de salidas. Seis sesiones, unos 2.500 eventos
reproducidos, 38 de ellos fallos:

| Pasada | Alarmas de patrón (D2) | Cuáles |
|---|---|---|
| antes | 7 | `cd` «salió con 0 sin salida» ×3; una captura `.png` escrita 4 veces; un `.md` en Downloads editado 4 veces; `docs/PROBLEMAS.md` ×4; `index.astro` ×4 |
| después | 2 | dos `grep` vacíos seguidos; `index.astro` editado 4 veces sin check |

Las dos que quedan son verdaderas por diseño: una búsqueda que no encuentra nada dos veces es
justo el «limpio que no se distingue de no miré», y cuatro ediciones de código sin un check
entre medias es el patrón de José. Las cinco falsas y su arreglo, cada una con caso en rojo:

- `cd repo && pnpm test` se anotaba como `cd` → `programa()` salta el `cd … &&` inicial.
- «verde ambiguo» contaba cualquier programa callado (`git add`, `mkdir`) → solo buscadores
  (`grep`, `rg`, `find`, `curl`, `git diff`…) y checks.
- «ediciones sin verde» contaba documentación, imágenes y ficheros fuera del repo → solo código
  dentro del repo; `.md`, `.txt`, imágenes y PDF no cuentan.
- La lista de checks verdes era literal (`pnpm test`) y no reconocía `pnpm run check`,
  `astro check`, `scripts/comprobar-*.sh` → expresiones en `CHECKS_VERDES`.
- D1 disparaba `auth` por `grep -rn token src` → los programas de solo lectura (sin redirección,
  `-i`, `tee` ni `xargs`) no cuentan para D1.

Lo que el control negativo enseña sobre D1: salta mucho en sesiones reales (en una sesión con
seis repos, 14 avisos de perfil; `auth` y `secretos` salen en las cinco sesiones, porque en esta
casa `pass show`, `.env` y `session` están en todas partes). Cada aviso sube el repo a nivel 2 y
el gate exige segunda pasada. Es lo diseñado en §4 D1, pero en uso real puede ser el «guardián
que grita siempre» de §1.

**Decisión de José (05-09): un perfil sube el nivel al segundo toque de escritura, no al
primero.** Aplicado: `toques_perfil` en `config/observacion.json` (`_defecto: 2`; `exterior: 1`,
porque una dependencia se añade en un solo comando y es D3). La batería muta el umbral a 1 y a 3
para demostrar que se lee. Medido en las mismas cinco sesiones: avisos de perfil **38 → 32**.
Reduce poco, y conviene saberlo: el ruido no viene de toques sueltos sino de trabajo real que
toca `auth` y `secretos` una y otra vez en varios repos. La siguiente palanca, si sigue
molestando, son perfiles por repo en `config/riesgo.json` (un repo de documentación no tiene
`auth`), o subir el umbral solo para `auth` y `secretos`.

El check `rompelo.control-negativo-sesiones` (solo local; en CI no hay transcripts) exige
**exactamente** las dos alarmas legítimas: un observador que dejara de mirar daría cero y pasaría
un simple «no más de dos». Y si una sesión reproduce fallos y el libro no tiene ningún código
distinto de 0, falla con «el observador no ve los fallos»: visto en rojo con una copia mutada
de `bin/rompelo` que no lee códigos.

### 12.2 · Tarde del 05-09: informe, nivel 3, inglés, disparadores

- §8: el informe de cierre lleva una sección «Qué observó el observador»: nivel, perfiles
  tocados, patrones vistos, permisos pedidos (con fecha y si se recordaron) y si el nivel se bajó a
  mano y por qué. Caso en rojo primero (el informe no los listaba).
- §5 nivel 3: el contrato admite `checks_nivel3` (ids del registro). A nivel 0 y 2 no se exigen ni
  se ejecutan; el aviso de nivel 2 los nombra como disponibles; con `rompelo permiso <patron> si`
  el repo pasa a nivel 3, `rompelo check` los ejecuta y el gate los exige con el prefijo
  «nivel 3:». Siete casos, vistos en rojo.
- Idioma: `ROMPELO_LANG=en` o `"idioma": "en"` en `config/observacion.json` traduce los mensajes
  del gate y del observador (tabla `EN` en `bin/rompelo`; el informe sigue en español). La
  batería comprueba que un bloqueo inglés no lleva restos en español y que sin la variable sigue
  en español.
- §9.3: cada incidente lleva `disparador`; `corpus/TABLA.md` tiene la sección «Qué lo habría
  visto». Seis de 32 no tienen disparador ni gate (clases R, T y A: viven fuera del cierre).

Pendiente de este diseño: §4 D3 más allá del perfil `exterior`; perfiles por repo si los dos
toques siguen gritando. NO VERIFICADO: la forma de `tool_response` de Codex para un comando que
falla (`adapters/codex/PROMPT-CODEX.md`, Parte 1, punto 4).

