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
# Claude Code real: PostToolUse solo llega en éxito y tool_response es {stdout, stderr, interrupted, isImage}, SIN código.
claude_ok_ev() { python3 - "$ROMPELO" "$1" "$R" "$2" "$3" "$4" <<'PY'
import json,subprocess,sys
r,sid,cwd,cmd,out,err=sys.argv[1:7]
ev={"session_id":sid,"cwd":cwd,"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":cmd},"tool_response":{"stdout":out,"stderr":err,"interrupted":False,"isImage":False}}
p=subprocess.run([r,"observe","claude"],input=json.dumps(ev),capture_output=True,text=True); sys.stdout.write(p.stdout)
PY
}
# Claude Code real: un comando que sale con != 0 llega por PostToolUseFailure con `error` = "Exit code N\n<salida>".
fail_ev() { python3 - "$ROMPELO" "$1" "$R" "$2" "$3" "${4:-false}" <<'PY'
import json,subprocess,sys
r,sid,cwd,cmd,err,intr=sys.argv[1:7]
ev={"session_id":sid,"cwd":cwd,"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":cmd},"error":err,"is_interrupt":intr=="true"}
p=subprocess.run([r,"observe","claude"],input=json.dumps(ev),capture_output=True,text=True); sys.stdout.write(p.stdout)
PY
}
ultimo_codigo() { tail -1 "$ROMPELO_HOME/state/sesiones/claude-$SID.jsonl" | python3 -c "import json,sys;print(json.load(sys.stdin).get('codigo'))"; }
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
o="$(edit_ev $SID functions/api/newsletter.ts)"; [ -z "$o" ] && [ "$(nivel)" = 0 ] && ok "primer toque a functions/api/: todavía silencio (decisión de José, 05-09: dos toques)" || bad "primer toque junta" "$o"
o="$(edit_ev $SID functions/api/newsletter.ts)"; printf '%s' "$o" | grep -q 'toca `junta`' && ok "segundo toque a functions/api/: dispara el perfil junta" || bad "perfil junta" "$o"
out="$(hook $SID)"; printf '%s' "$out" | grep -q 'perfil `junta`' && ok "contrato con toca_junta:false, pero el gate exige cruce" || bad "junta manda" "$out"
"$ROMPELO" cruce -- true >/dev/null; "$ROMPELO" check >/dev/null; out="$(hook $SID)"; [ -z "$out" ] && ok "con cruce real: silencio" || bad "junta cumplida" "$out"

echo "── D1 no lee prosa: un heredoc que ESCRIBE sobre functions/api no es tocar functions/api (falso positivo en vivo, 05-09)"
reset_estado; nueva_sesion
o="$(bash_ev $SID $'cat > docs/x.md <<\'EOF\'\nla junta vive en functions/api/ y usa process.env\nEOF' 0 '' '')"
[ -z "$o" ] && [ "$(nivel)" = 0 ] && ok "heredoc con palabras de riesgo: silencio" || bad "heredoc" "$o"
bash_ev $SID 'wrangler pages deploy dist' 0 'ok' '' >/dev/null
o="$(bash_ev $SID 'wrangler pages deploy dist' 0 'ok' '')"; printf '%s' "$o" | grep -q 'toca `despliegue`' && ok "el mismo texto como comando, dos veces, sí dispara" || bad "comando real" "$o"

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
for i in 1 2 3; do edit_ev $SID src/a.ts >/dev/null; done
o="$(edit_ev $SID src/a.ts)"; printf '%s' "$o" | grep -q 'editado 4 veces' && ok "cuarta edición sin verde: aviso" || bad "thrashing" "$o"
reset_estado; nueva_sesion
for i in 1 2 3; do edit_ev $SID src/a.ts >/dev/null; done
bash_ev $SID 'pnpm test' 0 '12 passed' '' >/dev/null
o="$(edit_ev $SID src/a.ts)"; [ -z "$o" ] && ok "un check verde entre medias reinicia el contador" || bad "reinicio" "$o"

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

echo "── Claude Code de verdad: el fallo llega por PostToolUseFailure, no por PostToolUse (INC-0031)"
reset_estado; nueva_sesion
o1="$(fail_ev $SID 'pnpm test' $'Exit code 1\nError: expected 200 got 500 at line 41')"
[ -z "$o1" ] && [ "$(ultimo_codigo)" = 1 ] && ok "primer fallo: código 1 leído de la primera línea de error, sin aviso" || bad "PostToolUseFailure 1" "$o1 codigo=$(ultimo_codigo)"
o2="$(fail_ev $SID 'pnpm test' $'Exit code 1\nError: expected 200 got 503 at line 97')"
printf '%s' "$o2" | grep -q 'mismo error 2 veces' && printf '%s' "$o2" | grep -q 'en rojo 2 veces' && ok "segundo fallo: firma repetida y check en rojo" || bad "PostToolUseFailure 2" "$o2"
o3="$(fail_ev $SID 'sleep 999' 'Command timed out after 2m 0s' true)"
[ -z "$o3" ] && [ "$(ultimo_codigo)" = None ] && ok "interrupción sin línea de código: código desconocido, sin aviso" || bad "interrupción" "$o3 codigo=$(ultimo_codigo)"

echo "── ruido del harness: «Shell cwd was reset» en stderr no es un error ni un verde ambiguo (INC-0032)"
reset_estado; nueva_sesion
for i in 1 2 3; do o="$(claude_ok_ev $SID 'cd /tmp && git status' 'clean' 'Shell cwd was reset to /Users/x')"; done
[ -z "$o" ] && [ "$(nivel)" = 0 ] && ok "tres comandos con el aviso de cwd: silencio y nivel 0" || bad "ruido cwd" "$o nivel=$(nivel)"
tail -1 "$ROMPELO_HOME/state/sesiones/claude-$SID.jsonl" | grep -q '"firma": null' && ok "un comando que salió bien no lleva firma de error" || bad "firma en éxito" "$(tail -1 "$ROMPELO_HOME/state/sesiones/claude-$SID.jsonl")"

