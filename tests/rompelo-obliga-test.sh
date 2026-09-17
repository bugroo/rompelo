#!/bin/bash
# Batería de `afecta` (registro) y `obliga` (config/obliga.json y .rompelo/obliga.json): el diff dicta el contrato.
#   afecta: globs de un check; si ningún fichero cambiado casa, el check NO APLICA (ni se exige ni se ejecuta) y su
#           huella solo mira esas rutas (editar otra cosa no lo caduca).
#   obliga: glob → {checks, junta, prueba}; una ruta cambiada que casa añade esas obligaciones al contrato efectivo
#           aunque el agente no las declarara. Cada caso se ve FALLAR y PASAR. ROMPELO_HOME desechable (disparo turno).
# Exit 0 = todo OK · 1 = hay fallos · 2 = no se pudo ejecutar.
. "$(dirname "$0")/lib.sh"
[ -x "$ROMPELO" ] || { echo "no existe $ROMPELO"; exit 2; }
T="$(mktemp -d)"; export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
export ROMPELO_HOME="$T/home"; mkdir -p "$ROMPELO_HOME/checks" "$ROMPELO_HOME/config"
printf '{"defecto":"turno"}' > "$ROMPELO_HOME/config/disparo.json"
CANARY="$T/canario"; CANARY2="$T/canario2"
cat > "$ROMPELO_HOME/checks/registry.json" <<J
{"ok": {"argv": ["true"]},
 "sh-check": {"argv": ["touch", "$CANARY"], "afecta": ["*.sh", "scripts/**"]},
 "ts-check": {"argv": ["touch", "$CANARY2"], "afecta": ["src/**/*.ts"], "no_afecta": ["src/**/*.md"]},
 "mal-afecta": {"argv": ["true"], "afecta": "*.sh"}}
J
R="$T/repo"; mkdir -p "$R/src" "$R/functions/api" "$R/tests"; cd "$R" || exit 2
git init -q && git config user.email t@t && git config user.name t
echo a > src/a.ts && echo r > README.md && echo s > run.sh && echo f > functions/api/f.ts && echo t > tests/a.test.ts && git add -A && git commit -qm base
contrato() { python3 - "$@" <<'PY'
import json,sys;f='.rompelo/task.json';c=json.load(open(f))
for kv in sys.argv[1:]:
    k,v=kv.split('=',1); c[k]=json.loads(v)
json.dump(c,open(f,'w'),indent=1,ensure_ascii=False)
PY
}
limpio() { git checkout -q -- . && git clean -qfd; }

