# Auditoría de Rómpelo

Fecha: 7 de septiembre de 2026.

Commit: `86001d25aa08703e85f1d7636b1a1336babe988e`.

## Dictamen

[INFERENCIA — confianza ALTA] Mantener Python y la CLI. No ampliar todavía a un framework multiagente, MCP o monorepo TypeScript. El valor está en los controles positivos, la evidencia y el protocolo común; los siguientes cambios deben reforzar que el guardián no confunda un error propio con un resultado favorable.

El proyecto ya tiene mecanismos útiles y pruebas deliberadamente negativas. No es solamente una colección de prompts. Sin embargo, aún hay rutas que admiten evidencia obsoleta, resultados globales ambiguos de CI y estados que pueden degradarse silenciosamente. No debe ser la única autoridad para aprobar merge o despliegue hasta corregir esas rutas.

## Alcance probado y no probado

Se leyó el núcleo y sus flujos de contrato, Git, ejecución, evidencia, cierre, observación y permisos; adaptadores de Claude/Codex/CI; configuración, pruebas y documentación relevantes. Se inspeccionó la ejecución de GitHub Actions correspondiente al commit. Se ejecutaron pruebas focalizadas de funciones extraídas en repositorios temporales.

**No se obtuvo una copia completa descargada del repositorio en el contenedor. No se ejecutaron aquí las baterías originales completas ni los clientes reales de Claude Code/Codex.** Los resultados de 113/113 y 75/75 son del job remoto leído. Las pruebas focalizadas no equivalen a una integración end-to-end del cliente. La revisión no certifica cada archivo auxiliar ni que no existan otros fallos.

No se modificó el repositorio remoto ni configuración del Mac. El canario de privacidad es ficticio. No se inspeccionaron secretos del usuario.

## Qué conservar

El positivo del gate muta una copia y exige exactamente el fallo esperado de scope, no cualquier excepción. El positivo del analizador crea el caso malo y comprueba su contenido. El runner conserva la distinción entre instrumento ciego, instrumento incapaz de inspeccionar y hallazgo del objetivo cuando esos estados llegan correctamente. La documentación reconoce límites como evidencia editable, controles todavía ausentes y diferencia entre invocar el adaptador y observar que el cliente lo invocó. Estas decisiones deben preservarse.

Fuentes: `tests/control-positivo.py`, `docs/control-positivo.md`, `checks/registry.json`.

## Cómo leer las prioridades

P1: corregir antes de usarlo como autoridad única o recomendar adopción externa amplia. P2: robustez/semántica que debe resolverse en la siguiente iteración. P3: portabilidad/mantenibilidad. No son puntuaciones CVSS.

REPRODUCIDO_FUNCION significa ejecución focalizada de un extracto; CONFIRMADO_CODIGO no implica haber ejecutado la integración; PENDIENTE_RUNTIME no se cuenta como bug confirmado. El registro diferencia hechos de propuestas y conserva IDs para futuras revisiones.

## Registro de hallazgos

| ID | Prioridad | Evidencia | Asunto |
|---|---|---|---|
| RMP-001 | P1 | REPRODUCIDO_FUNCION | La huella no identifica de forma suficiente el estado inspeccionado |
| RMP-002 | P1 | REPRODUCIDO_FUNCION | Una base inexistente se sustituye por HEAD silenciosamente |
| RMP-003 | P1 | REPRODUCIDO_FUNCION | Errores de configuración y estado pueden desactivar la garantía |
| RMP-004 | P1 | REPRODUCIDO_ASERCION | Una aserción de paso acepta un hook averiado |
| RMP-005 | P1 | REPRODUCIDO_FUNCION | La plantilla CI no carga el registro del consumidor como promete |
| RMP-006 | P1 | OBSERVADO_CI_Y_CODIGO | El resultado global de CI puede ser OK con obligaciones sin comprobar |
| RMP-007 | P1 | REPRODUCIDO_FUNCION | La evidencia puede persistir secretos presentes en argv |
| RMP-008 | P2 | CONFIRMADO_CODIGO_MAS_PRUEBA_DE_HASH | close y verify pueden juzgar contratos distintos |
| RMP-009 | P2 | REPRODUCIDO_FUNCION | Registrar no después de sí no revoca la elevación |
| RMP-010 | P2 | REPRODUCIDO_FUNCION_Y_REVISION | El runner carece de límites y salida binaria rompe la evaluación |
| RMP-011 | P2 | CONFIRMADO_CODIGO_Y_PROTOCOLO | El observador responde PostToolUse a eventos PostToolUseFailure |
| RMP-012 | P2 | CONFIRMADO_CODIGO | Disposición escrita y segunda pasada no constituyen adjudicación |
| RMP-013 | P2 | CONFIRMADO_CODIGO_FRENTE_A_DISENO | Historia entre sesiones y retención no coinciden con lo descrito |
| RMP-014 | P2 | CONFIRMADO_CODIGO | checks vacío impide ejecutar checks_nivel3 aunque se exijan |
| RMP-015 | P2 | CONFIRMADO_CODIGO | Eliminar una prueba satisface prueba presente en diff |
| RMP-016 | P2 | CONFIRMADO_CONFIGURACION | CI no está aún consolidada como autoridad de merge reproducible |
| RMP-017 | P2 | CONFIRMADO_CODIGO | El recall del corpus es una anotación, no una medida ejecutada |
| RMP-018 | P3 | PROPUESTA | Portabilidad: separar núcleo, instalación, configuración y datos |
| RMP-019 | P2 | PENDIENTE_RUNTIME | Verificar edición nativa apply_patch de Codex |

