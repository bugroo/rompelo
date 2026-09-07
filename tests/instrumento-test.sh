#!/bin/bash
# Control del propio instrumento de prueba (RMP-004, 07-09-2026). Las aserciones de tests/lib.sh
# se ejercitan contra binarios FALSOS: un hook que muere, uno ausente, uno que imprime JSON roto,
# uno que contamina la salida, uno que no responde, uno que bloquea bien pero sale con 1. Ninguno
# puede contar como «deja parar» ni como «bloquea». Y al revés: un hook sano callado pasa la
# aserción de silencio y un bloqueo bien formado pasa la de bloqueo (control en las dos direcciones).
# Exit 0 = el instrumento distingue · 1 = alguna aserción se traga un fallo.
T="$(mktemp -d)"; export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
falso() { printf '#!/bin/sh\n%s\n' "$2" > "$T/$1"; chmod +x "$T/$1"; echo "$T/$1"; }
R="$T"   # cwd que reciben los hooks falsos; da igual, no lo miran

export ROMPELO_BIN="$(falso muere 'echo "Traceback: boom" >&2; exit 1')"
. "$(dirname "$0")/lib.sh"
ROMPELO_HOOK_TIMEOUT=2
TOTAL=0; MAL=0
caso() { TOTAL=$((TOTAL+1)); if [ "$1" -eq 0 ]; then echo "  ✅ $2"; else MAL=$((MAL+1)); echo "  ❌ $2"; fi; }
# debe_fallar <nombre> <función> <args…>: la aserción tiene que registrar un ❌ (FAIL sube en 1)
debe_fallar() { local n="$1"; shift; local antes=$FAIL; "$@" >/dev/null; [ $FAIL -eq $((antes+1)) ]; caso $? "$n"; }
debe_pasar()  { local n="$1"; shift; local antes=$PASS; local f=$FAIL; "$@" >/dev/null; [ $PASS -eq $((antes+1)) ] && [ $FAIL -eq $f ]; caso $? "$n"; }

echo "── hook que muere (stderr + código 1, stdout vacío)"
debe_fallar "espera_paso no acepta un hook muerto como silencio" espera_paso x s1
debe_fallar "espera_bloqueo no acepta un hook muerto" espera_bloqueo x s1 "lo que sea"
out="$(hook_stop claude s1 "$R")"; printf '%s' "$out" | grep -q 'INSTRUMENTO ROTO: rc=1' && caso 0 "la salida lleva la marca con el código" || caso 1 "marca ausente: $out"

echo "── binario ausente"
ROMPELO="$T/no-existe"
debe_fallar "espera_paso con binario ausente" espera_paso x s2
debe_fallar "espera_bloqueo con binario ausente" espera_bloqueo x s2 "x"

echo "── sin permiso de ejecución"
printf '#!/bin/sh\nexit 0\n' > "$T/sin-x"; ROMPELO="$T/sin-x"
debe_fallar "espera_paso con binario sin +x" espera_paso x s2b

