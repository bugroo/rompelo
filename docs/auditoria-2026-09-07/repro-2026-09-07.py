"""Reproduce los hallazgos de la auditoría contra bin/rompelo REAL (importado), con ROMPELO_HOME aislado."""
import importlib.util, importlib.machinery, os, subprocess, sys, tempfile, json, shutil, stat

HOME_ROMPELO = tempfile.mkdtemp(prefix="rompelo-home-")
os.environ["ROMPELO_HOME"] = HOME_ROMPELO
loader = importlib.machinery.SourceFileLoader("rompelo", os.environ.get("ROMPELO_BIN") or os.path.expanduser("~/rompelo/bin/rompelo"))
spec = importlib.util.spec_from_loader("rompelo", loader)
R = importlib.util.module_from_spec(spec); loader.exec_module(R)
BIN = os.environ.get("ROMPELO_BIN") or os.path.expanduser("~/rompelo/bin/rompelo")

def sh(*a, cwd=None, inp=None, env=None):
    e = dict(os.environ); e.update(env or {})
    return subprocess.run(list(a), cwd=cwd, input=inp, capture_output=True, text=True, env=e)

def repo():
    d = tempfile.mkdtemp(prefix="rompelo-repo-")
    sh("git", "init", "-q", cwd=d); sh("git", "config", "user.email", "x@x", cwd=d); sh("git", "config", "user.name", "x", cwd=d)
    sh("git", "config", "core.quotePath", "true", cwd=d)  # valor por defecto de git; explícito para que la prueba no dependa de ~/.gitconfig
    return os.path.realpath(d)

def commit(d, msg="c"):
    sh("git", "add", "-A", cwd=d); sh("git", "commit", "-q", "-m", msg, cwd=d)

def w(d, p, s): 
    open(os.path.join(d, p), "w").write(s)

res = {}
def rep(k, ok, detalle=""):
    res[k] = ok; print(f"{'REPRODUCIDO' if ok else 'NO reproducido'}  {k}  {detalle}")

# ── RMP-001 huella ───────────────────────────────────────────────────────────
d = repo(); w(d, "normal.py", "a\n"); w(d, "año.py", "a\n"); w(d, "run.sh", "#!/bin/sh\n"); commit(d)
base = R.head(d)
h0 = R.huella_arbol(d, base)
w(d, "normal.py", "b\n"); h1 = R.huella_arbol(d, base)
rep("RMP-001 control positivo (normal.py cambia la huella)", h0 != h1)
w(d, "normal.py", "a\n")
w(d, "año.py", "b\n"); h2 = R.huella_arbol(d, base)
rep("RMP-001a año.py cambia y la huella NO cambia", h2 == h0, f"cambiados={R.ficheros_cambiados(d, base)}")
w(d, "año.py", "a\n")
os.chmod(os.path.join(d, "run.sh"), 0o755); h3 = R.huella_arbol(d, base)
rep("RMP-001b +x no cambia la huella", h3 == h0, f"cambiados={R.ficheros_cambiados(d, base)}")
os.chmod(os.path.join(d, "run.sh"), 0o644)
# symlink: destino distinto con contenido idéntico
w(d, "t1.txt", "same\n"); w(d, "t2.txt", "same\n"); os.symlink("t1.txt", os.path.join(d, "ln")); commit(d, "ln")
base2 = R.head(d); hs0 = R.huella_arbol(d, base2)
os.remove(os.path.join(d, "ln")); os.symlink("t2.txt", os.path.join(d, "ln")); hs1 = R.huella_arbol(d, base2)
rep("RMP-001c symlink cambia de destino y la huella NO cambia", hs0 == hs1, f"cambiados={R.ficheros_cambiados(d, base2)}")
# repo sin HEAD con fichero staged
d2 = repo(); w(d2, "s.py", "x\n"); sh("git", "add", "s.py", cwd=d2)
rep("RMP-001d staged en repo sin HEAD queda fuera de cambiados", R.ficheros_cambiados(d2, None) == [], f"cambiados={R.ficheros_cambiados(d2, None)}")

# ── RMP-002 base inexistente ────────────────────────────────────────────────
try:
    rep("RMP-002 ref_base('deadbeef') devuelve HEAD en silencio", R.ref_base(d, "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef") == "HEAD")