echo "── afecta: el check no aplica si ninguna ruta cambiada casa"
"$ROMPELO" init --id A1 --check ok --check sh-check --check ts-check >/dev/null || exit 2
echo b > README.md
espera_bloqueo "README cambiado: falta `ok`" a1 'check `ok` sin ejecutar'
out="$(hook_stop claude a1 "$R")"; printf '%s' "$out" | grep -q 'sh-check' && bad "sh-check exigido sin ruta que case" "$out" || ok "sh-check no aplica: no se exige"
out="$("$ROMPELO" check 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'sh-check.*no aplica' && [ ! -e "$CANARY" ] && ok "rompelo check: sh-check «no aplica» y NO se ejecuta" || bad "check ejecutó o no marcó sh-check (rc=$rc)" "$out"
espera_paso "solo README: verde con ok" a1
"$ROMPELO" verify --ci --json > "$T/v.json" || bad "verify --ci debía dar 0"
[ ! -e "$CANARY" ] && ok "verify --ci tampoco ejecuta un check que no aplica" || bad "verify --ci ejecutó sh-check sin ruta que case"
python3 - "$T/v.json" <<'PY' && ok "verify --ci --json: sh-check N/A" || bad "verify --ci --json sin N/A"
import json,sys;d=json.load(open(sys.argv[1]));r=d.get("resultados",{});sys.exit(0 if r.get("sh-check")=="N/A" and r.get("ok")=="PASS" else 1)
PY
echo "── afecta: al tocar una ruta que casa, se exige y se ejecuta; su huella solo mira sus rutas"
echo s2 > run.sh
espera_bloqueo "run.sh cambiado: sh-check sin ejecutar" a2 'check `sh-check` sin ejecutar'
"$ROMPELO" check --id sh-check >/dev/null && [ -e "$CANARY" ] && ok "sh-check se ejecuta al aplicar" || bad "sh-check no se ejecutó"
espera_bloqueo "y ok quedó caducado por run.sh" a2 'check `ok` se ejecutó sobre otro árbol'
"$ROMPELO" check --id ok >/dev/null || exit 2
espera_paso "todo al día" a2
echo c > README.md
espera_bloqueo "README de nuevo: ok caduca" a3 'check `ok` se ejecutó sobre otro árbol'
out="$(hook_stop claude a3 "$R")"; printf '%s' "$out" | grep -q 'sh-check' && bad "sh-check caducó por un README (afecta no acota la huella)" "$out" || ok "sh-check sigue vigente: README no está en afecta"
echo n > src/n.ts
espera_bloqueo "src/n.ts: ts-check pasa a exigirse" a4 'check `ts-check` sin ejecutar'
"$ROMPELO" check >/dev/null || exit 2
espera_paso "todo verde" a4
echo m > src/nota.md
out="$(hook_stop claude a5 "$R")"; printf '%s' "$out" | grep -q 'ts-check' && bad "src/nota.md caducó ts-check (no_afecta)" "$out" || ok "no_afecta sigue valiendo junto a afecta"
printf '%s' "$out" | grep -q 'check `ok`' && ok "…y ok sí caduca" || bad "ok no caducó" "$out"
echo "── afecta malformado en el registro: fail-closed"
contrato 'checks=["ok","mal-afecta"]'
espera_bloqueo "afecta que no es lista bloquea" a6 "afecta"
contrato 'checks=["ok","sh-check","ts-check"]'
limpio; rm -rf .rompelo

