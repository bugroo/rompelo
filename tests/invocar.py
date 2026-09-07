#!/usr/bin/env python3
"""Ejecuta `<binario> <sub> <agente>` pasándole stdin tal cual, con plazo. Es el único camino por el que
las baterías llaman al hook. Sano = existe, termina en plazo, código 0 y stderr vacío; si no, la salida
lleva una marca ⟦INSTRUMENTO ROTO…⟧ que ninguna aserción acepta, y el código de salida es 3.
Va en fichero aparte porque un `python3 - <<'PY'` usa stdin para el script y se traga el JSON del hook
(fallo real del 07-09-2026, cazado porque el control tenía un falso que devuelve lo que recibe)."""
import subprocess, sys

bin_, sub, agente, plazo = sys.argv[1:5]
entrada = sys.stdin.read()
try:
    p = subprocess.run([bin_, sub, agente], input=entrada, capture_output=True, text=True, timeout=float(plazo))
except FileNotFoundError:
    sys.stdout.write(f"⟦INSTRUMENTO ROTO: no existe {bin_}⟧\n"); sys.exit(3)
except PermissionError:
    sys.stdout.write(f"⟦INSTRUMENTO ROTO: sin permiso de ejecución {bin_}⟧\n"); sys.exit(3)
except subprocess.TimeoutExpired:
    sys.stdout.write(f"⟦INSTRUMENTO ROTO: sin respuesta en {plazo} s⟧\n"); sys.exit(3)
sys.stdout.write(p.stdout)
if p.returncode != 0 or p.stderr.strip():
    err = p.stderr.strip().splitlines()[-1] if p.stderr.strip() else ""
    sys.stdout.write(f"\n⟦INSTRUMENTO ROTO: rc={p.returncode} stderr={err[:160]}⟧\n"); sys.exit(3)
