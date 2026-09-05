# Control positivo por check

El registro puede declarar `triestado: true`: 0 limpio, 1 hallazgos, 2 no pudo mirar.
Los demás códigos, incluidas las señales y el 127 de ejecutable ausente, bloquean como
aborto por una ruta no prevista. El código original se conserva en la evidencia.
Un instrumento que devuelve incorrectamente 1 al morir sigue necesitando corregirse.

```json
{
  "mi.check": {
    "argv": ["python3", "tests/comprobar.py"],
    "cwd": "repo",
    "triestado": true,
    "min_lineas": 1,
    "control_positivo": {
      "argv": ["python3", "tests/control-con-caso-malo.py"],
      "cwd": "repo"
    }
  }
}
```

`control_positivo` es opcional. Cuando existe, `check` y `verify --ci` ejecutan su argv
sin shell antes del check real. Debe usar el **mismo instrumento** sobre una entrada
conocida mala; el registro no puede demostrar por sí solo que un script arbitrario lo haga.

| Código del control | Evidencia | Check real | Gate |
|---|---|---|---|
| 0 | `instrumento: ciego` | sin ejecutar, `codigo: null` | el verde no vale |
| 1 | `instrumento: operativo` | se ejecuta | exige código 0, salida mínima y huella vigente |
| 2 | `instrumento: no_pudo_mirar` | sin ejecutar | instrumento, no hallazgo |
| otro | `instrumento: abortado` | sin ejecutar | ruta no prevista |

La evidencia incluye códigos, recuentos, duración y hashes de salida de ambos procesos;
nunca su stdout ni stderr. La salida de `check` muestra código, líneas producidas frente al
mínimo y resultado del control. Un 0 que no alcanza `min_lineas` tampoco hace salir a `check`
con éxito. El informe distingue los checks con control de los que no lo declaran.

La evidencia se vincula a argv, cwd, triestado, mínimo y definición del control. Cambiar
esas reglas exige repetir la comprobación, incluso con una tarea cerrada. Un nuevo check
fallido tampoco queda oculto detrás de un cierre anterior sobre el mismo árbol.
Los cierres/evidencias anteriores a esta vinculación requieren `check` y `close` nuevos.

## Controles incluidos

- `rompelo.sin-var-pegada`: escribe el guion exacto `echo «$X»` en un directorio temporal,
  comprueba su contenido y exige que el analizador habitual detecte esa línea con código 1.
- `rompelo.tests`: copia `bin/rompelo`, confirma una única mutación que anula scope y ejecuta
  la batería habitual usando `ROMPELO_BIN` para señalar la copia. Solo acredita el fallo
  concreto de scope: cualquier otro fallo, mutación ausente o batería incompleta devuelve 2.

Ambos usan `tests/control-positivo.py`; no modifican el binario real. La batería a su vez usa
un `ROMPELO_HOME` temporal. El control del gate verifica scope; no acredita automáticamente
todos los requisitos ni todos los detectores de la batería.

## Cobertura y límite

La Parte 2 aporta el mecanismo, dos controles reales y 32 casos nuevos del gate. Base:
77/77 gate y 75/75 observador. Los casos iniciales dieron 23 fallos antes del cambio;
el caso adicional del cierre dio 1 fallo antes de corregirse. Gate posterior: 109/109.

INC-0022 y 0023 tienen ahora una barrera ejecutable para mutaciones no aplicadas o que no
crean el malo esperado. INC-0017 sigue parcial: si el instrumento miente con código 1,
triestado no lo arregla. INC-0020 sigue sin cobertura específica del runner con timeout.

**INC-0033, 0034 y 0035 siguen sin controles específicos de ClaveON.** Falta registrar y
ejercitar sus casos de etiqueta ausente, correo escapado y estilo CSS degradado sobre el
artefacto final. No los cubre el mutante de scope de Rómpelo. Sus YAML distinguen mecanismo
disponible de requisito probado; este cambio no edita ClaveON.

La ejecución automática de Stop en Codex está documentada en
[`observacion.md` §12.3](observacion.md#123--codex-en-vivo-05-09-mediodía-con-codex-exec-desde-esta-sesión).
También se cruzó esta Parte 2 con `codex exec`, sandbox `workspace-write` y `ROMPELO_HOME`
aislado: primer cierre bloqueado por control ciego; Codex corrigió el instrumento sintético,
ejecutó `check`, `close`, `verify` y terminó sin otro bloqueo. Un único `HookPrompt` nativo
descarta que se dejara cerrar por llegar al tope. El controlador no cumplió el contrato.
Fragmento literal del nuevo bloqueo:

```text
check `sintetico.cp`: su control positivo no detectó el caso malo; el verde no vale
```

Invocar el adaptador directamente, incluido el check de cruce de settings de Claude, prueba
esa línea configurada; no demuestra que un cliente la haya ejecutado automáticamente.
