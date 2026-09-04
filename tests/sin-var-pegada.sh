#!/bin/bash
# Variable pegada a un carácter multibyte («$X» o $X» o similares) mata un guion bajo set -u:
# bash lee el byte siguiente como parte del nombre. Mordió tres veces a rootml-de y una a
# assure el mismo día (INC-2026-0021). Triestado: 0 limpio · 1 hay ocurrencias · 2 no vi ficheros.
# Informa siempre de cuántos ficheros vio: un 0 sobre nada no es «limpio».
# La primera versión usaba grep -P y su control positivo falló (ugrep no casaba el rango);
# por eso el análisis va en Python, que se comporta igual en todas partes.
set -u
RAIZ="${1:-$HOME/assure}"
python3 - "$RAIZ" <<'PY'
import os, re, sys
raiz = sys.argv[1]
pat = re.compile(r"\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7f]")
vistos, hallazgos = 0, []
for d, _, fs in os.walk(raiz):
    if "/.git" in d:
        continue
    for f in fs:
        if not (f.endswith(".sh") or f.endswith(".bash")) or f == "sin-var-pegada.sh":
            continue
        vistos += 1
        p = os.path.join(d, f)
        try:
            for i, l in enumerate(open(p, encoding="utf-8", errors="replace"), 1):
                if pat.search(l):
                    hallazgos.append(f"{p}:{i}: {l.rstrip()}")
        except OSError:
            pass
if vistos == 0:
    print(f"no vi ningún guion en {raiz}: no puedo decir nada"); sys.exit(2)
if hallazgos:
    print(f"{vistos} ficheros vistos, variable pegada a multibyte en:"); print("\n".join(hallazgos)); sys.exit(1)
print(f"{vistos} ficheros vistos, 0 variables pegadas a multibyte"); sys.exit(0)
PY
