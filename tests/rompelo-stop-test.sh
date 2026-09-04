#!/bin/bash
# Pruebas del gate rompelo (v2: JSON, registro de checks, allowlist). Cada caso se ve
# FALLAR (bloquea con el motivo correcto) y PASAR (verde de partida y vuelta a verde).
# Usa un ROMPELO_HOME desechable: registro y allowlist propios, nunca los reales.
# Exit 0 = todo OK · 1 = hay fallos · 2 = no se pudo ejecutar.
ASSURE="$HOME/rompelo/bin/rompelo"
[ -x "$ASSURE" ] || { echo "no existe $ASSURE"; exit 2; }
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ❌ $1"; [ -n "$2" ] && echo "     salida: $2"; }
T="$(mktemp -d)"; export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
export ROMPELO_HOME="$T/home"; mkdir -p "$ROMPELO_HOME/checks" "$ROMPELO_HOME/config"
CANARY="$T/canario"
cat > "$ROMPELO_HOME/checks/registry.json" <<J
{"ok": {"argv": ["true"]}, "ko": {"argv": ["false"]}, "hay-a": {"argv": ["test", "-f", "src/a.txt"]},
 "canario": {"argv": ["touch", "$CANARY"]},
 "mudo": {"argv": ["true"], "min_lineas": 1}, "habla": {"argv": ["echo", "1 visto"], "min_lineas": 1}}
