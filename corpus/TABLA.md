# Corpus de fallos reales · tabla generada

Generado desde `incidents/` (15 incidentes). No editar a mano: `python3 bin/assure-corpus.py`.

## Lo que decide

Clases: **S** señal disponible al Stop · **T** en el momento de la herramienta (PreToolUse) · **C** contexto o ámbito · **A** auditoría/adjudicación · **R** runtime, después de desplegar · **M** mixto.

| Pregunta | Recuento |
|---|---|
| Reparto por clase | **A**: 2 · **C**: 3 · **M**: 2 · **R**: 2 · **S**: 3 · **T**: 3 (de 15) |
| recall del Stop gate sobre la clase S | **3 de 3** |
| Cobertura del Stop gate sobre TODOS (no es la métrica, se deja por honestidad) | sí: 4 · parcial: 3 · no: 8 |
| ¿Cuántos tienen ya un control hoy? | sí: 4 · parcial: 5 · **no: 6** |

## Por tipo de gate que lo habría cazado

| Gate | Incidentes | Existe hoy |
|---|---|---|
| `pretooluse-destructivo` | 3 (0001, 0007, 0008) | no, sí |
| `deriva-generada` | 3 (0002, 0003, 0012) | parcial, sí |
| `stop-junta` | 2 (0004, 0014) | no, parcial |
| `instrumento-control-positivo` | 2 (0006, 0013) | parcial, sí |
| `stop-checks` | 1 (0005) | parcial |
| `stop-hallazgos` | 1 (0009) | no |
| `alerta-operacional` | 1 (0010) | sí |
| `stop-prueba-toca-diff` | 1 (0011) | no |
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
