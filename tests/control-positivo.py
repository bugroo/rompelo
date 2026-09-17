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
    resumen = re.findall(r"^PASS=(\d+) FAIL=(\d+) ROTOS=(\d+)$", r.stdout, re.M)
    if len(resumen) != 1:
        print("la batería no completó su recuento; instrumento no verificado")
        return 2
    pasa, falla, rotos = map(int, resumen[0])
    if rotos:
        print(f"la batería vio {rotos} invocación(es) del hook rotas (crash, timeout, stderr): instrumento no verificado")
        return 2
    fallos = [linea.strip() for linea in r.stdout.splitlines() if linea.strip().startswith("❌")]
    esperado = "❌ fuera de scope (esperaba bloqueo con «fuera de scope_paths: docs/x.md»)"
    print(f"1 mutación de scope confirmada; batería PASS={pasa} FAIL={falla}")
    if r.returncode == 0 and falla == 0 and pasa > 0:
        return 0
    if r.returncode == 1 and falla == 1 and pasa > 0 and fallos == [esperado]:
        return 1
    print("el fallo no es exclusivamente el de scope esperado; no cuenta como control detectado")
    return 2


def ocr_review(tmp):
    """El mismo instrumento (tests/ocr-review-test.sh) contra un envoltorio con el tope de tamaño anulado:
    tiene que fallar solo en el caso del tope. Copia la batería a un árbol temporal porque la batería
    localiza el envoltorio por su propia ruta (dirname/..)."""
    original = RAIZ / "checks/ocr-review.py"
    texto = original.read_text(encoding="utf-8")
    antes, despues = "    if tope > 0:\n", "    if False:  # mutación de control positivo: tope anulado\n"
    if texto.count(antes) != 1:
        print("no pude aplicar exactamente una mutación del tope; no cuenta como hallazgo")
        return 2
    (tmp / "checks").mkdir()
    (tmp / "tests").mkdir()
    mutante = tmp / "checks/ocr-review.py"
    mutante.write_text(texto.replace(antes, despues, 1), encoding="utf-8")
    aplicado = mutante.read_text(encoding="utf-8")
    assert antes not in aplicado and aplicado.count(despues) == 1 and aplicado != texto
    for f in ("checks/ocr-control-positivo.py", "tests/ocr-review-test.sh"):
        (tmp / f).write_text((RAIZ / f).read_text(encoding="utf-8"), encoding="utf-8")
    r = correr(["bash", str(tmp / "tests/ocr-review-test.sh")], cwd=str(tmp))
    resumen = re.findall(r"^(\d+) casos, (\d+) fallos$", r.stdout, re.M)
    if len(resumen) != 1:
        print("la batería no completó su recuento; instrumento no verificado")
        return 2
    vistos, fallos = map(int, resumen[0])
    lineas_fallo = [l for l in r.stdout.splitlines() if l.startswith("FALLO")]
    print(f"1 mutación del tope confirmada; batería {vistos} casos, {fallos} fallos")
    if r.returncode == 0 and fallos == 0 and vistos > 0:
        return 0
    if r.returncode == 1 and fallos == 1 and len(lineas_fallo) == 1 and lineas_fallo[0].startswith("FALLO tope:"):
        return 1
    print("el fallo no es exclusivamente el del tope esperado; no cuenta como control detectado")
    return 2