### RMP-001 — La huella no identifica de forma suficiente el estado inspeccionado

**P1 · REPRODUCIDO_FUNCION · confianza ALTA**

**Dónde:** `bin/rompelo :: ficheros_cambiados, huella_arbol`

**Evidencia:** En las funciones extraídas, año.py, nombres con tabulador/salto de línea, cambios de ejecutabilidad, cambio de destino de symlink con bytes iguales y archivo staged en repo sin HEAD conservan la huella pese a cambiar el sujeto. ASCII normal cambia la huella: control positivo.

**Impacto:** Una comprobación anterior puede seguir pareciendo vigente; también puede clasificarse mal el scope. No es una colisión criptográfica de SHA: se está representando mal la entrada.

**Corrección propuesta:** Usar salidas Git delimitadas por NUL y comprobar returncode. Representar tipo, modo, contenido, destino de enlace y estado inicial sin HEAD. Especificar el tratamiento de submódulos, archivos ignorados y exclusiones. Conservar la propiedad deseada: staging/commit de idéntico contenido no debe invalidar por sí solo.

**Aceptación:** Cambiar contenido de rutas Unicode/control, tipo o modo invalida evidencia; add/commit de idéntico contenido no la invalida; repo inicial y errores Git tienen resultado explícito.

**Fuentes:** [bin/rompelo](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo)

**Resultado local:** `evidence/git-probes.json`

### RMP-002 — Una base inexistente se sustituye por HEAD silenciosamente

**P1 · REPRODUCIDO_FUNCION · confianza ALTA**

**Dónde:** `bin/rompelo :: ref_base`; `.github/workflows/ci.yml`; `.rompelo/task.json`

**Evidencia:** ref_base devuelve HEAD si cat-file no encuentra una base explícita. Dos commits limpios distintos producen la misma huella vacía con missing-ref. La CI propia hace checkout superficial; el contrato cita una base anterior distinta del HEAD auditado.

**Impacto:** La CI puede ejecutar tests pero no comprobar el diff que cree estar examinando. La pérdida del historial no debe convertirse en ausencia de cambios.

**Corrección propuesta:** Rechazar una base explícita ausente. Resolver y conservar la identidad de la base; recuperar historial o base necesaria en CI; separar la base de una tarea del rango del PR.

**Aceptación:** Clone superficial sin base: ERROR/NO_VERIFICADO, nunca comparar silenciosamente con HEAD. Con base disponible, el scope contiene todos los cambios previstos.

**Fuentes:** [bin/rompelo](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo) · [.github/workflows/ci.yml](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/.github/workflows/ci.yml) · [.rompelo/task.json](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/.rompelo/task.json)

**Resultado local:** `evidence/git-probes.json`

### RMP-003 — Errores de configuración y estado pueden desactivar la garantía

**P1 · REPRODUCIDO_FUNCION · confianza ALTA**

**Dónde:** `bin/rompelo :: repos_permitidos, cmd_hook, leer_json_o, estado_repo, guardar_estado_repo`; `adapters/claude/rompelo-stop.sh`

**Evidencia:** Un repos.json truncado lanza JSONDecodeError antes del try que convierte errores a bloqueo. En la reproducción el hook no emite JSON. Un archivo de estado truncado se transforma en {}, perdiendo nivel y perfiles. El adaptador hace exec directo.

**Impacto:** El controlador puede no bloquear cuando no pudo evaluar; perder el estado puede omitir controles reforzados. Las escrituras directas sin transacción hacen pertinente ensayar concurrencia/interrupciones; la carrera completa no se ha reproducido aquí.

**Corrección propuesta:** Distinguir ausencia inicial legítima, corrupción y fallo de E/S. Emitir un veredicto de instrumento indisponible, conservar el último estado válido y usar escritura atómica más exclusión/transacción para actualizaciones concurrentes.

**Aceptación:** Allowlist o estado truncado, permisos denegados y dos procesos concurrentes no producen un PASS ni una degradación silenciosa.

