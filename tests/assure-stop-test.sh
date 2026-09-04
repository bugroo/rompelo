#!/bin/bash
# Pruebas del gate assure. Cada caso se ve FALLAR (bloquea con el motivo correcto) y
# se ve PASAR (verde de partida y vuelta a verde tras deshacer la mutación).
# Exit 0 = todo OK · 1 = hay fallos · 2 = no se pudo ejecutar.
ASSURE="$HOME/assure/bin/assure"
[ -x "$ASSURE" ] || { echo "no existe $ASSURE"; exit 2; }
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ❌ $1"; [ -n "$2" ] && echo "     salida: $2"; }
T="$(mktemp -d)"; export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
R="$T/repo"; mkdir -p "$R"; cd "$R" || exit 2
git init -q && git config user.email t@t && git config user.name t
mkdir -p src tests && echo a > src/a.txt && echo t > tests/a.test.txt && git add -A && git commit -qm base
hook() { # $1 agente, $2 sesión, $3 cwd → stdout
  printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"hook_event_name":"Stop"}' "$2" "$3" | "$ASSURE" hook "$1"; }
espera_bloqueo() { # $1 nombre, $2 sesión, $3 texto que debe aparecer en el motivo
  local out; out="$(hook claude "$2" "$R")"
  if printf '%s' "$out" | grep -q '"decision": *"block"' && printf '%s' "$out" | grep -qF -- "$3"; then ok "$1"; else bad "$1 (esperaba bloqueo con «$3»)" "$out"; fi; }
espera_paso() { local out; out="$(hook claude "$2" "$R")"; [ -z "$out" ] && ok "$1" || bad "$1 (esperaba silencio)" "$out"; }

echo "── control negativo: repo no alistado y cwd fuera de git"
espera_paso "sin .assure: silencio" s0
out="$(hook claude s0 "$T")"; [ -z "$out" ] && ok "cwd sin git: silencio" || bad "cwd sin git" "$out"

echo "── contrato"
"$ASSURE" init --id T1 --scope 'src/**' --scope 'tests/**' --check 'test -f src/a.txt' --check true --junta --prueba >/dev/null || exit 2
python3 - <<'PY'
import yaml;f='.assure/task.yaml';c=yaml.safe_load(open(f));c['hallazgos']=[{'id':'H1','texto':'x','disposicion':'rechazado','nota':'n'}];yaml.safe_dump(c,open(f,'w'),allow_unicode=True,sort_keys=False)
PY
espera_bloqueo "sin evidencia: bloquea por check" s1 "check 1 sin ejecutar"
espera_bloqueo "sin evidencia: bloquea por junta" s1b "no hay cruce real"
"$ASSURE" check >/dev/null && ok "assure check en verde (código 0)" || bad "assure check"
espera_bloqueo "checks hechos, falta el cruce" s2 "no hay cruce real"
"$ASSURE" cruce --nota "prueba" -- true >/dev/null && ok "assure cruce OK" || bad "assure cruce"

echo "── VERDE DE PARTIDA"
espera_paso "todo cumplido: deja parar" s3
"$ASSURE" verify >/dev/null && ok "assure verify → 0" || bad "verify debía dar 0"

echo "── mutación A: cambio de código sin prueba, y evidencia obsoleta"
echo b >> src/a.txt
grep -q b src/a.txt && ok "mutación A aplicada" || bad "mutación A no aplicada"
espera_bloqueo "evidencia sobre otro árbol" s4 "sobre otro árbol"
espera_bloqueo "cruce anterior al cambio" s4b "anterior al último cambio"
"$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null
espera_bloqueo "código sin prueba" s4c "ninguna prueba"
echo t2 >> tests/a.test.txt; "$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null
espera_paso "con prueba en el diff: deja parar" s4d

