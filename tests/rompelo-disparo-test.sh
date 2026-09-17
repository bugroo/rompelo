#!/bin/bash
# Batería del DISPARO de la puerta (docs/disparo.md): cuándo juzga rompelo.
#   entrega (defecto desde el 16-09-2026): PreToolUse deniega commit/push/deploy con el contrato sin cumplir;
#   Stop solo juzga cuando el cierre está declarado (frase del usuario en UserPromptSubmit, o `rompelo close` en rojo).
#   turno: Stop juzga en cada turno (comportamiento anterior).
# Cada caso se ve FALLAR (deniega/bloquea con el motivo correcto) y PASAR (silencio). ROMPELO_HOME desechable.
# Exit 0 = todo OK · 1 = hay fallos · 2 = no se pudo ejecutar.
. "$(dirname "$0")/lib.sh"   # ROMPELO, ok/bad, invocar, hook_stop, es_bloqueo, espera_*, resumen
[ -x "$ROMPELO" ] || { echo "no existe $ROMPELO"; exit 2; }
T="$(mktemp -d)"; export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
export ROMPELO_HOME="$T/home"; mkdir -p "$ROMPELO_HOME/checks" "$ROMPELO_HOME/config"
CANARY="$T/canario"
cat > "$ROMPELO_HOME/checks/registry.json" <<J
{"ok": {"argv": ["true"]}, "ko": {"argv": ["false"]}, "canario": {"argv": ["touch", "$CANARY"]}}
J
R="$T/repo"; mkdir -p "$R/src"; cd "$R" || exit 2
git init -q && git config user.email t@t && git config user.name t
echo a > src/a.txt && git add -A && git commit -qm base

# pretool <agente> <sid> <tool> <comando> [cwd] → salida del hook PreToolUse
pretool() { python3 - "$2" "${5:-$R}" "$3" "$4" <<'PY' | invocar hook "$1"
import json,sys
sid,cwd,tool,cmd=sys.argv[1:5]
ti={"command":cmd} if tool in ("Bash","shell") else {"file_path":cmd,"old_string":"a","new_string":"b"}
print(json.dumps({"session_id":sid,"cwd":cwd,"hook_event_name":"PreToolUse","tool_name":tool,"tool_input":ti,"tool_use_id":"t1"}))
PY
}
# prompt <agente> <sid> <texto> [cwd] → salida del hook UserPromptSubmit
prompt() { python3 - "$2" "${4:-$R}" "$3" <<'PY' | invocar hook "$1"
import json,sys
sid,cwd,texto=sys.argv[1:4]
print(json.dumps({"session_id":sid,"cwd":cwd,"hook_event_name":"UserPromptSubmit","prompt":texto}))
PY
}
# es_deny <salida> <texto>: JSON entero con hookSpecificOutput.permissionDecision=deny y el texto en la razón
es_deny() { python3 - "$1" "$2" <<'PY'
import json, sys
salida, texto = sys.argv[1:3]
try:
    d = json.loads(salida)
except ValueError:
    sys.exit(1)
h = d.get("hookSpecificOutput") if isinstance(d, dict) else None
sys.exit(0 if isinstance(h, dict) and h.get("hookEventName") == "PreToolUse" and h.get("permissionDecision") == "deny"
         and texto in str(h.get("permissionDecisionReason", "")) else 1)
PY
}
# tiene_contexto <salida> <texto>: JSON con hookSpecificOutput.additionalContext que contiene el texto
tiene_contexto() { python3 - "$1" "$2" <<'PY'
import json, sys
salida, texto = sys.argv[1:3]
try:
    d = json.loads(salida)
except ValueError:
    sys.exit(1)
h = d.get("hookSpecificOutput") if isinstance(d, dict) else None
sys.exit(0 if isinstance(h, dict) and texto in str(h.get("additionalContext", "")) else 1)
PY
}
espera_deny() { local out; out="$(pretool "${4:-claude}" "$2" Bash "$3" "${5:-$R}")"
  if es_deny "$out" "$6"; then ok "$1"; else bad "$1 (esperaba deny con «$6»)" "$out"; fi; }
espera_permite() { local out; out="$(pretool "${4:-claude}" "$2" "${5:-Bash}" "$3")"
  if [ -z "$out" ]; then ok "$1"; else bad "$1 (esperaba silencio)" "$out"; fi; }
