#!/bin/bash
# Batería de la capa de observación (docs/observacion.md). Cada disparador se ve SALTAR con un
# flujo de eventos sintético y NO SALTAR con una sesión sana. ROMPELO_HOME desechable.
# Exit 0 = todo OK · 1 = hay fallos · 2 = no se pudo ejecutar.
ROMPELO="$HOME/rompelo/bin/rompelo"; [ -x "$ROMPELO" ] || { echo "no existe $ROMPELO"; exit 2; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✅ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ❌ $1"; [ -n "$2" ] && echo "     salida: $2"; }
T="$(mktemp -d)"; export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
export ROMPELO_HOME="$T/home"; mkdir -p "$ROMPELO_HOME/checks" "$ROMPELO_HOME/config"
printf '{"ok": {"argv": ["true"]}}' > "$ROMPELO_HOME/checks/registry.json"
R="$T/repo"; mkdir -p "$R/src" "$R/functions/api"; cd "$R" || exit 2
git init -q && git config user.email t@t && git config user.name t && echo a > src/a.txt && git add -A && git commit -qm base
"$ROMPELO" init --id O1 --check ok >/dev/null || exit 2
SES=0
nueva_sesion() { SES=$((SES+1)); SID="s$SES"; }
# bash <sid> <comando> <codigo> <stdout> <stderr>  → salida del hook
bash_ev() { python3 - "$ROMPELO" "$1" "$R" "$2" "$3" "$4" "$5" "${AGENTE:-claude}" <<'PY'
import json,subprocess,sys
r,sid,cwd,cmd,code,out,err,ag=sys.argv[1:9]
ev={"session_id":sid,"cwd":cwd,"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":cmd},"tool_response":{"stdout":out,"stderr":err,"exit_code":int(code)}}
p=subprocess.run([r,"observe",ag],input=json.dumps(ev),capture_output=True,text=True); sys.stdout.write(p.stdout)
PY
}
edit_ev() { python3 - "$ROMPELO" "$1" "$R" "$2" "${AGENTE:-claude}" <<'PY'
import json,subprocess,sys
r,sid,cwd,path,ag=sys.argv[1:6]
ev={"session_id":sid,"cwd":cwd,"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":path,"old_string":"a","new_string":"b"},"tool_response":{"ok":True}}
p=subprocess.run([r,"observe",ag],input=json.dumps(ev),capture_output=True,text=True); sys.stdout.write(p.stdout)
PY
}
nivel() { python3 -c "import json,glob;d=[json.load(open(f)) for f in glob.glob('$ROMPELO_HOME/state/repos/*.json')];print(d[0].get('nivel',0) if d else 0)"; }
reset_estado() { rm -rf "$ROMPELO_HOME/state"; }
hook() { printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false}' "$1" "$R" | "$ROMPELO" hook claude; }

echo "── control negativo: sesión sana no dispara nada"
nueva_sesion; out=""
out+="$(bash_ev $SID 'pnpm test' 0 '12 passed' '')"; out+="$(bash_ev $SID 'git status' 0 'clean' '')"; out+="$(edit_ev $SID src/a.txt)"; out+="$(bash_ev $SID 'pnpm test' 0 '12 passed' '')"; out+="$(bash_ev $SID 'git commit -m x' 0 'ok' '')"
[ -z "$out" ] && [ "$(nivel)" = 0 ] && ok "cinco eventos sanos: silencio y nivel 0" || bad "sesión sana" "$out"
[ -f "$ROMPELO_HOME/state/sesiones/claude-$SID.jsonl" ] && ok "el libro de la sesión existe" || bad "libro"

echo "── privacidad: el libro no guarda texto de comandos ni salidas"
bash_ev $SID 'curl -H "Key: SECRETO-XYZ-123" https://x' 0 'RESPUESTA-SECRETA' '' >/dev/null
! grep -q 'SECRETO-XYZ\|RESPUESTA-SECRETA' "$ROMPELO_HOME/state/sesiones/claude-$SID.jsonl" && ok "ni el comando ni la salida están en el libro" || bad "fuga al libro"
grep -q '"prog": "curl"' "$ROMPELO_HOME/state/sesiones/claude-$SID.jsonl" && ok "sí guarda el programa" || bad "prog"