**Fuentes:** [bin/rompelo](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo) · [adapters/claude/rompelo-stop.sh](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/adapters/claude/rompelo-stop.sh)

**Resultado local:** `evidence/runtime-probes.json`

### RMP-004 — Una aserción de paso acepta un hook averiado

**P1 · REPRODUCIDO_ASERCION · confianza ALTA**

**Dónde:** `tests/rompelo-stop-test.sh :: espera_paso`; `tests/rompelo-observe-test.sh :: bash_ev, edit_ev, fail_ev`

**Evidencia:** espera_paso solo comprueba stdout vacío. Un hook de control que escribe un error en stderr y retorna 1 da PASS=1 FAIL=0. Los helpers Python del observador imprimen p.stdout sin propagar p.returncode.

**Impacto:** Parte de la batería confunde no bloquear con no haberse ejecutado correctamente. Esto no demuestra que toda la batería esté inválida; sí invalida esa aserción como prueba suficiente de paso.

**Corrección propuesta:** Comprobar returncode y esquema de salida, no solo texto o silencio; propagar errores en helpers. Añadir un control del instrumento: crash, binario ausente, timeout, JSON inválido y salida extra.

**Aceptación:** El mismo crash controlado debe fallar la aserción de paso; el gate sano sin motivos sí pasa. Un fallo de infraestructura no cuenta como mutación detectada.

**Fuentes:** [tests/rompelo-stop-test.sh](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/tests/rompelo-stop-test.sh) · [tests/rompelo-observe-test.sh](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/tests/rompelo-observe-test.sh)

**Resultado local:** `evidence/runtime-probes.json`

### RMP-005 — La plantilla CI no carga el registro del consumidor como promete

**P1 · REPRODUCIDO_FUNCION · confianza ALTA**

**Dónde:** `adapters/ci/rompelo-gate.yml`; `bin/rompelo :: registro`

**Evidencia:** La plantilla clona Rómpelo y usa ese clon como ROMPELO_HOME. El clon contiene checks/registry.json. registro solo recurre a .rompelo/registry.json cuando no existe ningún registro global. Reproducción: con global solo aparece rompelo.tests; sin global sí aparece consumer.test.

**Impacto:** El consumidor no obtiene los checks documentados; IDs propios resultan desconocidos o se usa un registro ajeno. La suite prueba HOME vacío, no la topología real de la plantilla.

**Corrección propuesta:** Separar instalación del ejecutable, directorio de estado y origen del registro. Hacer explícito el registro aprobado para CI y su precedencia; no cargar registro del repo de forma implícita en sesiones locales no confiables.

**Aceptación:** Un proyecto consumidor temporal con check exclusivo funciona ejecutando literalmente la plantilla corregida y evidencia que el check real de ese proyecto corrió.

**Fuentes:** [adapters/ci/rompelo-gate.yml](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/adapters/ci/rompelo-gate.yml) · [bin/rompelo](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo)

**Resultado local:** `evidence/runtime-probes.json`

### RMP-006 — El resultado global de CI puede ser OK con obligaciones sin comprobar

**P1 · OBSERVADO_CI_Y_CODIGO · confianza ALTA**

**Dónde:** `bin/rompelo :: cmd_verify, motivos_bloqueo, checks_exigidos`; `.github/workflows/ci.yml`

**Evidencia:** El job auditado omite dos checks solo_local y el cruce real, imprime advertencias y termina OK. --estricto bloquea junta, pero no elimina la omisión de solo_local. Los checks de nivel3 dependen de estado local ausente en un runner nuevo.

**Impacto:** Un éxito de CI no equivale a contrato íntegramente satisfecho. La omisión local está documentada; el problema es usar el mismo veredicto afirmativo y presentarlo como juez completo.

**Corrección propuesta:** Separar PASS, FAIL, ERROR, SKIPPED y WAIVED. Un check obligatorio no verificable deja contrato incompleto salvo excepción explícita autorizada. Congelar obligaciones efectivas de tarea de forma portable, no depender del estado local para reconstruirlas en CI.

**Aceptación:** Cualquier check requerido omitido deja can_close=false o una excepción trazable. El mismo contrato efectivo impone las mismas obligaciones localmente y en CI; ambas pueden diferir en capacidad pero no ocultarlo.

**Fuentes:** [bin/rompelo](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo) · [.github/workflows/ci.yml](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/.github/workflows/ci.yml)

### RMP-007 — La evidencia puede persistir secretos presentes en argv

**P1 · REPRODUCIDO_FUNCION · confianza ALTA**

**Dónde:** `bin/rompelo :: ejecutar, cmd_cruce, informe_llano, cmd_observe`

**Evidencia:** ejecutar incluye argv íntegro en el objeto de evidencia. Un canario ficticio aparece conservado. cruce imprime el comando y, si falla, salida final; el modo ROMPELO_DEBUG_FORMA añade cabeza=resp[:120] pese al comentario de solo forma.

