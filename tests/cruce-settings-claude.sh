#!/bin/bash
# Cruce de la junta settings.json ↔ hook Stop ↔ assure, ejecutando la línea TAL CUAL
# está configurada (no una ruta escrita aquí). Crea un repo alistado desechable con el
# contrato sin cumplir y exige que la línea configurada devuelva decision: block.
# El repo desechable entra en la allowlist REAL (es lo que cruza el hook real) y se
# quita al final. Exit 0 = la junta responde · 1 = no responde · 2 = no se pudo evaluar.
set -u
S="$HOME/.claude/settings.json"
CMD=$(python3 - "$S" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
c=[h['command'] for m in d.get('hooks',{}).get('Stop',[]) for h in m.get('hooks',[]) if 'assure' in h.get('command','')]
print(c[0] if c else '')
PY
)
[ -n "$CMD" ] || { echo "settings.json no tiene ningún hook Stop de assure"; exit 2; }
T=$(mktemp -d); export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
git -C "$T" init -q && git -C "$T" config user.email t@t && git -C "$T" config user.name t
echo a > "$T/a" && git -C "$T" add -A && git -C "$T" commit -qm base
( cd "$T" && "$HOME/assure/bin/assure" init --id CRUCE --check assure.tests --junta >/dev/null ) || { echo "init falló"; exit 2; }
OUT=$(printf '{"session_id":"cruce","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$T" | sh -c "$CMD")
python3 - "$HOME/assure/config/repos.json" "$T" <<'PY'
import json,os,sys
f,t=sys.argv[1],os.path.realpath(sys.argv[2])
d=json.load(open(f)); d["repos"]=[r for r in d["repos"] if os.path.realpath(r)!=t]
json.dump(d,open(f,"w"),indent=2); open(f,"a").write("\n")
PY
rm -rf "$T"
if printf '%s' "$OUT" | grep -q '"decision": *"block"' && printf '%s' "$OUT" | grep -q 'sin ejecutar'; then
  echo "junta OK: la línea configurada «${CMD}» bloquea con motivo"; exit 0
fi
echo "junta ROTA: la línea configurada no bloqueó. Salida: $OUT"; exit 1