echo "── D2 firma repetida: el mismo error dos veces con números distintos"
reset_estado; nueva_sesion
o1="$(bash_ev $SID 'pnpm test' 1 '' 'Error: expected 200 got 500 at line 41')"
[ -z "$o1" ] && ok "primer fallo: todavía no salta" || bad "saltó a la primera" "$o1"
o2="$(bash_ev $SID 'pnpm test' 1 '' 'Error: expected 200 got 503 at line 97')"
printf '%s' "$o2" | grep -q 'el mismo error 2 veces' && printf '%s' "$o2" | grep -q additionalContext && ok "segundo fallo con la misma firma: aviso" || bad "firma repetida" "$o2"
[ "$(nivel)" = 2 ] && ok "nivel del repo = 2" || bad "nivel" "$(nivel)"
o3="$(bash_ev $SID 'pnpm test' 1 '' 'Error: expected 200 got 500 at line 41')"
[ -z "$o3" ] && ok "tercer fallo: el aviso no se repite en la sesión" || bad "aviso repetido" "$o3"
o4="$(bash_ev $SID 'git push' 1 '' 'fatal: could not read from remote')"
[ -z "$o4" ] && ok "otro error distinto, una vez: silencio" || bad "otro error" "$o4"

echo "── el gate a nivel 2 exige segunda pasada"
out="$(hook $SID)"; printf '%s' "$out" | grep -q 'segunda_pasada' && ok "sin segunda_pasada: bloquea" || bad "segunda pasada" "$out"
python3 - <<'PY'
import json;f='.rompelo/task.json';c=json.load(open(f));c['segunda_pasada']='revisado el diff entero; nada nuevo';json.dump(c,open(f,'w'))
PY
"$ROMPELO" check >/dev/null; out="$(hook $SID)"; [ -z "$out" ] && ok "con segunda_pasada y checks: silencio" || bad "nivel 2 cumplido" "$out"

echo "── D1 perfil junta manda sobre el contrato"
reset_estado; nueva_sesion
o="$(edit_ev $SID functions/api/newsletter.ts)"; printf '%s' "$o" | grep -q 'toca `junta`' && ok "editar functions/api/ dispara el perfil junta" || bad "perfil junta" "$o"
out="$(hook $SID)"; printf '%s' "$out" | grep -q 'perfil `junta`' && ok "contrato con toca_junta:false, pero el gate exige cruce" || bad "junta manda" "$out"
"$ROMPELO" cruce -- true >/dev/null; "$ROMPELO" check >/dev/null; out="$(hook $SID)"; [ -z "$out" ] && ok "con cruce real: silencio" || bad "junta cumplida" "$out"

echo "── D1 no lee prosa: un heredoc que ESCRIBE sobre functions/api no es tocar functions/api (falso positivo en vivo, 05-09)"
reset_estado; nueva_sesion
o="$(bash_ev $SID $'cat > docs/x.md <<\'EOF\'\nla junta vive en functions/api/ y usa process.env\nEOF' 0 '' '')"
[ -z "$o" ] && [ "$(nivel)" = 0 ] && ok "heredoc con palabras de riesgo: silencio" || bad "heredoc" "$o"
o="$(bash_ev $SID 'wrangler pages deploy dist' 0 'ok' '')"; printf '%s' "$o" | grep -q 'toca `despliegue`' && ok "el mismo texto como comando sí dispara" || bad "comando real" "$o"

echo "── D1 perfil exterior exige afirmaciones"
reset_estado; nueva_sesion
o="$(bash_ev $SID 'pnpm add left-pad' 0 'added 1 package' '')"; printf '%s' "$o" | grep -q 'toca `exterior`' && ok "pnpm add dispara el perfil exterior" || bad "perfil exterior" "$o"
out="$(hook $SID)"; printf '%s' "$out" | grep -q 'ninguna afirmación' && ok "sin afirmaciones: bloquea" || bad "exterior" "$out"
python3 - <<'PY'
import json;f='.rompelo/task.json';c=json.load(open(f));c['afirmaciones']=[{"texto":"left-pad es MIT","estado":"verificado","fuente":"npmjs.com/package/left-pad","cita":"License MIT"}];json.dump(c,open(f,'w'))
PY
"$ROMPELO" check >/dev/null; out="$(hook $SID)"; [ -z "$out" ] && ok "con afirmación verificada: silencio" || bad "exterior cumplido" "$out"