marcas() { ls "$ROMPELO_HOME/state/marcas" 2>/dev/null | grep -c '^cerrando-'; }
# plantar_marca <tarea>: deja a mano la marca de cierre de este repo (mismo nombre que el binario: sha256 de la raíz real)
plantar_marca() { python3 - "$ROMPELO_HOME" "$R" "$1" <<'PY'
import hashlib, json, os, sys
home, root, tarea = sys.argv[1:4]
os.makedirs(os.path.join(home, "state", "marcas"), exist_ok=True)
f = os.path.join(home, "state", "marcas", "cerrando-" + hashlib.sha256(os.path.realpath(root).encode()).hexdigest()[:16])
json.dump({"tarea": tarea, "quien": "prueba", "fecha": "hoy"}, open(f, "w"))
PY
}

echo "── fuera de la allowlist: PreToolUse y UserPromptSubmit callan y no ejecutan nada"
mkdir -p .rompelo && printf '{"id":"AJENO","estado":"abierta","scope_paths":["**"],"checks":["canario"],"toca_junta":false}' > .rompelo/task.json
espera_permite "commit en repo no alistado: silencio" a0 "git commit -m x"
out="$(prompt claude a0 "termina y sube esto")"; [ -z "$out" ] && ok "prompt de cierre en repo no alistado: silencio" || bad "prompt en repo no alistado" "$out"
[ ! -e "$CANARY" ] && ok "y no ejecutó el check del contrato ajeno" || bad "ejecutó un check de un repo no registrado"
rm -rf .rompelo

echo "── entrega (defecto sin config): Stop calla mientras se trabaja; PreToolUse deniega al entregar"
"$ROMPELO" init --id D1 --scope 'src/**' --check ok >/dev/null || exit 2
grep -q '"disparo"' .rompelo/task.json && bad "init sin --disparo no debe escribir el campo (manda la config)" || ok "init sin --disparo deja el campo fuera"
echo b > src/a.txt
espera_paso "Stop con el contrato sin cumplir y sin cierre declarado: silencio (entrega)" e1
espera_permite "PreToolUse con un comando corriente: silencio" e1 "ls -la"
espera_permite "PreToolUse con Edit: silencio" e1 "src/a.txt" claude Edit
espera_permite "PreToolUse con git status: silencio" e1 "git status"
espera_deny "git commit con el contrato sin cumplir: deny" e1 "git commit -m 'x'" claude "$R" 'check `ok` sin ejecutar'
out="$(pretool claude e1 Bash "git commit -m x")"; es_deny "$out" "Siguiente: rompelo check" && ok "la razón del deny trae la línea Siguiente:" || bad "deny sin Siguiente:" "$out"
espera_deny "cd x && git push: deny" e1 "cd src && git push origin main" claude "$R" 'sin ejecutar'
espera_deny "git -C dir commit: deny" e1 "git -C $R commit -am x" claude "$R" 'sin ejecutar'
espera_deny "gh pr create: deny" e1 "gh pr create --fill" claude "$R" 'sin ejecutar'
espera_deny "wrangler pages deploy: deny" e1 "pnpm exec wrangler pages deploy dist" claude "$R" 'sin ejecutar'
espera_deny "scripts/desplegar.sh: deny" e1 "bash scripts/desplegar.sh" claude "$R" 'sin ejecutar'
espera_deny "Codex recibe el mismo deny" e1 "git commit -m x" codex "$R" 'sin ejecutar'
espera_permite "git commit --dry-run no es entregar: silencio" e1 "git commit --dry-run"
espera_permite "una palabra suelta 'deploy' en un echo no es entregar" e1 "echo deploy pendiente"
echo "── compuestos y comillas (17-09-2026): se juzga por tramo, no por el texto entero"
espera_deny "un --dry-run en otro tramo no exime al push: deny" e1 "git push --dry-run && git push origin main" claude "$R" 'sin ejecutar'
espera_deny "bash -c 'git commit …' es un commit: deny" e1 "bash -c 'git commit -m x'" claude "$R" 'sin ejecutar'
espera_deny "eval \"git push\" es un push: deny" e1 'eval "git push origin main"' claude "$R" 'sin ejecutar'
out="$(pretool claude e1 Bash "pnpm test && git add -A && git commit -m x")"
es_deny "$out" 'sin ejecutar' && es_deny "$out" 'El comando lleva más tramos que el que entrega' && es_deny "$out" 'git commit -m x' && ok "compuesto: el deny dice que separe la preparación del commit y cita el tramo" || bad "deny de compuesto sin la explicación" "$out"
out="$(pretool claude e1 Bash "git commit -m x")"
es_deny "$out" 'sin ejecutar' && ! es_deny "$out" 'más tramos' && ok "un commit solo: deny sin hablar de tramos" || bad "commit solo habla de tramos" "$out"
[ "$(marcas)" = "0" ] && ok "el deny no declara cierre (sin marca)" || bad "el deny dejó marca de cierre"
"$ROMPELO" check >/dev/null || exit 2
espera_permite "contrato cumplido: el commit pasa" e1 "git commit -am x"
espera_paso "contrato cumplido: Stop calla" e1

