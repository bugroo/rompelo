#!/bin/bash
# Prueba del envoltorio checks/ocr-review.py con un `ocr` falso en PATH (sin LLM, sin red).
# Cada caso dice qué JSON devuelve el falso y qué código tiene que dar el envoltorio.
# Control positivo del propio test: un caso con hallazgo grave TIENE que dar 1; si el envoltorio
# dejara de leer `comments`, ese caso lo caza.
set -u
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP:?}"' EXIT
mkdir -p "$TMP/bin" "$TMP/repo"
git -C "$TMP/repo" init -q -b main && echo a > "$TMP/repo/a.ts" && git -C "$TMP/repo" add -A && git -C "$TMP/repo" -c user.name=t -c user.email=t@t commit -qm base
echo b >> "$TMP/repo/a.ts"   # árbol sucio: el envoltorio hace la pasada workspace
fallos=0; vistos=0
caso() {  # nombre, código esperado, rc del falso, JSON que imprime el falso
  local nombre="$1" esperado="$2" rc_falso="$3" json="$4"
  printf '#!/bin/bash\nprintf %%s %q\nexit %s\n' "$json" "$rc_falso" > "$TMP/bin/ocr"; chmod +x "$TMP/bin/ocr"
  local salida; salida="$(cd "$TMP/repo" && PATH="$TMP/bin:$PATH" python3 "$RAIZ/checks/ocr-review.py" 2>&1)"; local rc=$?
  vistos=$((vistos+1))
  if [ "$rc" = "$esperado" ]; then echo "OK   $nombre → $rc"; else echo "FALLO $nombre → $rc (esperado $esperado): $salida"; fallos=$((fallos+1)); fi
}
J_OK='{"status":"complete","llm":{"model":"falso"},"summary":{"files_reviewed":3,"total_tokens":10},"comments":[]}'
J_LOW='{"status":"complete","llm":{"model":"falso"},"summary":{"files_reviewed":3,"total_tokens":10},"comments":[{"path":"a.ts","start_line":1,"end_line":1,"severity":"low","category":"style","content":"nit"}]}'
J_HIGH='{"status":"complete","llm":{"model":"falso"},"summary":{"files_reviewed":3,"total_tokens":10},"comments":[{"path":"a.ts","start_line":2,"end_line":2,"severity":"high","category":"bug","content":"grave"}]}'
J_SKIP='{"status":"skipped","llm":{"model":"falso"},"message":"nada","comments":[]}'
J_WARN='{"status":"complete","llm":{"model":"falso"},"summary":{"files_reviewed":2,"total_tokens":10},"comments":[],"warnings":[{"path":"b.ts","error":"subagente caído"}]}'
J_ERR='{"status":"completed_with_errors","llm":{"model":"falso"},"summary":{"files_reviewed":0},"comments":[]}'
caso "sin comentarios → 0"                    0 0 "$J_OK"
caso "solo low con umbral medium → 0"         0 0 "$J_LOW"
caso "high → 1 (control positivo)"            1 0 "$J_HIGH"
caso "skipped, cero ficheros → 2"             2 0 "$J_SKIP"
caso "warnings, cobertura incompleta → 2"     2 0 "$J_WARN"
caso "status con errores → 2"                 2 0 "$J_ERR"
caso "ocr sale con 1 → 2"                     2 1 "$J_OK"
caso "ocr no devuelve JSON → 2"               2 0 "esto no es json"
J_RARO='{"status":"complete","llm":{"model":"falso"},"summary":{"files_reviewed":3,"total_tokens":10},"comments":[{"path":"a.ts","start_line":2,"end_line":2,"severity":"Blocker","category":"bug","content":"nivel desconocido"}]}'
J_ROTO='{"status":"complete","llm":{"model":"falso"},"summary":{"files_reviewed":"tres","total_tokens":10},"comments":[]}'
caso "severidad desconocida cuenta como grave → 1" 1 0 "$J_RARO"
caso "summary mal formado → 2, nunca 1"           2 0 "$J_ROTO"
# umbral configurable: con OCR_UMBRAL=low el nit ya cuenta
printf '#!/bin/bash\nprintf %%s %q\n' "$J_LOW" > "$TMP/bin/ocr"; chmod +x "$TMP/bin/ocr"
( cd "$TMP/repo" && PATH="$TMP/bin:$PATH" OCR_UMBRAL=low python3 "$RAIZ/checks/ocr-review.py" >/dev/null 2>&1 ); rc=$?; vistos=$((vistos+1))
if [ "$rc" = 1 ]; then echo "OK   umbral low cuenta el nit → 1"; else echo "FALLO umbral low → $rc (esperado 1)"; fallos=$((fallos+1)); fi
# el falso tiene que haber sido llamado de verdad (el envoltorio deja .rompelo/ocr-ultimo.json)
[ -s "$TMP/repo/.rompelo/ocr-ultimo.json" ] && grep -q '"falso"' "$TMP/repo/.rompelo/ocr-ultimo.json" && echo "OK   el envoltorio guardó la salida del instrumento" || { echo "FALLO no quedó ocr-ultimo.json con el modelo falso"; fallos=$((fallos+1)); }
# modo rango: contrato con base != HEAD → pasada rango; y .rompelo/** sucio NO añade pasada workspace (OCR-3)
git -C "$TMP/repo" checkout -q -- a.ts   # árbol limpio salvo .rompelo/
BASE="$(git -C "$TMP/repo" rev-parse HEAD)"; echo c >> "$TMP/repo/a.ts" && git -C "$TMP/repo" add -A && git -C "$TMP/repo" -c user.name=t -c user.email=t@t commit -qm segundo
mkdir -p "$TMP/repo/.rompelo" && printf '{"base":"%s"}\n' "$BASE" > "$TMP/repo/.rompelo/task.json"
printf '#!/bin/bash\nprintf %%s %q\n' "$J_OK" > "$TMP/bin/ocr"; chmod +x "$TMP/bin/ocr"
( cd "$TMP/repo" && PATH="$TMP/bin:$PATH" python3 "$RAIZ/checks/ocr-review.py" >/dev/null 2>&1 ); rc=$?; vistos=$((vistos+1))
pasadas="$(python3 -c "import json;print(' '.join(json.load(open('$TMP/repo/.rompelo/ocr-ultimo.json'))['pasadas']))")"
case "$pasadas" in rango*) [ "$rc" = 0 ] && [[ "$pasadas" != *workspace* ]] && echo "OK   base != HEAD → solo pasada rango ($pasadas)" || { echo "FALLO rango: rc=$rc pasadas='$pasadas'"; fallos=$((fallos+1)); } ;;
  *) echo "FALLO no hubo pasada rango: '$pasadas'"; fallos=$((fallos+1)) ;; esac
