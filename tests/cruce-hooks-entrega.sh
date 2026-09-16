#!/bin/bash
# Cruce de la junta hooks ↔ adaptador ↔ binario para el disparo `entrega`: ejecuta el ADAPTADOR de PreToolUse tal cual
# está en adapters/claude/rompelo-hook.sh (que llama a $HOME/rompelo/bin/rompelo) con un payload PreToolUse real de
# Claude Code (`git commit`) sobre un repo alistado con el contrato sin cumplir, y exige un deny con motivo; después,
# un UserPromptSubmit de cierre tiene que dejar contexto y un Stop tiene que bloquear. Con ROMPELO_CRUCE_HOME=<dir>
# se cruza otro árbol de rompelo (un worktree) montando un HOME falso donde `rompelo` es un enlace a ese árbol.
# Exit 0 = la junta responde · 1 = no responde · 2 = no se pudo evaluar.
set -u
ARBOL="${ROMPELO_CRUCE_HOME:-$HOME/rompelo}"
[ -x "$ARBOL/bin/rompelo" ] || { echo "no existe $ARBOL/bin/rompelo"; exit 2; }
T=$(mktemp -d); export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
if [ "$ARBOL" != "$HOME/rompelo" ]; then
  mkdir -p "$T/home"; ln -s "$ARBOL" "$T/home/rompelo"; export HOME="$T/home"   # el adaptador resuelve $HOME/rompelo → el árbol pedido
fi
ADAPT="$ARBOL/adapters/claude/rompelo-hook.sh"; STOP="$ARBOL/adapters/claude/rompelo-stop.sh"
[ -x "$ADAPT" ] && [ -x "$STOP" ] || { echo "faltan adaptadores ejecutables en $ARBOL/adapters/claude"; exit 2; }
R="$T/repo"; mkdir -p "$R"
git -C "$R" init -q && git -C "$R" config user.email t@t && git -C "$R" config user.name t
echo a > "$R/a" && git -C "$R" add -A && git -C "$R" commit -qm base
( cd "$R" && "$ARBOL/bin/rompelo" init --id CRUCE-ENTREGA --check rompelo.tests >/dev/null ) || { echo "init falló"; exit 2; }
echo b > "$R/a"
limpiar() { python3 - "$ARBOL/config/repos.json" "$R" <<'PY'
import json,os,sys
f,t=sys.argv[1],os.path.realpath(sys.argv[2])
try:
    d=json.load(open(f)); d["repos"]=[r for r in d["repos"] if os.path.realpath(r)!=t]
    json.dump(d,open(f,"w"),indent=2); open(f,"a").write("\n")
except FileNotFoundError:
    pass
PY
rm -f "$ARBOL/state/marcas/cerrando-$(python3 -c 'import hashlib,os,sys;print(hashlib.sha256(os.path.realpath(sys.argv[1]).encode()).hexdigest()[:16])' "$R")"
rm -rf "$T"; }
fallo() { echo "junta ROTA: $1"; echo "salida: $2"; limpiar; exit 1; }
# 1) PreToolUse Bash `git commit` → deny
OUT=$(printf '{"session_id":"cruce-%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit -am x"},"tool_use_id":"t1"}' "$$" "$R" | "$ADAPT")
printf '%s' "$OUT" | grep -q '"permissionDecision": *"deny"' && printf '%s' "$OUT" | grep -q 'sin ejecutar' || fallo "PreToolUse commit no denegó" "$OUT"
# 2) PreToolUse Bash `ls` → silencio
OUT=$(printf '{"session_id":"cruce-%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_use_id":"t2"}' "$$" "$R" | "$ADAPT")
[ -z "$OUT" ] || fallo "PreToolUse ls no fue silencio" "$OUT"
# 3) Stop sin cierre declarado → silencio (entrega)
OUT=$(printf '{"session_id":"cruce-%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$$" "$R" | "$STOP")
[ -z "$OUT" ] || fallo "Stop sin cierre declarado no fue silencio (¿disparo turno?)" "$OUT"
# 4) UserPromptSubmit «termina» → contexto; 5) Stop → bloquea
OUT=$(printf '{"session_id":"cruce-%s","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"termina y sube esto"}' "$$" "$R" | "$ADAPT")
printf '%s' "$OUT" | grep -q '"additionalContext"' && printf '%s' "$OUT" | grep -q 'CRUCE-ENTREGA' || fallo "UserPromptSubmit de cierre sin contexto" "$OUT"
OUT=$(printf '{"session_id":"cruce-%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$$" "$R" | "$STOP")
printf '%s' "$OUT" | grep -q '"decision": *"block"' && printf '%s' "$OUT" | grep -q 'sin ejecutar' || fallo "Stop tras el cierre declarado no bloqueó" "$OUT"
limpiar
echo "junta OK: adaptador $ADAPT → binario $ARBOL/bin/rompelo: deny al commit, silencio en ls y en Stop sin cierre, contexto al pedir cierre, bloqueo en Stop después"
exit 0
