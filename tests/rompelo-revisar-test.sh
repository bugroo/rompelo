#!/bin/bash
# Batería de `rompelo revisar`: la segunda pasada con manifiesto (docs/disparo.md §revisar). A nivel ≥ 2 el gate exige un
# manifiesto CERRADO sobre la huella actual: cada fichero cambiado revisado o saltado con motivo; los hallazgos pasan al
# contrato sin disposición. Cada caso se ve FALLAR y PASAR. ROMPELO_HOME desechable (disparo turno).
# Exit 0 = todo OK · 1 = hay fallos · 2 = no se pudo ejecutar.
. "$(dirname "$0")/lib.sh"
[ -x "$ROMPELO" ] || { echo "no existe $ROMPELO"; exit 2; }
T="$(mktemp -d)"; export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR" "$T/bin"
export ROMPELO_HOME="$T/home"; mkdir -p "$ROMPELO_HOME/checks" "$ROMPELO_HOME/config"
printf '{"defecto":"turno"}' > "$ROMPELO_HOME/config/disparo.json"
printf '{"ok": {"argv": ["true"]}}' > "$ROMPELO_HOME/checks/registry.json"
R="$T/repo"; mkdir -p "$R/src"; cd "$R" || exit 2
git init -q && git config user.email t@t && git config user.name t
echo a > src/a.txt && echo b > src/b.txt && git add -A && git commit -qm base
"$ROMPELO" init --id R1 --check ok >/dev/null || exit 2
EV=".rompelo/evidence/R1"; MAN="$EV/revision.json"
nivel2() { local est; est="$ROMPELO_HOME/state/repos/$(python3 -c "import hashlib,os,sys;print(hashlib.sha256(os.path.realpath(sys.argv[1]).encode()).hexdigest()[:16])" "$R").json"
  mkdir -p "$(dirname "$est")"; printf '{"nivel": 2, "perfiles": [], "patrones": ["firma_repetida"]}' > "$est"; }
manifiesto() { python3 - "$MAN" "$@" <<'PY'
import json,sys
f=sys.argv[1]; rv=json.load(open(f))
for kv in sys.argv[2:]:
    k,v=kv.split('=',1)
    if k.startswith('f:'):  # f:<path>=estado[:motivo]
        est,_,mot=v.partition(':')
        for x in rv['ficheros']:
            if x['path']==k[2:]: x['estado']=est; x['motivo']=mot
    else:
        rv[k]=json.loads(v)
json.dump(rv,open(f,'w'),indent=1,ensure_ascii=False)
PY
}
contrato() { python3 - "$@" <<'PY'
import json,sys;f='.rompelo/task.json';c=json.load(open(f))
for kv in sys.argv[1:]:
    k,v=kv.split('=',1); c[k]=json.loads(v)
json.dump(c,open(f,'w'),indent=1,ensure_ascii=False)
PY
}

echo "── nivel 0: nadie pide revisión"
echo a2 > src/a.txt; echo n > src/nuevo.txt
"$ROMPELO" check >/dev/null || exit 2
espera_paso "nivel 0 con checks: silencio, sin revisar" n0