# tope de tamaño (OCR-9): 2000 líneas sin seguimiento no llegan a ocr → 2, y el falso NO se ejecuta
seq 1 2000 > "$TMP/repo/grande.ts"
printf '#!/bin/bash\ntouch %q\nprintf %%s %q\n' "$TMP/llamado" "$J_OK" > "$TMP/bin/ocr"; chmod +x "$TMP/bin/ocr"
rm -f "$TMP/llamado"; salida="$(cd "$TMP/repo" && PATH="$TMP/bin:$PATH" python3 "$RAIZ/checks/ocr-review.py" 2>&1)"; rc=$?; vistos=$((vistos+1))
if [ "$rc" = 2 ] && [ ! -e "$TMP/llamado" ] && [[ "$salida" == *"demasiado grande"* ]]; then echo "OK   2000 líneas > tope → 2 sin llamar a ocr"; else echo "FALLO tope: rc=$rc llamado=$([ -e "$TMP/llamado" ] && echo sí || echo no): $salida"; fallos=$((fallos+1)); fi
# el tope se sube a sabiendas: OCR_MAX_LINEAS=0 lo quita y ocr sí corre
rm -f "$TMP/llamado"; ( cd "$TMP/repo" && PATH="$TMP/bin:$PATH" OCR_MAX_LINEAS=0 python3 "$RAIZ/checks/ocr-review.py" >/dev/null 2>&1 ); rc=$?; vistos=$((vistos+1))
if [ "$rc" = 0 ] && [ -e "$TMP/llamado" ]; then echo "OK   OCR_MAX_LINEAS=0 → sin tope, ocr llamado → 0"; else echo "FALLO sin tope: rc=$rc llamado=$([ -e "$TMP/llamado" ] && echo sí || echo no)"; fallos=$((fallos+1)); fi
rm -f "$TMP/repo/grande.ts" "$TMP/llamado"
# comments: null explícito no revienta (OCR-5)
caso "comments null → 0, no TypeError" 0 0 '{"status":"complete","llm":{"model":"falso"},"summary":{"files_reviewed":1,"total_tokens":1},"comments":null}'
# hallazgo grave sin path ni content → sigue siendo 1, no 2 por KeyError (OCR-8)
caso "grave sin path/content → 1, no KeyError" 1 0 '{"status":"complete","llm":{"model":"falso"},"summary":{"files_reviewed":1,"total_tokens":1},"comments":[{"severity":"critical","category":"bug"}]}'
# control positivo: si ocr cuelga más del plazo, 2 y no traceback (OCR-7)
printf '#!/bin/bash\nsleep 5\n' > "$TMP/bin/ocr"; chmod +x "$TMP/bin/ocr"
( PATH="$TMP/bin:$PATH" OCR_CP_TIMEOUT=1 python3 "$RAIZ/checks/ocr-control-positivo.py" >/dev/null 2>&1 ); rc=$?; vistos=$((vistos+1))
[ "$rc" = 2 ] && echo "OK   control positivo con plazo agotado → 2" || { echo "FALLO control positivo plazo → $rc (esperado 2)"; fallos=$((fallos+1)); }
echo "$vistos casos, $fallos fallos"
[ "$fallos" = 0 ]