def disparo(tmp):
    """La batería del disparo (tests/rompelo-disparo-test.sh) contra un binario que, con disparo `entrega`, calla en
    Stop aunque el cierre esté declarado: tiene que fallar exactamente en los casos que exigen ese bloqueo o que retiren la marca."""
    original = RAIZ / "bin/rompelo"
    texto = original.read_text(encoding="utf-8")
    antes = "            if not cierre_declarado(root, tid, contrato_cerrado(root)):\n                return 0"
    despues = "            if True:  # mutación de control positivo: el cierre declarado no cuenta\n                return 0"
    if texto.count(antes) != 1:
        print("no pude aplicar exactamente una mutación del disparo; no cuenta como hallazgo")
        return 2
    mutante = tmp / "rompelo-mutante"
    mutante.write_text(texto.replace(antes, despues, 1), encoding="utf-8")
    mutante.chmod(original.stat().st_mode)
    aplicado = mutante.read_text(encoding="utf-8")
    assert antes not in aplicado and aplicado.count(despues) == 1 and aplicado != texto
    r = correr(["bash", str(RAIZ / "tests/rompelo-disparo-test.sh")],
               env=dict(os.environ, ROMPELO_BIN=str(mutante)), cwd=str(RAIZ))
    resumen = re.findall(r"^PASS=(\d+) FAIL=(\d+) ROTOS=(\d+)$", r.stdout, re.M)
    if len(resumen) != 1:
        print("la batería no completó su recuento; instrumento no verificado")
        return 2
    pasa, falla, rotos = map(int, resumen[0])
    if rotos:
        print(f"la batería vio {rotos} invocación(es) del hook rotas: instrumento no verificado")
        return 2
    fallos = sorted(l.strip() for l in r.stdout.splitlines() if l.strip().startswith("❌"))
    esperados = sorted(["❌ Stop tras el cierre declarado: bloquea (esperaba bloqueo con «check `ok` se ejecutó sobre otro árbol»)",
                        "❌ Stop tras close en rojo: bloquea (esperaba bloqueo con «check `ok` se ejecutó sobre otro árbol»)",
                        "❌ la marca sigue tras cumplir",  # un Stop que nunca juzga tampoco retira la marca
                        "❌ la marca huérfana sigue (1)",  # ni la de un contrato cerrado
                        "❌ la marca de la otra tarea sigue (1)",  # ni la de otra tarea
                        "❌ y Stop bloquea con la marca legítima (esperaba bloqueo con «check `ok` sin ejecutar»)"])
    print(f"1 mutación del disparo confirmada; batería PASS={pasa} FAIL={falla}")
    if r.returncode == 0 and falla == 0 and pasa > 0:
        return 0
    if r.returncode == 1 and falla == len(esperados) and pasa > 0 and fallos == esperados:
        return 1
    print("el fallo no es exclusivamente el del disparo esperado; no cuenta como control detectado")
    return 2


def obliga(tmp):
    """La batería de obliga contra un binario en el que TODA regla aplica aunque ninguna ruta cambiada case:
    tiene que fallar exactamente en los tres casos que exigen que una regla sin ruta no añada nada."""
    original = RAIZ / "bin/rompelo"
    texto = original.read_text(encoding="utf-8")
    antes = "        if not any(casa(p, glob) for p in cambiados):\n            continue\n        for cid in ob[\"checks\"]:"
    despues = "        if False:  # mutación de control positivo: toda regla aplica\n            continue\n        for cid in ob[\"checks\"]:"
    if texto.count(antes) != 1:
        print("no pude aplicar exactamente una mutación de obliga; no cuenta como hallazgo")
        return 2
    mutante = tmp / "rompelo-mutante"
    mutante.write_text(texto.replace(antes, despues, 1), encoding="utf-8")
    mutante.chmod(original.stat().st_mode)
    aplicado = mutante.read_text(encoding="utf-8")
    assert antes not in aplicado and aplicado.count(despues) == 1 and aplicado != texto
    r = correr(["bash", str(RAIZ / "tests/rompelo-obliga-test.sh")],
               env=dict(os.environ, ROMPELO_BIN=str(mutante)), cwd=str(RAIZ))
    resumen = re.findall(r"^PASS=(\d+) FAIL=(\d+) ROTOS=(\d+)$", r.stdout, re.M)
    if len(resumen) != 1:
        print("la batería no completó su recuento; instrumento no verificado")
        return 2
    pasa, falla, rotos = map(int, resumen[0])
    if rotos:
        print(f"la batería vio {rotos} invocación(es) del hook rotas: instrumento no verificado")
        return 2
    fallos = sorted(l.strip() for l in r.stdout.splitlines() if l.strip().startswith("❌"))
    esperados = sorted(["❌ obliga exigió algo sin ruta que case", "❌ run.sh + sh-check hecho: verde (esperaba silencio)",
                        "❌ cruzado: verde (esperaba silencio)"])
    print(f"1 mutación de obliga confirmada; batería PASS={pasa} FAIL={falla}")
    if r.returncode == 0 and falla == 0 and pasa > 0:
        return 0
    if r.returncode == 1 and falla == 3 and pasa > 0 and fallos == esperados:
        return 1
    print("el fallo no es exclusivamente el de obliga esperado; no cuenta como control detectado")
    return 2


