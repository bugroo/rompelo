# Encargo para Codex · assure, lado Codex y módulo «control positivo»

Contexto en una línea: `~/assure/` es una puerta de cierre por tarea para agentes de código.
Un hook `Stop` llama a `~/assure/bin/assure hook <agente>`, que lee `.assure/task.json` del
repo y bloquea el cierre hasta que el contrato se cumple. Hoy funciona y está cruzado en vivo
en Claude Code. Tu trabajo tiene dos partes, en este orden. Lee antes `~/assure/README.md`,
`~/assure/adapters/codex/LEEME.md` y `~/assure/bin/assure --help`.

Reglas que no se negocian:
- No escribas en `~/.claude/**`. Es de Claude Code. Tú solo tocas `~/.codex/**` y `~/assure/**`.
- `~/assure/bin/assure` sigue siendo Python 3.9 con biblioteca estándar. Sin PyYAML, sin
  dependencias, sin reescribirlo en Bash ni en TypeScript, sin monorepo.
- Nada se da por bueno sin haberlo visto fallar. Cada condición nueva del gate se ve primero en
  ROJO con un caso que la incumple y luego en VERDE con uno bueno, y las dos cosas quedan en
  `~/assure/tests/assure-stop-test.sh`. Antes de tocar nada, la batería tiene que estar en verde:
  `bash ~/assure/tests/assure-stop-test.sh` (hoy: PASS=58 FAIL=0).
- Cuando mutes un fichero para ver rojo, comprueba que la mutación ocurrió (grep del cambio) y
  que crea el fallo que buscas. Una mutación que no casa no prueba nada.
- Commits en `~/assure` con mensajes en español y sin ninguna atribución a IA
  (nada de Co-Authored-By ni «generated with»).
- No toques producción ni datos de clientes. Todo en repos desechables (`mktemp -d`).
- Lo que no puedas verificar se entrega como NO VERIFICADO, diciendo qué falta.

## Parte 1 · Instalar el hook Stop de assure en Codex y cruzarlo en vivo

1. Fusiona, sin sustituir, la entrada `Stop` de `~/assure/adapters/codex/hooks.json` en
   `~/.codex/hooks.json`. Ya existen dos hooks Stop (`global_protocol.py` y el de ai-memory);
   se quedan. El guion de fusión está en `~/assure/adapters/codex/LEEME.md`. Haz copia previa
   de `~/.codex/hooks.json` con fecha en el nombre.
2. La confianza del hook la da José en la interfaz de Codex (`/hooks`, revisar y confiar).
   Dile exactamente qué entrada tiene que aceptar. No intentes escribir el hash de confianza
   en `config.toml` a mano.
3. Cruce real, después de que José lo haya confiado:
   - crea un repo desechable, haz un commit, y dentro ejecuta
     `~/assure/bin/assure init --id CRUCE-CODEX --check assure.sin-var-pegada --junta`
     (eso lo alista en `~/assure/config/repos.json`);
   - termina el turno con el contrato sin cumplir. Tiene que llegarte un bloqueo con dos
     motivos: check sin ejecutar y junta sin cruzar;
   - cumple el contrato (`assure check`, `assure cruce -- true`, `assure close`) y termina el
     turno otra vez: silencio;
   - quita el repo desechable de `~/assure/config/repos.json` y bórralo.
   Reporta las tres cosas con la salida literal del bloqueo. Si no llega el bloqueo, no lo
   arregles a ciegas: mide si el hook corrió (`~/.codex/hooks.json`, estado en `config.toml`,
   salida de `printf '{"cwd":"<repo>","session_id":"x"}' | ~/assure/bin/assure hook codex`).
4. Anota el resultado en `~/assure/adapters/codex/LEEME.md`, sección «Estado», con fecha.

## Parte 2 · Módulo «control positivo»: que un check no pueda dar verde sin haber mirado