J
R="$T/repo"; mkdir -p "$R"; cd "$R" || exit 2
git init -q && git config user.email t@t && git config user.name t
mkdir -p src tests && echo a > src/a.txt && echo t > tests/a.test.txt && git add -A && git commit -qm base
hook() { printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$2" "$3" | "$ASSURE" hook "$1"; }
espera_bloqueo() { local out; out="$(hook claude "$2" "$R")"
  if printf '%s' "$out" | grep -q '"decision": *"block"' && printf '%s' "$out" | grep -qF -- "$3"; then ok "$1"; else bad "$1 (esperaba bloqueo con «$3»)" "$out"; fi; }
espera_paso() { local out; out="$(hook claude "$2" "$R")"; [ -z "$out" ] && ok "$1" || bad "$1 (esperaba silencio)" "$out"; }
contrato() { python3 - "$@" <<'PY'
import json,sys;f='.rompelo/task.json';c=json.load(open(f))
for kv in sys.argv[1:]:
    k,v=kv.split('=',1); c[k]=json.loads(v)
json.dump(c,open(f,'w'),indent=1,ensure_ascii=False)
PY
}

echo "── allowlist: repo no registrado con .rompelo/ ajeno → silencio y NADA se ejecuta"
mkdir -p .rompelo && printf '{"id":"AJENO","estado":"abierta","scope_paths":["**"],"checks":["canario"],"toca_junta":false}' > .rompelo/task.json
espera_paso "repo fuera de la allowlist: silencio" s0
[ ! -e "$CANARY" ] && ok "y no ejecutó el check del contrato ajeno" || bad "ejecutó un check de un repo no registrado"
out="$(hook claude s0 "$T")"; [ -z "$out" ] && ok "cwd sin git: silencio" || bad "cwd sin git" "$out"
rm -rf .rompelo

echo "── init: rechaza ids fuera del registro y no ejecuta cadenas"
"$ASSURE" init --id X --check 'true; touch '"$CANARY" >/dev/null 2>&1 && bad "init aceptó una cadena de comando" || ok "init rechaza un check que no es id del registro"
[ ! -e "$CANARY" ] && ok "la cadena no se ejecutó" || bad "la cadena SE EJECUTÓ"
"$ASSURE" init --id T1 --scope 'src/**' --scope 'tests/**' --check hay-a --check ok --junta --prueba >/dev/null || exit 2
grep -q "$R" "$ROMPELO_HOME/config/repos.json" && ok "init apunta el repo en la allowlist" || bad "allowlist"
[ "$(cat .rompelo/evidence/.gitignore)" = "*" ] && [ "$(git status --porcelain)" = "?? .rompelo/" ] && ok "la evidencia se autoignora; solo el contrato queda por commitear" || bad "gitignore" "$(git status --porcelain)"
contrato 'hallazgos=[{"id":"H1","texto":"x","disposicion":"rechazado"}]'

echo "── contrato inválido (fail-closed)"
cp .rompelo/task.json "$T/task.bak"
printf '{"id": [' > .rompelo/task.json;          espera_bloqueo "JSON malformado bloquea" s1 "no pudo evaluar"
printf '{"id":"T1"}' > .rompelo/task.json;        espera_bloqueo "campo obligatorio ausente bloquea" s1b "claves obligatorias"
cp "$T/task.bak" .rompelo/task.json
contrato 'scope_paths=["../fuera/**"]';           espera_bloqueo "scope con ../ se rechaza" s1c "sin '..'"
contrato 'scope_paths=["/etc/**"]';               espera_bloqueo "scope absoluto se rechaza" s1d "sin '..'"
cp "$T/task.bak" .rompelo/task.json
contrato 'checks=["ok","true; touch '"$CANARY"'"]'; espera_bloqueo "check con inyección se rechaza" s1e "ids [a-z0-9._-]"
[ ! -e "$CANARY" ] && ok "y no se ejecutó" || bad "SE EJECUTÓ la inyección"
contrato 'checks=["ok","noexiste"]';              espera_bloqueo "check desconocido bloquea sin ejecutar" s1f "no está en el registro"
"$ASSURE" check >/dev/null 2>&1; [ $? -ne 0 ] && ok "rompelo check se niega con id desconocido" || bad "check ejecutó con id desconocido"
cp "$T/task.bak" .rompelo/task.json
rm -f .rompelo/task.json;                           espera_bloqueo "contrato ausente en repo registrado bloquea" s1g "no pudo evaluar"
cp "$T/task.bak" .rompelo/task.json

echo "── evidencia"
espera_bloqueo "sin evidencia: bloquea por check" s2 "check \`hay-a\` sin ejecutar"
espera_bloqueo "sin evidencia: bloquea por junta" s2b "no hay cruce real"
"$ASSURE" check >/dev/null && ok "rompelo check en verde" || bad "rompelo check"
espera_bloqueo "checks hechos, falta el cruce" s2c "no hay cruce real"
"$ASSURE" cruce --nota "p" -- true >/dev/null && ok "rompelo cruce por argv OK" || bad "cruce"

echo "── VERDE DE PARTIDA"
espera_paso "todo cumplido: deja parar" s3
"$ASSURE" verify >/dev/null && ok "rompelo verify → 0" || bad "verify debía dar 0"

echo "── mutación A: cambio de código sin prueba; evidencia obsoleta"
echo b >> src/a.txt; grep -q b src/a.txt && ok "mutación A aplicada" || bad "mutación A"
espera_bloqueo "evidencia sobre otro árbol" s4 "sobre otro árbol"
espera_bloqueo "cruce anterior al cambio" s4b "anterior al último cambio"
"$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null
espera_bloqueo "código sin prueba" s4c "ninguna prueba"
echo t2 >> tests/a.test.txt; "$ASSURE" check >/dev/null; "$ASSURE" cruce --id ok >/dev/null
espera_paso "con prueba en el diff y cruce por id: deja parar" s4d

echo "── mutación B: un check en rojo"
contrato 'checks=["hay-a","ko"]'; grep -q '"ko"' .rompelo/task.json && ok "mutación B aplicada" || bad "mutación B"
"$ASSURE" check >/dev/null 2>&1; [ $? -eq 1 ] && ok "rompelo check devuelve 1" || bad "check debía devolver 1"
espera_bloqueo "check fallido bloquea" s5 "FALLÓ con código 1"
contrato 'checks=["hay-a","ok"]'; "$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null
espera_paso "deshecha B: verde" s5b

echo "── mutación C: hallazgo sin disposición"
contrato 'hallazgos=[{"id":"H1","disposicion":"rechazado"},{"id":"H2","texto":"y"}]'
espera_bloqueo "hallazgo sin disposición" s6 "hallazgo sin disposición: H2"
contrato 'hallazgos=[{"id":"H1","disposicion":"rechazado"},{"id":"H2","disposicion":"aceptado"}]'
espera_paso "deshecha C: verde" s6b

echo "── mutación D: fichero fuera de scope"
mkdir -p docs && echo x > docs/x.md
espera_bloqueo "fuera de scope" s7 "fuera de scope_paths: docs/x.md"
rm docs/x.md && rmdir docs; "$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null
espera_paso "deshecha D: verde" s7b

echo "── afirmaciones con estado (criterio de ir a la fuente)"
contrato 'toca_exterior=true'
espera_bloqueo "toca_exterior sin afirmaciones bloquea" s7a "ninguna afirmación con estado"
contrato 'afirmaciones=[{"texto":"la capa gratuita permite uso comercial","estado":"verificado","fuente":"https://x/pricing"}]'
espera_bloqueo "verificado sin cita bloquea" s7b2 "sin fuente de primera mano o sin cita"
contrato 'afirmaciones=[{"texto":"a","estado":"seguro"}]'
espera_bloqueo "estado inventado bloquea" s7b3 "sin estado válido"
contrato 'afirmaciones=[{"texto":"a","estado":"derivado"}]'
espera_bloqueo "derivado sin origen bloquea" s7b4 "sin decir de qué"
contrato 'afirmaciones=[{"texto":"a","estado":"no_verificado"}]'
espera_bloqueo "no_verificado sin qué falta bloquea" s7b5 "sin decir qué falta"
contrato 'afirmaciones=[{"texto":"a","estado":"verificado","fuente":"doc oficial","cita":"frase literal"},{"texto":"b","estado":"derivado","de":"a"},{"texto":"c","estado":"no_verificado","falta":"no hay acceso al panel"}]'
espera_paso "tres estados bien formados: verde" s7b6
contrato 'toca_exterior=false' 'afirmaciones=[]'

echo "── salida mínima: un 0 sin salida no es verde (INC-0018/0019)"
contrato 'checks=["hay-a","ok","mudo"]'; "$ASSURE" check >/dev/null
espera_bloqueo "check mudo con min_lineas bloquea" s7m "sin la salida mínima"
contrato 'checks=["hay-a","ok","habla"]'; "$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null
espera_paso "check que informa de lo visto: verde" s7n
contrato 'checks=["hay-a","ok"]'; "$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null

echo "── registry.local.json se fusiona y gana"
printf '{"local-ok": {"argv": ["true"]}, "ok": {"argv": ["true"], "descripcion": "sobrescrito"}}' > "$ROMPELO_HOME/checks/registry.local.json"
contrato 'checks=["hay-a","ok","local-ok"]'; "$ASSURE" check >/dev/null && ok "check local del overlay se ejecuta" || bad "overlay"
"$ASSURE" cruce -- true >/dev/null; espera_paso "overlay: verde" s7o
rm "$ROMPELO_HOME/checks/registry.local.json"; contrato 'checks=["hay-a","ok"]'; "$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null

echo "── registro cambiado tras ejecutar"
python3 - "$ROMPELO_HOME/checks/registry.json" <<'PY'
import json,sys;f=sys.argv[1];r=json.load(open(f));r['ok']={'argv':['true','--otro']};json.dump(r,open(f,'w'))
PY
espera_bloqueo "el argv del registro cambió después de la evidencia" s7c "cambió en el registro"
python3 - "$ROMPELO_HOME/checks/registry.json" <<'PY'
import json,sys;f=sys.argv[1];r=json.load(open(f));r['ok']={'argv':['true']};json.dump(r,open(f,'w'))
PY
espera_paso "registro restaurado: verde" s7d

echo "── tope de bloqueos (3) y luego aviso sin bloquear"
echo c >> src/a.txt
for i in 1 2 3; do out="$(hook claude s9 "$R")"; printf '%s' "$out" | grep -q "($i/3)" && ok "bloqueo $i/3" || bad "bloqueo $i" "$out"; done
out="$(hook claude s9 "$R")"; printf '%s' "$out" | grep -q systemMessage && ! printf '%s' "$out" | grep -q '"decision"' && ok "4º intento: systemMessage, sin bloqueo" || bad "tope" "$out"

echo "── paridad Claude/Codex: mismos motivos"
A="$(hook claude p1 "$R" | python3 -c 'import json,sys;print(json.load(sys.stdin)["reason"].split(chr(10))[1:])')"
B="$(hook codex  p2 "$R" | python3 -c 'import json,sys;print(json.load(sys.stdin)["reason"].split(chr(10))[1:])')"
[ -n "$A" ] && [ "$A" = "$B" ] && ok "claude y codex devuelven los mismos motivos" || bad "paridad" "claude=$A codex=$B"
"$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null

echo "── close, commit del mismo contenido, reapertura"
"$ASSURE" close >/dev/null && grep -q '"estado": "cerrada"' .rompelo/task.json && ok "close deja estado cerrada" || bad "close"
espera_paso "cerrada y sin cambios: silencio" s10
git add -A >/dev/null && git commit -qm "mismo contenido" && ok "commit hecho" || bad "commit"
espera_paso "cerrada y commit del mismo contenido: sigue en silencio" s10c
echo d >> src/a.txt
espera_bloqueo "cerrada con cambios posteriores" s10b "cambios posteriores al cierre"
"$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null
"$ASSURE" close >/dev/null && ok "se puede volver a cerrar tras rehacer la evidencia" || bad "re-close"
espera_paso "re-cerrada: silencio" s10d

echo "── verify --ci: juez independiente, no se cree la evidencia guardada"
contrato 'checks=["hay-a","ok"]' 'toca_junta=true'
rm -f .rompelo/evidence/T1/check-*.json
"$ASSURE" verify --ci >"$T/ci.txt" 2>&1; rc=$?; [ $rc -eq 0 ] && grep -q 'ADVERTENCIA' "$T/ci.txt" && ok "--ci ejecuta los checks él mismo y deja la junta como advertencia" || bad "--ci" "rc=$rc $(cat "$T/ci.txt")"
"$ASSURE" verify --ci --estricto >/dev/null 2>&1; [ $? -eq 1 ] && ok "--ci --estricto bloquea por la junta" || bad "--estricto"
contrato 'checks=["hay-a","ko"]' 'toca_junta=false'
"$ASSURE" verify --ci >"$T/ci.txt" 2>&1; [ $? -eq 1 ] && grep -q 'FALLÓ' "$T/ci.txt" && ok "--ci en rojo con un check que falla" || bad "--ci ko" "$(cat "$T/ci.txt")"
contrato 'checks=["hay-a","ok"]'
"$ASSURE" verify --ci --json | python3 -c 'import json,sys;d=json.load(sys.stdin);assert d["ok"] and d["advertencias"]==[]' && ok "--ci --json bien formado" || bad "--ci --json"
echo "── registro de respaldo en el repo cuando ROMPELO_HOME no tiene ninguno (runner de CI)"
mkdir -p "$T/vacio"; printf '{"hay-a": {"argv": ["test","-f","src/a.txt"]}, "ok": {"argv": ["true"]}}' > .rompelo/registry.json
ROMPELO_HOME="$T/vacio" "$ASSURE" verify --ci >/dev/null 2>&1 && ok "sin registro en HOME, vale .rompelo/registry.json del repo" || bad "fallback"
rm .rompelo/registry.json
ROMPELO_HOME="$T/vacio" "$ASSURE" verify --ci >"$T/ci.txt" 2>&1; [ $? -eq 1 ] && grep -q 'no está en el registro' "$T/ci.txt" && ok "sin ningún registro: bloquea, no ejecuta" || bad "sin registro" "$(cat "$T/ci.txt")"
"$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null; "$ASSURE" close >/dev/null

echo "── contrato cambiado después del cierre (hallazgo de Codex, 05-09)"
contrato 'checks=["hay-a","ok","habla"]'
espera_bloqueo "check añadido a una tarea cerrada: bloquea" s13 "sin ejecutar"
contrato 'checks=["hay-a","ok"]'
espera_paso "contrato restaurado: silencio" s13b

echo "── solo_local: un check que no puede correr en CI se salta con advertencia"
python3 - "$ROMPELO_HOME/checks/registry.json" <<'PY2'
import json,sys;f=sys.argv[1];r=json.load(open(f));r['local']={'argv':['false'],'solo_local':True};json.dump(r,open(f,'w'))
PY2
contrato 'checks=["hay-a","ok","local"]'
"$ASSURE" verify --ci >"$T/ci.txt" 2>&1; rc=$?; [ $rc -eq 0 ] && grep -q 'solo_local' "$T/ci.txt" && ok "--ci salta el check solo_local y lo dice" || bad "solo_local en CI" "rc=$rc $(cat "$T/ci.txt")"
"$ASSURE" check >/dev/null 2>&1; [ $? -eq 1 ] && ok "fuera de CI el check solo_local sí corre (y aquí falla)" || bad "solo_local local"
contrato 'checks=["hay-a","ok"]'; "$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null; "$ASSURE" close >/dev/null

echo "── fichero NUEVO: commitearlo no cambia la huella (mismo contenido)"
echo n > src/nuevo.txt; "$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null; "$ASSURE" close >/dev/null
espera_paso "cerrada con fichero nuevo sin rastrear: silencio" s12
git add -A >/dev/null && git commit -qm "fichero nuevo" && ok "commit del fichero nuevo" || bad "commit"
espera_paso "cerrada y el fichero nuevo ya commiteado: sigue en silencio" s12b

echo
echo "PASS=$PASS FAIL=$FAIL"
rm -rf "$T"
[ "$FAIL" -eq 0 ]
