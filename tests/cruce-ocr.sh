#!/bin/bash
# Cruce de la junta rompelo → checks/ocr-review.py → ocr → api_key_cmd (vault) → proveedor LLM → JSON → código.
# La junta está cruzada si el envoltorio llegó al modelo y juzgó ficheros: código 0 (limpio) o 1 (hallazgos).
# Un 2 (no pudo mirar) o cualquier otro código es junta rota. Los hallazgos NO se tragan: se imprimen y
# van al contrato con disposición; este guion solo dice si el cable está conectado.
set -u
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$RAIZ/checks/ocr-review.py" "$@"; rc=$?
[ "$rc" = 0 ] || [ "$rc" = 1 ] || { echo "junta ROTA: el envoltorio devolvió $rc"; exit 1; }
top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "junta ROTA: sin repo"; exit 1; }
python3 - "$top/.rompelo/ocr-ultimo.json" "$rc" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
if not d.get("modelo") or int(d.get("ficheros") or 0) == 0:
    print("junta ROTA: sin modelo o sin ficheros juzgados"); sys.exit(1)
n = len(d.get("comentarios") or [])
print(f"junta cruzada: {d['modelo']} juzgó {d['ficheros']} ficheros ({', '.join(d['pasadas'])}); código {sys.argv[2]}, {n} comentario(s) → disposición en el contrato")
PY
