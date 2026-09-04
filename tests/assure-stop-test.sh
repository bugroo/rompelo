#!/bin/bash
# Pruebas del gate assure (v2: JSON, registro de checks, allowlist). Cada caso se ve
# FALLAR (bloquea con el motivo correcto) y PASAR (verde de partida y vuelta a verde).
# Usa un ASSURE_HOME desechable: registro y allowlist propios, nunca los reales.
# Exit 0 = todo OK · 1 = hay fallos · 2 = no se pudo ejecutar.
ASSURE="$HOME/assure/bin/assure"
[ -x "$ASSURE" ] || { echo "no existe $ASSURE"; exit 2; }
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ❌ $1"; [ -n "$2" ] && echo "     salida: $2"; }
T="$(mktemp -d)"; export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
export ASSURE_HOME="$T/home"; mkdir -p "$ASSURE_HOME/checks" "$ASSURE_HOME/config"
CANARY="$T/canario"
cat > "$ASSURE_HOME/checks/registry.json" <<J
{"ok": {"argv": ["true"]}, "ko": {"argv": ["false"]}, "hay-a": {"argv": ["test", "-f", "src/a.txt"]},
 "canario": {"argv": ["touch", "$CANARY"]}}
J
R="$T/repo"; mkdir -p "$R"; cd "$R" || exit 2
git init -q && git config user.email t@t && git config user.name t
mkdir -p src tests && echo a > src/a.txt && echo t > tests/a.test.txt && git add -A && git commit -qm base
hook() { printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$2" "$3" | "$ASSURE" hook "$1"; }
espera_bloqueo() { local out; out="$(hook claude "$2" "$R")"
  if printf '%s' "$out" | grep -q '"decision": *"block"' && printf '%s' "$out" | grep -qF -- "$3"; then ok "$1"; else bad "$1 (esperaba bloqueo con «$3»)" "$out"; fi; }
espera_paso() { local out; out="$(hook claude "$2" "$R")"; [ -z "$out" ] && ok "$1" || bad "$1 (esperaba silencio)" "$out"; }
contrato() { python3 - "$@" <<'PY'
import json,sys;f='.assure/task.json';c=json.load(open(f))
for kv in sys.argv[1:]:
    k,v=kv.split('=',1); c[k]=json.loads(v)
json.dump(c,open(f,'w'),indent=1,ensure_ascii=False)
PY
}

echo "── allowlist: repo no registrado con .assure/ ajeno → silencio y NADA se ejecuta"
mkdir -p .assure && printf '{"id":"AJENO","estado":"abierta","scope_paths":["**"],"checks":["canario"],"toca_junta":false}' > .assure/task.json
espera_paso "repo fuera de la allowlist: silencio" s0
[ ! -e "$CANARY" ] && ok "y no ejecutó el check del contrato ajeno" || bad "ejecutó un check de un repo no registrado"
out="$(hook claude s0 "$T")"; [ -z "$out" ] && ok "cwd sin git: silencio" || bad "cwd sin git" "$out"
rm -rf .assure

echo "── init: rechaza ids fuera del registro y no ejecuta cadenas"
"$ASSURE" init --id X --check 'true; touch '"$CANARY" >/dev/null 2>&1 && bad "init aceptó una cadena de comando" || ok "init rechaza un check que no es id del registro"
[ ! -e "$CANARY" ] && ok "la cadena no se ejecutó" || bad "la cadena SE EJECUTÓ"
"$ASSURE" init --id T1 --scope 'src/**' --scope 'tests/**' --check hay-a --check ok --junta --prueba >/dev/null || exit 2
grep -q "$R" "$ASSURE_HOME/config/repos.json" && ok "init apunta el repo en la allowlist" || bad "allowlist"
[ "$(cat .assure/evidence/.gitignore)" = "*" ] && [ "$(git status --porcelain)" = "?? .assure/" ] && ok "la evidencia se autoignora; solo el contrato queda por commitear" || bad "gitignore" "$(git status --porcelain)"
contrato 'hallazgos=[{"id":"H1","texto":"x","disposicion":"rechazado"}]'

echo "── contrato inválido (fail-closed)"
cp .assure/task.json "$T/task.bak"
printf '{"id": [' > .assure/task.json;          espera_bloqueo "JSON malformado bloquea" s1 "no pudo evaluar"
printf '{"id":"T1"}' > .assure/task.json;        espera_bloqueo "campo obligatorio ausente bloquea" s1b "claves obligatorias"
cp "$T/task.bak" .assure/task.json
contrato 'scope_paths=["../fuera/**"]';           espera_bloqueo "scope con ../ se rechaza" s1c "sin '..'"
contrato 'scope_paths=["/etc/**"]';               espera_bloqueo "scope absoluto se rechaza" s1d "sin '..'"
cp "$T/task.bak" .assure/task.json
contrato 'checks=["ok","true; touch '"$CANARY"'"]'; espera_bloqueo "check con inyección se rechaza" s1e "ids [a-z0-9._-]"
[ ! -e "$CANARY" ] && ok "y no se ejecutó" || bad "SE EJECUTÓ la inyección"
contrato 'checks=["ok","noexiste"]';              espera_bloqueo "check desconocido bloquea sin ejecutar" s1f "no está en el registro"
"$ASSURE" check >/dev/null 2>&1; [ $? -ne 0 ] && ok "assure check se niega con id desconocido" || bad "check ejecutó con id desconocido"
cp "$T/task.bak" .assure/task.json
rm -f .assure/task.json;                           espera_bloqueo "contrato ausente en repo registrado bloquea" s1g "no pudo evaluar"
cp "$T/task.bak" .assure/task.json

echo "── evidencia"
espera_bloqueo "sin evidencia: bloquea por check" s2 "check \`hay-a\` sin ejecutar"
espera_bloqueo "sin evidencia: bloquea por junta" s2b "no hay cruce real"
"$ASSURE" check >/dev/null && ok "assure check en verde" || bad "assure check"
espera_bloqueo "checks hechos, falta el cruce" s2c "no hay cruce real"
"$ASSURE" cruce --nota "p" -- true >/dev/null && ok "assure cruce por argv OK" || bad "cruce"

echo "── VERDE DE PARTIDA"
espera_paso "todo cumplido: deja parar" s3
"$ASSURE" verify >/dev/null && ok "assure verify → 0" || bad "verify debía dar 0"

echo "── mutación A: cambio de código sin prueba; evidencia obsoleta"
echo b >> src/a.txt; grep -q b src/a.txt && ok "mutación A aplicada" || bad "mutación A"
espera_bloqueo "evidencia sobre otro árbol" s4 "sobre otro árbol"
espera_bloqueo "cruce anterior al cambio" s4b "anterior al último cambio"
"$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null
espera_bloqueo "código sin prueba" s4c "ninguna prueba"
echo t2 >> tests/a.test.txt; "$ASSURE" check >/dev/null; "$ASSURE" cruce --id ok >/dev/null
espera_paso "con prueba en el diff y cruce por id: deja parar" s4d

echo "── mutación B: un check en rojo"
contrato 'checks=["hay-a","ko"]'; grep -q '"ko"' .assure/task.json && ok "mutación B aplicada" || bad "mutación B"
"$ASSURE" check >/dev/null 2>&1; [ $? -eq 1 ] && ok "assure check devuelve 1" || bad "check debía devolver 1"
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

echo "── registro cambiado tras ejecutar"
python3 - "$ASSURE_HOME/checks/registry.json" <<'PY'
import json,sys;f=sys.argv[1];r=json.load(open(f));r['ok']={'argv':['true','--otro']};json.dump(r,open(f,'w'))
PY
espera_bloqueo "el argv del registro cambió después de la evidencia" s7c "cambió en el registro"
python3 - "$ASSURE_HOME/checks/registry.json" <<'PY'
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
"$ASSURE" close >/dev/null && grep -q '"estado": "cerrada"' .assure/task.json && ok "close deja estado cerrada" || bad "close"
espera_paso "cerrada y sin cambios: silencio" s10
git add -A >/dev/null && git commit -qm "mismo contenido" && ok "commit hecho" || bad "commit"
espera_paso "cerrada y commit del mismo contenido: sigue en silencio" s10c
echo d >> src/a.txt
espera_bloqueo "cerrada con cambios posteriores" s10b "cambios posteriores al cierre"
"$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null
"$ASSURE" close >/dev/null && ok "se puede volver a cerrar tras rehacer la evidencia" || bad "re-close"
espera_paso "re-cerrada: silencio" s10d

echo
echo "PASS=$PASS FAIL=$FAIL"
rm -rf "$T"
[ "$FAIL" -eq 0 ]