**Impacto:** Riesgo condicionado a que argumentos o salidas contengan datos sensibles. No se identificó una credencial real expuesta en esta prueba ni se inspeccionó el vault del usuario. No almacenar stdout completo no basta para afirmar ausencia de secretos.

**Corrección propuesta:** Usar identificadores y argumentos redactados; suministrar secretos por referencias o entorno sin persistir valores; sanitizar errores y modos debug, aplicar permisos restrictivos y retención real. No presentar un hash de un secreto de baja entropía como protección suficiente.

**Aceptación:** Canarios en cabeceras, URL, argumentos, stdout, stderr y debug no aparecen en evidencia, informes ni logs persistidos.

**Fuentes:** [bin/rompelo](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo)

**Resultado local:** `evidence/runtime-probes.json`

### RMP-008 — close y verify pueden juzgar contratos distintos

**P2 · CONFIRMADO_CODIGO_MAS_PRUEBA_DE_HASH · confianza ALTA**

**Dónde:** `bin/rompelo :: motivos_bloqueo, hash_contrato, cmd_close, informe_llano`

**Evidencia:** motivos_bloqueo crea una copia efectiva con toca_junta=True cuando lo fuerza el perfil; close firma el contrato original. La comparación focalizada produce hashes distintos sin una edición de usuario. No se ejecutó el ciclo completo de CLI aquí.

**Impacto:** Tras cerrar correctamente puede aparecer de nuevo contrato cambiado, reproduciendo una contradicción operacional. El informe también puede omitir un cruce impuesto solo por perfil.

**Corrección propuesta:** Una función común debe resolver y versionar contrato efectivo + políticas; cierre, verificador e informe consumen exactamente ese objeto.

**Aceptación:** Perfil junta con toca_junta:false: ejecutar evidencias, close y verify sin cambios debe mantenerse válido e informar el cruce exigido.

**Fuentes:** [bin/rompelo](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo)

**Resultado local:** `evidence/runtime-probes.json`

### RMP-009 — Registrar no después de sí no revoca la elevación

**P2 · REPRODUCIDO_FUNCION · confianza ALTA**

**Dónde:** `bin/rompelo :: cmd_permiso, checks_exigidos`; `docs/observacion.md :: permisos`

**Evidencia:** permiso security si seguido de permiso security no deja nivel3 y permiso previo. recordar se persiste, pero no define por sí solo una caducidad de tarea; todos los checks_nivel3 se exigen por nivel global del repo.

**Impacto:** Ambigüedad de consentimiento y alcance, especialmente con herramientas externas de coste. El proyecto reconoce que el agente registra el permiso: no se presenta aquí como control de identidad resistente a engaño.

**Corrección propuesta:** Separar nivel de rigor de autorizaciones efectivas. Autorizar por acción/check, tarea, perfil y vigencia; última decisión negativa revoca el permiso correspondiente. Hacer explícita la semántica de recordar.

**Aceptación:** Sí→no revoca; sí sin recordar no se traslada a otra tarea; permiso de A no habilita B.

**Fuentes:** [bin/rompelo](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo) · [docs/observacion.md](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/docs/observacion.md)

**Resultado local:** `evidence/runtime-probes.json`

### RMP-010 — El runner carece de límites y salida binaria rompe la evaluación

**P2 · REPRODUCIDO_FUNCION_Y_REVISION · confianza ALTA**

**Dónde:** `bin/rompelo :: ejecutar`; `docs/control-positivo.md`

**Evidencia:** subprocess.run no recibe timeout y captura salida completa en memoria. Un proceso inocuo que emite byte 0xff produce UnicodeDecodeError no capturado. La documentación ya reconoce ausencia de control específico del runner con timeout.

**Impacto:** Una herramienta colgada, verbosa o con salida no UTF-8 puede impedir completar el gate. No se hicieron pruebas de agotamiento de memoria ni se dejó un proceso infinito.

**Corrección propuesta:** Plazo por check, cancelación de grupo de procesos, captura en bytes y decodificación explícita, límite de salida/recursos y resultado ERROR diferenciado.

**Aceptación:** Proceso dormido, hijo persistente, salida excesiva y bytes inválidos terminan de forma acotada y nunca se confunden con hallazgo del objetivo.

**Fuentes:** [bin/rompelo](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo) · [docs/control-positivo.md](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/docs/control-positivo.md)

**Resultado local:** `evidence/runtime-probes.json`

### RMP-011 — El observador responde PostToolUse a eventos PostToolUseFailure

**P2 · CONFIRMADO_CODIGO_Y_PROTOCOLO · confianza ALTA**

**Dónde:** `bin/rompelo :: cmd_observe`; `adapters/claude/settings-fragment.json`; `adapters/claude/rompelo-observe.sh`