echo "── cierre declarado por el usuario (UserPromptSubmit) → Stop juzga hasta cerrar"
echo c > src/a.txt
out="$(prompt claude e2 "termina y sube esto a main")"
tiene_contexto "$out" "D1" && tiene_contexto "$out" 'check `ok` se ejecutó sobre otro árbol' && tiene_contexto "$out" "Siguiente: rompelo check" && ok "prompt de cierre: contexto con la tarea y lo que falta" || bad "prompt de cierre sin contexto útil" "$out"
[ "$(marcas)" = "1" ] && ok "prompt de cierre deja la marca" || bad "prompt de cierre no dejó marca ($(marcas))"
espera_bloqueo "Stop tras el cierre declarado: bloquea" e2 'check `ok` se ejecutó sobre otro árbol'
out="$(prompt claude e2 "mira qué hay en src")"; [ -z "$out" ] && ok "un prompt corriente no añade contexto" || bad "prompt corriente habló" "$out"
[ "$(marcas)" = "1" ] && ok "y no quita la marca" || bad "un prompt corriente quitó la marca"
"$ROMPELO" check >/dev/null || exit 2
espera_paso "cumplido: Stop calla" e2
[ "$(marcas)" = "0" ] && ok "cumplido: la marca se retira" || bad "la marca sigue tras cumplir"
echo d > src/a.txt
espera_paso "cambio nuevo sin cierre declarado: silencio otra vez" e2

echo "── cierre declarado por `rompelo close` en rojo"
"$ROMPELO" close >/dev/null 2>&1 && bad "close debía fallar (check caducado)" || ok "close en rojo"
[ "$(marcas)" = "1" ] && ok "close en rojo deja la marca" || bad "close en rojo no dejó marca"
espera_bloqueo "Stop tras close en rojo: bloquea" e3 'check `ok` se ejecutó sobre otro árbol'
"$ROMPELO" check >/dev/null && "$ROMPELO" close >/dev/null || exit 2
[ "$(marcas)" = "0" ] && ok "close en verde retira la marca" || bad "close en verde dejó la marca"
espera_paso "cerrada: Stop calla" e3
espera_permite "cerrada: el push pasa" e3 "git push"
echo e > src/a.txt
espera_deny "cerrada pero con cambios después: el commit se deniega" e3 "git commit -am x" claude "$R" 'cambios posteriores al cierre'
espera_paso "cerrada con cambios y sin cierre declarado: Stop calla" e3

echo "── marca huérfana: un contrato cerrado no la sostiene, ni una marca de otra tarea (incidente 17-09-2026)"
out="$(prompt claude e5 "termina y sube esto")"
tiene_contexto "$out" "ya está cerrada" && tiene_contexto "$out" "rompelo init" && ok "prompt de cierre sobre contrato cerrado: dice que está cerrada y qué hacer" || bad "prompt de cierre sobre contrato cerrado" "$out"
[ "$(marcas)" = "0" ] && ok "y no deja marca sobre un contrato cerrado" || bad "dejó marca sobre un contrato cerrado ($(marcas))"
plantar_marca "D1"
[ "$(marcas)" = "1" ] || bad "no pude plantar la marca de prueba"
espera_paso "marca de una tarea cerrada (de otra sesión o de ayer): Stop calla" e5
[ "$(marcas)" = "0" ] && ok "y retira la marca huérfana" || bad "la marca huérfana sigue ($(marcas))"
"$ROMPELO" init --force --id D1B --scope 'src/**' --check ok >/dev/null || exit 2
echo huerfana > src/a.txt
plantar_marca "OTRA"
espera_paso "marca a nombre de otra tarea con el contrato abierto y sin cumplir: Stop calla" e5
[ "$(marcas)" = "0" ] && ok "y retira la marca de la otra tarea" || bad "la marca de la otra tarea sigue ($(marcas))"
out="$(prompt claude e5 "termina y sube esto")"; tiene_contexto "$out" "D1B" && ok "el cierre declarado de verdad sigue funcionando" || bad "prompt de cierre en D1B" "$out"
espera_bloqueo "y Stop bloquea con la marca legítima" e5 'check `ok` sin ejecutar'
"$ROMPELO" check >/dev/null && "$ROMPELO" close >/dev/null || exit 2
[ "$(marcas)" = "0" ] || bad "close en verde dejó la marca (D1B)"
"$ROMPELO" init --force --id D1 --scope 'src/**' --check ok >/dev/null || exit 2