echo "── el código de salida no se lee del texto de la salida (INC-0032)"
nueva_sesion
claude_ok_ev $SID 'curl -s https://x' 'HTTP exit code: 200 ok' '' >/dev/null
[ "$(ultimo_codigo)" = 0 ] && ok "«exit code: 200» en stdout no es un código de salida" || bad "código desde stdout" "codigo=$(ultimo_codigo)"
claude_ok_ev $SID 'cat doc.md' $'la doc dice: exits with code 2\nExit code 1 aparece en la doc' '' >/dev/null
[ "$(ultimo_codigo)" = 0 ] && ok "«Exit code 1» dentro de un documento tampoco" || bad "código desde doc" "codigo=$(ultimo_codigo)"

echo "── control negativo con sesiones reales (05-09, 6 sesiones, 2.500 eventos): lo que saltó y no debía"
reset_estado; nueva_sesion
for i in 1 2; do o="$(claude_ok_ev $SID 'git add -A' '' '')"; done
[ -z "$o" ] && [ "$(nivel)" = 0 ] && ok "dos «git add» sin salida: silencio (callar es su comportamiento normal, no «no miré»)" || bad "git add silencioso" "$o"
claude_ok_ev $SID 'cd /tmp && grep -rn foo src' '' '' >/dev/null
tail -1 "$ROMPELO_HOME/state/sesiones/claude-$SID.jsonl" | grep -q '"prog": "grep"' && ok "«cd x && grep …» se anota como grep, no como cd" || bad "prog tras cd" "$(tail -1 "$ROMPELO_HOME/state/sesiones/claude-$SID.jsonl")"
reset_estado; nueva_sesion
for i in 1 2 3 4; do o="$(edit_ev $SID docs/notas.md)"; done
[ -z "$o" ] && ok "cuatro ediciones de un .md: silencio (documentación no necesita un check verde)" || bad "md" "$o"
reset_estado; nueva_sesion
for i in 1 2 3 4; do o="$(edit_ev $SID /tmp/fuera-del-repo.ts)"; done
[ -z "$o" ] && ok "cuatro ediciones de un fichero fuera del repo: silencio" || bad "fuera del repo" "$o"
reset_estado; nueva_sesion
for i in 1 2 3; do edit_ev $SID src/a.ts >/dev/null; done
claude_ok_ev $SID 'pnpm run check' '0 errors' '' >/dev/null
o="$(edit_ev $SID src/a.ts)"; [ -z "$o" ] && ok "«pnpm run check» en verde cuenta como check y reinicia el contador" || bad "pnpm run check" "$o"
reset_estado; nueva_sesion
for i in 1 2 3; do edit_ev $SID src/a.ts >/dev/null; done
o="$(edit_ev $SID src/a.ts)"; printf '%s' "$o" | grep -q 'editado 4 veces' && ok "y sin ese check, la cuarta edición de código sí avisa (control positivo)" || bad "thrashing código" "$o"
reset_estado; nueva_sesion
o="$(claude_ok_ev $SID 'grep -rn token src' 'src/a.ts:1: token' '')"
[ -z "$o" ] && ok "buscar la palabra token no es tocar auth (lectura)" || bad "grep auth" "$o"
o="$(claude_ok_ev $SID 'grep -i token src/a.ts' 'src/a.ts:1: token' '')"
[ -z "$o" ] && ok "«grep -i» sigue siendo lectura (la -i de sed es otra)" || bad "grep -i" "$o"
o="$(claude_ok_ev $SID 'sed -i s/x/y/ src/auth/session.ts' '' '')"
[ -z "$o" ] && o="$(claude_ok_ev $SID 'sed -i s/x/y/ src/auth/session.ts' '' '')"
printf '%s' "$o" | grep -q 'toca `auth`' && ok "escribir en src/auth dos veces sí dispara" || bad "sed auth" "$o"

echo "── toques por perfil: se leen de config/observacion.json (mutación a 1 y a 3)"
reset_estado; nueva_sesion; printf '{"toques_perfil": {"_defecto": 1}}' > "$ROMPELO_HOME/config/observacion.json"
o="$(edit_ev $SID functions/api/x.ts)"; printf '%s' "$o" | grep -q 'toca `junta`' && ok "umbral 1: salta al primer toque" || bad "toques 1" "$o"
reset_estado; nueva_sesion; printf '{"toques_perfil": {"_defecto": 3}}' > "$ROMPELO_HOME/config/observacion.json"
edit_ev $SID functions/api/x.ts >/dev/null; o="$(edit_ev $SID functions/api/x.ts)"; [ -z "$o" ] && ok "umbral 3: el segundo toque calla" || bad "toques 3" "$o"
o="$(edit_ev $SID functions/api/x.ts)"; printf '%s' "$o" | grep -q 'toca `junta`' && ok "umbral 3: el tercero salta" || bad "toques 3 tercero" "$o"
reset_estado; nueva_sesion; printf '{"toques_perfil": {"_defecto": 2, "exterior": 1}}' > "$ROMPELO_HOME/config/observacion.json"
o="$(bash_ev $SID 'pnpm add left-pad' 0 'added 1 package' '')"; printf '%s' "$o" | grep -q 'toca `exterior`' && ok "excepción por perfil: exterior a un toque" || bad "excepción exterior" "$o"
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
