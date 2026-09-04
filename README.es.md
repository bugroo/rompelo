# rompelo

**Tu agente de código no puede decir «hecho» hasta que una comprobación que se ha visto fallar diga que sí.**

`rompelo` es una puerta de cierre para agentes de código. Se engancha al hook `Stop` de Claude
Code y de Codex, lee un contrato pequeño de la tarea en curso y no deja terminar hasta que la
evidencia existe: checks ejecutados sobre el código actual, una petición real por el camino
desplegado cuando dos sistemas tienen que coincidir, hallazgos con decisión, afirmaciones con
fuente. Lo decide código normal, fuera del modelo. Un verde que no podía haber sido rojo no cuenta.

English documentation: [README.md](README.md).

## Cómo funciona

![Cómo funciona: el agente dice hecho, el hook Stop llama a rompelo, rompelo lee el contrato y lo compara con la evidencia; si falta algo bloquea con motivos, si todo se cumple hay silencio](docs/img/es/como-funciona.png)

## El problema del que parte

![Gráfico de barras de 28 incidentes reales por clase: instrumento ciego 8, señal al parar 6, contexto 4, mixto 3, al ejecutar la herramienta 3, auditoría 2, producción 2](docs/img/es/corpus.png)

Veintiocho incidentes reales de un mes de código escrito por agentes, cada uno anotado con lo
que parecía verde cuando el agente dijo «hecho» ([corpus/TABLA.md](corpus/TABLA.md), generado
desde [incidents/](incidents/)). La clase mayor no es «la prueba falló». Es «la comprobación no
podía fallar»: un validador sobre el artefacto equivocado, un guardián que muere y sale con el
código reservado a un hallazgo real, un `0` después de un timeout, «no tests» leído como cero
fallos, una mutación que nunca se aplicó. Un modelo cuidadoso no los caza, porque nada parece
incoherente. Solo forzar el fallo los caza.

## Lo que ve el agente

![Salida real del hook: la tarea no puede darse por terminada; dos checks sin ejecutar; junta sin cruce real](docs/img/es/bloqueo.png)

El agente recibe la lista exacta de condiciones sin cumplir y sigue trabajando. Tres bloqueos
por tarea y sesión; después `rompelo` avisa al usuario y suelta, para que nadie quede atrapado.

## Cada puerta se vio en rojo antes de fiarse de ella

![Tres pasos: verde de partida, mutación confirmada que lo pone en rojo, deshecha y verde otra vez](docs/img/es/rojo-primero.png)

La batería (63 casos, en CI en cada push) aplica este ciclo a cada condición de la propia
puerta. Cuando una mutación se usa para forzar el rojo, la prueba confirma primero que la
mutación ocurrió. Una mutación que no se aplicó no prueba nada, y ese error está dos veces en el corpus.

## Qué exige la puerta

Un repo se alista con `rompelo init`, que escribe `.rompelo/task.json` y apunta el repo en una
allowlist local. Desde entonces el agente no puede terminar una tarea hasta que:

| Condición | Cómo se cumple |
|---|---|
| cada id de check ha corrido sobre el contenido **actual** del árbol (huella del contenido, no el commit) | `rompelo check`. Los ids se resuelven en tu `checks/registry.json` (argv, sin shell). La salida no se guarda nunca: solo código, duración y hash |
| un check que sale con 0 sin la salida mínima declarada **no** es verde | `min_lineas` en el registro |
| si la tarea toca una junta con otro sistema, un cruce real **después** del último cambio | `rompelo cruce -- <comando real>` o `--id <check del registro>` |
| cada hallazgo tiene disposición | `hallazgos` en el contrato |
| cada afirmación sobre el mundo exterior tiene estado | `afirmaciones`: `verificado` exige fuente de primera mano y cita textual, `derivado` exige de qué se deduce, `no_verificado` exige qué falta |
| cada fichero cambiado está dentro de `scope_paths` | o se amplía el scope a propósito |
| si se exige, hay un fichero de prueba en el diff | verde no es cubierto |