**Evidencia:** El mismo adaptador recibe ambos eventos; la salida fija hookEventName="PostToolUse". La documentación oficial de Claude muestra PostToolUseFailure en la respuesta de fallo. No se ejecutó aquí el cliente real para medir la consecuencia de ese desajuste.

**Impacto:** El aviso al agente tras un fallo no cumple el contrato documentado y puede perderse o tratarse como error, aunque el estado local ya se haya actualizado.

**Corrección propuesta:** Validar el evento de entrada y emitir el evento correcto; pruebas de esquema específicas de cada agente y payloads reales sanitizados.

**Aceptación:** Un segundo PostToolUseFailure produce salida con hookEventName=PostToolUseFailure aceptada por un cliente real de versión registrada.

**Fuentes:** [bin/rompelo](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo) · [adapters/claude/settings-fragment.json](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/adapters/claude/settings-fragment.json) · [adapters/claude/rompelo-observe.sh](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/adapters/claude/rompelo-observe.sh)

### RMP-012 — Disposición escrita y segunda pasada no constituyen adjudicación

**P2 · CONFIRMADO_CODIGO · confianza ALTA**

**Dónde:** `bin/rompelo :: motivos_bloqueo, leer_contrato, informe_llano`

**Evidencia:** Un hallazgo supera el control si disposicion es cualquier cadena no vacía. segunda_pasada y las fuentes de afirmaciones se comprueban como campos, no como pruebas. El flujo es estructural: no existe una verificación semántica automática de la fuente.

**Impacto:** Escribir pendiente puede eliminar el bloqueo sin resolver el hallazgo. Los contadores o prosa de revisión no estabilizan auditorías. No es un fallo por permitir que un agente deshonesto edite archivos: incluso un estado razonable puede interpretarse mal.

**Corrección propuesta:** Enums validados, severidad/bloqueante, estados y transiciones; rechazado requiere motivo; corregido requiere regresión; aceptado requiere excepción. Mantener ID estable y evidencia asociada. Etiquetar afirmación como declarada, no verificada por máquina, cuando corresponda.

**Aceptación:** Estado desconocido o pendiente no desbloquea; una segunda auditoría actualiza el mismo ID y conserva motivos, pruebas y retractaciones.

**Fuentes:** [bin/rompelo](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo)

### RMP-013 — Historia entre sesiones y retención no coinciden con lo descrito

**P2 · CONFIRMADO_CODIGO_FRENTE_A_DISENO · confianza ALTA**

**Dónde:** `bin/rompelo :: cmd_observe, main`; `docs/observacion.md :: secciones 2, 4`

**Evidencia:** El diseño habla de últimas24h del repo y state prune/retención30d. cmd_observe lee únicamente el JSONL de agente-sesión actual. No existe subcomando state en main. Los niveles persistentes no equivalen a comparar errores de sesiones distintas.

**Impacto:** Un error una vez en Claude y otra en Codex puede no activar firma repetida. La retención anunciada no es una garantía ejecutable. La documentación es de diseño y necesita distinguir implementado de previsto.

**Corrección propuesta:** Agregar ventana por repo y fingerprints deduplicados con aislamiento de worktree/tarea; implementar limpieza/retención o retirar esa promesa; exportación redaccionada.

**Aceptación:** Repetición distribuida en dos sesiones dispara dentro de la ventana y no fuera. Limpieza tiene prueba con reloj controlado y no elimina evidencias aún necesarias.

**Fuentes:** [bin/rompelo](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo) · [docs/observacion.md](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/docs/observacion.md)

### RMP-014 — checks vacío impide ejecutar checks_nivel3 aunque se exijan

**P2 · CONFIRMADO_CODIGO · confianza ALTA**

**Dónde:** `bin/rompelo :: cmd_check, checks_exigidos`

**Evidencia:** cmd_check retorna0 inmediatamente si c["checks"] está vacío, antes de calcular checks_exigidos. A nivel3 estos últimos pueden contener checks_nivel3.

**Impacto:** La CLI dice que no hay checks y no ejecuta obligaciones que el gate sigue exigiendo: tarea atrapada.

**Corrección propuesta:** Calcular primero el conjunto efectivo y decidir si está vacío después.

**Aceptación:** Contrato con checks=[] y checks_nivel3=[externo] a nivel3 ejecuta externo, guarda evidencia y retorna su resultado.

**Fuentes:** [bin/rompelo](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo)

### RMP-015 — Eliminar una prueba satisface prueba presente en diff

**P2 · CONFIRMADO_CODIGO · confianza ALTA**

**Dónde:** `bin/rompelo :: motivos_bloqueo, ficheros_cambiados`

