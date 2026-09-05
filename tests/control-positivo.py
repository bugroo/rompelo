#!/usr/bin/env python3
"""Ejercita el mismo instrumento con un malo conocido: 1 detectado, 0 ciego, 2 no pudo mirar.

No convierte cualquier error de infraestructura en hallazgo. Solo imprime recuentos;
la salida del instrumento se consume en memoria y no se guarda.
"""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

RAIZ = Path(__file__).resolve().parent.parent


def correr(argv, **kw):
    return subprocess.run(argv, capture_output=True, text=True, timeout=300, **kw)


def variable_pegada(tmp):
    malo = tmp / "malo.sh"
    malo.write_text('echo «$X»\n', encoding="utf-8")
    assert malo.read_text(encoding="utf-8") == 'echo «$X»\n'
    r = correr(["bash", str(RAIZ / "tests/sin-var-pegada.sh"), str(tmp)])
    if r.returncode == 1 and "1 ficheros vistos" in r.stdout and str(malo) + ":1:" in r.stdout:
        print("1 guion malo creado; el mismo analizador detectó la variable pegada")
        return 1
    if r.returncode == 0:
        print("1 guion malo creado; el analizador no lo detectó")
        return 0
    print("el analizador no pudo inspeccionar su control conocido")
    return 2


def gate(tmp):
    original = RAIZ / "bin/rompelo"
    texto = original.read_text(encoding="utf-8")
    antes, despues = "    if fuera:\n", "    if False:  # mutación de control positivo: scope anulado\n"
    if texto.count(antes) != 1:
        print("no pude aplicar exactamente una mutación de scope; no cuenta como hallazgo")
        return 2
    mutante = tmp / "rompelo-mutante"
    mutante.write_text(texto.replace(antes, despues, 1), encoding="utf-8")
    mutante.chmod(original.stat().st_mode)
    aplicado = mutante.read_text(encoding="utf-8")
    assert antes not in aplicado and aplicado.count(despues) == 1 and aplicado != texto
    r = correr(["bash", str(RAIZ / "tests/rompelo-stop-test.sh")],
               env=dict(os.environ, ROMPELO_BIN=str(mutante)), cwd=str(RAIZ))
    resumen = re.findall(r"^PASS=(\d+) FAIL=(\d+)$", r.stdout, re.M)
    if len(resumen) != 1:
        print("la batería no completó su recuento; instrumento no verificado")
        return 2
    pasa, falla = map(int, resumen[0])
    fallos = [linea.strip() for linea in r.stdout.splitlines() if linea.strip().startswith("❌")]
    esperado = "❌ fuera de scope (esperaba bloqueo con «fuera de scope_paths: docs/x.md»)"
    print(f"1 mutación de scope confirmada; batería PASS={pasa} FAIL={falla}")
    if r.returncode == 0 and falla == 0 and pasa > 0:
        return 0
    if r.returncode == 1 and falla == 1 and pasa > 0 and fallos == [esperado]:
        return 1
    print("el fallo no es exclusivamente el de scope esperado; no cuenta como control detectado")
    return 2


def main():
    modos = {"sin-var-pegada": variable_pegada, "gate": gate}
    if len(sys.argv) != 2 or sys.argv[1] not in modos:
        print("uso: control-positivo.py sin-var-pegada|gate", file=sys.stderr)
        return 2
    try:
        with tempfile.TemporaryDirectory(prefix="rompelo-positivo-") as d:
            return modos[sys.argv[1]](Path(d))
    except (OSError, subprocess.TimeoutExpired, AssertionError) as exc:
        print(f"control no pudo mirar: {type(exc).__name__}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
