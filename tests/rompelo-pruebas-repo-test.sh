#!/bin/bash
# Batería de .rompelo/pruebas.json (16-11-2026): el repo declara dónde viven sus pruebas además de las de siempre.
# Antes había que escribir `pruebas_glob` a mano en cada contrato de claveon-admin (sus pruebas de pantalla son
# scripts/qa/ui/*-e2e.mjs). Cada caso se ve FALLAR y PASAR; ROMPELO_HOME desechable (disparo turno).
#   1. sin fichero: igual que siempre (una e2e fuera de test/ no cuenta como prueba)
#   2. con fichero: la e2e cuenta
#   3. con fichero: las de siempre siguen contando (se suman, no se sustituyen)
#   4. fichero malformado: bloquea diciendo cuál, no se ignora
#   5. `pruebas_glob` del contrato sigue mandando sobre todo
#   6. borrar la e2e no es cubrir
# Exit 0 = todo OK · 1 = hay fallos · 2 = no se pudo ejecutar.
. "$(dirname "$0")/lib.sh"
[ -x "$ROMPELO" ] || { echo "no existe $ROMPELO"; exit 2; }
T="$(mktemp -d)"; export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
export ROMPELO_HOME="$T/home"; mkdir -p "$ROMPELO_HOME/checks" "$ROMPELO_HOME/config"
printf '{"defecto":"turno"}' > "$ROMPELO_HOME/config/disparo.json"
printf '{"ok": {"argv": ["true"]}}' > "$ROMPELO_HOME/checks/registry.json"
R="$T/repo"; mkdir -p "$R/src" "$R/scripts/qa/ui" "$R/tests"; cd "$R" || exit 2
git init -q && git config user.email t@t && git config user.name t
echo a > src/a.ts && echo e > scripts/qa/ui/vieja-e2e.mjs && echo t > tests/a.test.ts && git add -A && git commit -qm base
contrato() { python3 - "$@" <<'PY'
import json,sys;f='.rompelo/task.json';c=json.load(open(f))
for kv in sys.argv[1:]:
    k,v=kv.split('=',1); c[k]=json.loads(v)
json.dump(c,open(f,'w'),indent=1,ensure_ascii=False)
PY
}
abrir() { "$ROMPELO" init --force --id "$1" --check ok --prueba >/dev/null || exit 2; }
SIN='el diff cambia código y ninguna prueba'

echo "── 1. sin .rompelo/pruebas.json: la e2e no cuenta (comportamiento de siempre)"
abrir P1
echo b > src/a.ts && echo n > scripts/qa/ui/nueva-e2e.mjs
"$ROMPELO" check >/dev/null || exit 2
espera_bloqueo "código + e2e, sin fichero: bloquea por falta de prueba" p1 "$SIN"

echo "── 2. con el fichero: la e2e cuenta"
printf '{"pruebas_glob": ["scripts/qa/**/*-e2e.mjs"]}' > .rompelo/pruebas.json
"$ROMPELO" check >/dev/null || exit 2
espera_paso "código + e2e, con fichero: verde" p2

echo "── 3. con el fichero: las de siempre siguen contando"
git add -A && git commit -qm p2 >/dev/null
abrir P3
echo c > src/a.ts && echo u > tests/a.test.ts
"$ROMPELO" check >/dev/null || exit 2
espera_paso "código + tests/a.test.ts, con fichero: verde" p3
git checkout -q -- tests/a.test.ts
espera_bloqueo "control: sin tocar ninguna prueba, bloquea" p3b "$SIN"

echo "── 4. fichero malformado: bloquea y dice cuál"
cp .rompelo/pruebas.json "$T/bueno.json"
for malo in '{"pruebas_glob": "scripts/**"}' '{"pruebas_glob": []}' '{"otra": 1}' '{"pruebas_glob": [""]}' 'no es json'; do
  printf '%s' "$malo" > .rompelo/pruebas.json
  espera_bloqueo "malformado ($malo): bloquea" "p4$RANDOM" 'pruebas.json'
done
cp "$T/bueno.json" .rompelo/pruebas.json

echo "── 5. pruebas_glob del contrato manda"
echo n2 > scripts/qa/ui/nueva-e2e.mjs
"$ROMPELO" check >/dev/null || exit 2
espera_paso "control: código + e2e, con fichero: verde" p5a
contrato 'pruebas_glob=["nada/**"]'
"$ROMPELO" check >/dev/null || exit 2
espera_bloqueo "contrato con pruebas_glob propio: la e2e ya no cuenta" p5 "$SIN"

echo "── 6. borrar la e2e no es cubrir"
abrir P6
git checkout -q -- scripts/qa/ui/nueva-e2e.mjs; echo d > src/a.ts; git rm -q scripts/qa/ui/vieja-e2e.mjs
"$ROMPELO" check >/dev/null || exit 2
espera_bloqueo "código + e2e borrada: bloquea" p6 "$SIN"

cd / && rm -rf "$T"
resumen
