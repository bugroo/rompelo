# Contribuir

Gracias por mirar. Tres reglas y un formato.

## Lo que no se negocia

1. **Nada se da por bueno sin haberlo visto fallar.** Toda condición nueva del gate o del
   observador entra con dos casos en la batería (`tests/rompelo-stop-test.sh`,
   `tests/rompelo-observe-test.sh`): uno que la incumple y se ve en ROJO antes del arreglo, y uno
   bueno que se ve en VERDE después. Si el rojo se consigue mutando algo, la prueba confirma que
   la mutación ocurrió. Un PR que añade una condición sin su caso en rojo no se fusiona.
2. **`bin/rompelo` es Python 3.9 con biblioteca estándar.** Sin dependencias, sin shell para
   ejecutar comandos (argv siempre), sin guardar salida de comandos (puede llevar secretos).
3. **Los incidentes son la fuente.** Un cambio de comportamiento que sale de un fallo real lleva
   su YAML en `incidents/` (mismo esquema que los existentes, con `disparador`) y se regenera
   `corpus/TABLA.md` con `python3 bin/rompelo-corpus.py`.

## Antes de abrir el PR

```bash
bash tests/rompelo-stop-test.sh        # PASS=109 FAIL=0
bash tests/rompelo-observe-test.sh     # PASS=75 FAIL=0
bash tests/sin-var-pegada.sh           # 0 limpio · 1 hallazgos · 2 no pude mirar
python3 bin/rompelo-corpus.py
```

CI corre lo mismo en Ubuntu más `rompelo verify --ci` sobre este repo. Los checks marcados
`solo_local` en `checks/registry.json` no corren en CI y no pueden ser la única prueba de algo.
`verify --ci` ejecuta también los controles positivos registrados: un 1 del control acredita
el malo esperado, no el check real. Contrato y límites en [docs/control-positivo.md](docs/control-positivo.md).

## Formato

- Commits en español o en inglés, en presente, diciendo qué cambia para quien usa la herramienta.
  Si el cambio viene de un incidente, cítalo (`INC-2026-00NN`).
- Mensajes nuevos del gate o del observador van en español en el código y con su entrada en la
  tabla `EN` de `bin/rompelo`; la batería comprueba que un bloqueo en inglés no lleva restos.
- Documentación: `README.md` (inglés) y `README.es.md` (español) van a la par.