def revisar(tmp):
    """La batería de revisar contra un gate que da por vigente cualquier manifiesto cerrado aunque sea de otro árbol:
    tiene que fallar exactamente en el caso que exige volver a revisar tras un cambio."""
    original = RAIZ / "bin/rompelo"
    texto = original.read_text(encoding="utf-8")
    antes = '    return rv if (rv and rv.get("cerrada") and rv.get("huella") == hu) else None\n'
    despues = '    return rv if (rv and rv.get("cerrada")) else None  # mutación de control positivo: huella ignorada\n'
    if texto.count(antes) != 1:
        print("no pude aplicar exactamente una mutación de la revisión; no cuenta como hallazgo")
        return 2
    mutante = tmp / "rompelo-mutante"
    mutante.write_text(texto.replace(antes, despues, 1), encoding="utf-8")
    mutante.chmod(original.stat().st_mode)
    aplicado = mutante.read_text(encoding="utf-8")
    assert antes not in aplicado and aplicado.count(despues) == 1 and aplicado != texto
    r = correr(["bash", str(RAIZ / "tests/rompelo-revisar-test.sh")],
               env=dict(os.environ, ROMPELO_BIN=str(mutante)), cwd=str(RAIZ))
    resumen = re.findall(r"^PASS=(\d+) FAIL=(\d+) ROTOS=(\d+)$", r.stdout, re.M)
    if len(resumen) != 1:
        print("la batería no completó su recuento; instrumento no verificado")
        return 2
    pasa, falla, rotos = map(int, resumen[0])
    if rotos:
        print(f"la batería vio {rotos} invocación(es) del hook rotas: instrumento no verificado")
        return 2
    fallos = sorted(l.strip() for l in r.stdout.splitlines() if l.strip().startswith("❌"))
    esperados = sorted(["❌ cambio posterior: vuelve a pedir rompelo revisar (esperaba bloqueo con «rompelo revisar»)"])
    print(f"1 mutación de la revisión confirmada; batería PASS={pasa} FAIL={falla}")
    if r.returncode == 0 and falla == 0 and pasa > 0:
        return 0
    if r.returncode == 1 and falla == len(esperados) and pasa > 0 and fallos == esperados:
        return 1
    print("el fallo no es exclusivamente el de la revisión esperado; no cuenta como control detectado")
    return 2