**Evidencia:** exige_prueba_en_diff considera el nombre de cualquier archivo cambiado que case con un glob; no usa estado añadido/modificado/eliminado ni comprueba test ejecutado.

**Impacto:** Borrar un test puede satisfacer el requisito de haber cambiado una prueba; no acredita protección nueva contra el fallo.

**Corrección propuesta:** Distinguir tipos de cambio y ligar aceptación/regresión a test_id ejecutado. Una baja de pruebas requiere justificación expresa.

**Aceptación:** Cambio de código + eliminación del único test no cuenta como regresión protegida; añadir una prueba que falla antes y pasa después sí.

**Fuentes:** [bin/rompelo](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo)

### RMP-016 — CI no está aún consolidada como autoridad de merge reproducible

**P2 · CONFIRMADO_CONFIGURACION · confianza ALTA**

**Dónde:** `.github/workflows/ci.yml`; `adapters/ci/rompelo-gate.yml`

**Evidencia:** Plantilla consume main de Rómpelo sin SHA fijo, actions usa tag y PyYAML se instala sin fijación en CI propia. API de main informa protected:false y consulta rulesets devolvió[] en la revisión. El token observado en el job sí era de lectura: no se afirma acceso de escritura.

**Impacto:** Un nuevo commit remoto puede cambiar el juez sin cambiar el consumidor. Tener workflow verde no impone por sí solo un control obligatorio de merge.

**Corrección propuesta:** Fijar revisiones verificadas, permisos explícitos mínimos, revisión de cambios al juez/políticas y check obligatorio con ruleset. Separar testear Rómpelo de usar una versión aprobada de Rómpelo para juzgar otro proyecto.

**Aceptación:** Mismo consumidor + misma revisión fijada reproducen el juez; un PR con gate fallido no puede integrarse por el flujo protegido normal.

**Fuentes:** [.github/workflows/ci.yml](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/.github/workflows/ci.yml) · [adapters/ci/rompelo-gate.yml](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/adapters/ci/rompelo-gate.yml)

### RMP-017 — El recall del corpus es una anotación, no una medida ejecutada

**P2 · CONFIRMADO_CODIGO · confianza ALTA**

**Dónde:** `bin/rompelo-corpus.py`; `.github/workflows/ci.yml`

**Evidencia:** El numerador se calcula contando spike_cubre==sí en YAML. El generador no reproduce incidentes ni calcula resultados de detectores. La CI genera TABLA.md, pero ese paso no comprueba que el archivo versionado no haya quedado desactualizado.

**Impacto:** La tabla es útil como cobertura prevista, pero no prueba sensibilidad real ni generalización a incidentes nuevos.

**Corrección propuesta:** Renombrar a cobertura declarada mientras no haya runner de incidentes. Añadir IDs únicos/enums, fixtures ejecutables, controles negativos, separación entre corpus de diseño y holdout, comparación de tabla regenerada.

**Aceptación:** Cada cobertura demostrada referencia ejecución roja/verde y prueba reproducible; cambiar una etiqueta YAML no mejora la métrica medida.

**Fuentes:** [bin/rompelo-corpus.py](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo-corpus.py) · [.github/workflows/ci.yml](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/.github/workflows/ci.yml)

### RMP-018 — Portabilidad: separar núcleo, instalación, configuración y datos

**P3 · PROPUESTA · confianza ALTA**

**Dónde:** `bin/rompelo`; `adapters/claude/rompelo-stop.sh`; `adapters/claude/settings-fragment.json`; `adapters/codex/hooks.json`

**Evidencia:** El núcleo, observador, runner, idiomas y CLI conviven en un archivo; adaptadores apuntan a ~/rompelo; la ruta del comando en settings-fragment de Claude no está entrecomillada como la de Codex.

**Impacto:** Dificulta pruebas unitarias, instalación en otra ruta, Windows y coexistencia de versiones/perfiles. No se ha validado Windows ni los alias del Mac del usuario.

**Corrección propuesta:** Mantener Python; extraer pocos módulos, empaquetar CLI, añadir doctor e instalación idempotente con copia y diff de configuración. Mantener adaptadores delgados y matriz de versiones/entornos. Nuevos comandos son propuestas, no capacidades existentes.

**Aceptación:** Instalación en HOME con espacios, directorio alternativo y dos proyectos con igual basename no mezclan estado ni checks; Linux/macOS y versiones de Python declaradas pasan la matriz.

**Fuentes:** [bin/rompelo](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo) · [adapters/claude/rompelo-stop.sh](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/adapters/claude/rompelo-stop.sh) · [adapters/claude/settings-fragment.json](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/adapters/claude/settings-fragment.json) · [adapters/codex/hooks.json](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/adapters/codex/hooks.json)

### RMP-019 — Verificar edición nativa apply_patch de Codex

**P2 · PENDIENTE_RUNTIME · confianza MEDIA**