echo "── mutación B: un check en rojo"
# El YAML guarda «true» entrecomillado ('true'); un sed sobre `- true` no casa y la
# mutación no ocurre. Se muta por YAML y se comprueba que ocurrió.
mutar_check() { python3 - "$1" <<'PY'
import sys,yaml;f='.assure/task.yaml';c=yaml.safe_load(open(f));c['checks_obligatorios'][1]=sys.argv[1];yaml.safe_dump(c,open(f,'w'),allow_unicode=True,sort_keys=False)
PY
}
mutar_check false
grep -q "'false'" .assure/task.yaml && ok "mutación B aplicada" || bad "mutación B no aplicada"
"$ASSURE" check >/dev/null 2>&1; [ $? -eq 1 ] && ok "assure check devuelve 1" || bad "check debía devolver 1"
espera_bloqueo "check fallido bloquea" s5 "FALLÓ con código 1"
mutar_check true; "$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null
espera_paso "deshecha B: vuelve a verde" s5b

echo "── mutación C: hallazgo sin disposición"
python3 - <<'PY'
import yaml;f='.assure/task.yaml';c=yaml.safe_load(open(f));c['hallazgos'].append({'id':'H2','texto':'y'});yaml.safe_dump(c,open(f,'w'),allow_unicode=True,sort_keys=False)
PY
grep -q 'H2' .assure/task.yaml && ok "mutación C aplicada" || bad "mutación C no aplicada"
espera_bloqueo "hallazgo sin disposición" s6 "hallazgo sin disposición: H2"
python3 - <<'PY'
import yaml;f='.assure/task.yaml';c=yaml.safe_load(open(f));c['hallazgos'][1]['disposicion']='aceptado';yaml.safe_dump(c,open(f,'w'),allow_unicode=True,sort_keys=False)
PY
espera_paso "deshecha C: verde" s6b

echo "── mutación D: fichero fuera de scope"
mkdir -p docs && echo x > docs/x.md
espera_bloqueo "fuera de scope" s7 "fuera de scope_paths: docs/x.md"
rm docs/x.md && rmdir docs; "$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null
espera_paso "deshecha D: verde" s7b

echo "── mutación E: contrato ilegible o ausente (fail-closed)"
cp .assure/task.yaml "$T/task.bak"; printf 'id: [\n' > .assure/task.yaml
espera_bloqueo "contrato ilegible bloquea" s8 "no pudo evaluar"
rm .assure/task.yaml
espera_bloqueo "contrato ausente con .assure/ bloquea" s8b "no pudo evaluar"
cp "$T/task.bak" .assure/task.yaml
espera_paso "restaurado: verde" s8c

echo "── tope de bloqueos (3) y luego aviso sin bloquear"
echo c >> src/a.txt
for i in 1 2 3; do out="$(hook claude s9 "$R")"; printf '%s' "$out" | grep -q "($i/3)" && ok "bloqueo $i/3" || bad "bloqueo $i" "$out"; done
out="$(hook claude s9 "$R")"; printf '%s' "$out" | grep -q systemMessage && ! printf '%s' "$out" | grep -q '"decision"' && ok "4º intento: systemMessage, sin bloqueo" || bad "tope" "$out"
"$ASSURE" check >/dev/null; "$ASSURE" cruce -- true >/dev/null

echo "── close y reapertura por cambios posteriores"
"$ASSURE" close >/dev/null && grep -q '^estado: cerrada' .assure/task.yaml && ok "close deja estado: cerrada" || bad "close"
espera_paso "cerrada y sin cambios: silencio" s10
echo d >> src/a.txt
espera_bloqueo "cerrada con cambios posteriores" s10b "cambios posteriores al cierre"

echo "── adaptador codex: mismo JSON"
out="$(hook codex s11 "$R")"; printf '%s' "$out" | grep -q '"decision": *"block"' && ok "codex: bloquea con decision/reason" || bad "codex" "$out"
printf '%s' "$out" | python3 -c 'import json,sys;json.load(sys.stdin)' && ok "salida es JSON válido" || bad "JSON inválido"

echo
echo "PASS=$PASS FAIL=$FAIL"
rm -rf "$T"
[ "$FAIL" -eq 0 ]