Lo que no hace, a propósito:

- Nunca ejecuta cadenas que vengan del repositorio. El contrato solo lleva ids; una orden
  inyectada se rechaza sin ejecutarse (probado con un fichero canario en la batería).
- Guarda silencio en repos fuera de la allowlist: un `.rompelo/` ajeno no engancha nada.
- No lee la salida de los comandos, que puede llevar secretos.
- Falla cerrado: un contrato ilegible en un repo alistado bloquea.
- Sin dependencias. Biblioteca estándar de Python 3.9 y git.

## Instalar

```bash
git clone https://github.com/bugroo/rompelo ~/rompelo
cp ~/rompelo/checks/registry.example.json ~/rompelo/checks/registry.local.json   # tus checks
```

En `registry.local.json` viven tus comandos, un id cada uno, como argv:

```json
{
  "mi-app.test": {"argv": ["pnpm", "test"], "cwd": "repo", "min_lineas": 1},
  "mi-app.humo": {"argv": ["node", "scripts/humo.mjs"], "cwd": "repo"}
}
```

Después, el hook:

- **Claude Code**: añade la entrada `Stop` de
  [`adapters/claude/settings-fragment.json`](adapters/claude/settings-fragment.json) a
  `~/.claude/settings.json`.
- **Codex**: fusiona [`adapters/codex/hooks.json`](adapters/codex/hooks.json) en
  `~/.codex/hooks.json` y confía el hook en `/hooks`. Detalle en
  [`adapters/codex/LEEME.md`](adapters/codex/LEEME.md).

## Usar

```bash
cd tu-repo
~/rompelo/bin/rompelo init --id T-42 --scope 'src/**' --check mi-app.test --junta
# ... el agente trabaja ...
~/rompelo/bin/rompelo check                                     # ejecuta los checks registrados y guarda evidencia
~/rompelo/bin/rompelo cruce --nota "petición real" -- curl -sf https://…   # el cruce real
~/rompelo/bin/rompelo close                                     # se niega si falta algo
```

`rompelo verify` enseña el veredicto en cualquier momento. `rompelo --help` lo lista todo.

## Verificado, y no

- 63 casos en [`tests/rompelo-stop-test.sh`](tests/rompelo-stop-test.sh), cada condición vista
  en rojo con una mutación confirmada y luego en verde. CI los corre en Ubuntu en cada push.
- El lado de Claude Code está cruzado en vivo: terminar un turno con el contrato sin cumplir
  devolvió el bloqueo con los motivos correctos, y la línea configurada en `settings.json` la
  reproduce [`tests/cruce-settings-claude.sh`](tests/cruce-settings-claude.sh), visto dar sus tres códigos.
- **No verificado:** el lado de Codex en vivo. El adaptador sigue el contrato oficial del hook;
  instalarlo y confiarlo es del usuario. La capa de observación de
  [docs/observacion.md](docs/observacion.md) es diseño, no código.

## Hoja de ruta, en orden

1. Control positivo por check registrado: el instrumento tiene que detectar una entrada mala conocida antes de que su verde valga.
2. Capa de observación: tres disparadores (riesgo de la tarea, firma de error repetida, afirmaciones sobre el mundo) que suben el rigor avisando antes, y piden permiso una vez antes de gastar en comprobaciones externas.
3. Informe de cierre en llano: qué se comprobó y se vio fallar, qué no se pudo comprobar, qué queda a tu cargo.
4. `rompelo verify --ci` como juez independiente en los pull requests.
5. Incidentes que se compilan en checks registrados: una lección como detector, no como prosa.

## Trabajo relacionado

[Agentic OS](https://github.com/KbWen/agentic-os) exige un flujo por fases con evidencia en git
hooks y CI. [Hermes Agent](https://github.com/NousResearch/hermes-agent) aprende skills de la
experiencia. Stryker y PIT miden la fuerza de las pruebas con mutación. `rompelo` va al lado y
añade lo que ninguno comprueba: que la comprobación estaba mirando.

MIT.