echo "── obliga (config global): el diff añade checks, junta y prueba al contrato efectivo"
cat > "$ROMPELO_HOME/config/obliga.json" <<'J'
{"reglas": {"functions/api/**": {"junta": true}, "*.sh": {"checks": ["sh-check"]}, "src/**": {"checks": ["ts-check"], "prueba": true}}}
J
"$ROMPELO" init --id O1 --check ok >/dev/null || exit 2
echo b > README.md
espera_bloqueo "README: solo ok" o1 'check `ok` sin ejecutar'
out="$(hook_stop claude o1 "$R")"; printf '%s' "$out" | grep -qE 'sh-check|ts-check|cruce real' && bad "obliga exigió algo sin ruta que case" "$out" || ok "sin ruta que case, nada extra"
echo s2 > run.sh
espera_bloqueo "run.sh: obliga exige sh-check" o2 'check `sh-check` sin ejecutar'
out="$(hook_stop claude o2 "$R")"; printf '%s' "$out" | grep -q 'obliga' && ok "el motivo dice que viene de obliga" || bad "motivo sin origen" "$out"
grep -q 'sh-check' .rompelo/task.json && bad "obliga escribió en el contrato" || ok "el contrato escrito no cambia (es efectivo)"
rm -f "$CANARY"; "$ROMPELO" check >/dev/null && [ -e "$CANARY" ] && ok "rompelo check ejecuta el check obligado" || bad "check no ejecutó sh-check"
espera_paso "run.sh + sh-check hecho: verde" o2
echo f2 > functions/api/f.ts
espera_bloqueo "functions/api: obliga exige junta" o3 'obliga'
out="$(hook_stop claude o3 "$R")"; printf '%s' "$out" | grep -q 'cruce real' && ok "…pide cruce real" || bad "sin cruce" "$out"
"$ROMPELO" check >/dev/null && "$ROMPELO" cruce --nota x -- true >/dev/null || exit 2
espera_paso "cruzado: verde" o3
echo n > src/n.ts
espera_bloqueo "src/: obliga exige ts-check" o4 'check `ts-check` sin ejecutar'
"$ROMPELO" check >/dev/null || exit 2
espera_bloqueo "src/ sin prueba: obliga exige prueba en el diff" o4 'exige_prueba_en_diff'
echo t2 > tests/a.test.ts
"$ROMPELO" check >/dev/null && "$ROMPELO" cruce --nota x -- true >/dev/null || exit 2
espera_paso "con prueba: verde" o4
"$ROMPELO" close >/dev/null || bad "close debía cerrar"
python3 - <<'PY' && ok "obligaciones_efectivas del cierre llevan los checks obligados y la junta" || bad "obligaciones_efectivas sin lo obligado"
import json;c=json.load(open('.rompelo/task.json'));oe=c.get('obligaciones_efectivas',{})
import sys;sys.exit(0 if 'sh-check' in oe.get('checks',[]) and 'ts-check' in oe.get('checks',[]) and oe.get('toca_junta') is True and oe.get('exige_prueba_en_diff') is True else 1)
PY
echo "── obliga con un check que no está en el registro: bloquea sin ejecutar"
cat > "$ROMPELO_HOME/config/obliga.json" <<'J'
{"reglas": {"*.sh": {"checks": ["noexiste"]}}}
J
echo s3 > run.sh
espera_bloqueo "check obligado desconocido bloquea" o5 'check `noexiste` no está en el registro'
echo "── obliga corrupto o malformado: fail-closed"
printf '{' > "$ROMPELO_HOME/config/obliga.json"
espera_bloqueo "obliga.json corrupto bloquea" o6 "obliga"
printf '{"reglas": {"*.sh": {"checks": "sh-check"}}}' > "$ROMPELO_HOME/config/obliga.json"
espera_bloqueo "obliga.json con checks que no es lista bloquea" o7 "obliga"
printf '{"reglas": {"../x/**": {"junta": true}}}' > "$ROMPELO_HOME/config/obliga.json"
espera_bloqueo "obliga.json con glob sucio bloquea" o8 "obliga"
rm -f "$ROMPELO_HOME/config/obliga.json"
limpio; rm -rf .rompelo

echo "── obliga del repo (.rompelo/obliga.json, versionado): también en CI"
"$ROMPELO" init --id O2 --check ok >/dev/null || exit 2
printf '{"reglas": {"*.sh": {"checks": ["sh-check"]}}}' > .rompelo/obliga.json
echo s4 > run.sh
espera_bloqueo "obliga del repo exige sh-check" r1 'check `sh-check` sin ejecutar'
"$ROMPELO" check >/dev/null || exit 2
git add -A && git commit -qm "obliga" && "$ROMPELO" close >/dev/null || exit 2
mkdir -p "$T/runner/checks"; cp "$ROMPELO_HOME/checks/registry.json" "$T/runner/checks/"
ROMPELO_HOME="$T/runner" "$ROMPELO" verify --ci --json > "$T/ci.json"; rc=$?
python3 - "$T/ci.json" <<'PY' && ok "verify --ci (otro ROMPELO_HOME, sin obliga global) exige y ejecuta sh-check por el obliga del repo" || bad "CI no vio el obliga del repo (rc=$rc)" "$(cat "$T/ci.json")"
import json,sys;d=json.load(open(sys.argv[1]));r=d.get("resultados",{});sys.exit(0 if r.get("sh-check")=="PASS" and r.get("ok")=="PASS" else 1)
PY
echo "── por_repo en obliga global"
printf '{"reglas": {}, "por_repo": {"%s": {"reglas": {"README.md": {"checks": ["ts-check"]}}}}}' "$R" > "$ROMPELO_HOME/config/obliga.json"
echo z > README.md
espera_bloqueo "por_repo: README exige ts-check" r2 'check `ts-check` sin ejecutar'

cd / && rm -rf "$T"
resumen