def observe(tmp):
    """La batería del observador (tests/rompelo-observe-test.sh) contra un binario cuyo observador nunca sube el
    repo a nivel 2: tiene que fallar exactamente en lo que depende de esa escalada (el nivel, la segunda pasada
    y los perfiles junta y exterior que el nivel impone sobre el contrato)."""
    original = RAIZ / "bin/rompelo"
    texto = original.read_text(encoding="utf-8")
    antes = '    est["nivel"] = max(int(est.get("nivel", 0) or 0), 2)\n'
    despues = '    est["nivel"] = int(est.get("nivel", 0) or 0)  # mutación de control positivo: el observador nunca sube el nivel\n'
    if texto.count(antes) != 1:
        print("no pude aplicar exactamente una mutación del observador; no cuenta como hallazgo")
        return 2
    mutante = tmp / "rompelo-mutante"
    mutante.write_text(texto.replace(antes, despues, 1), encoding="utf-8")
    mutante.chmod(original.stat().st_mode)
    aplicado = mutante.read_text(encoding="utf-8")
    assert antes not in aplicado and aplicado.count(despues) == 1 and aplicado != texto
    r = correr(["bash", str(RAIZ / "tests/rompelo-observe-test.sh")],
               env=dict(os.environ, ROMPELO_BIN=str(mutante)), cwd=str(RAIZ))
    resumen = re.findall(r"^PASS=(\d+) FAIL=(\d+) ROTOS=(\d+)$", r.stdout, re.M)
    if len(resumen) != 1:
        print("la batería no completó su recuento; instrumento no verificado")
        return 2
    pasa, falla, rotos = map(int, resumen[0])
    if rotos:
        print(f"la batería vio {rotos} invocación(es) del hook rotas: instrumento no verificado")
        return 2
    fallos = sorted(l.strip() for l in r.stdout.splitlines() if l.strip().startswith("❌"))
    esperados = sorted(["❌ nivel",  # el repo no llega a 2
                        "❌ segunda pasada",  # y el gate no la exige
                        "❌ junta manda",  # ni el perfil junta
                        "❌ exterior"])  # ni el perfil exterior
    print(f"1 mutación del observador confirmada; batería PASS={pasa} FAIL={falla}")
    if r.returncode == 0 and falla == 0 and pasa > 0:
        return 0
    if r.returncode == 1 and falla == len(esperados) and pasa > 0 and fallos == esperados:
        return 1
    print("el fallo no es exclusivamente el del observador esperado; no cuenta como control detectado")
    return 2


def instrumento(tmp):
    """La batería del instrumento (tests/instrumento-test.sh) contra un tests/lib.sh cuyo `es_bloqueo` acepta cualquier
    JSON como bloqueo: tiene que fallar exactamente en las dos distinciones que dependen de leer el JSON (otro texto,
    JSON sin decision=block). Se copian los tres ficheros a un árbol temporal porque la batería carga lib.sh por su
    propia ruta."""
    original = RAIZ / "tests/lib.sh"
    texto = original.read_text(encoding="utf-8")
    antes = 'sys.exit(0 if isinstance(d, dict) and d.get("decision") == "block" and texto in str(d.get("reason", "")) else 1)\n'
    despues = 'sys.exit(0)  # mutación de control positivo: cualquier JSON cuenta como bloqueo\n'
    if texto.count(antes) != 1:
        print("no pude aplicar exactamente una mutación del instrumento; no cuenta como hallazgo")
        return 2
    (tmp / "tests").mkdir()
    for f in ("invocar.py", "instrumento-test.sh"):
        (tmp / "tests" / f).write_text((RAIZ / "tests" / f).read_text(encoding="utf-8"), encoding="utf-8")
    mutante = tmp / "tests/lib.sh"
    mutante.write_text(texto.replace(antes, despues, 1), encoding="utf-8")
    aplicado = mutante.read_text(encoding="utf-8")
    assert antes not in aplicado and aplicado.count(despues) == 1 and aplicado != texto
    r = correr(["bash", str(tmp / "tests/instrumento-test.sh")], cwd=str(tmp))
    resumen = re.findall(r"^instrumento: (\d+) de (\d+) distinciones correctas$", r.stdout, re.M)
    if len(resumen) != 1:
        print("la batería no completó su recuento; instrumento no verificado")
        return 2
    bien, total = map(int, resumen[0])
    fallos = sorted(l.strip() for l in r.stdout.splitlines() if l.strip().startswith("❌"))
    esperados = sorted(["❌ bloqueo sano con OTRO texto no pasa",
                        "❌ un JSON sin decision=block no es bloqueo"])
    print(f"1 mutación del instrumento confirmada; batería {bien} de {total} distinciones")
    if r.returncode == 0 and bien == total and total > 0:
        return 0
    if r.returncode == 1 and total - bien == len(esperados) and bien > 0 and fallos == esperados:
        return 1
    print("el fallo no es exclusivamente el del instrumento esperado; no cuenta como control detectado")
    return 2