echo "── nivel 2: hace falta manifiesto cerrado sobre la huella actual"
nivel2
espera_bloqueo "nivel 2 sin manifiesto: bloquea pidiendo rompelo revisar" n2 'rompelo revisar'
out="$(hook_stop claude n2 "$R")"; printf '%s' "$out" | grep -q 'Siguiente: rompelo revisar' && ok "Siguiente: empieza por rompelo revisar" || bad "Siguiente sin revisar" "$out"
out="$("$ROMPELO" revisar --cerrar 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'no hay manifiesto' && ok "--cerrar sin manifiesto: error claro" || bad "--cerrar sin manifiesto (rc=$rc)" "$out"
out="$(PATH=/usr/bin:/bin "$ROMPELO" revisar 2>&1)"; rc=$?   # PATH sin ocr: el caso «sin ocr» no depende de lo que tenga instalado la máquina
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'src/a.txt' && printf '%s' "$out" | grep -q 'src/nuevo.txt' && printf '%s' "$out" | grep -q 'huella v2:' && ok "revisar lista los ficheros cambiados y la huella" || bad "revisar (rc=$rc)" "$out"
printf '%s' "$out" | grep -q 'nuevo .*src/nuevo.txt' && printf '%s' "$out" | grep -q 'modificado .*src/a.txt' && ok "distingue nuevo de modificado" || bad "tipos" "$out"
printf '%s' "$out" | grep -q 'ocr no está en PATH' && ok "sin ocr: lo dice y remite a las reglas de la casa" || bad "sin ocr" "$out"
printf '%s' "$out" | grep -q 'criterio' && ok "imprime el criterio" || bad "criterio" "$out"
python3 - "$MAN" <<'PY' && ok "el manifiesto esqueleto tiene los 2 ficheros con estado vacío y cerrada=false" || bad "esqueleto"
import json,sys;rv=json.load(open(sys.argv[1]));f={x['path']:x['estado'] for x in rv['ficheros']}
sys.exit(0 if f=={'src/a.txt':'','src/nuevo.txt':''} and rv['cerrada'] is False and rv['hallazgos']==[] else 1)
PY
out="$("$ROMPELO" revisar --cerrar 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'no vale (revisado | saltado)' && ok "--cerrar con estados vacíos: error" || bad "estados vacíos (rc=$rc)" "$out"
manifiesto 'f:src/a.txt=revisado' 'f:src/nuevo.txt=saltado'
out="$("$ROMPELO" revisar --cerrar 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'saltado sin motivo' && ok "saltado sin motivo: error" || bad "saltado sin motivo (rc=$rc)" "$out"
manifiesto 'f:src/nuevo.txt=saltado:fichero generado' 'hallazgos=[{"id":"REV-1","path":"src/a.txt","linea":1,"categoria":"bug","severidad":"high","texto":"a2 no es a"}]'
out="$("$ROMPELO" revisar --cerrar 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '1 revisado(s), 1 saltado(s), 1 hallazgo(s) (1 nuevo(s)' && ok "--cerrar completo: cierra y pasa el hallazgo al contrato" || bad "cerrar (rc=$rc)" "$out"
python3 - <<'PY' && ok "el contrato tiene REV-1 sin disposición y segunda_pasada con la huella" || bad "contrato tras cerrar"
import json,sys;c=json.load(open('.rompelo/task.json'));h=[x for x in c.get('hallazgos',[]) if x.get('id')=='REV-1']
sys.exit(0 if len(h)==1 and 'disposicion' not in h[0] and h[0].get('categoria')=='bug' and 'manifiesto sobre v2:' in c.get('segunda_pasada','') else 1)
PY
espera_bloqueo "con manifiesto cerrado: ya no pide revisar, pide la disposición" n3 'hallazgo sin disposición: REV-1'
out="$(hook_stop claude n3 "$R")"; printf '%s' "$out" | grep -q 'rompelo revisar' && bad "seguía pidiendo revisar" "$out" || ok "…y no vuelve a pedir revisar"
contrato 'hallazgos=[{"id":"REV-1","path":"src/a.txt","linea":1,"categoria":"bug","severidad":"high","texto":"a2 no es a","disposicion":"aceptado","nota":"es el dato de prueba"}]'
"$ROMPELO" check >/dev/null || exit 2
espera_paso "revisión cerrada + hallazgo dispuesto + checks: silencio" n3
out="$("$ROMPELO" revisar --cerrar 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '0 nuevo(s)' && ok "--cerrar otra vez sobre la misma huella: idempotente, no duplica el hallazgo" || bad "idempotencia (rc=$rc)" "$out"

echo "── un cambio después de cerrar caduca la revisión"
echo a3 > src/a.txt
espera_bloqueo "cambio posterior: vuelve a pedir rompelo revisar" n4 'rompelo revisar'
out="$("$ROMPELO" revisar --cerrar 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'otro árbol' && ok "--cerrar con manifiesto viejo: otro árbol" || bad "manifiesto viejo (rc=$rc)" "$out"
"$ROMPELO" revisar >/dev/null || exit 2
python3 - "$MAN" <<'PY' && ok "revisar abre un manifiesto nuevo (huella nueva, sin estados)" || bad "manifiesto nuevo"
import json,sys;rv=json.load(open(sys.argv[1]));sys.exit(0 if rv['cerrada'] is False and all(x['estado']=='' for x in rv['ficheros']) else 1)
PY
manifiesto 'f:src/a.txt=revisado' 'f:src/nuevo.txt=revisado'
"$ROMPELO" revisar --cerrar >/dev/null && "$ROMPELO" check >/dev/null || exit 2
espera_paso "revisado de nuevo: silencio" n4

echo "── cobertura: un fichero que falta o sobra en el manifiesto"
echo a4 > src/a.txt; "$ROMPELO" revisar >/dev/null || exit 2
python3 - "$MAN" <<'PY'
import json,sys;f=sys.argv[1];rv=json.load(open(f));rv['ficheros']=[{"path":"src/a.txt","estado":"revisado","motivo":""},{"path":"src/otro.txt","estado":"revisado","motivo":""}];json.dump(rv,open(f,'w'))
PY
out="$("$ROMPELO" revisar --cerrar 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'faltan en el manifiesto: src/nuevo.txt' && printf '%s' "$out" | grep -q 'no en el diff: src/otro.txt' && ok "falta uno y sobra otro: los dos errores" || bad "cobertura (rc=$rc)" "$out"
"$ROMPELO" revisar >/dev/null; manifiesto 'f:src/a.txt=revisado' 'f:src/nuevo.txt=revisado' 'hallazgos=[{"id":"X","texto":"t","categoria":"cosmética"}]'
out="$("$ROMPELO" revisar --cerrar 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'categoría «cosmética» no vale' && ok "categoría inventada: error" || bad "categoría (rc=$rc)" "$out"
manifiesto 'hallazgos=[{"id":"X","texto":"t"},{"id":"X","texto":"u"}]'
out="$("$ROMPELO" revisar --cerrar 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'hallazgo repetido: X' && ok "id repetido: error" || bad "repetido (rc=$rc)" "$out"
manifiesto 'hallazgos=[]'; "$ROMPELO" revisar --cerrar >/dev/null && "$ROMPELO" check >/dev/null || exit 2
espera_paso "arreglado: silencio" n5
out="$("$ROMPELO" revisar sobrante 2>&1)"; rc=$?; [ "$rc" -ne 0 ] && ok "argumento suelto: error" || bad "argumento suelto pasó" "$out"

