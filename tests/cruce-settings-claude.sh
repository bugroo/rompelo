#!/bin/bash
# Cruce de la junta settings.json ↔ hook Stop ↔ rompelo, ejecutando la línea TAL CUAL
# está configurada (no una ruta escrita aquí). Crea un repo alistado desechable con el
# contrato sin cumplir y exige que la línea configurada devuelva decision: block.
# El repo desechable entra en la allowlist REAL (es lo que cruza el hook real) y se
# quita al final. Exit 0 = la junta responde · 1 = no responde · 2 = no se pudo evaluar.
set -u
S="$HOME/.claude/settings.json"
CMD=$(python3 - "$S" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
c=[h['command'] for m in d.get('hooks',{}).get('Stop',[]) for h in m.get('hooks',[]) if 'rompelo' in h.get('command','')]
print(c[0] if c else '')
PY
)
[ -n "$CMD" ] || { echo "settings.json no tiene ningún hook Stop de rompelo"; exit 2; }
T=$(mktemp -d); export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
git -C "$T" init -q && git -C "$T" config user.email t@t && git -C "$T" config user.name t
echo a > "$T/a" && git -C "$T" add -A && git -C "$T" commit -qm base
( cd "$T" && "$HOME/rompelo/bin/rompelo" init --id CRUCE --check rompelo.tests --junta >/dev/null ) || { echo "init falló"; exit 2; }
# Con disparo `entrega` (defecto desde el 16-09-2026) el Stop solo juzga con el cierre declarado: un `close` en rojo lo declara.
( cd "$T" && "$HOME/rompelo/bin/rompelo" close >/dev/null 2>&1 )
OUT=$(printf '{"session_id":"cruce-%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$$" "$T" | sh -c "$CMD")
python3 - "$HOME/rompelo/config/repos.json" "$T" <<'PY'
import json,os,sys
f,t=sys.argv[1],os.path.realpath(sys.argv[2])
d=json.load(open(f)); d["repos"]=[r for r in d["repos"] if os.path.realpath(r)!=t]
json.dump(d,open(f,"w"),indent=2); open(f,"a").write("\n")
PY
rm -rf "$T"
rm -f "$HOME/rompelo/state/marcas/cerrando-$(python3 -c 'import hashlib,os,sys;print(hashlib.sha256(os.path.realpath(sys.argv[1]).encode()).hexdigest()[:16])' "$T")"
if printf '%s' "$OUT" | grep -q '"decision": *"block"' && printf '%s' "$OUT" | grep -q 'sin ejecutar'; then
  echo "junta OK: la línea configurada «${CMD}» bloquea con motivo"; exit 0
fi
echo "junta ROTA: la línea configurada no bloqueó. Salida: $OUT"; exit 1