def portabilidad(tmp):
    """La batería de portabilidad (tests/portabilidad-test.sh) contra un binario que nombra el estado del repo por el
    nombre de la carpeta y no por el hash de la ruta real: dos proyectos con la misma carpeta comparten estado, y la
    batería tiene que verlo (antes del 17-09-2026 no lo veía: comprobaba con `permiso`, que no vive ahí, y contaba
    los cerrojos como ficheros de estado)."""
    original = RAIZ / "bin/rompelo"
    texto = original.read_text(encoding="utf-8")
    antes = '    return os.path.join(ESTADO, "repos", hashlib.sha256(root.encode()).hexdigest()[:16] + ".json")\n'
    despues = '    return os.path.join(ESTADO, "repos", os.path.basename(root) + ".json")  # mutación de control positivo: estado por nombre de carpeta\n'
    if texto.count(antes) != 1:
        print("no pude aplicar exactamente una mutación del estado por repo; no cuenta como hallazgo")
        return 2
    mutante = tmp / "rompelo-mutante"
    mutante.write_text(texto.replace(antes, despues, 1), encoding="utf-8")
    mutante.chmod(original.stat().st_mode)
    aplicado = mutante.read_text(encoding="utf-8")
    assert antes not in aplicado and aplicado.count(despues) == 1 and aplicado != texto
    r = correr(["bash", str(RAIZ / "tests/portabilidad-test.sh")],
               env=dict(os.environ, ROMPELO_BIN=str(mutante)), cwd=str(RAIZ))
    resumen = re.findall(r"^PASS=(\d+) FAIL=(\d+) ROTOS=(\d+)$", r.stdout, re.M)
    if len(resumen) != 1:
        print("la batería no completó su recuento; instrumento no verificado")
        return 2
    pasa, falla, rotos = map(int, resumen[0])
    if rotos:
        print(f"la batería vio {rotos} invocación(es) del hook rotas: instrumento no verificado")
        return 2
    fallos = sorted(l.strip() for l in r.stdout.splitlines() if l.strip().startswith("❌"))
    esperados = sorted(["❌ estado mezclado",  # b/app hereda el nivel 2 de a/app
                        "❌ estado por ruta",  # un solo fichero de estado para dos repos
                        "❌ doctor escribió"])  # y el recuento posterior también ve uno
    print(f"1 mutación del estado por repo confirmada; batería PASS={pasa} FAIL={falla}")
    if r.returncode == 0 and falla == 0 and pasa > 0:
        return 0
    if r.returncode == 1 and falla == len(esperados) and pasa > 0 and fallos == esperados:
        return 1
    print("el fallo no es exclusivamente el del estado por repo esperado; no cuenta como control detectado")
    return 2


def main():
    modos = {"sin-var-pegada": variable_pegada, "gate": gate, "ocr-review": ocr_review, "disparo": disparo, "obliga": obliga, "revisar": revisar, "observe": observe, "instrumento": instrumento, "portabilidad": portabilidad}
    if len(sys.argv) != 2 or sys.argv[1] not in modos:
        print("uso: control-positivo.py sin-var-pegada|gate|ocr-review|disparo|obliga|revisar|observe|instrumento|portabilidad", file=sys.stderr)
        return 2
    try:
        with tempfile.TemporaryDirectory(prefix="rompelo-positivo-") as d:
            return modos[sys.argv[1]](Path(d))
    except (OSError, subprocess.TimeoutExpired, AssertionError) as exc:
        print(f"control no pudo mirar: {type(exc).__name__}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