echo "── ocr en PATH: las reglas salen de ocr delegate rule (sin LLM)"
cat > "$T/bin/ocr" <<'EOF'
#!/bin/bash
[ "$1" = delegate ] && [ "$2" = rule ] && printf '%s' '{"schema_version":"1","groups":[{"group_id":1,"source":"global","pattern":"**/*.txt","files":["src/a.txt","src/nuevo.txt"],"rule":"REGLA-FALSA: no dejes a2"}]}' && exit 0
exit 1
EOF
chmod +x "$T/bin/ocr"
echo a5 > src/a.txt
out="$(PATH="$T/bin:$PATH" "$ROMPELO" revisar 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'REGLA-FALSA' && printf '%s' "$out" | grep -q 'reglas (global: \*\*/\*.txt) para: src/a.txt, src/nuevo.txt' && ok "reglas agrupadas de ocr delegate en el manifiesto" || bad "ocr delegate (rc=$rc)" "$out"
printf '#!/bin/bash\nexit 1\n' > "$T/bin/ocr"
out="$(PATH="$T/bin:$PATH" "$ROMPELO" revisar 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'ocr delegate rule no respondió' && ok "ocr roto: lo dice y sigue (nunca bloquea el manifiesto)" || bad "ocr roto (rc=$rc)" "$out"

echo "── modo texto (config) y modo inválido"
rm -f "$MAN"; git checkout -q -- src/a.txt
printf '{"segunda_pasada": "texto"}' > "$ROMPELO_HOME/config/observacion.json"
contrato 'segunda_pasada=""'   # --cerrar había escrito el campo; en modo texto es el agente quien lo pone
"$ROMPELO" check >/dev/null || exit 2
espera_bloqueo "modo texto sin campo: bloquea pidiendo el campo" t1 'campo `segunda_pasada`'
contrato 'segunda_pasada="revisado a mano, nada"'
espera_paso "modo texto con campo: silencio (comportamiento anterior)" t1
printf '{"segunda_pasada": "adivina"}' > "$ROMPELO_HOME/config/observacion.json"
espera_bloqueo "modo inválido: fail-closed" t2 'segunda_pasada'
rm -f "$ROMPELO_HOME/config/observacion.json"
espera_bloqueo "sin config: el defecto es el manifiesto" t3 'rompelo revisar'

echo "── el manifiesto viaja con el PR: evidence/.gitignore deja fuera solo el revision.json de la tarea en curso (PR #15, 19-09-2026)"
GI=".rompelo/evidence/.gitignore"; ESPERADO="$(printf '*\n!R1/\n!R1/revision.json')"
[ "$(cat "$GI")" = "$ESPERADO" ] && ok "gitignore de evidencia: todo menos R1/revision.json" || bad "gitignore de evidencia" "$(cat "$GI")"
mkdir -p .rompelo/evidence/R1 .rompelo/evidence/VIEJA && : > .rompelo/evidence/R1/revision.json && : > .rompelo/evidence/R1/check-ok.json && : > .rompelo/evidence/VIEJA/revision.json
git check-ignore -q .rompelo/evidence/R1/revision.json && bad "R1/revision.json sigue ignorado: el CI no lo verá" || ok "R1/revision.json NO está ignorado (git check-ignore)"
git check-ignore -q .rompelo/evidence/R1/check-ok.json && ok "R1/check-ok.json sí está ignorado" || bad "check-ok.json no está ignorado: las salidas de checks viajarían"
git check-ignore -q .rompelo/evidence/VIEJA/revision.json && ok "el manifiesto de OTRA tarea sigue ignorado (no aparecen 56 ficheros de golpe)" || bad "VIEJA/revision.json no está ignorado"
printf '*\n' > "$GI"; "$ROMPELO" check >/dev/null 2>&1
[ "$(cat "$GI")" = "$ESPERADO" ] && ok "un * viejo se migra al pasar por rompelo" || bad "el * viejo no se migró" "$(cat "$GI")"
printf '*\n!OTRA/\n!OTRA/revision.json\n' > "$GI"; "$ROMPELO" check >/dev/null 2>&1
[ "$(cat "$GI")" = "$ESPERADO" ] && ok "la excepción de otra tarea se reescribe a la tarea en curso" || bad "no reescribió la excepción de otra tarea" "$(cat "$GI")"
printf '# mio\n*\n' > "$GI"; "$ROMPELO" check >/dev/null 2>&1
[ "$(cat "$GI")" = "$(printf '# mio\n*')" ] && ok "un .gitignore escrito a mano no se toca" || bad "pisó un .gitignore a mano" "$(cat "$GI")"

cd / && rm -rf "$T"
resumen
