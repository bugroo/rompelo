#!/bin/bash
# `rompelo init` cuando el trabajo YA está commiteado (15-11-2026).
#
# Medido en uso real: el contrato se abrió después del commit, init tomó HEAD como base, el diff salió vacío o sin la
# prueba («el diff cambia código y ninguna prueba»), y como la base solo avanza hubo que rehacer rama y PR. Ahora,
# si HEAD lleva commits propios respecto a origin/main, la base es el punto donde la rama sale de main; `--base-head`
# conserva lo de antes. Y `test_*.py` (convención de pytest) cuenta como prueba.
. "$(dirname "$0")/lib.sh"
[ -x "$ROMPELO" ] || { echo "no existe $ROMPELO"; exit 2; }
T="$(mktemp -d)"; export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
export ROMPELO_HOME="$T/home"; mkdir -p "$ROMPELO_HOME/checks" "$ROMPELO_HOME/config"
printf '{"defecto":"turno"}' > "$ROMPELO_HOME/config/disparo.json"
printf '{"ok": {"argv": ["true"]}}' > "$ROMPELO_HOME/checks/registry.json"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

git init -q --bare "$T/origen.git"
R="$T/repo"; git clone -q "$T/origen.git" "$R" 2>/dev/null; cd "$R" || exit 2
git config user.email t@t && git config user.name t
git checkout -q -b main
mkdir -p src && echo a > src/a.py && git add -A && git commit -qm base && git push -q origin main 2>/dev/null
SALIDA_MAIN="$(git rev-parse HEAD)"
base() { python3 -c "import json;print(json.load(open('.rompelo/task.json'))['base'])"; }
cambiados() { "$ROMPELO" status 2>&1 | grep '^cambiados:' ; }

echo "── rama con el trabajo ya commiteado (y empujada a su propia rama remota)"
git checkout -q -b tarea
echo b > src/a.py && mkdir -p src/ops && echo 'assert True' > src/ops/test_algo.py && git add -A && git commit -qm trabajo
git push -q -u origin tarea 2>/dev/null
out="$("$ROMPELO" init --id T1 --check ok --prueba 2>&1)"
[ "$(base)" = "$SALIDA_MAIN" ] && ok "la base es la salida de la rama respecto a origin/main" || bad "base = $(base), esperaba $SALIDA_MAIN" "$out"
printf '%s' "$out" | grep -q '1 commit' && ok "init dice cuántos commits de la rama entran" || bad "init no lo dice" "$out"
cambiados | grep -q 'src/a.py' && ok "el contrato ve el cambio commiteado" || bad "contrato vacío" "$(cambiados)"
cambiados | grep -q 'src/ops/test_algo.py' && ok "precondición: la prueba test_algo.py está en el diff" || bad "precondición falla: sin test_algo.py en el diff, lo de abajo sería verde en vacío" "$(cambiados)"
out="$("$ROMPELO" check 2>&1)"
out="$("$ROMPELO" close 2>&1)"
printf '%s' "$out" | grep -q 'ninguna prueba' && bad "test_algo.py no cuenta como prueba" "$out" || ok "test_*.py cuenta como prueba (close no pide prueba)"

echo "── --base-head: lo de antes"
"$ROMPELO" init --force --id T2 --check ok --base-head >/dev/null 2>&1
[ "$(base)" = "$(git rev-parse HEAD)" ] && ok "--base-head deja la base en HEAD" || bad "--base-head no respetado: $(base)"

echo "── en main sin commits propios: HEAD, como siempre"
git checkout -q main
"$ROMPELO" init --force --id T3 --check ok >/dev/null 2>&1
[ "$(base)" = "$(git rev-parse HEAD)" ] && ok "sin commits propios la base es HEAD" || bad "base inesperada en main: $(base)"

echo "── repo sin origin/main: HEAD, como siempre"
R2="$T/suelto"; mkdir -p "$R2" && cd "$R2" && git init -q && git config user.email t@t && git config user.name t
echo x > x && git add -A && git commit -qm uno && echo y > x && git commit -qam dos
"$ROMPELO" init --id T4 --check ok >/dev/null 2>&1
[ "$(base)" = "$(git rev-parse HEAD)" ] && ok "sin remoto la base es HEAD" || bad "base inesperada sin remoto: $(base)"

echo
echo "pasan $PASS · fallan $FAIL"
[ "$FAIL" -eq 0 ]
