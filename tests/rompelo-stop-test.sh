#!/bin/bash
# Pruebas del gate rompelo (v2: JSON, registro de checks, allowlist). Cada caso se ve
# FALLAR (bloquea con el motivo correcto) y PASAR (verde de partida y vuelta a verde).
# Usa un ROMPELO_HOME desechable: registro y allowlist propios, nunca los reales.
# Exit 0 = todo OK · 1 = hay fallos · 2 = no se pudo ejecutar.
. "$(dirname "$0")/lib.sh"   # ROMPELO (binario junto a los tests), ok/bad, hook_stop, espera_*, resumen
ASSURE="$ROMPELO"; export ROMPELO_BIN_PARA_PY="$ROMPELO"
[ -x "$ASSURE" ] || { echo "no existe $ASSURE"; exit 2; }
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
hook() { hook_stop "$1" "$2" "$3"; }   # <agente> <sid> <cwd>; la aserción de código/stderr/plazo vive en lib.sh
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
contrato 'hallazgos=[{"id":"H1","texto":"x","disposicion":"rechazado","motivo":"falso positivo"}]'

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
echo "── check: argumentos (antes se descartaban en silencio y ejecutaba todo)"
out="$("$ASSURE" check no.existe.jamas 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ! printf '%s' "$out" | grep -q '\[1/' && ok "check con argumento suelto: error y NO ejecuta nada" || bad "check aceptó un argumento suelto (rc=$rc)" "$out"
out="$("$ASSURE" check --id 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "check --id sin valor: error" || bad "check --id sin valor pasó" "$out"
out="$("$ASSURE" check --id canario 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && [ ! -e "$CANARY" ] && ok "check --id de un check fuera del contrato: error y no lo ejecuta" || bad "check --id ejecutó un check ajeno al contrato" "$out"
out="$("$ASSURE" check --id hay-a 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^\[1/1\] hay-a' && ! printf '%s' "$out" | grep -q '\] ok' && ok "check --id ejecuta solo el pedido (1/1)" || bad "check --id no acotó" "$out"
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
contrato 'hallazgos=[{"id":"H1","disposicion":"rechazado","motivo":"x"},{"id":"H2","texto":"y"}]'
espera_bloqueo "hallazgo sin disposición" s6 "hallazgo sin disposición: H2"
contrato 'hallazgos=[{"id":"H1","disposicion":"rechazado","motivo":"x"},{"id":"H2","disposicion":"aceptado","nota":"y"}]'
espera_paso "deshecha C: verde" s6b