except ValueError as e:
    rep("RMP-002 ref_base('deadbeef') devuelve HEAD en silencio", False, f"ahora lanza: {str(e)[:60]}")
d3 = repo(); w(d3, "a.py", "1\n"); commit(d3); w(d3, "a.py", "2\n"); commit(d3, "2")
try:
    rep("RMP-002b dos commits distintos, base inexistente → huella vacía igual", R.huella_arbol(d3, "0"*40) == R.huella_arbol(d3, "1"*40) and R.ficheros_cambiados(d3, "0"*40) == [])
except ValueError as e:
    rep("RMP-002b dos commits distintos, base inexistente → huella vacía igual", False, f"ahora lanza: {str(e)[:60]}")

# ── RMP-005 registro del consumidor ignorado si hay global ──────────────────
d4 = repo(); os.makedirs(os.path.join(d4, ".rompelo")); w(d4, ".rompelo/registry.json", json.dumps({"consumer.test": {"argv": ["true"]}}))
os.makedirs(os.path.join(HOME_ROMPELO, "checks")); w(HOME_ROMPELO, "checks/registry.json", json.dumps({"rompelo.tests": {"argv": ["true"]}}))
reg = R.registro(d4)
rep("RMP-005 con registro global, consumer.test no aparece", "consumer.test" not in reg and "rompelo.tests" in reg, f"ids={sorted(reg)}")

# ── RMP-003 repos.json truncado → hook sin JSON / traceback ─────────────────
d5 = repo(); w(d5, "x.py", "1\n"); commit(d5)
os.makedirs(os.path.join(HOME_ROMPELO, "config"), exist_ok=True)
w(HOME_ROMPELO, "config/repos.json", '{"repos": ["' + d5 + '"')  # truncado
p = sh(BIN, "hook", "claude", inp=json.dumps({"session_id": "s", "cwd": d5, "stop_hook_active": False}))
rep("RMP-003a repos.json truncado: hook sale sin JSON de decisión", p.returncode != 0 and not p.stdout.strip(), f"rc={p.returncode} stderr_last={p.stderr.strip().splitlines()[-1] if p.stderr.strip() else ''}")
w(HOME_ROMPELO, "config/repos.json", json.dumps({"repos": [d5]}))
# estado truncado → nivel 3 y perfiles desaparecen
f_est = R.ruta_estado_repo(d5); R.guardar_estado_repo(d5, {"nivel": 3, "perfiles": ["junta"], "permisos": ["security"]})
open(f_est, "w").write('{"nivel": 3, "perfiles": ["junta"')
rep("RMP-003b estado truncado → {} (nivel y perfiles desaparecen)", R.estado_repo(d5) == {})
os.remove(f_est)

# ── RMP-004 espera_paso acepta hook averiado ────────────────────────────────
fake = tempfile.mkdtemp(); fb = os.path.join(fake, "rompelo"); open(fb, "w").write("#!/bin/sh\necho 'Traceback: boom' >&2\nexit 1\n"); os.chmod(fb, 0o755)
script = f'''PASS=0; FAIL=0; ROMPELO="{fb}"; R="{d5}"
ok() {{ PASS=$((PASS+1)); }}; bad() {{ FAIL=$((FAIL+1)); }}
hook() {{ printf '{{"session_id":"%s","cwd":"%s","stop_hook_active":false}}' "$1" "$R" | "$ROMPELO" hook claude; }}
espera_paso() {{ local out; out="$(hook claude "$2" "$R")"; [ -z "$out" ] && ok "$1" || bad "$1 (esperaba silencio)" "$out"; }}
espera_paso "x" s0 2>/dev/null; echo "PASS=$PASS FAIL=$FAIL"'''
p = sh("bash", "-c", script)
rep("RMP-004 espera_paso: hook que muere con rc=1 cuenta como PASS", "PASS=1 FAIL=0" in p.stdout, p.stdout.strip())

