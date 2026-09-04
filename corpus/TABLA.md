# Corpus de fallos reales · tabla generada

Generado desde `incidents/` (30 incidentes). No editar a mano: `python3 bin/rompelo-corpus.py`.

## Lo que decide

Clases: **S** señal disponible al Stop · **T** en el momento de la herramienta (PreToolUse) · **C** contexto o ámbito · **A** auditoría/adjudicación · **R** runtime, después de desplegar · **I** instrumento: la comprobación no podía fallar · **M** mixto.

| Pregunta | Recuento |
|---|---|
| Reparto por clase | **A**: 2 · **C**: 4 · **I**: 10 · **M**: 3 · **R**: 2 · **S**: 6 · **T**: 3 (de 30) |
| recall del Stop gate sobre la clase S | **5 de 6** |
| Cobertura del Stop gate sobre TODOS (no es la métrica, se deja por honestidad) | sí: 8 · parcial: 5 · no: 17 |
| ¿Cuántos tienen ya un control hoy? | sí: 11 · parcial: 7 · **no: 12** |

## Por tipo de gate que lo habría cazado

| Gate | Incidentes | Existe hoy |
|---|---|---|
| `instrumento-control-positivo` | 12 (0006, 0013, 0016, 0017, 0018, 0019, 0020, 0022, 0023, 0025, 0029, 0030) | no, parcial, sí |
| `deriva-generada` | 4 (0002, 0003, 0012, 0026) | parcial, sí |
| `pretooluse-destructivo` | 3 (0001, 0007, 0008) | no, sí |
| `stop-junta` | 3 (0004, 0014, 0027) | no, parcial |
| `stop-checks` | 3 (0005, 0021, 0028) | parcial, sí |
| `stop-prueba-toca-diff` | 2 (0011, 0024) | no |
| `stop-hallazgos` | 1 (0009) | no |
| `alerta-operacional` | 1 (0010) | sí |
| `ledger-auditoria` | 1 (0015) | no |

## Los incidentes

| Id | Fecha | Clase | Señal disponible al Stop | Gate | Existe hoy | Spike |
|---|---|---|---|---|---|---|
| 0001 | 2026-08-13 | T | ninguna al Stop: el secreto ya estaba impreso al ejecutar el comando | `pretooluse-destructivo` | sí | no |
| 0002 | 2026-08-13 | M | solo si un check compara lo desplegado con origin/main (no existía); la prueba unitaria daba verde | `deriva-generada` | sí | parcial |
| 0003 | 2026-08-13 | C | ninguna: el error vive en documentos leídos como verdad | `deriva-generada` | parcial | no |
| 0004 | 2026-08-31 | S | una petición real al endpoint desplegado devolvía 403 desde el primer día | `stop-junta` | parcial | sí |
| 0005 | 2026-09-04 | S | abrir la página en un navegador lanzaba el ReferenceError | `stop-checks` | parcial | sí |
| 0006 | 2026-08-31 | M | un control positivo del vigilante (VENTANA=1) lo habría delatado al escribirlo | `instrumento-control-positivo` | sí | parcial |
| 0007 | 2026-08-31 | T | ninguna al Stop: el borrado ocurre al ejecutar el comando | `pretooluse-destructivo` | no | no |
| 0008 | 2026-08-24 | T | ninguna al Stop: la escritura ocurre al ejecutar el comando | `pretooluse-destructivo` | no | no |
| 0009 | 2026-08-27 | A | el hallazgo existía por escrito desde el 22-08 sin disposición | `stop-hallazgos` | no | sí |
| 0010 | 2026-08-27 | R | ninguna al Stop: los fallos ocurren días después en producción | `alerta-operacional` | sí | no |
| 0011 | 2026-09-03 | S | el diff añadía código y ningún fichero de prueba cambiaba | `stop-prueba-toca-diff` | no | sí |
| 0012 | 2026-09-03 | C | ninguna medible en el árbol: la afirmación era sobre otro ámbito (el despliegue) | `deriva-generada` | parcial | no |
| 0013 | 2026-08-14 | C | ninguna: búsqueda en un ámbito y afirmación sobre otro | `instrumento-control-positivo` | parcial | no |
| 0014 | 2026-08-27 | R | el ciclo de verificación pasó; el token caducó 15 minutos después | `stop-junta` | no | no |
| 0015 | 2026-09-03 | A | mismo commit, dos conclusiones; sin ledger no hay señal comparable | `ledger-auditoria` | no | parcial |
| 0016 | 2026-09-04 | I | sí: el validador rechazaba código correcto, bastaba un control positivo | `instrumento-control-positivo` | no | no |
| 0017 | 2026-09-04 | I | sí: stderr no vacío junto a un código de hallazgo | `instrumento-control-positivo` | parcial | no |
| 0018 | 2026-09-04 | I | sí: salida vacía en una orden que siempre imprime | `instrumento-control-positivo` | sí | sí |
| 0019 | 2026-09-04 | I | sí: 0 pruebas ejecutadas | `instrumento-control-positivo` | sí | sí |
| 0020 | 2026-09-04 | I | sí: el mensaje decía timed out | `instrumento-control-positivo` | no | no |
| 0021 | 2026-09-04 | S | sí: el patrón es grepeable | `stop-checks` | sí | sí |
| 0022 | 2026-09-04 | I | sí: hash igual antes y después | `instrumento-control-positivo` | sí | no |
| 0023 | 2026-09-04 | I | sí: el patrón que se busca no casaba con el mutante | `instrumento-control-positivo` | no | no |
| 0024 | 2026-09-04 | S | sí: el diff toca ficheros de prueba | `stop-prueba-toca-diff` | no | parcial |
| 0025 | 2026-09-04 | I | sí: la entidad estaba en el fichero | `instrumento-control-positivo` | no | no |
| 0026 | 2026-09-04 | C | no: la señal es la ausencia de un check | `deriva-generada` | parcial | no |
| 0027 | 2026-09-04 | M | no del todo: la señal está en el sistema, no en el árbol | `stop-junta` | no | parcial |
| 0028 | 2026-09-04 | S | sí: ShellCheck instalado y no ejecutado | `stop-checks` | sí | sí |
| 0029 | 2026-09-05 | I | sí: el propio hook bloqueó con «cambios posteriores al cierre» sobre un árbol limpio | `instrumento-control-positivo` | sí | no |
| 0030 | 2026-09-05 | I | sí: el contrato y la evidencia de cierre no coincidían y nadie lo comparaba | `instrumento-control-positivo` | sí | no |