echo "── hallazgos (RMP-012): la disposición es un estado con su respaldo, no una cadena"
contrato 'hallazgos=[{"id":"H3","texto":"z","disposicion":"pendiente"}]'
espera_bloqueo "«pendiente» no desbloquea" s6c "H3"
contrato 'hallazgos=[{"id":"H3","texto":"z","disposicion":"arreglado"}]'
espera_bloqueo "un estado inventado tampoco" s6d "confirmado | rechazado | aceptado"
contrato 'hallazgos=[{"id":"H3","texto":"z","disposicion":"rechazado"}]'
espera_bloqueo "rechazado sin motivo bloquea" s6e "rechazado sin motivo"
contrato 'hallazgos=[{"id":"H3","texto":"z","disposicion":"aceptado"}]'
espera_bloqueo "aceptado sin nota bloquea" s6f "aceptado sin nota"
contrato 'hallazgos=[{"id":"H3","texto":"z","disposicion":"confirmado"}]'
espera_bloqueo "confirmado sin regresión bloquea" s6g "confirmado sin regresión"
contrato 'hallazgos=[{"id":"H3","texto":"z","disposicion":"confirmado","regresion":"no.existe"}]'
espera_bloqueo "la regresión tiene que ser un check del registro o una prueba del diff" s6h "regresión"
contrato 'hallazgos=[{"id":"H3","texto":"z","disposicion":"confirmado","regresion":"tests/a.test.txt"},{"id":"H4","disposicion":"rechazado","motivo":"falso positivo: la ruta no existe"},{"id":"H5","disposicion":"aceptado","nota":"riesgo asumido hasta v2"}]'
espera_paso "confirmado con prueba del diff, rechazado con motivo, aceptado con nota: verde" s6i
contrato 'hallazgos=[{"id":"H3","texto":"z","disposicion":"confirmado","regresion":"ok"}]'
espera_paso "confirmado con un check del registro como regresión: verde" s6j
contrato 'hallazgos=[{"id":"H1","disposicion":"rechazado","motivo":"x"},{"id":"H2","disposicion":"aceptado","nota":"y"}]'

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
echo "── registro del consumidor (RMP-005): explícito con ROMPELO_REGISTRO=repo, nunca implícito"
mkdir -p "$T/vacio"; printf '{"hay-a": {"argv": ["test","-f","src/a.txt"]}, "ok": {"argv": ["true"]}}' > .rompelo/registry.json
ROMPELO_REGISTRO=repo ROMPELO_HOME="$T/vacio" "$ASSURE" verify --ci >"$T/ci.txt" 2>&1 && grep -q 'registro: .rompelo/registry.json' "$T/ci.txt" && ok "ROMPELO_REGISTRO=repo usa .rompelo/registry.json del repo y lo dice" || bad "registro repo" "$(cat "$T/ci.txt")"
ROMPELO_HOME="$T/vacio" "$ASSURE" verify --ci >"$T/ci.txt" 2>&1; [ $? -ne 0 ] && grep -q 'ROMPELO_REGISTRO=repo' "$T/ci.txt" && ok "sin registro en HOME y sin la variable: error que explica cómo habilitarlo (antes cargaba el del repo en silencio)" || bad "fallback implícito" "$(cat "$T/ci.txt")"
printf '{"ok": {"argv": ["true"]}}' > "$T/vacio.json"; mkdir -p "$T/conglobal/checks"; cp "$T/vacio.json" "$T/conglobal/checks/registry.json"
ROMPELO_REGISTRO=repo ROMPELO_HOME="$T/conglobal" "$ASSURE" verify --ci >"$T/ci.txt" 2>&1 && grep -q 'registro: .rompelo/registry.json' "$T/ci.txt" && ok "con registro global presente, =repo sigue eligiendo el del consumidor (topología real de la plantilla)" || bad "repo con global" "$(cat "$T/ci.txt")"
ROMPELO_HOME="$T/conglobal" "$ASSURE" verify --ci >"$T/ci.txt" 2>&1; [ $? -eq 1 ] && grep -q 'hay-a.*no está en el registro' "$T/ci.txt" && ok "sin la variable manda el global aunque le falte el check: bloquea, no ejecuta el del repo" || bad "global manda" "$(cat "$T/ci.txt")"
rm .rompelo/registry.json
ROMPELO_HOME="$T/vacio" "$ASSURE" verify --ci >"$T/ci.txt" 2>&1; [ $? -ne 0 ] && ok "sin ningún registro: error, no ejecuta" || bad "sin registro" "$(cat "$T/ci.txt")"
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
echo "── resultado de CI (RMP-006): lo ejecutado pasa ≠ contrato completo"
grep -q 'puede cerrarse' "$T/ci.txt" && bad "CI dice «puede cerrarse» con un check sin comprobar" "$(cat "$T/ci.txt")" || ok "con un check omitido, CI no dice «puede cerrarse»"
grep -q 'INCOMPLETO' "$T/ci.txt" && ok "lo llama INCOMPLETO y nombra lo que falta" || bad "sin INCOMPLETO" "$(cat "$T/ci.txt")"
"$ASSURE" verify --ci --json > "$T/ci.json" 2>/dev/null; python3 - "$T/ci.json" <<'PY'
import json,sys;d=json.load(open(sys.argv[1]))
assert d["ok"] is True and d["completo"] is False, d
assert d["resultados"]["local"]=="SKIPPED" and d["resultados"]["ok"]=="PASS" and d["resultados"]["hay-a"]=="PASS", d["resultados"]
PY
[ $? -eq 0 ] && ok "--json: ok=true (lo ejecutado pasa), completo=false, resultados PASS/SKIPPED por check" || bad "json ci" "$(cat "$T/ci.json")"
"$ASSURE" verify --ci --estricto >/dev/null 2>&1; [ $? -eq 1 ] && ok "--estricto: un check omitido bloquea" || bad "estricto con SKIPPED"
contrato 'excepciones=[{"que":"local","motivo":"necesita el navegador de esta máquina; cruzado a mano el 07-09","quien":"jose"}]'
"$ASSURE" verify --ci --json > "$T/ci.json" 2>/dev/null; rc=$?; python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["completo"] is True and d["resultados"]["local"]=="WAIVED",d' "$T/ci.json" && [ $rc -eq 0 ] && ok "excepción explícita en el contrato: WAIVED y completo" || bad "waiver" "$(cat "$T/ci.json")"
"$ASSURE" verify --ci --estricto >/dev/null 2>&1; [ $? -eq 0 ] && ok "--estricto acepta la excepción explícita (trazable en el contrato)" || bad "estricto con WAIVED"
contrato 'excepciones=[{"que":"local"}]'
"$ASSURE" verify --ci >"$T/ci.txt" 2>&1; [ $? -ne 0 ] && grep -q 'excepciones' "$T/ci.txt" && ok "una excepción sin motivo ni quién se rechaza" || bad "waiver sin motivo aceptado" "$(cat "$T/ci.txt")"
contrato 'excepciones=[]'
contrato 'checks=["hay-a","ok"]' 'toca_junta=true'
"$ASSURE" verify --ci --json > "$T/ci.json" 2>/dev/null; python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["completo"] is False and d["resultados"]["junta"]=="SKIPPED",d' "$T/ci.json" && ok "la junta sin cruzar en CI es SKIPPED, no silencio" || bad "junta skipped" "$(cat "$T/ci.json")"
contrato 'excepciones=[{"que":"junta","motivo":"cruzada a mano contra staging el 07-09","quien":"jose"}]'
"$ASSURE" verify --ci --estricto --json > "$T/ci.json" 2>/dev/null; rc=$?; python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["completo"] is True and d["resultados"]["junta"]=="WAIVED",d' "$T/ci.json" && [ $rc -eq 0 ] && ok "junta con excepción explícita: WAIVED también en --estricto" || bad "junta waived" "$(cat "$T/ci.json")"
contrato 'excepciones=[]' 'toca_junta=false' 'checks=["hay-a","ok","local"]'
"$ASSURE" check >/dev/null 2>&1; [ $? -eq 1 ] && ok "fuera de CI el check solo_local sí corre (y aquí falla)" || bad "solo_local local"
contrato 'checks=["hay-a","ok"]'; "$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null; "$ASSURE" close >/dev/null

