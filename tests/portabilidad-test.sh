#!/bin/bash
# Portabilidad y diagnóstico (RMP-018, 07-09-2026): HOME con espacios, dos proyectos con la misma carpeta,
# instalación en otro directorio, y `rompelo doctor` como diagnóstico sin acciones peligrosas.
. "$(dirname "$0")/lib.sh"
T="$(mktemp -d)"; export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
export ROMPELO_HOME="$T/home"; mkdir -p "$ROMPELO_HOME/checks" "$ROMPELO_HOME/config"
printf '{"ok": {"argv": ["true"]}}' > "$ROMPELO_HOME/checks/registry.json"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"

echo "── HOME con espacio: la línea de settings.json de Claude tiene que sobrevivir al shell"
H="$T/con espacio"; mkdir -p "$H/rompelo/bin" "$H/rompelo/adapters/claude"; cp "$RAIZ"/adapters/claude/*.sh "$H/rompelo/adapters/claude/"; ln -s "$ROMPELO" "$H/rompelo/bin/rompelo"
CMD="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["hooks"]["Stop"][0]["hooks"][0]["command"])' "$RAIZ/adapters/claude/settings-fragment.json")"
out="$(printf '{"session_id":"esp","cwd":"%s","stop_hook_active":false}' "$T" | HOME="$H" ROMPELO_HOME="$ROMPELO_HOME" sh -c "$CMD" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "la línea Stop del fragmento de Claude corre con HOME='… con espacio' (rc 0, silencio)" || bad "fragmento Claude con espacio (rc=$rc)" "$out"
CMDO="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["hooks"]["PostToolUse"][0]["hooks"][0]["command"])' "$RAIZ/adapters/claude/settings-fragment.json")"
out="$(printf '{"session_id":"esp","cwd":"%s","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{}}' "$T" | HOME="$H" ROMPELO_HOME="$ROMPELO_HOME" sh -c "$CMDO" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "y la de PostToolUse también" || bad "fragmento observe con espacio (rc=$rc)" "$out"
CMDC="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["hooks"]["Stop"][0]["hooks"][0]["command"])' "$RAIZ/adapters/codex/hooks.json")"
out="$(printf '{"session_id":"esp","cwd":"%s","stop_hook_active":false}' "$T" | HOME="$H" ROMPELO_HOME="$ROMPELO_HOME" sh -c "$CMDC" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "la línea Stop de Codex también" || bad "hooks.json Codex con espacio (rc=$rc)" "$out"

echo "── dos proyectos con la misma carpeta no mezclan estado ni evidencia"
for d in a b; do mkdir -p "$T/$d/app/src"; (cd "$T/$d/app" && git init -q && git config user.email t@t && git config user.name t && echo x > src/a.txt && git add -A && git commit -qm b && "$ROMPELO" init --id "T-$d" --check ok >/dev/null 2>&1); done
(cd "$T/a/app" && "$ROMPELO" permiso herramientas si >/dev/null && "$ROMPELO" check >/dev/null)
(cd "$T/b/app" && "$ROMPELO" nivel | grep -q 'nivel 0') && ok "el permiso dado en a/app no aparece en b/app (estado por ruta real, no por nombre)" || bad "estado mezclado" "$(cd "$T/b/app" && "$ROMPELO" nivel)"
[ -f "$T/a/app/.rompelo/evidence/T-a/check-ok.json" ] && [ ! -e "$T/b/app/.rompelo/evidence/T-b/check-ok.json" ] && ok "la evidencia vive en cada repo" || bad "evidencia mezclada"
[ "$(ls "$ROMPELO_HOME/state/repos/" | grep -c json)" = 2 ] && ok "dos ficheros de estado, uno por ruta" || bad "estado por ruta" "$(ls "$ROMPELO_HOME/state/repos/")"

echo "── instalación en otro directorio: ROMPELO_HOME manda sobre ~/rompelo"
mkdir -p "$T/otra/checks"; printf '{"solo-aqui": {"argv": ["true"]}}' > "$T/otra/checks/registry.json"
(cd "$T/a/app" && ROMPELO_HOME="$T/otra" "$ROMPELO" init --force --id T-otra --check solo-aqui >/dev/null 2>&1 && ROMPELO_HOME="$T/otra" "$ROMPELO" check | grep -q 'solo-aqui') && ok "con ROMPELO_HOME alternativo se usa su registro y su allowlist" || bad "ROMPELO_HOME alternativo"
[ -f "$T/otra/config/repos.json" ] && ! grep -q "$T/a/app" "$ROMPELO_HOME/config/repos.json" 2>/dev/null || true
grep -q 'T-otra' "$T/a/app/.rompelo/task.json" && [ -f "$T/otra/config/repos.json" ] && ok "y la allowlist se escribe en ese HOME, no en el otro" || bad "allowlist en HOME alternativo"

echo "── rompelo doctor: diagnóstico sin acciones"
out="$(cd "$T/a/app" && "$ROMPELO" doctor 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "doctor sale con 0" || { bad "doctor rc=$rc" "$out"; out=""; }   # sin 0 no se leen palabras (la ayuda las contiene)
for k in 'python' 'ROMPELO_HOME' 'registro' 'allowlist' 'estado' 'git ' 'hooks'; do printf '%s' "$out" | grep -qi "$k" && ok "doctor informa de: $k" || bad "doctor no dice $k" "$out"; done
printf '%s' "$out" | grep -q 'solo-aqui\|1 check' && ok "doctor dice qué registro eligió y cuántos checks tiene" || bad "doctor registro" "$out"
[ "$(ls "$ROMPELO_HOME/state/repos/" | grep -c json)" = 2 ] && ok "doctor no escribe estado" || bad "doctor escribió"

rm -rf "$T"; resumen