echo "── D2 ediciones sin verde (thrashing) y su reinicio con un check verde"
reset_estado; nueva_sesion
for i in 1 2 3; do edit_ev $SID src/a.txt >/dev/null; done
o="$(edit_ev $SID src/a.txt)"; printf '%s' "$o" | grep -q 'editado 4 veces' && ok "cuarta edición sin verde: aviso" || bad "thrashing" "$o"
reset_estado; nueva_sesion
for i in 1 2 3; do edit_ev $SID src/a.txt >/dev/null; done
bash_ev $SID 'pnpm test' 0 '12 passed' '' >/dev/null
o="$(edit_ev $SID src/a.txt)"; [ -z "$o" ] && ok "un check verde entre medias reinicia el contador" || bad "reinicio" "$o"

echo "── D2 verde ambiguo: 0 sin salida dos veces"
reset_estado; nueva_sesion
bash_ev $SID 'grep -rn foo src' 0 '' '' >/dev/null
o="$(bash_ev $SID 'grep -rn bar src' 0 '' '')"; printf '%s' "$o" | grep -q 'sin salida' && ok "dos grep vacíos: aviso" || bad "verde ambiguo" "$o"

echo "── umbrales: se leen de config/observacion.json (mutación 1 y 99)"
reset_estado; nueva_sesion; printf '{"firma_repetida": 1}' > "$ROMPELO_HOME/config/observacion.json"
o="$(bash_ev $SID 'pnpm test' 1 '' 'Error: boom 1')"; printf '%s' "$o" | grep -q 'mismo error 1 veces' && ok "umbral 1: salta a la primera" || bad "umbral 1" "$o"
reset_estado; nueva_sesion; printf '{"firma_repetida": 99, "check_en_rojo": 99}' > "$ROMPELO_HOME/config/observacion.json"
bash_ev $SID 'pnpm test' 1 '' 'Error: boom 1' >/dev/null; o="$(bash_ev $SID 'pnpm test' 1 '' 'Error: boom 2')"; [ -z "$o" ] && ok "umbral 99: no salta" || bad "umbral 99" "$o"
rm "$ROMPELO_HOME/config/observacion.json"

echo "── paridad Claude/Codex sobre el mismo flujo"
reset_estado; nueva_sesion
A="$(bash_ev $SID 'pnpm test' 1 '' 'Error: x 1' ; bash_ev $SID 'pnpm test' 1 '' 'Error: x 2')"
reset_estado; nueva_sesion
B="$(AGENTE=codex bash_ev $SID 'pnpm test' 1 '' 'Error: x 1' ; AGENTE=codex bash_ev $SID 'pnpm test' 1 '' 'Error: x 2')"
[ -n "$A" ] && [ "$A" = "$B" ] && ok "mismo aviso por los dos adaptadores" || bad "paridad" "A=$A B=$B"

echo "── permiso y nivel"
"$ROMPELO" permiso firma-repetida si --recordar | grep -q 'nivel del repo: 3' && ok "permiso sí sube a nivel 3 y se recuerda" || bad "permiso"
grep -q '"recordar": true' "$ROMPELO_HOME/config/permisos.json" && ok "permisos.json guarda la respuesta" || bad "permisos.json"
"$ROMPELO" nivel bajar --motivo "prueba" | grep -q 'nivel 0' && ok "nivel bajar deja 0 con motivo" || bad "nivel bajar"

echo "── repo fuera de la allowlist: se observa pero no se escala"
reset_estado; nueva_sesion; R2="$T/ajeno"; mkdir -p "$R2"; git -C "$R2" init -q
o="$(python3 - "$ROMPELO" $SID "$R2" <<'PY'
import json,subprocess,sys
r,sid,cwd=sys.argv[1:4]
for i in (1,2):
    ev={"session_id":sid,"cwd":cwd,"tool_name":"Bash","tool_input":{"command":"pnpm test"},"tool_response":{"stderr":"Error: y","exit_code":1}}
    p=subprocess.run([r,"observe","claude"],input=json.dumps(ev),capture_output=True,text=True); sys.stdout.write(p.stdout)
PY
)"; [ -z "$o" ] && [ ! -d "$ROMPELO_HOME/state/repos" ] && ok "sin aviso ni estado para un repo no alistado" || bad "ajeno" "$o"

echo "── entrada malformada: silencio y rastro en observe.err"
printf 'basura' | "$ROMPELO" observe claude; rc=$?; [ $rc -eq 0 ] && [ -f "$ROMPELO_HOME/state/observe.err" ] && ok "no rompe la sesión y deja rastro" || bad "malformado" "rc=$rc"

echo; echo "PASS=$PASS FAIL=$FAIL"; rm -rf "$T"; [ "$FAIL" -eq 0 ]