echo "── contrato efectivo único (RMP-008): el perfil exige junta; close y verify juzgan lo mismo"
contrato 'checks=["hay-a","ok"]' 'toca_junta=false' 'segunda_pasada="revisado"' 'estado="abierta"'
EST1="$ROMPELO_HOME/state/repos/$(python3 -c "import hashlib,os,sys;print(hashlib.sha256(os.path.realpath(sys.argv[1]).encode()).hexdigest()[:16])" "$R").json"
mkdir -p "$(dirname "$EST1")"; printf '{"nivel": 2, "perfiles": ["junta"], "patrones": []}' > "$EST1"
"$ASSURE" check >/dev/null; rm -f .rompelo/evidence/T1/cruce.json
espera_bloqueo "perfil junta con toca_junta:false: exige cruce" ef1 "perfil \`junta\`"
"$ASSURE" cruce -- true >/dev/null; "$ASSURE" close >"$T/close.txt" 2>&1 && ok "close con la junta exigida por perfil" || bad "close perfil" "$(cat "$T/close.txt")"
espera_paso "verify justo después de close, sin tocar nada: silencio (antes: «el contrato cambió»)" ef2
grep -q 'cruce real de la junta' .rompelo/evidence/T1/INFORME.md && ok "el informe cuenta el cruce que de verdad se exigió" || bad "informe sin cruce" "$(cat .rompelo/evidence/T1/INFORME.md)"
python3 -c 'import json;c=json.load(open(".rompelo/task.json"));o=c["obligaciones_efectivas"];assert o["toca_junta"] is True and o["nivel"]==2 and "junta" in o["perfiles"],o' && ok "el contrato lleva las obligaciones efectivas con las que se cerró (viajan con la tarea)" || bad "obligaciones_efectivas"
python3 - <<'PY'
import json;f='.rompelo/task.json';c=json.load(open(f));c['obligaciones_efectivas']['toca_junta']=False;json.dump(c,open(f,'w'))
PY
espera_bloqueo "rebajar a mano las obligaciones efectivas invalida el cierre" ef3 "contrato cambió"
"$ASSURE" close >/dev/null 2>&1; espera_paso "re-cerrado: silencio" ef4

echo "── checks: [] no apaga los de nivel 3 (RMP-014)"
contrato 'checks=[]' 'checks_nivel3=["habla"]' 'estado="abierta"'
printf '{"nivel": 3, "perfiles": [], "patrones": [], "permisos": ["x"]}' > "$EST1"
"$ASSURE" check > "$T/n3.txt" 2>&1; rc=$?
[ $rc -eq 0 ] && grep -q 'habla' "$T/n3.txt" && [ -f .rompelo/evidence/T1/check-habla.json ] && ok "rompelo check ejecuta el de nivel 3 aunque checks esté vacío" || bad "nivel3 con checks vacío rc=$rc" "$(cat "$T/n3.txt")"
"$ASSURE" cruce -- true >/dev/null; "$ASSURE" close >/dev/null 2>&1 && ok "y cierra" || bad "close n3"
echo "── las obligaciones viajan: un runner sin estado local exige lo mismo que había al cerrar"
mkdir -p "$T/runner/checks"; cp "$ROMPELO_HOME/checks/registry.json" "$T/runner/checks/"
ROMPELO_HOME="$T/runner" "$ASSURE" verify --ci --json > "$T/ci.json" 2>/dev/null; python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["resultados"].get("habla")=="PASS",d' "$T/ci.json" && ok "CI sin estado ejecuta el check de nivel 3 que el cierre dejó escrito" || bad "obligaciones en CI" "$(cat "$T/ci.json")"
contrato 'checks=["hay-a","ok"]' 'checks_nivel3=[]' 'obligaciones_efectivas=null'; rm -f "$EST1"
"$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null; "$ASSURE" close >/dev/null 2>&1

echo "── tope alcanzado ≠ verificado: queda escrito"
contrato 'estado="abierta"' 'checks=["ko"]'; "$ASSURE" check >/dev/null 2>&1
for i in 1 2 3 4; do hook claude tope9 "$R" >/dev/null; done
[ -f .rompelo/evidence/T1/SIN-VERIFICAR.json ] && grep -q 'FALLÓ' .rompelo/evidence/T1/SIN-VERIFICAR.json && ok "tras el tope queda SIN-VERIFICAR.json con los motivos" || bad "sin marca de SIN VERIFICAR"
"$ASSURE" status 2>/dev/null | grep -q 'SIN VERIFICAR' && ok "status lo dice" || bad "status calla el SIN VERIFICAR" "$("$ASSURE" status 2>/dev/null | head -3)"
contrato 'checks=["hay-a","ok"]'; "$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null; "$ASSURE" close >/dev/null 2>&1
[ ! -f .rompelo/evidence/T1/SIN-VERIFICAR.json ] && ok "un cierre de verdad la quita" || bad "SIN-VERIFICAR persiste tras cerrar"

echo "── init sin --check detecta los checks del repo"
R2="$T/repo2"; mkdir -p "$R2/src"; (cd "$R2" && git init -q && git config user.email t@t && git config user.name t \
  && printf '{"name":"demo","scripts":{"test":"vitest run","typecheck":"tsc --noEmit","dev":"vite"}}' > package.json && : > pnpm-lock.yaml \
  && printf 'test:\n\techo t\n' > Makefile && git add -A && git commit -qm base)
