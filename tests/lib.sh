#!/bin/bash
# Helpers comunes de las baterías. Se cargan con `. "$(dirname "$0")/lib.sh"`.
#
# Lo que cambió el 07-09-2026 (RMP-004 de la auditoría): antes `espera_paso` daba por bueno cualquier
# stdout vacío, y un hook que moría con código 1 y un traceback en stderr contaba como «deja parar».
# Ahora cada invocación del hook pasa por `invocar`, que mira código de salida, stderr y tiempo, y
# cuando algo de eso falla mete en la salida una marca ⟦INSTRUMENTO ROTO…⟧ que ninguna aserción acepta:
# ni la de silencio (la salida ya no está vacía) ni la de bloqueo (la marca no es JSON).
#
# El binario por defecto es el que está JUNTO a los tests, no ~/rompelo: probar otro árbol probaba el
# binario en producción (el observe-test lo tenía escrito a mano).
ROMPELO="${ROMPELO_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/rompelo}"
ROMPELO_HOOK_TIMEOUT="${ROMPELO_HOOK_TIMEOUT:-30}"
PASS=0; FAIL=0
# Los hooks se invocan dentro de `$(…)`, o sea en subshell: el recuento de roturas va a un fichero.
ROTOS_F="$(mktemp)"
ok()  { PASS=$((PASS+1)); echo "  ✅ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     salida: $2"; true; }  # siempre 0: `x && bad || ok` no puede acabar en ok

# invocar <subcomando> <agente>  (JSON por stdin) → stdout del hook, con marca si el proceso no está sano.
# Sano = existe, termina antes del plazo, código 0 y stderr vacío. Cualquier otra cosa es un fallo del
# instrumento, no una decisión del gate, y se cuenta en ROTOS además de estropear la salida.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
invocar() { python3 "$LIB_DIR/invocar.py" "$ROMPELO" "$1" "$2" "$ROMPELO_HOOK_TIMEOUT"; local rc=$?
  [ "$rc" -eq 3 ] && echo "$1 $2" >> "$ROTOS_F"; return 0; }

# hook_stop <agente> <sid> <cwd> → salida del hook Stop
hook_stop() { printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$2" "$3" | invocar hook "$1"; }

# observar <agente> <json> → salida del observador
observar() { printf '%s' "$2" | invocar observe "$1"; }

# es_bloqueo <salida> <texto>: la salida ENTERA es un JSON con decision=block y el texto en reason.
# Un prefijo basura, un JSON truncado o la marca de instrumento roto no pasan.
es_bloqueo() { python3 - "$1" "$2" <<'PY'
import json, sys
salida, texto = sys.argv[1:3]
try:
    d = json.loads(salida)
except ValueError:
    sys.exit(1)
sys.exit(0 if isinstance(d, dict) and d.get("decision") == "block" and texto in str(d.get("reason", "")) else 1)
PY
}

# espera_bloqueo <nombre> <sid> <texto> [agente] [cwd]
espera_bloqueo() { local out; out="$(hook_stop "${4:-claude}" "$2" "${5:-$R}")"
  if es_bloqueo "$out" "$3"; then ok "$1"; else bad "$1 (esperaba bloqueo con «$3»)" "$out"; fi; }
# espera_paso <nombre> <sid> [agente] [cwd]: silencio sano = proceso sano y stdout vacío.
espera_paso() { local out; out="$(hook_stop "${3:-claude}" "$2" "${4:-$R}")"
  if [ -z "$out" ]; then ok "$1"; else bad "$1 (esperaba silencio)" "$out"; fi; }

# resumen: imprime el recuento y devuelve 0 solo si nada falló y ningún hook se rompió.
resumen() { local rotos; rotos=$(wc -l < "$ROTOS_F" | tr -d ' '); rm -f "$ROTOS_F"
  echo; echo "PASS=$PASS FAIL=$FAIL ROTOS=$rotos"; [ "$FAIL" -eq 0 ] && [ "$rotos" -eq 0 ]; }
