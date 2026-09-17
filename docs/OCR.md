# ocr (alibaba/open-code-review) como check de rompelo

Medido el 16-09-2026 con ocr v1.12.3 (binario de GitHub Release, sha256 verificado) y `claude-sonnet-5`.

## Reparto

- **ocr** lee el diff y produce hallazgos (`path`, líneas, `severity`, `category`) con un LLM.
  Selección de ficheros y reglas por path deterministas; `--format json`.
- **rompelo** exige que la tarea no se cierre sin haber ejecutado el check y sin disposición para
  cada hallazgo. No compiten: ocr opina, rompelo concede.
- **`ocr review` devuelve 0 aunque encuentre defectos** (doc oficial, «Exit codes»). Por eso el check
  es `checks/ocr-review.py` (`~/bin/ocr-rompelo`), triestado: 0 limpio · 1 hallazgos ≥ `OCR_UMBRAL`
  (medium) · 2 no pudo mirar (sin ocr, sin ficheros, subagente caído, status ≠ complete).

## Instalación (sin npm)

```bash
gh release download vX.Y.Z --repo alibaba/open-code-review -p opencodereview-darwin-arm64 -p sha256sum.txt
shasum -a 256 -c <(grep 'opencodereview-darwin-arm64$' sha256sum.txt)   # tiene que decir OK
install -m 755 opencodereview-darwin-arm64 ~/bin/ocr
ocr config set provider anthropic
ocr config set providers.anthropic.api_key_cmd 'pass show external/anthropic/api-key | tail -n1'   # la clave es la última línea; nada en claro en disco
ocr config set model claude-sonnet-5
ocr llm test
```

`~/.opencodereview/config.json` queda 0600 y sin clave. `api_key_cmd` corre con `sh -c`: `pass` tiene
que estar en PATH y gpg-agent con la frase cargada (`preset-vault.sh`). El plugin oficial para Claude
Code NO se instala: manda `npm i -g`, arregla solo y descarta hallazgos en silencio.

## Uso en una tarea

`ocr.review` es `solo_local`: CI lo deja en SKIPPED («OK PARCIAL, contrato INCOMPLETO») y el cierre lo decide quien lo cruza fuera con `rompelo cruce -- bash tests/cruce-ocr.sh`.

```bash
rompelo init --check ocr.review ...      # o añadir "ocr.review" a checks del contrato
rompelo check                            # ejecuta ocr sobre base..HEAD (+ workspace si hay cambios)
# hallazgos → .rompelo/ocr-ultimo.json; cada uno con disposición (arreglado / refutado con motivo)
```

Codex usa el mismo binario por PATH (cruzado el 16-09 con `codex exec`: código 1, 13/13).
Reglas de la casa para todos los proyectos: `~/.opencodereview/rule.json` (Temporal, secretos,
raya de acento, `shell=True`, `rm -rf $VAR`, UPDATE sin WHERE). Por repo: `.opencodereview/rule.json`.
**Siempre `merge_system_rule: true`**: sin él la regla sustituye la lista del sistema.

## Lo medido (banco de 14 defectos plantados, 13 reales + 1 de diseño, 3 cambios limpios)

| Corrida | Reglas | Encontrados | Extras en código real | Tokens |
|---|---|---|---|---|
| 1 | sistema | 11/12 (D01 Temporal y D14 raya no son del sistema) | 2 (padding, `var(--brand)`) | 342k |
| 2, 3, 6, 7 (Codex) | casa | **13/13** | 1 (`estado` sin defecto en Astro) | 260–335k |
| 4 | casa | 9/13 (faltan Temporal, await, CORS, timing) | 0 | 235k |
| 5 | casa | 11/13 (faltan Temporal, await) | 3 sobre `.rompelo/` y `rule.json` (corregido: el envoltorio los excluye) | 358k |

Recall medio con reglas 72/78 = 92 %, mínimo 69 %: **el mismo diff da distinto resultado cada vez**.
Cambio limpio: 0 hallazgos, 40k tokens (el coste fijo por corrida). 40 ficheros con 3 defectos en
posiciones 5/22/39, `--effort low`: 3/3, 0 falsos positivos, 35 s, 122k tokens.
Coste estimado por corrida del banco a tarifas de Sonnet 5 (2/10 $ por millón, caché 0,2/2,5):
0,4–0,5 $. Control positivo (`checks/ocr-control-positivo.py`, inyección SQL, effort low): 11 s.

## Esfuerzo, presupuesto y tope (16-09-2026)

- `OCR_EFFORT=auto|low|medium|high` (auto: `low` hasta `OCR_LINEAS_LOW=150` líneas cambiadas, `medium` por encima). Un
  `--effort` pasado a mano al envoltorio manda.
- `OCR_PRESUPUESTO_TOKENS` (600000; 0 = sin tope) → `--max-tokens-budget`. Si ocr lo agota deja ficheros en `warnings` y
  el envoltorio devuelve 2 (cobertura incompleta), nunca 0.
- `OCR_MAX_LINEAS` (1500; 0 = sin tope): por encima el envoltorio sale con 2 sin llamar a ocr.
- `rompelo revisar` usa `ocr delegate rule` (sin LLM, 0 $) para poner las reglas por fichero en el manifiesto de la
  segunda pasada; no sustituye a `ocr.review`, que es el par de ojos independiente.

## Límites

- Tope de tamaño: `OCR_MAX_LINEAS` (1500 por defecto, `0` = sin tope) líneas añadidas+borradas por
  pasada; por encima el envoltorio sale con 2 **antes** de llamar a ocr. Motivo medido el 16-09-2026: un
  `verify --ci` en local con `ocr.review` en el contrato revisó en modo workspace 1 800 líneas que otro
  agente había dejado en el árbol (45 llamadas, 1,3 M tokens, ~1,8 $) sin que nadie lo pidiera. Dos
  lecciones más de ese día: `solo_local` en `ocr.review` para que `verify --ci` no lo repita, y un solo
  agente por árbol de trabajo (el otro, en un worktree).

- Recall no determinista: es un par de ojos más, no la prueba. Los checks de tests y el cruce de junta
  siguen siendo obligatorios.
- Tests excluidos por defecto (`**/*.test.ts`, `*_test.go`…): `include` en `rule.json` si se quieren.
- Ficheros ignorados por git no entran (`.env` no viaja); `.txt`/`.md` tampoco (extensión no soportada).
- El código viaja al proveedor configurado. Con Anthropic es el mismo destino que Claude Code.
- NO VERIFICADO: benchmark AACR y badge OpenSSF Gold del README; voz humana de José sobre las reglas.