(cd "$R2" && "$ASSURE" init --id D1 > "$T/init.txt" 2>&1) && ok "init sin --check no falla" || bad "init auto" "$(cat "$T/init.txt")"
python3 - "$R2/.rompelo/task.json" "$ROMPELO_HOME/checks/registry.local.json" <<'PY2'
import json,sys
c=json.load(open(sys.argv[1])); r=json.load(open(sys.argv[2]))
assert c["checks"]==["repo2.test","repo2.typecheck"], c["checks"]          # make test no duplica el .test
assert r["repo2.test"]["argv"]==["pnpm","test"], r["repo2.test"]
assert r["repo2.typecheck"]["argv"]==["pnpm","run","typecheck"], r["repo2.typecheck"]
assert "repo2.dev" not in r
PY2
[ $? -eq 0 ] && ok "detecta test y typecheck con pnpm, ignora dev, no duplica make test" || bad "detección"
rm -f "$ROMPELO_HOME/checks/registry.local.json"
(cd "$R2" && rm -rf .rompelo && "$ASSURE" init --id D2 --sin-detectar > /dev/null 2>&1 && python3 -c 'import json;assert json.load(open(".rompelo/task.json"))["checks"]==[]') && ok "--sin-detectar deja los checks vacíos" || bad "--sin-detectar"

echo "── informe en llano al cerrar"
contrato 'checks=["hay-a","ok"]' 'afirmaciones=[{"texto":"x","estado":"no_verificado","falta":"acceso al panel"}]' 'hallazgos=[{"id":"H9","texto":"borde","disposicion":"aceptado","nota":"no bloquea"}]'
"$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null
"$ASSURE" close > "$T/close.txt" 2>&1; rc=$?
[ $rc -eq 0 ] && grep -q '## Qué se comprobó' "$T/close.txt" && grep -q 'acceso al panel' "$T/close.txt" && grep -q 'H9 aceptado' "$T/close.txt" && [ -f .rompelo/evidence/T1/INFORME.md ] && ok "close imprime y guarda el informe con los tres bloques" || bad "informe" "rc=$rc $(cat "$T/close.txt")"
contrato 'afirmaciones=[]' 'hallazgos=[]'; "$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null; "$ASSURE" close >/dev/null

echo "── fichero NUEVO: commitearlo no cambia la huella (mismo contenido)"
echo n > src/nuevo.txt; "$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null; "$ASSURE" close >/dev/null
espera_paso "cerrada con fichero nuevo sin rastrear: silencio" s12
git add -A >/dev/null && git commit -qm "fichero nuevo" && ok "commit del fichero nuevo" || bad "commit"
espera_paso "cerrada y el fichero nuevo ya commiteado: sigue en silencio" s12b

echo "── control positivo por check y triestado (INC-0018/0021/0025)"
contrato 'estado="abierta"' 'checks=["positivo"]' 'toca_junta=false'
cat > "$ROMPELO_HOME/control.py" <<'PY'
import os, pathlib, sys
p = pathlib.Path(os.environ['ROMPELO_HOME'])
with (p / 'orden').open('a') as f: f.write('control\n')
print('CANARIO_SALIDA_PRIVADA_CONTROL')
sys.exit(int((p / 'control-codigo').read_text()))
PY
cat > "$ROMPELO_HOME/real.py" <<'PY'
import os, pathlib, sys
p = pathlib.Path(os.environ['ROMPELO_HOME'])
with (p / 'orden').open('a') as f: f.write('real\n')
print('CANARIO_SALIDA_PRIVADA_REAL\n2 vistos')
sys.exit(int((p / 'real-codigo').read_text()))
PY
python3 - "$ROMPELO_HOME" <<'PY'
import json, sys
p=sys.argv[1]
e={'argv':['python3',p+'/real.py'],'cwd':'repo','min_lineas':2,'triestado':True,
   'control_positivo':{'argv':['python3',p+'/control.py'],'cwd':'rompelo'}}
json.dump({'positivo':e},open(p+'/checks/registry.local.json','w'))
PY
positivo() { printf '%s' "$1" > "$ROMPELO_HOME/control-codigo"; printf '%s' "$2" > "$ROMPELO_HOME/real-codigo";
  : > "$ROMPELO_HOME/orden"; "$ASSURE" check > "$T/positivo.txt" 2>&1; rc=$?; }
