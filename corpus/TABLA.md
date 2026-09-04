# Corpus de fallos reales · tabla generada

Generado desde `incidents/` (15 incidentes). No editar a mano: `python3 bin/assure-corpus.py`.

## Lo que decide

| Pregunta | Recuento |
|---|---|
| ¿Cuántos habría cazado el Stop gate de la Fase 1? | **sí: 5** · parcial: 1 · no: 9 de 15 |
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

| Id | Fecha | Tipo | Qué parecía verde | Gate | Existe hoy | Spike |
|---|---|---|---|---|---|---|
| 0001 | 2026-08-13 | destructivo | La regla que lo prohibía existía por escrito en env-bootstrap.md y el CLAUDE.md global describía un guardián de Bash como activo. | `pretooluse-destructivo` | sí | no |
| 0002 | 2026-08-13 | prueba-ciega | test/backup-script.test.mjs en verde durante meses. Comparaba el repositorio consigo mismo: exigía un remoto r2-claveon que no existe en el servidor. | `deriva-generada` | sí | no |
| 0003 | 2026-08-13 | contexto-perdido | 177 documentos describían el sistema. INVENTARIO.md decía que todo pasaba por Caddy; CLAUDE.md decía que dos guardianes estaban activos. Leídos, no medidos. | `deriva-generada` | parcial | no |
| 0004 | 2026-08-31 | junta | Código correcto en los dos lados, pruebas en verde, despliegue sin error, revisión sin hallazgos. El borde mandaba CRM_API_KEY y el servidor comparaba NEWSLETTER_API_KEY. | `stop-junta` | parcial | sí |
| 0005 | 2026-09-04 | prueba-ciega | pnpm build 0 errores, astro check 0 errores, 964 pruebas en verde. Todas leen el fichero fuente o el HTML servido. | `stop-checks` | parcial | sí |
| 0006 | 2026-08-31 | instrumento | El aviso semanal llegaba y parecía trabajar. Comparaba por nombre contra un campo que cada envío sobreescribe; los leads sí estaban. | `instrumento-control-positivo` | sí | no |
| 0007 | 2026-08-31 | destructivo | Mensaje de «no hice nada» y ningún stash creado. Pérdida de datos disfrazada de no-op. | `pretooluse-destructivo` | no | no |
| 0008 | 2026-08-24 | destructivo | Los datos resultantes eran correctos por casualidad. psql confirmó cada UPDATE porque iban antes del begin, no dentro. | `pretooluse-destructivo` | no | no |
| 0009 | 2026-08-27 | contexto-perdido | La auditoría del 22-08 lo anotó como aviso de tipado y el plan lo cerró con «ya señalado, no ampliado hoy». Nadie preguntó a dónde apuntaba el 2. | `stop-hallazgos` | no | sí |
| 0010 | 2026-08-27 | silencio-operacional | Los workflows estaban activos y el panel no mostraba nada rojo salvo leyendo la API a mano ejecución por ejecución. | `alerta-operacional` | sí | no |
| 0011 | 2026-09-03 | prueba-ciega | «Tests en verde» era cierto. Ninguno ejercitaba el código añadido. | `stop-prueba-toca-diff` | no | sí |
| 0012 | 2026-09-03 | ambito | git diff limpio entre las ramas. Publicar desde ahí habría borrado el rediseño entero, porque producción no sigue a main. | `deriva-generada` | parcial | no |
| 0013 | 2026-08-14 | resultado-nulo | Una búsqueda vacía leída como negativo. C3 quedó mal enunciado dos días. | `instrumento-control-positivo` | parcial | no |
| 0014 | 2026-08-27 | junta | Ciclo 2583 en verde, borrador creado, dado por cerrado. Desde las 19:15 todos los ciclos fallaban con INVALID_TOKEN. | `stop-junta` | no | sí |
| 0015 | 2026-09-03 | contexto-perdido | Auditoría cerrada con las páginas marcadas como revisadas. Misma entrada, distinta conclusión un día después. | `ledger-auditoria` | no | parcial |

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
