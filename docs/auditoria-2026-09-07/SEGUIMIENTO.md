# Seguimiento de la auditoría del 07-09-2026

Snapshot auditado: `86001d2`. Contraste contra el binario real (07-09, sesión Claude Code): `repro-2026-09-07.py`
y `repro2-2026-09-07.py` en esta carpeta, ejecutados sobre `af6ee5e` (mismo código que el snapshot).
Resultado: 17 comprobaciones ejecutadas, 17 reproducidas; cubren RMP-001 (a, a', b, c, d, e), 002 (2),
003 (a, b), 004, 005, 007, 008, 009, 010 (2), 011, 013, 014, 015; RMP-016 confirmado por API
(`main` `protected: false`, 0 rulesets). No reproducidos entonces: 006, 012, 017, 018, 019.

Baterías de partida sobre `8c8c6e9` (07-09): `rompelo.tests` 113/113 · `rompelo.observe-tests` 75/75.
Son cifras históricas; cada lote anota las suyas.

Rama de trabajo: `mejoras-auditoria-2026-09-07` en el worktree `~/rompelo-dev`. `~/rompelo` (el binario que
ejecutan los hooks activos de todas las sesiones) no se toca hasta que José decida.

## Tabla por hallazgo

Formato: estado previo → prueba roja → cambio → prueba verde → regresiones → limitaciones → revisión.

| ID | Estado previo | Prueba roja | Cambio | Prueba verde | Regresiones | Limitaciones | Revisión |
|---|---|---|---|---|---|---|---|
| RMP-004 | `espera_paso` aceptaba stdout vacío sin mirar código ni stderr; helpers del observador tiraban `returncode`; `observe-test` ejecutaba `~/rompelo/bin/rompelo` a mano (el binario en producción, no el del árbol probado) | `repro-2026-09-07.py`: hook falso con rc=1 y traceback → `PASS=1 FAIL=0` | `tests/lib.sh` + `tests/invocar.py`: toda invocación pasa por un runner con plazo que exige rc 0 y stderr vacío y mete marca ⟦INSTRUMENTO ROTO⟧ en la salida; `espera_bloqueo` parsea la salida ENTERA como JSON; binario por defecto = el que está junto a los tests; `resumen` devuelve 1 si hubo roturas aunque nadie mirase la salida; `control-positivo.py` exige `ROTOS=0` | `tests/instrumento-test.sh`: 26/26 (muerto, ausente, sin +x, JSON truncado, contaminado, rc 1 con JSON bueno, stderr con JSON bueno, sin respuesta en 2 s, stdin perdido; y el control negativo: silencio sano y bloqueo sano pasan) | `rompelo.tests` 113/113 ROTOS=0 · `observe-tests` 75/75 ROTOS=0 · `control-positivo.py gate` → 1 (112/1, solo el fallo de scope) | El primer runner usaba un heredoc y perdía el stdin: lo cazó el control con un falso que devuelve lo que recibe, no la revisión. Queda documentado en `invocar.py` | pendiente |
| RMP-001 | `ficheros_cambiados` partía la salida humana de `git diff --name-only` por líneas; `año.py` llegaba como `"a\303\261o.py"`, `huella_arbol` no lo encontraba y lo firmaba como `D`; el modo y el destino del enlace no entraban en la huella; en un repo sin HEAD lo preparado no contaba | `repro2-2026-09-07.py` (5/5) y la sección «huella» de `rompelo-stop-test.sh`: 16 ❌ antes del cambio | `-z --no-renames` + `surrogateescape`; `sujeto()` = D · F:/X:<sha256> · L:<sha del destino> · S:<commit> · T:dir; huella `v2:<16 hex>`; evidencia sin `v2:` = «formato antiguo, vuelve a ejecutar»; repo sin commits = árbol vacío; `git_ok` levanta `GitError` (fail-closed en el hook) | 138/138: Unicode, tab, espacio, dos modificaciones seguidas, +x en limpio y sobre modificado, symlink t2→t3, renombrado (D+A), commit del mismo contenido en silencio, `año.py` dentro de `src/*.py`, git con índice ilegible → bloqueo | observe 75/75 · instrumento 26/26 · mutante de scope → 1 (137/1) · `repro-2026-09-07.py`: 001a-d y 002 pasan a NO reproducido | Ficheros ignorados por `.gitignore` no cuentan (documentado). Un submódulo se firma por su commit, no por su contenido. Renombrado = borrado + alta, no se conserva el vínculo | pendiente |
| RMP-002 | `ref_base` devolvía `HEAD` si la base no existía; la CI propia hacía checkout superficial | `repro-2026-09-07.py` RMP-002/002b; batería h16 | base explícita ausente → `ValueError` con instrucción (fetch o corregir); `sin-head` = árbol vacío explícito; `ci.yml` con `fetch-depth: 0` | h16 en verde: bloqueo «no existe en este repo» | idem | El rango de PR frente a la base de tarea sigue siendo la base del contrato: CI juzga lo que el contrato dice, no lo que GitHub calcula. NO VERIFICADO en Actions hasta el push | pendiente |
| RMP-015 (mínimo) | borrar el único test satisfacía `exige_prueba_en_diff` | h23 rojo | una ruta con `sujeto == "D"` no cuenta como prueba en el diff | h23/h24 verdes | idem | No vincula el requisito al test ejecutado (eso es bloque F) | pendiente |