registro_positivo() { python3 - "$ROMPELO_HOME/checks/registry.local.json" "$1" "$2" <<'PY'
import json, sys
f,k,v=sys.argv[1:];d=json.load(open(f));d['positivo'][k]=json.loads(v);json.dump(d,open(f,'w'))
PY
}
positivo 0 0
[ "$rc" -eq 1 ] && ok "check rechaza el control ciego" || bad "check aceptó el control ciego"
espera_bloqueo "control con 0 bloquea el verde" cp0 "su control positivo no detectó el caso malo; el verde no vale"
python3 - <<'PY'
import json
e=json.load(open('.rompelo/evidence/T1/check-positivo.json'))
assert e.get('instrumento')=='ciego' and e.get('codigo') is None and e['control_positivo']['codigo']==0
PY
[ $? -eq 0 ] && ok "evidencia ciego con código real desconocido" || bad "evidencia del control ciego"
[ "$(cat "$ROMPELO_HOME/orden")" = control ] && ok "control ciego impide ejecutar el check real" || bad "ejecutó el real con instrumento ciego"
positivo 2 0
espera_bloqueo "control con 2 no pudo mirar" cp2 "control positivo NO PUDO MIRAR (instrumento, no hallazgo)"
[ "$rc" -eq 1 ] && [ "$(cat "$ROMPELO_HOME/orden")" = control ] && ok "control con 2 no ejecuta el real" || bad "control con 2 ejecutó el real"
positivo 3 0
espera_bloqueo "control con 3 aborta por ruta no prevista" cp3 "control positivo abortó por una ruta no prevista (código 3)"
[ "$rc" -eq 1 ] && [ "$(cat "$ROMPELO_HOME/orden")" = control ] && ok "control inesperado no ejecuta el real" || bad "control inesperado ejecutó el real"
positivo 1 2
espera_bloqueo "triestado 2 distingue instrumento de hallazgo" tri2 "NO PUDO MIRAR (instrumento, no hallazgo; código 2)"
out="$(hook codex tri2b "$R")"; ! printf '%s' "$out" | grep -q FALLÓ && ok "triestado 2 no dice FALLÓ" || bad "triestado 2 confundido con hallazgo"
positivo 1 3
espera_bloqueo "triestado 3 tiene motivo propio" tri3 "abortó por una ruta no prevista (código 3)"
positivo 1 1
espera_bloqueo "triestado 1 sigue siendo hallazgo" tri1 "FALLÓ con código 1"
positivo 1 0
[ "$rc" -eq 0 ] && ok "control 1 y real 0: check verde" || bad "rechazó control válido"
espera_paso "control detecta el malo y check limpio: silencio" cpbueno
[ "$(cat "$ROMPELO_HOME/orden")" = "$(printf 'control\nreal')" ] && ok "el control corre antes del real" || bad "orden incorrecto"
grep -q '2/2 líneas' "$T/positivo.txt" && grep -q 'control positivo: código 1' "$T/positivo.txt" && ok "informa recuento y resultado del control" || bad "salida sin recuentos/control" "$(cat "$T/positivo.txt")"
python3 - <<'PY'
import json
f='.rompelo/evidence/T1/check-positivo.json';s=open(f).read();e=json.loads(s)
assert 'CANARIO_SALIDA_PRIVADA' not in s
assert e['control_positivo']['lineas_salida']==1 and e['lineas_salida']==2
assert e['control_positivo']['sha_salida'] and e['sha_salida']
PY
[ $? -eq 0 ] && ok "solo códigos, recuentos y hashes; ninguna salida guardada" || bad "privacidad de la evidencia"
registro_positivo min_lineas 3
positivo 1 0
[ "$rc" -eq 1 ] && ok "check tampoco llama verde al 0 sin salida mínima" || bad "check dijo verde sin salida mínima"
espera_bloqueo "control válido no exime salida mínima" cpmin "sin la salida mínima"
registro_positivo min_lineas 2
positivo 1 0
espera_paso "salida suficiente restaura verde" cpminbien
registro_positivo cwd '"rompelo"'
espera_bloqueo "cambiar cwd invalida evidencia" cpcwd "cambió en el registro"
registro_positivo cwd '"repo"'
espera_paso "cwd restaurado: verde" cpcwdbien
registro_positivo triestado false
espera_bloqueo "cambiar triestado invalida evidencia" cpdef "cambió en el registro"
registro_positivo triestado true
"$ASSURE" close >/dev/null
python3 - "$ROMPELO_HOME/checks/registry.local.json" <<'PY'
import json,sys
f=sys.argv[1];d=json.load(open(f));d['positivo']['control_positivo']['cwd']='repo';json.dump(d,open(f,'w'))
PY
espera_bloqueo "control cambiado invalida incluso el cierre" cpcerrado "cambió en el registro"
positivo 1 0
"$ASSURE" close >/dev/null
espera_paso "nuevo control ejecutado y cierre rehecho: silencio" cpcerradobien
positivo 0 0
espera_bloqueo "control recién fallado invalida el cierre sin cambiar el árbol" cpcerradociego "el verde no vale"
"$ASSURE" verify --ci --json > "$T/cp-ci.json"; rc=$?
python3 - "$T/cp-ci.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]));assert not d['ok'] and any('el verde no vale' in m for m in d['motivos'])
PY
[ $? -eq 0 ] && [ "$rc" -eq 1 ] && ok "CI ejecuta también el control ciego y bloquea" || bad "CI ignoró el control"
ROMPELO_LANG=en "$ASSURE" verify --ci --json > "$T/cp-en.json"
grep -q 'positive control did not detect' "$T/cp-en.json" && ! grep -q 'verde no vale' "$T/cp-en.json" && ok "control ciego traducido al inglés" || bad "control en inglés"
positivo 1 2
ROMPELO_LANG=en "$ASSURE" verify --ci --json > "$T/cp-en.json"
grep -q 'COULD NOT INSPECT' "$T/cp-en.json" && ! grep -q 'NO PUDO' "$T/cp-en.json" && ok "triestado traducido al inglés" || bad "triestado en inglés"
positivo 1 0
"$ASSURE" verify --ci --json | python3 -c 'import json,sys;assert json.load(sys.stdin)["ok"]' && ok "CI acepta control 1 y real 0" || bad "CI rechazó control válido"
registro_positivo control_positivo '{"argv":"touch canario","cwd":"repo"}'
: > "$ROMPELO_HOME/orden"
"$ASSURE" check >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && [ ! -s "$ROMPELO_HOME/orden" ] && ok "control malformado se rechaza antes de ejecutar" || bad "control malformado ejecutó el real"
espera_bloqueo "control malformado bloquea el cierre" cpinvalido "no pudo evaluar"