# ── RMP-008 close firma el contrato original; verify compara el efectivo ────
w(HOME_ROMPELO, "checks/registry.json", json.dumps({"ok": {"argv": ["true"]}}))
os.makedirs(os.path.join(d5, ".rompelo"), exist_ok=True)
c = {"schema": 1, "id": "T", "estado": "abierta", "base": R.head(d5), "scope_paths": ["**"], "checks": ["ok"], "toca_junta": False, "hallazgos": [], "segunda_pasada": "x"}
w(d5, ".rompelo/task.json", json.dumps(c))
R.guardar_estado_repo(d5, {"nivel": 2, "perfiles": ["junta"], "patrones": []})
sh(BIN, "check", cwd=d5); sh(BIN, "cruce", "--", "true", cwd=d5)
pc = sh(BIN, "close", cwd=d5); pv = sh(BIN, "verify", cwd=d5)
rep("RMP-008 close OK y verify inmediato dice 'contrato cambió' sin edición", pc.returncode == 0 and "contrato cambió" in pv.stdout, f"close_rc={pc.returncode} verify: {pv.stdout.strip().splitlines()[-1] if pv.stdout.strip() else pv.stderr.strip()[-200:]}")

# ── RMP-009 permiso si → no no revoca ───────────────────────────────────────
R.guardar_estado_repo(d5, {})
sh(BIN, "permiso", "security", "si", cwd=d5); sh(BIN, "permiso", "security", "no", cwd=d5)
rep("RMP-009 tras si→no el nivel sigue en 3", R.estado_repo(d5).get("nivel") == 3, f"estado={R.estado_repo(d5)}")

# ── RMP-010 salida no UTF-8 → excepción ─────────────────────────────────────
try:
    R.ejecutar(["printf", "\\377"], d5); rep("RMP-010 bytes inválidos rompen ejecutar()", False)
except UnicodeDecodeError as e:
    rep("RMP-010 bytes inválidos rompen ejecutar()", True, type(e).__name__)
import inspect
rep("RMP-010b subprocess.run sin timeout en ejecutar()", "timeout" not in inspect.getsource(R.ejecutar))

# ── RMP-014 checks=[] y checks_nivel3 ───────────────────────────────────────
c14 = dict(c, checks=[], checks_nivel3=["ok"], estado="abierta"); w(d5, ".rompelo/task.json", json.dumps(c14))
R.guardar_estado_repo(d5, {"nivel": 3})
p = sh(BIN, "check", cwd=d5)
rep("RMP-014 check no ejecuta el nivel3 con checks=[]", "no tiene checks" in p.stdout and not os.path.exists(os.path.join(d5, ".rompelo/evidence/T/check-ok.json")) or "no tiene checks" in p.stdout, p.stdout.strip())

# ── RMP-015 borrar el test satisface exige_prueba_en_diff ───────────────────
d6 = repo(); os.makedirs(os.path.join(d6, "tests")); w(d6, "app.py", "1\n"); w(d6, "tests/test_a.py", "1\n"); commit(d6)
os.makedirs(os.path.join(d6, ".rompelo")); c15 = dict(c, base=R.head(d6), exige_prueba_en_diff=True, checks=[]); w(d6, ".rompelo/task.json", json.dumps(c15))
w(d6, "app.py", "2\n"); os.remove(os.path.join(d6, "tests/test_a.py"))
m = R.motivos_bloqueo(d6)
rep("RMP-015 código cambiado + test borrado no bloquea por exige_prueba_en_diff", not any("ninguna prueba" in x for x in m), f"motivos={m}")

# ── RMP-007 argv íntegro en evidencia ───────────────────────────────────────
e, _ = R.ejecutar(["true", "--token", "CANARIO_SECRETO_123"], d5)
rep("RMP-007 el canario del argv queda en la evidencia", "CANARIO_SECRETO_123" in json.dumps(e))

# ── RMP-011 hookEventName fijo ──────────────────────────────────────────────
src = open(BIN).read()
rep("RMP-011 hookEventName siempre 'PostToolUse' en cmd_observe", '"hookEventName": "PostToolUse"' in src and '"hookEventName": "PostToolUseFailure"' not in src)
# ── RMP-013 state prune no existe ───────────────────────────────────────────
p = sh(BIN, "state", "prune", cwd=d5)
rep("RMP-013 `rompelo state prune` no existe", p.returncode != 0 and "desconocido" in (p.stderr + p.stdout))

print("\nRESUMEN:", sum(res.values()), "de", len(res), "reproducidos")
shutil.rmtree(HOME_ROMPELO, ignore_errors=True)