**Dónde:** `bin/rompelo :: evento_desde_hook, patrones_de`; `adapters/codex/hooks.json`

**Evidencia:** El código extrae parches de cmd, pero cmd se forma solo para herramientas shell. Puede haber rutas explícitas normalizadas por el harness que eviten el problema. Falta capturar el payload real de apply_patch de la versión exacta de Codex para decidir.

**Impacto:** Posible pérdida de señales de edición/riesgo. No se presenta como fallo de integración confirmado.

**Corrección propuesta:** Capturar esquema sanitizado real para Write/Edit/apply_patch y probar normalización de rutas relativas contra el repo, con veredicto desconocido para formas no soportadas.

**Aceptación:** Fixture real de parche con varios archivos registra todos los destinos y produce las mismas señales que Edit equivalente.

**Fuentes:** [bin/rompelo](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/bin/rompelo) · [adapters/codex/hooks.json](https://github.com/bugroo/rompelo/blob/86001d25aa08703e85f1d7636b1a1336babe988e/adapters/codex/hooks.json)

## Lo que NO se ha clasificado como nueva vulnerabilidad

El tope de tres bloqueos y posterior aviso es una política documentada, probada y orientada a evitar bucles. Dejar que el agente termine el turno no debe equivaler a aprobar la tarea: conviene persistir UNVERIFIED o NEEDS_HUMAN y separar ambos resultados.

Que un agente con los mismos permisos pueda editar contrato/evidencia es un límite explícito del modelo de confianza. No se atribuye a Rómpelo una defensa contra un atacante con control total del usuario. Sí se recomienda proteger la política y la versión del verificador en CI para evitar degradaciones accidentales y revisión autocontenida.

Las limitaciones del payload textual de Codex ya están documentadas en el proyecto. La auditoría no las presenta como descubrimiento nuevo. La comprobación de apply_patch permanece pendiente hasta obtener una forma real completa del cliente y versión específicos.

## Mejoras que responden a los dos problemas originales

### Código que falla días después

El Stop gate verifica un momento. No prueba por sí mismo que una sesión se renueve, una cola sobreviva a reinicio ni un despliegue siga sano mañana. Crear perfiles concretos: expiración/refresh de token con reloj simulado, reintentos e idempotencia, reinicios, degradación de API, migración/rollback y datos antiguos. Cada perfil activa checks registrados, no instrucciones abiertas de pensar como senior.

Una evidencia de cruce debería distinguir artefacto esperado y artefacto observado, entorno, aserciones funcionales, momento y vigencia. Código0 de un comando no prueba que ese comando atravesara la junta correcta ni que consultara el despliegue actual. Preferir pruebas de la operación observable frente a un simple200 o a `true`. Estas son ampliaciones propuestas; no capacidades actuales certificadas.

### Auditorías que cambian de opinión

Crear un ledger con ID estable, commit/alcance, precondiciones, reproducer, evidencia, severidad, estado y disposición. Separar candidato, confirmado, corregido, rechazado y riesgo aceptado. Toda retractación conserva la conclusión anterior y la evidencia que motivó cambiarla. No usar votación de modelos ni una cadena libre como sustituto de adjudicación.

Un incidente se convierte en aprendizaje ejecutable cuando enlaza a un control registrado y a una reproducción mala/buena. Las anotaciones YAML por sí solas son memoria y planificación, no una medida de prevención conseguida.

## Arquitectura proporcionada

Mantener un único proyecto Python. Extraer gradualmente módulos pequeños: snapshot Git; contrato/veredicto puro; runner; persistencia; normalización de eventos; CLI. Sin once paquetes ni servidor nuevo. Mantener dependencias de ejecución pequeñas y añadir herramientas de test solo como dependencias de desarrollo.

Separar directorio de instalación, configuración global de confianza, estado local y contrato del proyecto. Agregar un `doctor` —comando propuesto— que compruebe versión, registro seleccionado, rutas, hooks cargados, capacidades observadas, binarios y causas de desconocido. Un instalador posterior debe fusionar ajustes con copia y diff; nunca sobreescribir ajustes existentes ni dar por confiado un hook sin el procedimiento del cliente.

La matriz de compatibilidad debe distinguir el mismo núcleo lógico de la integración real: Claude Stop; Claude fallo de herramienta; Codex Stop; Codex Bash; Codex parches; CLI no interactiva; HOME con espacios; worktrees; repos con igual basename; Linux/macOS. Windows no debe anunciarse hasta probarse.

## Plan de implementación y criterios de salida

**Cambio 1: instrumento y snapshot.** Corregir RMP-001 a004, runner y privacidad. Añadir las reproducciones como regresiones reales de la CLI. Deben verse fallar antes del arreglo, pasar después y seguir pasando los casos sanos anteriores.

**Cambio 2: consumidor real y veredicto global.** Corregir registro de CI, política de omitidos, base del PR y origen de obligaciones. Probar un repo consumidor desechable con su propio check. El resultado del job debe distinguir pruebas aprobadas de contrato completo.

**Cambio 3: estado y protocolización.** Contrato efectivo único, permisos revocables, escritura transaccional y eventos correctos. Probar secuencias, no solo ejemplos aislados: iniciar, elevar, ejecutar, cerrar, reabrir, revocar, interrumpir y recuperar.

**Cambio 4: problema original.** Ledger de hallazgos + controles de fallos temporales + corpus ejecutable. Medir errores escapados, falsos bloqueos y contradicciones sin evidencia sobre casos no usados para escribir las reglas.

**Cambio 5: adopción externa.** Paquete reproducible, documentación generada de capacidades reales, instalador/doctor, versiones soportadas, políticas obligatorias y distribución fijada por commit/release verificada.

No fijar porcentajes universales arbitrarios de éxito. Para los bugs reproducidos aquí, el criterio es eliminar cada contraejemplo sin perder controles sanos. Para generalización a otros proyectos, publicar tamaño del corpus, precondiciones y tasa medida con incertidumbre; no contar etiquetas YAML como recall.

## Investigación externa aplicada

- [Git: rutas y modos del diff](https://git-scm.com/docs/git-diff): Usar protocolo de rutas -z, no salida de presentación humana.
- [Claude Code: contrato de hooks](https://code.claude.com/docs/en/hooks): Eventos de fallo, salida y efecto de errores del propio hook.
- [Codex: hooks](https://learn.chatgpt.com/docs/hooks): Cobertura real de herramientas, formas de integración y límites del guard.
- [Python: subprocess](https://docs.python.org/3/library/subprocess.html): Timeout, captura y tratamiento de salida; no atribuir a un check un fallo del runner.
- [Hypothesis: stateful tests](https://hypothesis.readthedocs.io/en/latest/stateful.html): Generar secuencias y verificar invariantes, además de fixtures escritos a mano.
- [mutmut](https://mutmut.readthedocs.io/): Mutación de código Python; posible dependencia de desarrollo tras hacer importable el núcleo.
- [Stryker: estados de mutantes](https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/): Distinguir mutación detectada, superviviente, no cubierta y error del instrumento.
- [Anthropic: Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents): Juzgar el resultado en el entorno y calibrar el evaluador, no solo la narración del agente.
- [Anthropic: Infrastructure noise](https://www.anthropic.com/engineering/infrastructure-noise): Fijar y registrar infraestructura de evaluación para no atribuir variación ambiental al modelo.
- [Google SRE: Testing for reliability](https://sre.google/sre-book/testing-reliability/): Complementar tests con verificación operacional, monitorización y recuperación.
- [GitHub: Secure use](https://docs.github.com/en/actions/reference/security/secure-use): Fijación por SHA, permisos mínimos, protección de secretos y workflows.
- [GitHub: Protected branches](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches): Convertir comprobaciones en requisito del flujo de merge.
- [SLSA: Provenance](https://slsa.dev/spec/v1.2/provenance): Referencia para vincular evidencia, sujeto y productor; no se reclama conformidad SLSA.

Estas referencias justifican patrones concretos, no que instalar una librería garantice calidad. Hypothesis ayuda a explorar secuencias; mutmut, a evaluar si los tests distinguen cambios dañinos; Anthropic separa resultado real de narración y advierte del ruido ambiental; SRE extiende la evaluación a operación; GitHub convierte checks en restricciones del flujo. Ninguna sustituye un contrato suficiente ni la verificación del caso de José.

## Comprobaciones de las conclusiones

1. **¿La CI verde contradice los hallazgos?** No: demuestra que los casos existentes pasan; no que cubran los contraejemplos adicionales. La aserción de paso defectuosa se reprodujo por separado.
2. **¿Todos los hallazgos son vulnerabilidades?** No. Hay errores de lógica, brechas de integración, riesgos condicionados, carencias de método y propuestas.
3. **¿Se probó todo en Claude y Codex reales?** No. Se inspeccionó documentación y evidencia del autor; esta auditoría ejecutó funciones aisladas, no los clientes.
4. **¿Cambiar de lenguaje lo resuelve?** No se encontró evidencia de ello. Los fallos son de protocolo, representación y validación.
5. **¿La repetición de una auditoría debe borrar este registro?** No. Cada ID conserva su estado hasta que una nueva evidencia confirme, rechace o cierre el caso.

## Decisión

Continuar el proyecto, conservando Python y el núcleo pequeño. Corregir primero la fiabilidad de la evidencia y del veredicto. Ampliar después con ledger y controles operacionales específicos. Mientras tanto, usarlo como ayuda local explícitamente limitada, no como única prueba de que una tarea está terminada.