## Títulos

- **0001** · Tres credenciales impresas en el chat al trazar un guion con bash -x (`~/ClaveON_B2C/docs/incidente-2026-08-13-fuga-credenciales.md`)
- **0002** · El guion de copias versionado no era el desplegado, y su test llevaba meses en verde (`~/ClaveON_B2C/docs/PROBLEMAS.md#A7`)
- **0003** · Seis documentos canónicos decían cosas falsas y cada error de método del día salió de fiarse de uno (`~/ClaveON_B2C/docs/PROBLEMAS.md#A8 y`)
- **0004** · Newsletter desplegado cinco días sin dar de alta a nadie, doce altas rechazadas con 403 (`memoria feedback_el_fallo_vive_en_la_junta; PROBLEMAS.md N82`)
- **0005** · La página del QR rota con 964 pruebas en verde, build y astro check limpios (`memoria feedback_probar_ejecutando_no_leyendo`)
- **0006** · El reconciliador de leads gritaba en falso cada lunes y mandaba a mirar un DLQ vacío (`memoria project_claveon_reconciliador_falso_positivo`)
- **0007** · git stash -u con pathspec dijo «No local changes to save» y borró ficheros sin rastrear (`memoria feedback_git_stash_u_pathspec_borra`)
- **0008** · 47 filas de producción modificadas al probar un backfill «dentro de una transacción» mal atada (`memoria feedback_nunca_probar_escrituras_contra_produccion`)
- **0009** · El fallback del switch enviaba lo que no entendía a «descartado»; visto el 22-08, archivado sin responder, mordió el 27-08 (`~/ClaveON_B2C/docs/PROBLEMAS-RESUELTOS.md#N66; ERRORLOG P16`)
- **0010** · Catorce ejecuciones fallidas del asistente en catorce días y ningún aviso a nadie (`~/ClaveON_B2C/docs/PROBLEMAS-RESUELTOS.md#N41`)
- **0011** · Cierre automático de lead entregado con 575 pruebas en verde y ninguna tocaba la línea nueva (`memoria feedback_medir_antes_de_afirmar (caso 3)`)
- **0012** · «Estos commits salen sobre main sin depender del rediseño»: cierto para el código, falso para el despliegue (`memoria feedback_medir_antes_de_afirmar (caso 4)`)
- **0013** · «No existe copia de la clave GPG», medido solo en este Mac; había una en un disco externo desde hacía 42 días (`memoria feedback_medir_y_afirmar_mismo_ambito; PROBLEMAS.md C3`)
- **0014** · Cambio de servidor MCP de Zoho: URL cambiada en tres nodos y la credencial seguía apuntando al viejo; la reconexión duró quince minutos (`~/ClaveON_B2C/docs/PROBLEMAS-RESUELTOS.md#N72`)
- **0015** · La auditoría del 02-09 dio por revisadas las páginas de barrio; al día siguiente, sobre el mismo commit, compartían el 58 % del texto (`memoria feedback_medir_antes_de_afirmar (regla 6)`)
- **0016** · node -c validaba código de un nodo n8n que el runtime envuelve en una función: fallaba con código bueno y pasaba código malo (`relato de la sesión rootml-de (backend ClaveON), mensaje entre sesiones del 04-09-2026; no reproducido aquí`)
- **0017** · un guardián de tres estados (0 coinciden, 1 no, 2 no pude mirar) murió por una variable sin definir y salió con 1: «producción se ha separado del repo» cuando no llegó a mirar (`relato de la sesión rootml-de (backend ClaveON), mensaje entre sesiones del 04-09-2026; no reproducido aquí`)
- **0018** · pnpm audit salió con 0 tras un TimeoutError: nunca llegó al registro; un wc -l da 0 porque la orden falló (`relato de la sesión rootml-de (backend ClaveON), mensaje entre sesiones del 04-09-2026; no reproducido aquí`)
- **0019** · vitest dijo «no tests» con el fichero roto de sintaxis y se leyó como 0 fallos (`relato de la sesión rootml-de (backend ClaveON), mensaje entre sesiones del 04-09-2026; no reproducido aquí`)
- **0020** · una prueba que lanza 54 procesos tardaba 3 s sola y agotaba el plazo de 5 s bajo carga, saliendo como fallo con mensaje «timed out» que en el listado se ve igual que un rojo real (`relato de la sesión rootml-de (backend ClaveON), mensaje entre sesiones del 04-09-2026; no reproducido aquí`)
- **0021** · variable pegada a carácter multibyte («$nombre») bajo set -u; arreglada tres veces en el mismo día, la tercera dentro de la biblioteca escrita para evitarlo. La misma sesión rompelo cayó en el mismo fallo con «$CMD» (`relato de la sesión rootml-de (backend ClaveON), mensaje entre sesiones del 04-09-2026; no reproducido aquí`)
- **0022** · la mutación no se aplicó: el replace no casó, el fichero quedó intacto, la prueba siguió verde y se iba a anotar «la prueba lo caza». Dos veces. También en rompelo hoy (sed sobre - true que el YAML guardaba entrecomillado) (`relato de la sesión rootml-de (backend ClaveON), mensaje entre sesiones del 04-09-2026; no reproducido aquí`)
- **0023** · la mutación se aplicó pero no creó el fallo: se escribió $VAR días con espacio para probar «variable pegada»; el fichero cambió, la prueba pasó y se concluyó «mi prueba es floja» (`relato de la sesión rootml-de (backend ClaveON), mensaje entre sesiones del 04-09-2026; no reproducido aquí`)
- **0024** · un refactor de rendimiento de una prueba es donde deja de mirar sin que nadie lo note; se volvieron a aplicar las mutaciones y seguían cazándose (`relato de la sesión rootml-de (backend ClaveON), mensaje entre sesiones del 04-09-2026; no reproducido aquí`)
- **0025** · el patrón buscaba el guion largo como carácter (—) y el escrito como entidad (&mdash;) sobrevivió (`relato de la sesión rootml-de (backend ClaveON), mensaje entre sesiones del 04-09-2026; no reproducido aquí`)
- **0026** · cinco de los fallos del día estaban escritos en las reglas del proyecto antes de empezar; escribir la regla no es aplicarla (`relato de la sesión rootml-de (backend ClaveON), mensaje entre sesiones del 04-09-2026; no reproducido aquí`)
- **0027** · se retiró el nodo que mandaba un SMS; el canon seguía diciendo que ese aviso sale por SMS, el workflow preparaba el texto y su guardián seguía en verde confirmando que los dos textos coincidían. Un guardián impecable vigilando algo que ya no ocurre (`relato de la sesión rootml-de (backend ClaveON), mensaje entre sesiones del 04-09-2026; no reproducido aquí`)
- **0028** · se copió la convención de otro guardián del repo y se propagó su fallo con confianza; ShellCheck estaba instalado y no se había pasado (`relato de la sesión rootml-de (backend ClaveON), mensaje entre sesiones del 04-09-2026; no reproducido aquí`)
- **0029** · La huella de rompelo cambiaba al commitear un fichero nuevo con el mismo contenido: el gate reabría la tarea sin que nada hubiera cambiado (`propio; bloqueo en vivo del hook Stop de rompelo en ~/rompelo, commit c77ffcf`)
- **0030** · Una tarea cerrada aceptaba un check obligatorio nuevo sin ejecutarlo: el contrato no formaba parte de la huella de cierre (`hallazgo de Codex al revisar rompelo (bin/rompelo:217), reproducido aquí con un caso en la batería`)