echo "── JSON truncado con código 0"
ROMPELO="$(falso truncado 'printf "{\"decision\": \"block\", \"reason\": \"falta"')"
debe_fallar "espera_bloqueo rechaza JSON truncado" espera_bloqueo x s3 "falta"
debe_fallar "espera_paso tampoco lo toma por silencio" espera_paso x s3

echo "── salida contaminada: texto antes del JSON"
ROMPELO="$(falso sucio 'echo "warning: algo"; printf "{\"decision\": \"block\", \"reason\": \"motivo real\"}"')"
debe_fallar "espera_bloqueo exige que TODA la salida sea el JSON" espera_bloqueo x s4 "motivo real"

echo "── bloqueo bien formado pero proceso no sano"
ROMPELO="$(falso rc1 'printf "{\"decision\": \"block\", \"reason\": \"motivo real\"}"; exit 1')"
debe_fallar "JSON correcto con código 1 no es un bloqueo" espera_bloqueo x s5 "motivo real"
ROMPELO="$(falso conerr 'printf "{\"decision\": \"block\", \"reason\": \"motivo real\"}"; echo "aviso" >&2')"
debe_fallar "JSON correcto con stderr no es un bloqueo" espera_bloqueo x s5b "motivo real"
ROMPELO="$(falso callaerr 'echo "aviso" >&2')"
debe_fallar "silencio con stderr no es silencio" espera_paso x s5c

echo "── sin respuesta (plazo de $ROMPELO_HOOK_TIMEOUT s)"
ROMPELO="$(falso lento 'sleep 10; exit 0')"
t0=$(date +%s); debe_fallar "espera_paso no se queda colgado ni lo da por silencio" espera_paso x s6; t1=$(date +%s)
[ $((t1-t0)) -lt 6 ] && caso 0 "y acotado en el tiempo ($((t1-t0)) s)" || caso 1 "tardó $((t1-t0)) s"

echo "── observador que muere"
ROMPELO="$T/muere"
o="$(observar claude '{"session_id":"s","cwd":"'"$R"'","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{}}')"
printf '%s' "$o" | grep -q 'INSTRUMENTO ROTO' && caso 0 "observar marca el hook roto (un «-z» ya no lo tomaría por silencio)" || caso 1 "observar sin marca: $o"

echo "── el stdin llega al hook (un heredoc se lo comía, 07-09)"
ROMPELO="$(falso eco 'cat')"
o="$(hook_stop claude sesion-canario "$R")"; printf '%s' "$o" | grep -q '"session_id":"sesion-canario"' && caso 0 "el hook recibe el JSON con el session_id" || caso 1 "stdin perdido: $o"
o="$(observar claude '{"session_id":"obs-canario"}')"; [ "$o" = '{"session_id":"obs-canario"}' ] && caso 0 "observar entrega el JSON entero" || caso 1 "observar perdió stdin: $o"

echo "── control negativo: un hook sano pasa lo que tiene que pasar"
ROMPELO="$(falso callado 'exit 0')"
debe_pasar "silencio sano pasa espera_paso" espera_paso x s7
debe_fallar "silencio sano NO pasa espera_bloqueo" espera_bloqueo x s7 "x"
ROMPELO="$(falso bloquea "printf '%s' '{\"decision\": \"block\", \"reason\": \"[rompelo] motivo real\\n- check x sin ejecutar\"}'")"
debe_pasar "bloqueo sano pasa espera_bloqueo con su texto" espera_bloqueo x s8 "sin ejecutar"
debe_fallar "bloqueo sano con OTRO texto no pasa" espera_bloqueo x s8 "texto que no está"
debe_fallar "bloqueo sano no pasa espera_paso" espera_paso x s8
ROMPELO="$(falso continua 'printf "{\"continue\": true}"')"
debe_fallar "un JSON sin decision=block no es bloqueo" espera_bloqueo x s9 ""

echo "── resumen: una rotura descartada con >/dev/null sigue contando"
ROTOS_F="$(mktemp)"; ROMPELO="$T/muere"; hook_stop claude s10 "$R" >/dev/null
[ "$(wc -l < "$ROTOS_F" | tr -d ' ')" = 1 ] && caso 0 "la rotura queda anotada aunque nadie mire la salida" || caso 1 "rotura no anotada"
ROTOS_F="$(mktemp)"; hook_stop claude s10 "$R" >/dev/null; PASS=1; FAIL=0
if resumen >/dev/null; then caso 1 "resumen dio 0 con una rotura"; else caso 0 "resumen devuelve 1 con FAIL=0 y una rotura"; fi
ROTOS_F="$(mktemp)"; PASS=1; FAIL=0
if resumen >/dev/null; then caso 0 "resumen devuelve 0 sano"; else caso 1 "resumen falló sin motivo"; fi

echo; echo "instrumento: $((TOTAL-MAL)) de $TOTAL distinciones correctas"
rm -rf "$T"
[ "$MAL" -eq 0 ]