echo "── prompt de cierre con el contrato ya cumplido: contexto tranquilo y sin marca"
"$ROMPELO" check >/dev/null && "$ROMPELO" close >/dev/null || exit 2
out="$(prompt claude e4 "haz el commit y el push")"
tiene_contexto "$out" "nada pendiente" && ok "contexto: nada pendiente" || bad "contexto con todo cumplido" "$out"
[ "$(marcas)" = "0" ] && ok "sin marca si no falta nada" || bad "marca con todo cumplido"

echo "── init --force (tarea nueva) retira la marca"
echo f > src/a.txt; "$ROMPELO" close >/dev/null 2>&1; [ "$(marcas)" = "1" ] || bad "no hay marca que retirar"
"$ROMPELO" init --force --id D2 --scope 'src/**' --check ok >/dev/null || exit 2
[ "$(marcas)" = "0" ] && ok "init --force retira la marca de la tarea anterior" || bad "init --force dejó la marca"

echo "── turno: por config y por contrato; valor inválido bloquea"
printf '{"defecto":"turno"}' > "$ROMPELO_HOME/config/disparo.json"
espera_bloqueo "config turno: Stop bloquea sin cierre declarado" t1 'check `ok` sin ejecutar'
espera_deny "config turno: el commit también se deniega" t1 "git commit -am x" claude "$R" 'sin ejecutar'
python3 - <<'PY'
import json;f='.rompelo/task.json';c=json.load(open(f));c['disparo']='entrega';json.dump(c,open(f,'w'))
PY
espera_paso "contrato disparo=entrega manda sobre la config turno" t1
python3 - <<'PY'
import json;f='.rompelo/task.json';c=json.load(open(f));c['disparo']='cuando-quiera';json.dump(c,open(f,'w'))
PY
espera_bloqueo "disparo inválido: fail-closed" t2 "disparo"
espera_deny "disparo inválido: el commit se deniega" t2 "git commit -am x" claude "$R" "disparo"
python3 - <<'PY'
import json;f='.rompelo/task.json';c=json.load(open(f));del c['disparo'];json.dump(c,open(f,'w'))
PY
printf '{"defecto":"entrega","por_repo":{"%s":{"defecto":"turno"}}}' "$R" > "$ROMPELO_HOME/config/disparo.json"
espera_bloqueo "por_repo turno manda sobre el defecto entrega" t3 'sin ejecutar'
printf '{"defecto":"entrega","entrega":["\\\\bmi-deploy\\\\b"],"cierre":["^\\\\s*venga, ciérralo\\\\b"]}' > "$ROMPELO_HOME/config/disparo.json"
espera_deny "patrón de entrega propio en la config" t4 "mi-deploy --prod" claude "$R" 'sin ejecutar'
espera_permite "con patrones propios, git commit ya no está en la lista" t4 "git commit -am x"
out="$(prompt claude t4 "termina")"; [ -z "$out" ] && ok "frase de cierre por defecto sustituida" || bad "frase por defecto seguía activa" "$out"
out="$(prompt claude t4 "venga, ciérralo")"; tiene_contexto "$out" "D2" && ok "frase de cierre propia" || bad "frase propia no reconocida" "$out"
rm -f "$ROMPELO_HOME/state/marcas"/cerrando-*
printf '{"defecto":"nunca"}' > "$ROMPELO_HOME/config/disparo.json"
espera_bloqueo "config con defecto inválido: fail-closed" t5 "disparo"
printf '{' > "$ROMPELO_HOME/config/disparo.json"
espera_bloqueo "config corrupta: fail-closed" t6 "disparo"
rm -f "$ROMPELO_HOME/config/disparo.json"

echo "── init --disparo escribe el campo y lo valida"
"$ROMPELO" init --force --id D3 --check ok --disparo turno >/dev/null || exit 2
grep -q '"disparo": "turno"' .rompelo/task.json && ok "init --disparo turno" || bad "init --disparo no escribió el campo"
"$ROMPELO" init --force --id D4 --check ok --disparo jamas >/dev/null 2>&1 && bad "init aceptó un disparo inválido" || ok "init rechaza un disparo inválido"

cd / && rm -rf "$T"
resumen