echo "── huella (RMP-001/002, 07-09): el sujeto es contenido + tipo + modo + destino del enlace, con nombres de cualquier clase"
R3="$T/repo3"; mkdir -p "$R3/src" "$R3/tests"
(cd "$R3" && git init -q && git config user.email t@t && git config user.name t && git config core.quotePath true \
  && printf 'a\n' > 'src/año.py' && printf 'a\n' > 'src/con espacio.py' && printf 'a\n' > "$(printf 'src/tab\there.py')" \
  && printf '#!/bin/sh\n' > src/run.sh && chmod 644 src/run.sh && printf 'same\n' > src/t1.txt && printf 'same\n' > src/t2.txt && printf 'same\n' > src/t3.txt \
  && ln -s t1.txt src/ln && echo t > tests/a.test.txt && git add -A && git commit -qm base)
R="$R3"; cd "$R3" || exit 2
"$ASSURE" init --id H1 --scope 'src/**' --scope 'tests/**' --check ok >/dev/null || exit 2
BASE3="$(git rev-parse HEAD)"
huella() { "$ASSURE" status 2>/dev/null | sed -n 's/.*huella \([^ ]*\).*/\1/p' | head -1; }
h0=$(huella)
printf 'b\n' > src/año.py; h1=$(huella)
[ -n "$h0" ] && [ "$h1" != "$h0" ] && ok "año.py: la primera modificación cambia la huella (control)" || bad "año.py primera" "$h0 → $h1"
printf 'c\n' > src/año.py; h2=$(huella)
[ "$h2" != "$h1" ] && ok "año.py: la segunda modificación también la cambia (antes se firmaba como borrado)" || bad "año.py segunda: huella igual" "$h1 = $h2"
"$ASSURE" status 2>/dev/null | grep -q "src/año.py" && ok "status lista el nombre real, no la forma entrecomillada de git" || bad "nombre entrecomillado" "$("$ASSURE" status 2>/dev/null | grep cambiados)"
contrato 'scope_paths=["src/*.py","tests/**"]'; "$ASSURE" check >/dev/null
espera_paso "año.py cabe en src/*.py: silencio (antes salía «fuera de scope» por el nombre entrecomillado)" h3
contrato 'scope_paths=["src/**","tests/**"]'
printf 'b\n' > "$(printf 'src/tab\there.py')"; h4=$(huella); printf 'c\n' > "$(printf 'src/tab\there.py')"; h5=$(huella)
[ "$h4" != "$h2" ] && [ "$h5" != "$h4" ] && ok "nombre con tabulador: las dos modificaciones cambian la huella" || bad "tabulador" "$h2 $h4 $h5"
printf 'b\n' > 'src/con espacio.py'; h6=$(huella); printf 'c\n' > 'src/con espacio.py'; h7=$(huella)
[ "$h6" != "$h5" ] && [ "$h7" != "$h6" ] && ok "nombre con espacio: las dos modificaciones cambian la huella" || bad "espacio" "$h5 $h6 $h7"
chmod 755 src/run.sh; h8=$(huella); [ "$h8" != "$h7" ] && ok "+x sobre un fichero limpio cambia la huella" || bad "+x limpio" "$h7 = $h8"
printf '#!/bin/sh\necho x\n' > src/run.sh; h9=$(huella); chmod 644 src/run.sh; h10=$(huella)
[ "$h9" != "$h8" ] && [ "$h10" != "$h9" ] && ok "el modo ejecutable forma parte del sujeto también sobre un fichero ya modificado" || bad "+x modificado" "$h8 $h9 $h10"
rm src/ln && ln -s t2.txt src/ln; h11=$(huella); rm src/ln && ln -s t3.txt src/ln; h12=$(huella)
[ "$h11" != "$h10" ] && [ "$h12" != "$h11" ] && ok "el destino del enlace simbólico forma parte del sujeto (mismo contenido, destinos distintos)" || bad "symlink" "$h10 $h11 $h12"
git mv src/t1.txt src/t9.txt
"$ASSURE" status 2>/dev/null | grep -q "src/t1.txt" && "$ASSURE" status 2>/dev/null | grep -q "src/t9.txt" && ok "renombrado: aparecen el origen (borrado) y el destino" || bad "renombrado" "$("$ASSURE" status 2>/dev/null | grep cambiados)"
"$ASSURE" check >/dev/null; "$ASSURE" close >/dev/null 2>&1 && ok "cierre con nombres raros, +x y symlink" || bad "close raros" "$("$ASSURE" verify 2>&1)"
espera_paso "cerrada: silencio" h13
git add -A >/dev/null && git commit -qm "mismo contenido" && espera_paso "commit del mismo contenido (nombres raros incluidos): sigue en silencio" h14
printf 'd\n' > src/año.py
espera_bloqueo "y una modificación más de año.py reabre" h15 "cambios posteriores al cierre"
contrato 'estado="abierta"' 'base="0000000000000000000000000000000000000000"'
espera_bloqueo "base explícita que no existe en el repo: bloquea, no compara con HEAD en silencio" h16 "no existe en este repo"
contrato "base=\"$BASE3\""
"$ASSURE" check >/dev/null
python3 - <<'PY'
import json;f='.rompelo/evidence/H1/check-ok.json';e=json.load(open(f));e['huella']='0123456789abcdef';json.dump(e,open(f,'w'))
PY
espera_bloqueo "evidencia con huella de formato antiguo (sin versión): hay que volver a ejecutar, no se migra" h17 "formato de huella antiguo"
"$ASSURE" check >/dev/null; espera_paso "reejecutado: silencio" h18
chmod 000 .git/index
espera_bloqueo "git falla (índice ilegible): bloquea diciendo que no pudo mirar" h19 "git"
chmod 644 .git/index; espera_paso "git restaurado: silencio" h20

