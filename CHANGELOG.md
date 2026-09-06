# Cambios

Formato: una entrada por versión, lo que cambia para quien usa la herramienta. Lo verificado y lo
no verificado de cada versión está en el relevo enlazado.

## Sin publicar

- `rompelo check` ya no descarta argumentos en silencio: `check no.existe` ejecutaba todo y
  decía «todos en verde» (INC-0037). Ahora solo admite `--id ID` (repetible, acotado a los
  checks exigidos por el contrato) y cualquier otro argumento es error sin ejecutar nada.
  Cuatro casos en rojo en la batería.
- `--help` y README avisan: una suite entera supera los 120 s del timeout por defecto de la
  herramienta Bash de Claude Code; lanzar con timeout ≥ 300000 o en segundo plano, e iterar con
  `--id`.
- Corpus 38 (I=18): INC-0037 y INC-0038 (código de salida del envoltorio que no es el del
  trabajo: cinco checks en verde reportados como exit 1).
- `docs/observacion.md` §9: el control positivo del observador abarca dos llamadas de
  herramienta separadas; solo repos git quedan cubiertos.
- Control positivo opcional por check: debe detectar un caso malo con código 1 antes de
  ejecutar el check real. Incluidos los controles de la batería (mutante de scope) y de
  `sin-var-pegada`; no se guarda salida de ninguno de los dos procesos.
- Triestado en el registro: hallazgo, instrumento que no pudo mirar y aborto inesperado
  tienen motivos distintos. `check` informa líneas/mínimo y resultado del control.
- Evidencia y cierre vinculados también a la definición del check; un cierre anterior no
  oculta un check recién fallado. Las evidencias antiguas requieren repetir `check`/`close`.
- Gate 77 → 109 casos. Cobertura concreta y límites de la Parte 2 en
  [docs/control-positivo.md](docs/control-positivo.md).
- Codex cruzado en vivo con `codex exec`: bloqueo del `Stop` con motivos, cierre por el propio
  agente, silencio después, tope de tres bloqueos. La marca del tope pasa de `tempdir` a
  `state/marcas/` (bajo el sandbox de Codex no se escribía y el tope nunca llegaba).
- Codex no manda código de salida en `PostToolUse`: el observador lo deja como desconocido en vez
  de 0 y saca la firma de error de la última línea por heurística (INC-2026-0036).
- `ROMPELO_DEBUG_FORMA=1` guarda la forma del payload (sin texto por defecto) en `state/forma.jsonl`.
- Corpus 32 → 36 (INC-0033 a 0036), batería del observador 64 → 75.
- Perfiles de riesgo por repo (`por_repo` en `config/riesgo.json` / `config/riesgo.local.json`).
- Nivel 3 usado de verdad: gitleaks y ShellCheck como `checks_nivel3` sobre un repo de trabajo.
- El motivo del gate a nivel 3 por permiso dice el nivel real («por permiso, sin patrones»).

## v0.1.0 · 2026-09-05

Primera versión etiquetada. Relevo: [docs/RELEVO-2026-09-05.md](docs/RELEVO-2026-09-05.md).

- Puerta de cierre por contrato (`.rompelo/task.json`, ids en un registro, argv sin shell,
  allowlist de repos) para el hook `Stop` de Claude Code y de Codex. Checks sobre la huella del
  contenido actual, salida mínima, cruce real de junta después del último cambio, hallazgos con
  disposición, afirmaciones con estado, scope, prueba en el diff. Tope de tres bloqueos.
- `rompelo verify --ci`: juez independiente que ignora la evidencia guardada. Workflow listo.
- `rompelo init` con detección de checks; `rompelo close` con informe en llano que incluye lo que
  vio el observador (nivel, perfiles, patrones, permisos).
- Capa de observación (`PostToolUse` y `PostToolUseFailure`): libro por sesión sin texto de
  comandos ni salidas, perfiles de riesgo (dos toques de escritura), patrones repetidos, niveles
  0/2/3, aviso una vez por patrón y sesión, `rompelo permiso`, `rompelo nivel bajar`. Checks de
  nivel 3 (`checks_nivel3` en el contrato) exigidos solo con permiso.
- Mensajes del gate y del observador en inglés con `ROMPELO_LANG=en` o `"idioma": "en"` en
  `config/observacion.json`. El informe de cierre sigue en español.
- Corpus de 32 incidentes reales con clase y disparador; tabla generada.
- Baterías: 77 casos del gate y 64 del observador, cada condición vista en rojo con mutación
  confirmada; control negativo con cinco sesiones reales reproducidas desde los transcripts.

Conocido y sin resolver en esta versión: el lado de Codex no está cruzado en vivo; la forma con
la que Codex entrega un comando que falla no está verificada; los checks no tienen control
positivo (es la Parte 2 de `adapters/codex/PROMPT-CODEX.md`).
