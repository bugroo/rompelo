# Cambios

Formato: una entrada por versión, lo que cambia para quien usa la herramienta. Lo verificado y lo
no verificado de cada versión está en el relevo enlazado.

## Sin publicar

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