echo "── exige_prueba_en_diff: borrar el único test no es «prueba en el diff» (RMP-015 mínimo)"
contrato 'exige_prueba_en_diff=true'
printf 'e\n' > src/año.py; git rm -q tests/a.test.txt
espera_bloqueo "código cambiado y test borrado: bloquea" h23 "ninguna prueba"
git checkout -q HEAD -- tests/a.test.txt; echo t3 >> tests/a.test.txt; "$ASSURE" check >/dev/null
espera_paso "con un test modificado de verdad: silencio" h24
contrato 'exige_prueba_en_diff=false'

echo "── repo sin primer commit: lo preparado en el índice cuenta desde el principio"
R4="$T/repo4"; mkdir -p "$R4"; R="$R4"; cd "$R4" || exit 2
git init -q && git config user.email t@t && git config user.name t
printf 'x\n' > s.py && git add s.py
"$ASSURE" init --id S1 --check ok >/dev/null 2>&1 || exit 2
"$ASSURE" status 2>/dev/null | grep -q "s.py" && ok "fichero preparado sin HEAD aparece en cambiados" || bad "staged sin HEAD" "$("$ASSURE" status 2>/dev/null | grep cambiados)"
h21=$(huella); printf 'y\n' > s.py; h22=$(huella); [ -n "$h21" ] && [ "$h22" != "$h21" ] && ok "y su contenido forma parte de la huella" || bad "staged sin HEAD huella" "$h21 $h22"
"$ASSURE" check >/dev/null; espera_paso "sin HEAD y check hecho: silencio" s21
git commit -qm primero >/dev/null; espera_paso "primer commit del mismo contenido: silencio" s22

echo "── errores propios del gate (RMP-003): corrupto no es «vacío» ni «autorizado»"
R5="$T/repo5"; mkdir -p "$R5/src"; R="$R5"; cd "$R5" || exit 2
git init -q && git config user.email t@t && git config user.name t && echo a > src/a.txt && git add -A && git commit -qm base
"$ASSURE" init --id E1 --check ok >/dev/null || exit 2; "$ASSURE" check >/dev/null
espera_paso "partida: verde" e0
cp "$ROMPELO_HOME/config/repos.json" "$T/repos.bak"; printf '{"repos": [' > "$ROMPELO_HOME/config/repos.json"
espera_bloqueo "allowlist truncada: bloquea diciendo que no puede saber si el repo está alistado (antes moría sin JSON)" e1 "allowlist"
cp "$T/repos.bak" "$ROMPELO_HOME/config/repos.json"; espera_paso "allowlist restaurada: verde" e2
mv "$ROMPELO_HOME/config/repos.json" "$T/repos.mv"; espera_paso "sin allowlist (primera ejecución): silencio, nada alistado" e3
mv "$T/repos.mv" "$ROMPELO_HOME/config/repos.json"
EST="$ROMPELO_HOME/state/repos/$(python3 -c "import hashlib,os,sys;print(hashlib.sha256(os.path.realpath(sys.argv[1]).encode()).hexdigest()[:16])" "$R5").json"  # la clave es la ruta real (/private/var…), no la de mktemp
mkdir -p "$(dirname "$EST")"; printf '{"nivel": 3, "perfiles": ["junta"' > "$EST"
espera_bloqueo "estado del repo truncado: bloquea (antes se leía como {} y el nivel 3 desaparecía)" e4 "estado"
[ "$(cat "$EST")" = '{"nivel": 3, "perfiles": ["junta"' ] && ok "y no lo sobrescribe" || bad "el gate reescribió el estado corrupto"
rm "$EST"; espera_paso "sin estado (primera vez): verde" e5
printf '{"x": [' > "$ROMPELO_HOME/config/permisos.json"
"$ASSURE" permiso lo-que-sea si >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && [ "$(cat "$ROMPELO_HOME/config/permisos.json")" = '{"x": [' ] && ok "permisos.json corrupto: permiso se niega y no lo pisa" || bad "permisos corrupto rc=$rc" "$(cat "$ROMPELO_HOME/config/permisos.json")"
rm "$ROMPELO_HOME/config/permisos.json"
python3 - "$ROMPELO_HOME" "$R5" <<'PY'
import json,os,sys,subprocess
home,repo=sys.argv[1:3]; est=os.path.join(home,"state","repos")
r=subprocess.run([os.environ["ROMPELO_BIN_PARA_PY"],"nivel"],cwd=repo,capture_output=True,text=True)
sobras=[f for f in os.listdir(est) if f.endswith(".tmp") or "~" in f] if os.path.isdir(est) else []
assert not sobras, sobras
PY
[ $? -eq 0 ] && ok "escrituras sin temporales huérfanos" || bad "temporales huérfanos"

echo "── estado concurrente (RMP-003): cinco observadores a la vez no se pisan"
rm -rf "$ROMPELO_HOME/state"
for p in auth secretos datos despliegue junta; do
  case $p in auth) c='sed -i s/a/b/ src/auth/login.ts';; secretos) c='sed -i s/a/b/ .env';; datos) c='psql -f migrations/1.sql';; despliegue) c='wrangler pages deploy dist';; junta) c='sed -i s/a/b/ functions/api/x.ts';; esac
  ( for i in 1 2; do printf '{"session_id":"conc-%s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"stdout":"","stderr":"","exit_code":0}}' "$p" "$R5" "$c" | ROMPELO_RETARDO_ESTADO=0.3 "$ASSURE" observe claude >/dev/null 2>&1; done ) &