Motivo, medido en `~/assure/corpus/TABLA.md`: de 28 incidentes reales, la clase mayor (8) es
«la comprobación no podía fallar»: validador sobre el artefacto equivocado, instrumento que
muere y sale con el código de hallazgo, `pnpm audit` con 0 tras un timeout, «no tests» leído
como 0 fallos, mutación que no casó. Hoy `assure` ya exige `min_lineas`. Falta esto:

1. **Triestado en el registro.** En `~/assure/checks/registry.json` cada check puede declarar
   `"triestado": true`. Significa que el comando promete 0 = limpio, 1 = hay hallazgos,
   2 = no pude mirar. `assure check` guarda el código tal cual y el gate distingue los motivos:
   con 1 «FALLÓ», con 2 «NO PUDO MIRAR (instrumento, no hallazgo)», y cualquier otro código
   distinto de 0 en un check triestado se trata como «abortó por una ruta no prevista», que
   bloquea con su propio motivo. Ejemplo ya escrito: `~/assure/tests/sin-var-pegada.sh`.
2. **Control positivo por check.** Cada entrada del registro puede declarar
   `"control_positivo": {"argv": [...], "cwd": "repo|assure"}`: un comando que ejecuta el
   mismo instrumento sobre una entrada que SABEMOS mala y que por tanto TIENE que salir con 1.
   `assure check` lo ejecuta antes del check real. Si el control positivo sale con 0, el
   instrumento está ciego: la evidencia se guarda con `"instrumento": "ciego"` y el gate bloquea
   con «check X: su control positivo no detectó el caso malo; el verde no vale». Si sale con 2,
   «no pudo mirar». Solo con 1 se ejecuta el check real y cuenta.
   Escribe el control positivo para `assure.sin-var-pegada` (un guion temporal con `«$X»`) y
   para `assure.tests` (la batería sobre una copia de `bin/assure` con una condición anulada,
   por ejemplo la de scope, tiene que dar FAIL>0).
3. **`assure check` informa de lo visto, no solo de lo malo.** En la salida de cada check,
   además del código: si el registro declara `min_lineas`, cuántas líneas produjo; si declara
   `control_positivo`, qué dio. Nada de la salida del comando se guarda (puede llevar secretos):
   solo recuentos y hashes, como ahora.
4. **Batería.** Casos nuevos, cada uno visto en rojo y en verde, con el `ASSURE_HOME`
   desechable que ya usa la batería: control positivo que pasa (bloquea, «ciego»); control
   positivo con 2 (bloquea, «no pudo mirar»); check triestado con 2 (bloquea con su motivo,
   distinto de FALLÓ); check triestado con código 3 (bloquea, «ruta no prevista»); y el caso
   bueno (control positivo con 1, check con 0: silencio).
5. **Corpus.** Marca en los YAML de `~/assure/incidents/` (campo `existe_hoy`) qué incidentes
   de clase I quedan cubiertos por esto, y regenera la tabla:
   `python3 ~/assure/bin/assure-corpus.py`. No inventes cobertura: solo los que un control
   positivo o el triestado habrían cazado de verdad.
6. Cierra tu propia tarea con assure: en `~/assure` el contrato `ASSURE-SPIKE-01` está cerrado;
   abre uno nuevo con `assure init --force --id ASSURE-CODEX-01 --check assure.tests
   --check assure.cruce-settings-claude --check assure.sin-var-pegada --junta`, y no des la
   tarea por terminada hasta que `assure verify` dé 0 y el hook te deje parar.

## Entrega

Tres bloques, en este orden: qué queda hecho, qué falta, qué problemas tiene el trabajo.
Con: comandos ejecutados y resultado; PASS/FAIL de la batería antes y después; la salida
literal del bloqueo en vivo de la Parte 1; y la lista de lo NO VERIFICADO con el motivo.
Sin narrar tus errores: si algo cambió una decisión, una línea.