done; wait
python3 - "$EST" <<'PY'
import json,sys
est=json.load(open(sys.argv[1])); falta=sorted({"auth","secretos","datos","despliegue","junta"}-set(est.get("perfiles",[])))
print("faltan:", falta); sys.exit(1 if falta else 0)
PY
[ $? -eq 0 ] && ok "los cinco perfiles quedan en el estado (lectura-modificación-escritura bajo cerrojo)" || bad "se perdieron actualizaciones concurrentes"
rm -rf "$ROMPELO_HOME/state"

echo "── runner (RMP-010): plazo, salida binaria, salida enorme, ejecutable ausente, hijos"
python3 - "$ROMPELO_HOME/checks/registry.json" <<'PY'
import json,sys;f=sys.argv[1];r=json.load(open(f))
r['lento']={'argv':['sh','-c','sleep 30 & sleep 30'],'timeout':1}
r['binario']={'argv':['python3','-c',"import sys;sys.stdout.buffer.write(b'\\xff\\xfe visto\\n')"],'min_lineas':1}
r['chorro']={'argv':['python3','-c',"print('x'*6000000)"]}
r['ausente']={'argv':['/no/existe/rompelo-canario']}
r['malplazo']={'argv':['true'],'timeout':'mucho'}
json.dump(r,open(f,'w'))
PY
contrato 'checks=["lento"]'; t0=$(date +%s); "$ASSURE" check >"$T/lento.txt" 2>&1; rc=$?; t1=$(date +%s)
[ "$rc" -ne 0 ] && [ $((t1-t0)) -lt 10 ] && grep -q 'no terminó' "$T/lento.txt" && ok "check que no termina: corta al plazo ($((t1-t0)) s) y lo dice" || bad "plazo rc=$rc $((t1-t0))s" "$(cat "$T/lento.txt")"
sleep 1; pgrep -f 'sleep 30' >/dev/null && bad "quedan hijos vivos tras el plazo" "$(pgrep -fl 'sleep 30')" || ok "no quedan hijos vivos (se mata el grupo de procesos)"
espera_bloqueo "y el gate lo cuenta como instrumento, no como hallazgo" r1 "no terminó"
contrato 'checks=["binario"]'; "$ASSURE" check >/dev/null 2>&1 && ok "salida no UTF-8: el check pasa (antes UnicodeDecodeError sin capturar)" || bad "binario"
contrato 'checks=["chorro"]'; "$ASSURE" check >/dev/null 2>&1 && python3 -c 'import json;e=json.load(open(".rompelo/evidence/E1/check-chorro.json"));assert e["salida_truncada"] is True and e["bytes_salida"]>6000000,e' && ok "salida de 6 MB: acotada, anotada como truncada, con el tamaño real" || bad "chorro" "$(cat .rompelo/evidence/E1/check-chorro.json 2>/dev/null)"
contrato 'checks=["ausente"]'; "$ASSURE" check >"$T/aus.txt" 2>&1; rc=$?
[ "$rc" -ne 0 ] && grep -q 'no pudo ejecutarse' "$T/aus.txt" && ok "ejecutable ausente: instrumento, no «FALLÓ con código 127»" || bad "ausente rc=$rc" "$(cat "$T/aus.txt")"
espera_bloqueo "y el gate lo dice igual" r2 "no pudo ejecutarse"
contrato 'checks=["malplazo"]'; "$ASSURE" check >/dev/null 2>&1; [ $? -ne 0 ] && ok "timeout no numérico en el registro se rechaza" || bad "malplazo aceptado"
contrato 'checks=["ok"]'; "$ASSURE" check >/dev/null

echo "── privacidad (RMP-007): la evidencia no guarda argumentos ni salida"
python3 - "$ROMPELO_HOME/checks/registry.json" <<'PY'
import json,sys;f=sys.argv[1];r=json.load(open(f))
r['con-token']={'argv':['sh','-c','echo "respuesta CANARIO_SALIDA_9"; exit 0','--','--header','Authorization: CANARIO_ARGV_7'],'min_lineas':1}
json.dump(r,open(f,'w'))
PY
contrato 'checks=["con-token"]' 'toca_junta=true'; "$ASSURE" check >/dev/null
"$ASSURE" cruce --nota "cruce" -- sh -c 'echo CANARIO_SALIDA_CRUCE_5; exit 1' -- --url 'https://user:CANARIO_URL_3@x' >/dev/null 2>&1
grep -rl 'CANARIO_' .rompelo/evidence/ >/dev/null 2>&1 && bad "canario en la evidencia" "$(grep -rl 'CANARIO_' .rompelo/evidence/)" || ok "ni argumentos ni salida del check ni del cruce llegan a la evidencia"
out="$(hook claude pr1 "$R")"; printf '%s' "$out" | grep -q 'CANARIO_' && bad "canario en el motivo de bloqueo" "$out" || ok "el motivo del cruce fallido no repite los argumentos"
"$ASSURE" cruce -- sh -c 'echo CANARIO_SALIDA_CRUCE_6' -- --header 'X: CANARIO_ARGV_8' >/dev/null; "$ASSURE" close >"$T/close.txt" 2>&1
grep -q 'CANARIO_' "$T/close.txt" .rompelo/evidence/E1/INFORME.md && bad "canario en el informe" || ok "el informe de cierre tampoco lleva argumentos"
grep -q 'cruce real de la junta: sh' .rompelo/evidence/E1/INFORME.md && ok "el informe sí dice el programa y la nota" || bad "informe sin programa" "$(grep cruce .rompelo/evidence/E1/INFORME.md)"
contrato 'checks=["ok"]' 'toca_junta=false'

rm -rf "$T"
resumen
